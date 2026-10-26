//
//  KELexer.swift
//  Kiln engine 2
//
//  Swift source → tokens. Keeps the whitespace facts Swift's grammar depends
//  on: whether a token follows a space or a newline decides prefix vs. binary
//  operators, whether `(` / `{` continue the previous expression, and where
//  statements end.
//

import Foundation

struct KEToken: CustomStringConvertible {
    enum Kind: Equatable {
        case ident(String)        // identifiers and keywords, `$name`, `$0`
        case int(Int)
        case double(Double)
        case string([KEStrPart], multiline: Bool)
        case op(String)           // operator character runs: + - == ?? ..< ...
        case punct(Character)     // ( ) [ ] { } , : ; . @ # \
        case eof
    }
    var kind: Kind
    var line: Int
    var col: Int
    /// Whitespace or a line start immediately precedes the token.
    var spaceBefore = false
    /// A newline (or comment containing one) precedes the token.
    var newlineBefore = false
    /// Whitespace or a newline immediately follows the token.
    var spaceAfter = false

    var description: String {
        switch kind {
        case .ident(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .string: return "string literal"
        case .op(let o): return o
        case .punct(let c): return String(c)
        case .eof: return "end of file"
        }
    }

    var identValue: String? { if case .ident(let s) = kind { return s }; return nil }
    var opValue: String? { if case .op(let s) = kind { return s }; return nil }
    func isPunct(_ c: Character) -> Bool { if case .punct(let p) = kind { return p == c }; return false }
    func isOp(_ o: String) -> Bool { if case .op(let p) = kind { return p == o }; return false }
    func isIdent(_ s: String) -> Bool { if case .ident(let p) = kind { return p == s }; return false }
}

enum KEStrPart: Equatable {
    case text(String)
    /// The source between `\(` and `)`, parsed later as call arguments so
    /// SwiftUI's `"\(value, specifier: "%.2f")"` works.
    case interp(String, line: Int)
}

struct KESyntaxError: Error, CustomStringConvertible {
    let message: String
    let line: Int
    let col: Int
    var description: String { "Line \(line): \(message)" }
}

struct KELexer {
    private let chars: [Character]
    private var i = 0
    private var line = 1
    private var col = 1
    private let lineOffset: Int

    init(_ source: String, lineOffset: Int = 0) {
        self.chars = Array(source)
        self.lineOffset = lineOffset
    }

    private static let opChars: Set<Character> = ["/", "=", "-", "+", "!", "*", "%", "<", ">", "&", "|", "^", "~", "?"]

    private func peek(_ o: Int = 0) -> Character? { i + o < chars.count ? chars[i + o] : nil }

    private mutating func advance() {
        if chars[i] == "\n" { line += 1; col = 1 } else { col += 1 }
        i += 1
    }

    mutating func tokenize() throws -> [KEToken] {
        var tokens: [KEToken] = []
        var sawSpace = true
        var sawNewline = true
        while true {
            // Whitespace and comments.
            while let c = peek() {
                if c == "\n" { sawNewline = true; sawSpace = true; advance() }
                else if c.isWhitespace { sawSpace = true; advance() }
                else if c == "/", peek(1) == "/" {
                    while let d = peek(), d != "\n" { _ = d; advance() }
                } else if c == "/", peek(1) == "*" {
                    var depth = 0
                    repeat {
                        if peek() == "/", peek(1) == "*" { depth += 1; advance(); advance() }
                        else if peek() == "*", peek(1) == "/" { depth -= 1; advance(); advance() }
                        else if peek() != nil { if peek() == "\n" { sawNewline = true }; advance() }
                        else { break }
                    } while depth > 0
                    sawSpace = true
                } else { break }
            }
            if !tokens.isEmpty { tokens[tokens.count - 1].spaceAfter = sawSpace }
            guard let c = peek() else {
                tokens.append(KEToken(kind: .eof, line: line + lineOffset, col: col, spaceBefore: true, newlineBefore: true, spaceAfter: true))
                return tokens
            }
            let startLine = line + lineOffset, startCol = col
            var tok = KEToken(kind: .eof, line: startLine, col: startCol, spaceBefore: sawSpace, newlineBefore: sawNewline)
            sawSpace = false
            sawNewline = false

            if c == "\"" || (c == "#" && (peek(1) == "\"" || (peek(1) == "#" && peek(2) == "\""))) {
                tok.kind = try lexString()
            } else if c.isNumber {
                tok.kind = try lexNumber()
            } else if c.isLetter || c == "_" || c == "$" {
                var s = String(c)
                advance()
                while let d = peek(), d.isLetter || d.isNumber || d == "_" { s.append(d); advance() }
                tok.kind = .ident(s)
            } else if c == "`" {
                advance()
                var s = ""
                while let d = peek(), d != "`" { s.append(d); advance() }
                if peek() == "`" { advance() }
                tok.kind = .ident(s)
            } else if c == "." && peek(1) == "." && (peek(2) == "." || peek(2) == "<") {
                let third = peek(2)!
                advance(); advance(); advance()
                tok.kind = .op(third == "." ? "..." : "..<")
            } else if Self.opChars.contains(c) {
                var s = String(c)
                advance()
                if c == "?" {
                    // `??` and `??=` glue; `?.`, `x?` and `a ? b : c` stay single so
                    // the parser can tell them apart by spacing.
                    if peek() == "?" { s.append("?"); advance(); if peek() == "=" { s.append("="); advance() } }
                } else if c == "!" {
                    if peek() == "=" { s.append("="); advance(); if peek() == "=" { s.append("="); advance() } }
                } else {
                    while let d = peek(), Self.opChars.contains(d), d != "?", d != "!" {
                        if d == "/", peek(1) == "/" || peek(1) == "*" { break }   // a comment follows
                        s.append(d); advance()
                    }
                }
                tok.kind = .op(s)
            } else if "()[]{},:;.@#\\".contains(c) {
                advance()
                tok.kind = .punct(c)
            } else {
                throw KESyntaxError(message: "unexpected character '\(c)'", line: startLine, col: startCol)
            }
            tokens.append(tok)
        }
    }

    private mutating func lexNumber() throws -> KEToken.Kind {
        var s = ""
        if peek() == "0", let x = peek(1), "xbo".contains(x) {
            advance(); advance()
            let radix = x == "x" ? 16 : (x == "b" ? 2 : 8)
            while let d = peek(), d.isHexDigit || d == "_" { if d != "_" { s.append(d) }; advance() }
            return .int(Int(s, radix: radix) ?? 0)
        }
        var isDouble = false
        while let d = peek(), d.isNumber || d == "_" { if d != "_" { s.append(d) }; advance() }
        if peek() == ".", let n = peek(1), n.isNumber {
            isDouble = true
            s.append("."); advance()
            while let d = peek(), d.isNumber || d == "_" { if d != "_" { s.append(d) }; advance() }
        }
        if let e = peek(), e == "e" || e == "E", let n = peek(1), n.isNumber || n == "-" || n == "+" {
            isDouble = true
            s.append("e"); advance()
            if peek() == "-" || peek() == "+" { s.append(peek()!); advance() }
            while let d = peek(), d.isNumber { s.append(d); advance() }
        }
        if isDouble { return .double(Double(s) ?? 0) }
        if let v = Int(s) { return .int(v) }
        return .double(Double(s) ?? 0)
    }

    private mutating func lexString() throws -> KEToken.Kind {
        let startLine = line + lineOffset
        var hashes = 0
        while peek() == "#" { hashes += 1; advance() }
        let multiline = peek() == "\"" && peek(1) == "\"" && peek(2) == "\""
        if multiline { advance(); advance(); advance() } else { advance() }
        var parts: [KEStrPart] = []
        var text = ""
        func closes(_ lexer: KELexer) -> Bool {
            if multiline {
                guard lexer.peek() == "\"", lexer.peek(1) == "\"", lexer.peek(2) == "\"" else { return false }
                for h in 0..<hashes where lexer.peek(3 + h) != "#" { return false }
                return true
            }
            guard lexer.peek() == "\"" else { return false }
            for h in 0..<hashes where lexer.peek(1 + h) != "#" { return false }
            return true
        }
        while true {
            guard let c = peek() else { throw KESyntaxError(message: "unterminated string", line: startLine, col: 0) }
            if closes(self) {
                if multiline { advance(); advance(); advance() } else { advance() }
                for _ in 0..<hashes { advance() }
                break
            }
            if c == "\n" && !multiline { throw KESyntaxError(message: "unterminated string", line: startLine, col: 0) }
            if c == "\\" {
                // With #"..."#, escapes need the same number of #.
                var k = 1
                var ok = true
                for _ in 0..<hashes { if peek(k) == "#" { k += 1 } else { ok = false; break } }
                if !ok { text.append(c); advance(); continue }
                for _ in 0..<k { advance() }
                guard let e = peek() else { break }
                switch e {
                case "n": text.append("\n"); advance()
                case "t": text.append("\t"); advance()
                case "r": text.append("\r"); advance()
                case "0": text.append("\0"); advance()
                case "\\": text.append("\\"); advance()
                case "\"": text.append("\""); advance()
                case "'": text.append("'"); advance()
                case "u":
                    advance()
                    if peek() == "{" {
                        advance()
                        var hex = ""
                        while let d = peek(), d != "}" { hex.append(d); advance() }
                        advance()
                        if let v = UInt32(hex, radix: 16), let sc = Unicode.Scalar(v) { text.append(Character(sc)) }
                    }
                case "(":
                    advance()
                    var depth = 1
                    var inner = ""
                    let iline = line + lineOffset
                    var inString = false
                    while let d = peek() {
                        if inString {
                            if d == "\\" { inner.append(d); advance(); if let n = peek() { inner.append(n); advance() }; continue }
                            if d == "\"" { inString = false }
                        } else {
                            if d == "\"" { inString = true }
                            if d == "(" { depth += 1 }
                            if d == ")" { depth -= 1; if depth == 0 { advance(); break } }
                        }
                        inner.append(d); advance()
                    }
                    if !text.isEmpty { parts.append(.text(text)); text = "" }
                    parts.append(.interp(inner, line: iline))
                case "\n" where multiline:
                    advance()   // line continuation
                    while let d = peek(), d == " " || d == "\t" { _ = d; advance() }
                default:
                    text.append(e); advance()
                }
                continue
            }
            text.append(c)
            advance()
        }
        if !text.isEmpty { parts.append(.text(text)) }
        if multiline { parts = Self.dedentMultiline(parts) }
        return .string(parts, multiline: multiline)
    }

    /// Multi-line literals drop the first newline, the last line's indentation
    /// (the closing delimiter's), and that indentation from every line.
    private static func dedentMultiline(_ parts: [KEStrPart]) -> [KEStrPart] {
        var joined = ""
        var marks: [(Int, KEStrPart)] = []
        for p in parts {
            if case .text(let t) = p { joined += t } else { marks.append((joined.count, p)); joined += "\u{FFFC}" }
        }
        var lines = joined.components(separatedBy: "\n")
        if let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        var indent = 0
        if let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            indent = last.count
            lines.removeLast()
        }
        let body = lines.map { l -> String in
            var s = Substring(l)
            var n = 0
            while n < indent, let f = s.first, f == " " || f == "\t" { s = s.dropFirst(); n += 1 }
            return String(s)
        }.joined(separator: "\n")
        var out: [KEStrPart] = []
        var buf = ""
        var interpIndex = 0
        for ch in body {
            if ch == "\u{FFFC}", interpIndex < marks.count {
                if !buf.isEmpty { out.append(.text(buf)); buf = "" }
                out.append(marks[interpIndex].1)
                interpIndex += 1
            } else { buf.append(ch) }
        }
        if !buf.isEmpty { out.append(.text(buf)) }
        return out
    }
}
