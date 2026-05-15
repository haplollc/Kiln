//
//  SwiftLexer.swift
//  SwiftRunner
//
//  Created by Claw on 2/21/26.
//

import Foundation

/// Errors that can occur during lexing
public enum LexerError: LocalizedError {
    case unexpectedCharacter(Character, line: Int, column: Int)
    case unterminatedString(line: Int)
    case invalidNumber(String, line: Int)

    /// The source line where the error occurred
    public var line: Int {
        switch self {
        case .unexpectedCharacter(_, let line, _): return line
        case .unterminatedString(let line): return line
        case .invalidNumber(_, let line): return line
        }
    }

    public var errorDescription: String? {
        switch self {
        case .unexpectedCharacter(let char, let line, let column):
            return "Unexpected character '\(char)' at line \(line), column \(column)"
        case .unterminatedString(let line):
            return "Unterminated string literal at line \(line) — missing closing quote"
        case .invalidNumber(let str, let line):
            return "Invalid number '\(str)' at line \(line)"
        }
    }
}

/// Tokenizes Swift source code
public final class SwiftLexer {
    private let source: String
    private var tokens: [Token] = []
    
    private var start: String.Index
    private var current: String.Index
    private var line: Int = 1
    private var column: Int = 1
    
    public init(source: String) {
        // Normalize smart/curly quotes to straight quotes before lexing.
        // LLMs and iOS text systems often produce these and they break string parsing.
        self.source = source
            .replacingOccurrences(of: "\u{201C}", with: "\"")  // left double "
            .replacingOccurrences(of: "\u{201D}", with: "\"")  // right double "
            .replacingOccurrences(of: "\u{2018}", with: "'")   // left single '
            .replacingOccurrences(of: "\u{2019}", with: "'")   // right single '
        self.start = self.source.startIndex
        self.current = self.source.startIndex
    }
    
    /// Tokenize the source code
    public func tokenize() throws -> [Token] {
        tokens = []
        start = source.startIndex
        current = source.startIndex
        line = 1
        column = 1
        
        while !isAtEnd {
            start = current
            try scanToken()
        }
        
        tokens.append(Token(type: .eof, line: line, column: column))
        return tokens
    }
    
    // MARK: - Scanning
    
    private func scanToken() throws {
        let c = advance()
        
        switch c {
        // Single character tokens
        case "(": addToken(.leftParen)
        case ")": addToken(.rightParen)
        case "{": addToken(.leftBrace)
        case "}": addToken(.rightBrace)
        case "[": addToken(.leftBracket)
        case "]": addToken(.rightBracket)
        case ",": addToken(.comma)
        case ":": addToken(.colon)
        case ".":
            if match(".") {
                if match("<") {
                    addToken(.halfOpenRange)  // ..<
                } else {
                    // Check for ... (third dot)
                    if match(".") {
                        addToken(.closedRange)  // ...
                    } else {
                        // Just .. which isn't valid Swift, emit two dots
                        addToken(.dot)
                        addToken(.dot)
                    }
                }
            } else {
                addToken(.dot)
            }
        case ";": addToken(.semicolon)
        case "?": addToken(match("?") ? .nilCoalescing : .questionMark)
        case "+": addToken(match("=") ? .plusEquals : .plus)
        case "-": addToken(match("=") ? .minusEquals : .minus)
        case "*": addToken(match("=") ? .starEquals : .star)
        case "%": addToken(.percent)
            
        // Two character tokens
        case "=":
            addToken(match("=") ? .equalEqual : .equals)
        case "!":
            addToken(match("=") ? .notEqual : .not)
        case "<":
            addToken(match("=") ? .lessEqual : .lessThan)
        case ">":
            addToken(match("=") ? .greaterEqual : .greaterThan)
        case "&":
            if match("&") { addToken(.and) }
        case "|":
            if match("|") { addToken(.or) }
            
        // Slash, comment, or /=
        case "/":
            if match("/") {
                // Line comment - skip to end of line
                while peek() != "\n" && !isAtEnd {
                    _ = advance()
                }
            } else if match("*") {
                // Block comment
                try scanBlockComment()
            } else if match("=") {
                addToken(.slashEquals)
            } else {
                addToken(.slash)
            }
            
        // Whitespace
        case " ", "\r", "\t":
            break
        case "\n":
            addToken(.newline)
            line += 1
            column = 1
            
        // String literals
        case "\"":
            try scanString()
            
        // $ binding prefix:
        //   `$name` → SwiftUI binding identifier (e.g. `text: $query`)
        //   `$0`, `$1` … → implicit closure-parameter shorthand
        // Both forms emit `.bindingIdentifier(name)`. Crucially, the digit
        // form must work — without it, `BookCard(book: $0)` lexes as
        // `BookCard(book: 0)` (the `$` gets dropped, `0` becomes a number)
        // and every iteration of `ForEach(books) { BookCard(book: $0) }`
        // passes literal `0` instead of the current item.
        case "$":
            if peek().isLetter || peek().isNumber || peek() == "_" {
                var name = ""
                while peek().isLetter || peek().isNumber || peek() == "_" {
                    name.append(advance())
                }
                addToken(.bindingIdentifier(name))
            }
            // bare $ without identifier — ignore

        // @ attributes (@State, @Binding, @MainActor, @ViewBuilder, @unknown, etc.)
        // Emit as .attribute(name). Parenthesized arguments (e.g.
        // @Environment(\.dismiss), @available(iOS 15, *)) are consumed here so the
        // parser sees a single attribute token — downstream code can treat the
        // attribute as a flat marker until richer attribute-arg support is added.
        case "@":
            var attrName = ""
            while peek().isLetter || peek().isNumber || peek() == "_" {
                attrName.append(advance())
            }
            if !attrName.isEmpty {
                addToken(.attribute(attrName))
            }
            // Swallow optional parenthesized argument list.
            if peek() == "(" {
                _ = advance()
                var depth = 1
                while depth > 0 && !isAtEnd {
                    let inner = advance()
                    if inner == "(" { depth += 1 }
                    if inner == ")" { depth -= 1 }
                }
            }

        // # directives (#Preview, #if, etc.) — skip the token
        case "#":
            while peek().isLetter || peek().isNumber || peek() == "_" {
                _ = advance()
            }

        // Backslash: keypath syntax (\.self, \.id, \.1)
        // Emit as dot + identifier so `\.self` becomes `.self` (the `\` is consumed)
        case "\\":
            if peek() == "." {
                _ = advance() // consume the `.`
                // Emit a dot token, then let the next scan pick up the identifier
                addToken(.dot)
            }
            // bare `\` without `.` — skip silently

        default:
            if c.isNumber {
                try scanNumber()
            } else if c.isLetter || c == "_" {
                scanIdentifier()
            } else {
                throw LexerError.unexpectedCharacter(c, line: line, column: column)
            }
        }
    }
    
    private func scanBlockComment() throws {
        var depth = 1
        while depth > 0 && !isAtEnd {
            let c = advance()
            if c == "\n" {
                line += 1
                column = 1
            } else if c == "/" && match("*") {
                depth += 1
            } else if c == "*" && match("/") {
                depth -= 1
            }
        }
    }
    
    private func scanString() throws {
        let startLine = line

        // First pass: collect raw characters and detect interpolation
        var hasInterpolation = false
        var rawChars: [Character] = []

        while peek() != "\"" && !isAtEnd {
            if peek() == "\n" {
                line += 1
                column = 1
            }
            if peek() == "\\" {
                if peekNext() == "(" {
                    hasInterpolation = true
                    // Consume \(
                    rawChars.append(advance()) // '\'
                    rawChars.append(advance()) // '('
                    // Consume until matching ')'
                    var depth = 1
                    while depth > 0 && !isAtEnd {
                        let c = advance()
                        rawChars.append(c)
                        if c == "(" { depth += 1 }
                        if c == ")" { depth -= 1 }
                    }
                    continue
                } else if peekNext() == "\"" {
                    // Escaped quote
                    rawChars.append(advance()) // '\'
                    rawChars.append(advance()) // '"'
                    continue
                }
            }
            rawChars.append(advance())
        }

        if isAtEnd {
            throw LexerError.unterminatedString(line: startLine)
        }

        // Closing quote
        _ = advance()

        if hasInterpolation {
            // Parse the raw characters into interpolation parts
            let parts = parseInterpolationParts(rawChars)
            addToken(.interpolatedString(parts: parts))
        } else {
            // Plain string — process escape sequences
            let value = String(rawChars)
            let processed = value
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\t", with: "\t")
                .replacingOccurrences(of: "\\\\", with: "\\")
            addToken(.string(processed))
        }
    }

    /// Split raw characters from an interpolated string into literal/expression parts
    private func parseInterpolationParts(_ chars: [Character]) -> [InterpolationPart] {
        var parts: [InterpolationPart] = []
        var i = 0
        var currentLiteral: [Character] = []

        while i < chars.count {
            if chars[i] == "\\" && i + 1 < chars.count && chars[i + 1] == "(" {
                // Flush any accumulated literal
                if !currentLiteral.isEmpty {
                    let text = String(currentLiteral)
                        .replacingOccurrences(of: "\\\"", with: "\"")
                        .replacingOccurrences(of: "\\n", with: "\n")
                        .replacingOccurrences(of: "\\t", with: "\t")
                        .replacingOccurrences(of: "\\\\", with: "\\")
                    parts.append(InterpolationPart(isExpression: false, content: text))
                    currentLiteral = []
                }
                // Skip \(
                i += 2
                // Collect expression content until matching )
                var depth = 1
                var exprChars: [Character] = []
                while i < chars.count && depth > 0 {
                    let c = chars[i]
                    if c == "(" { depth += 1 }
                    if c == ")" { depth -= 1 }
                    if depth > 0 {
                        exprChars.append(c)
                    }
                    i += 1
                }
                let exprContent = String(exprChars).trimmingCharacters(in: .whitespaces)
                parts.append(InterpolationPart(isExpression: true, content: exprContent))
            } else {
                currentLiteral.append(chars[i])
                i += 1
            }
        }

        // Flush remaining literal
        if !currentLiteral.isEmpty {
            let text = String(currentLiteral)
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\t", with: "\t")
                .replacingOccurrences(of: "\\\\", with: "\\")
            parts.append(InterpolationPart(isExpression: false, content: text))
        }

        return parts
    }
    
    private func scanNumber() throws {
        while peek().isNumber {
            _ = advance()
        }
        
        // Decimal part
        if peek() == "." && peekNext().isNumber {
            _ = advance() // consume "."
            while peek().isNumber {
                _ = advance()
            }
        }
        
        let numberString = String(source[start..<current])
        guard let value = Double(numberString) else {
            throw LexerError.invalidNumber(numberString, line: line)
        }
        
        addToken(.number(value))
    }
    
    private func scanIdentifier() {
        while peek().isLetter || peek().isNumber || peek() == "_" {
            _ = advance()
        }
        
        let text = String(source[start..<current])
        
        // Check for keywords
        if let keyword = Keyword(rawValue: text) {
            if keyword == .true {
                addToken(.boolean(true))
            } else if keyword == .false {
                addToken(.boolean(false))
            } else {
                addToken(.keyword(keyword))
            }
        } else {
            addToken(.identifier(text))
        }
    }
    
    // MARK: - Helpers
    
    private var isAtEnd: Bool {
        current >= source.endIndex
    }
    
    @discardableResult
    private func advance() -> Character {
        let c = source[current]
        current = source.index(after: current)
        column += 1
        return c
    }
    
    private func peek() -> Character {
        guard !isAtEnd else { return "\0" }
        return source[current]
    }
    
    private func peekNext() -> Character {
        let nextIndex = source.index(after: current)
        guard nextIndex < source.endIndex else { return "\0" }
        return source[nextIndex]
    }
    
    private func match(_ expected: Character) -> Bool {
        guard !isAtEnd else { return false }
        guard source[current] == expected else { return false }
        current = source.index(after: current)
        column += 1
        return true
    }
    
    private func addToken(_ type: TokenType) {
        tokens.append(Token(type: type, line: line, column: column))
    }
}
