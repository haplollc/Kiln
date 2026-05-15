//
//  Token.swift
//  SwiftRunner
//
//  Created by Claw on 2/21/26.
//

import Foundation

/// A part of an interpolated string — either literal text or an expression substring
public struct InterpolationPart: Equatable {
    public let isExpression: Bool
    public let content: String
    public init(isExpression: Bool, content: String) {
        self.isExpression = isExpression
        self.content = content
    }
}

/// Token types for the Swift lexer
public enum TokenType: Equatable {
    // Literals
    case string(String)
    case interpolatedString(parts: [InterpolationPart])
    case number(Double)
    case boolean(Bool)
    
    // Identifiers & Keywords
    case identifier(String)
    case bindingIdentifier(String)  // $name
    case keyword(Keyword)
    case attribute(String)           // @MainActor, @ViewBuilder, @unknown, etc.
    
    // Punctuation
    case leftParen       // (
    case rightParen      // )
    case leftBrace       // {
    case rightBrace      // }
    case leftBracket     // [
    case rightBracket    // ]
    case comma           // ,
    case colon           // :
    case dot             // .
    case semicolon       // ;
    case questionMark    // ?
    case nilCoalescing   // ??
    case halfOpenRange   // ..<
    case closedRange     // ...
    
    // Operators
    case equals          // =
    case plus            // +
    case minus           // -
    case star            // *
    case slash           // /
    case percent         // %

    // Compound assignment
    case plusEquals       // +=
    case minusEquals     // -=
    case starEquals      // *=
    case slashEquals     // /=
    
    // Comparison
    case equalEqual      // ==
    case notEqual        // !=
    case lessThan        // <
    case greaterThan     // >
    case lessEqual       // <=
    case greaterEqual    // >=
    
    // Logical
    case and             // &&
    case or              // ||
    case not             // !
    
    // Special
    case newline
    case eof
}

/// Swift keywords we support
public enum Keyword: String, CaseIterable {
    // Declarations
    case `let` = "let"
    case `var` = "var"
    case `func` = "func"
    case `struct` = "struct"
    case `enum` = "enum"
    case `extension` = "extension"
    case `protocol` = "protocol"

    // Control flow
    case `if` = "if"
    case `else` = "else"
    case `for` = "for"
    case `in` = "in"
    case `while` = "while"
    case `return` = "return"
    case `switch` = "switch"
    case `case` = "case"
    case `default` = "default"
    case `guard` = "guard"
    case `defer` = "defer"

    // Error handling
    case `do` = "do"
    case `catch` = "catch"
    case `try` = "try"
    case `throws` = "throws"
    case `throw` = "throw"

    // Concurrency (context-sensitive in Swift, but we treat them as keywords)
    case async = "async"
    case await = "await"

    // Booleans
    case `true` = "true"
    case `false` = "false"

    // Other
    case `nil` = "nil"
    case `self` = "self"
}

/// A token with its type and source location
public struct Token: Equatable {
    public let type: TokenType
    public let line: Int
    public let column: Int
    
    public init(type: TokenType, line: Int = 0, column: Int = 0) {
        self.type = type
        self.line = line
        self.column = column
    }
}

extension Token: CustomStringConvertible {
    public var description: String {
        switch type {
        case .string(let s): return "STRING(\"\(s)\")"
        case .interpolatedString(let parts):
            let desc = parts.map { $0.isExpression ? "\\(\($0.content))" : $0.content }.joined()
            return "INTERP(\"\(desc)\")"
        case .number(let n): return "NUMBER(\(n))"
        case .boolean(let b): return "BOOL(\(b))"
        case .identifier(let id): return "ID(\(id))"
        case .bindingIdentifier(let id): return "BIND($\(id))"
        case .keyword(let kw): return "KEYWORD(\(kw.rawValue))"
        case .attribute(let name): return "ATTR(@\(name))"
        case .leftParen: return "("
        case .rightParen: return ")"
        case .leftBrace: return "{"
        case .rightBrace: return "}"
        case .leftBracket: return "["
        case .rightBracket: return "]"
        case .comma: return ","
        case .colon: return ":"
        case .dot: return "."
        case .semicolon: return ";"
        case .questionMark: return "?"
        case .nilCoalescing: return "??"
        case .halfOpenRange: return "..<"
        case .closedRange: return "..."
        case .equals: return "="
        case .plus: return "+"
        case .minus: return "-"
        case .star: return "*"
        case .slash: return "/"
        case .percent: return "%"
        case .plusEquals: return "+="
        case .minusEquals: return "-="
        case .starEquals: return "*="
        case .slashEquals: return "/="
        case .equalEqual: return "=="
        case .notEqual: return "!="
        case .lessThan: return "<"
        case .greaterThan: return ">"
        case .lessEqual: return "<="
        case .greaterEqual: return ">="
        case .and: return "&&"
        case .or: return "||"
        case .not: return "!"
        case .newline: return "NEWLINE"
        case .eof: return "EOF"
        }
    }

    /// Human-readable description for error messages
    public var readableDescription: String {
        switch type {
        case .string(let s): return "string \"\(s.prefix(30))\(s.count > 30 ? "..." : "")\""
        case .interpolatedString: return "interpolated string"
        case .number(let n):
            return n == floor(n) ? "number '\(Int(n))'" : "number '\(n)'"
        case .boolean(let b): return "'\(b)'"
        case .identifier(let id): return "'\(id)'"
        case .bindingIdentifier(let id): return "'$\(id)'"
        case .keyword(let kw): return "keyword '\(kw.rawValue)'"
        case .attribute(let name): return "attribute '@\(name)'"
        case .leftParen: return "'('"
        case .rightParen: return "')'"
        case .leftBrace: return "'{'"
        case .rightBrace: return "'}'"
        case .leftBracket: return "'['"
        case .rightBracket: return "']'"
        case .comma: return "','"
        case .colon: return "':'"
        case .dot: return "'.'"
        case .semicolon: return "';'"
        case .questionMark: return "'?'"
        case .nilCoalescing: return "'??'"
        case .halfOpenRange: return "'..<'"
        case .closedRange: return "'...'"
        case .equals: return "'='"
        case .plus: return "'+'"
        case .minus: return "'-'"
        case .star: return "'*'"
        case .slash: return "'/'"
        case .percent: return "'%'"
        case .plusEquals: return "'+='"
        case .minusEquals: return "'-='"
        case .starEquals: return "'*='"
        case .slashEquals: return "'/='"
        case .equalEqual: return "'=='"
        case .notEqual: return "'!='"
        case .lessThan: return "'<'"
        case .greaterThan: return "'>'"
        case .lessEqual: return "'<='"
        case .greaterEqual: return "'>='"
        case .and: return "'&&'"
        case .or: return "'||'"
        case .not: return "'!'"
        case .newline: return "end of line"
        case .eof: return "end of input"
        }
    }
}
