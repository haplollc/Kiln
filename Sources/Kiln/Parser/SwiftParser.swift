//
//  SwiftParser.swift
//  SwiftRunner
//
//  Created by Claw on 2/21/26.
//

import Foundation

/// Errors that can occur during parsing
public enum ParserError: LocalizedError {
    case unexpectedToken(Token, expected: String, hint: String? = nil)
    case unexpectedEndOfInput
    case unsupportedConstruct(String, line: Int? = nil)

    /// The source line where the error occurred
    public var line: Int? {
        switch self {
        case .unexpectedToken(let token, _, _): return token.line
        case .unexpectedEndOfInput: return nil
        case .unsupportedConstruct(_, let line): return line
        }
    }

    public var errorDescription: String? {
        switch self {
        case .unexpectedToken(let token, let expected, let hint):
            var msg = "Line \(token.line): unexpected \(token.readableDescription), expected \(expected)"
            if let hint = hint {
                msg += " — \(hint)"
            }
            return msg
        case .unexpectedEndOfInput:
            return "Unexpected end of input — the code appears to be incomplete"
        case .unsupportedConstruct(let msg, let line):
            if let line = line {
                return "Line \(line): \(msg)"
            }
            return msg
        }
    }
}

/// Parses tokens into ViewNode AST
/// Stored struct definition for custom view support.
public struct ParsedStruct {
    public let properties: [String]  // init parameter names
    public let body: ViewNode
}

public final class SwiftParser {
    private var tokens: [Token] = []
    private var current: Int = 0

    /// Custom structs parsed during this session, keyed by struct name.
    public var parsedStructs: [String: ParsedStruct] = [:]

    /// Plan 5 capstone: per-struct field-type schemas for propagating `_type` tags
    /// through decoded JSON. Keyed by struct name → field name → inner type name
    /// (unwrapping `[T]?`, `[T]`, `T?` forms).
    public var parsedSchemas: [String: [String: String]] = [:]

    public init() {}
    
    /// Parse tokens into a ViewNode
    public func parse(_ tokens: [Token]) throws -> ViewNode {
        self.tokens = tokens
        self.current = 0

        print("[SwiftParser] parse() called with \(tokens.count) tokens")

        var statements: [ViewNode] = []

        while !isAtEnd {
            skipNewlines()
            if !isAtEnd {
                let node = try parseStatement()
                print("[SwiftParser] parseStatement() returned: \(node)")
                if case .empty = node {
                    continue
                }
                statements.append(node)
            }
        }

        let preResolve: ViewNode
        if statements.count == 1 {
            preResolve = statements[0]
        } else {
            preResolve = .block(statements)
        }
        // Forward-reference pass: structs defined later in the file aren't in
        // `parsedStructs` when their earlier callsites are parsed, so those
        // sites emit a plain `.functionCall(name, args)` that the renderer
        // can't recognize. Now that every struct in the source has been
        // collected, walk the AST and inline any `.functionCall` whose name
        // matches a registered struct.
        let result = resolveForwardStructReferences(preResolve)
        print("[SwiftParser] Final AST: \(result)")
        return result
    }

    /// Recursively replace `.functionCall(name, args)` nodes whose `name` is
    /// a registered custom view in `parsedStructs` with the inlined struct
    /// expansion (`.block([init-assignments, body])`). Same expansion shape
    /// the in-line path uses (see line ~1953), just applied post-hoc so the
    /// order in which structs and their callsites appear in source doesn't
    /// matter.
    private func resolveForwardStructReferences(_ node: ViewNode) -> ViewNode {
        func r(_ n: ViewNode) -> ViewNode { resolveForwardStructReferences(n) }
        switch node {
        case .functionCall(let name, let arguments):
            let resolvedArgs = arguments.map { Argument(label: $0.label, value: r($0.value)) }
            if let customStruct = parsedStructs[name] {
                var assignments: [ViewNode] = []
                for arg in resolvedArgs where arg.label != nil {
                    assignments.append(.assignment(name: arg.label!, isVar: true, value: arg.value))
                }
                for (i, propName) in customStruct.properties.enumerated() where i < resolvedArgs.count {
                    if resolvedArgs[i].label == nil {
                        assignments.append(.assignment(name: propName, isVar: true, value: resolvedArgs[i].value))
                    }
                }
                // Recurse into the inlined body too — it may itself contain
                // forward references to other later-defined structs.
                let resolvedBody = r(customStruct.body)
                return assignments.isEmpty ? resolvedBody : .block(assignments + [resolvedBody])
            }
            return .functionCall(name: name, arguments: resolvedArgs)

        case .block(let stmts):
            return .block(stmts.map(r))
        case .modified(let v, let mods):
            return .modified(view: r(v), modifiers: mods)
        case .vStack(let sp, let al, let ch):
            return .vStack(spacing: sp, alignment: al, children: ch.map(r))
        case .hStack(let sp, let al, let ch):
            return .hStack(spacing: sp, alignment: al, children: ch.map(r))
        case .zStack(let al, let ch):
            return .zStack(alignment: al, children: ch.map(r))
        case .scrollView(let axis, let ind, let content):
            return .scrollView(axis: axis, showsIndicators: ind, content: r(content))
        case .conditional(let cond, let then_, let else_):
            return .conditional(condition: r(cond), thenBody: r(then_), elseBody: else_.map(r))
        case .ternary(let cond, let t, let f):
            return .ternary(condition: r(cond), trueExpr: r(t), falseExpr: r(f))
        case .navigationStack(let ch):
            return .navigationStack(children: ch.map(r))
        case .navigationLink(let label, let dest):
            return .navigationLink(label: r(label), destination: r(dest))
        case .forEach(let range, let varname, let body):
            return .forEach(range: range, variable: varname, body: r(body))
        case .forEachCollection(let coll, let varname, let body):
            return .forEachCollection(collection: r(coll), variable: varname, body: r(body))
        case .lazyVGrid(let cols, let sp, let content):
            return .lazyVGrid(columns: cols.map(r), spacing: sp, content: r(content))
        case .lazyHGrid(let rows, let sp, let content):
            return .lazyHGrid(rows: rows.map(r), spacing: sp, content: r(content))
        case .button(let label, let action):
            return .button(label: r(label), action: action.map(r))
        case .assignment(let name, let isVar, let value):
            return .assignment(name: name, isVar: isVar, value: r(value))
        case .stateInit(let name, let value):
            return .stateInit(name: name, value: r(value))
        case .compoundAssignment(let variable, let op, let value):
            return .compoundAssignment(variable: variable, op: op, value: r(value))
        case .returnStmt(let v):
            return .returnStmt(v.map(r))
        case .functionDecl(let name, let params, let body, let isAsync, let isThrowing):
            return .functionDecl(name: name, parameters: params, body: r(body), isAsync: isAsync, isThrowing: isThrowing)
        case .extensionDeclaration(let target, let members):
            return .extensionDeclaration(target: target, members: members.map(r))
        case .enumDeclaration(let name, let cases, let members):
            return .enumDeclaration(name: name, cases: cases, members: members.map(r))
        case .guardExpr(let cond, let elseBlock):
            return .guardExpr(condition: r(cond), elseBlock: r(elseBlock))
        case .guardLet(let varname, let val, let elseBlock):
            return .guardLet(variable: varname, value: r(val), elseBlock: r(elseBlock))
        case .deferBlock(let body):
            return .deferBlock(r(body))
        case .doCatch(let body, let clauses):
            return .doCatch(body: r(body), clauses: clauses.map { CatchClause(binding: $0.binding, body: r($0.body)) })
        case .switchStmt(let scrut, let cases, let def):
            return .switchStmt(
                scrutinee: r(scrut),
                cases: cases.map { SwitchCase(pattern: $0.pattern, body: r($0.body)) },
                defaultBody: def.map(r)
            )
        case .throwStmt(let v):
            return .throwStmt(r(v))
        case .binary(let l, let op, let rt):
            return .binary(left: r(l), op: op, right: r(rt))
        case .propertyAccess(let obj, let prop):
            return .propertyAccess(object: r(obj), property: prop)
        case .methodCall(let obj, let method, let args):
            return .methodCall(
                object: r(obj),
                method: method,
                arguments: args.map { Argument(label: $0.label, value: r($0.value)) }
            )
        case .subscriptAccess(let obj, let idx):
            return .subscriptAccess(object: r(obj), index: r(idx))
        case .arrayLiteral(let elems):
            return .arrayLiteral(elems.map(r))
        case .stringInterpolation(let parts):
            return .stringInterpolation(parts.map { part in
                if case .expression(let e) = part { return .expression(r(e)) }
                return part
            })
        case .tupleBinding(let names, let value):
            return .tupleBinding(names: names, value: r(value))
        case .propertyAssignment(let target, let op, let value):
            return .propertyAssignment(target: r(target), op: op, value: r(value))
        case .closure(let params, let body):
            return .closure(parameters: params, body: r(body))
        case .geometryReader(let varname, let body):
            return .geometryReader(variable: varname, body: r(body))
        case .asyncImagePhased(let urlExpr, let empty, let succ, let fail, let bind):
            return .asyncImagePhased(
                urlExpression: r(urlExpr),
                emptyBranch: empty.map(r),
                successBranch: succ.map(r),
                failureBranch: fail.map(r),
                imageBinding: bind
            )
        case .asyncImageDynamic(let urlExpr):
            return .asyncImageDynamic(urlExpression: r(urlExpr))
        default:
            // Lifecycle/presentation modifiers (.onAppear, .taskAction, .sheet,
            // .alert, …) live on ViewModifier, not ViewNode, and their bodies
            // can in principle contain forward struct references too. For now
            // those are reached via `.modified(view: …)` descent on the view
            // they decorate; the modifier value itself isn't walked. Wire that
            // through here if/when a real callsite needs it.
            // Leaves and nodes whose substructure can't contain a struct callsite
            // (literals, bare identifiers, primitive shapes, modifier values).
            return node
        }
    }
    
    // MARK: - Statement Parsing
    
    private func parseStatement() throws -> ViewNode {
        skipNewlines()

        // Consume leading attributes (@MainActor, @ViewBuilder, @available(...), etc.)
        // transparently — they have no runtime effect in SwiftRunner at this stage.
        while case .attribute = peek().type {
            _ = advance()
            skipNewlines()
        }

        // Import statement (skip it)
        if case .identifier("import") = peek().type {
            return try parseImportStatement()
        }

        // Skip access control + declaration modifiers before struct/enum/extension/func/var.
        // Examples: `public struct`, `private static func`, `@MainActor private func`.
        if case .identifier(let mod) = peek().type,
           ["public", "private", "internal", "fileprivate", "open",
            "static", "final", "mutating", "nonmutating", "override"].contains(mod) {
            let saved = current
            _ = advance()
            skipNewlines()
            // Re-consume any attributes that appear between modifiers and the decl.
            while case .attribute = peek().type { _ = advance(); skipNewlines() }
            if check(.keyword(.struct)) { return try parseStructDeclaration() }
            if check(.keyword(.enum))   { return try parseEnumDeclaration() }
            if check(.keyword(.extension)) { return try parseExtensionDeclaration() }
            if check(.keyword(.func))   { return try skipFuncDeclaration() }
            if check(.keyword(.var)) || check(.keyword(.let)) {
                return try parseVariableDeclaration()
            }
            // Not a decl — restore and continue as expression
            current = saved
        }

        // Struct declaration — extract body view
        if check(.keyword(.struct)) {
            return try parseStructDeclaration()
        }

        // Enum declaration
        if check(.keyword(.enum)) {
            return try parseEnumDeclaration()
        }

        // Extension declaration
        if check(.keyword(.extension)) {
            return try parseExtensionDeclaration()
        }

        // Protocol declaration — skip body (not supported at runtime yet)
        if check(.keyword(.protocol)) {
            return try skipProtocolDeclaration()
        }

        // switch statement
        if check(.keyword(.switch)) {
            return try parseSwitchStatement()
        }

        // do { ... } catch { ... }
        if check(.keyword(.do)) {
            return try parseDoCatch()
        }

        // throw <expr>
        if check(.keyword(.throw)) {
            return try parseThrowStatement()
        }

        // guard let / guard <expr> else { ... }
        if check(.keyword(.guard)) {
            return try parseGuardStatement()
        }

        // defer { ... }
        if check(.keyword(.defer)) {
            return try parseDeferBlock()
        }

        // `return [<expr>]` — unwinds the enclosing function call scope.
        if check(.keyword(.return)) {
            _ = advance() // consume `return`
            if !check(.newline) && !check(.semicolon) && !check(.rightBrace)
                && !check(.keyword(.case)) && !check(.keyword(.default)) && !isAtEnd {
                let expr = try parseExpression()
                return .returnStmt(expr)
            }
            return .returnStmt(nil)
        }

        // Func declaration at top level — skip it
        if check(.keyword(.func)) {
            return try skipFuncDeclaration()
        }

        // Variable declaration
        if check(.keyword(.let)) || check(.keyword(.var)) {
            return try parseVariableDeclaration()
        }

        // Compound / property assignment. Accepts `name = …`, `name += …`,
        // `obj.prop = …`, `obj.a.b = …`, `arr[i] = …`.
        //
        // Strategy: do a cheap peek-ahead to see whether the current line has
        // an `=` / `+=` / ... at depth 0 before the next `{` or newline. Only
        // then do we consume an assignable LHS (which we build by a small local
        // parser that walks `.prop` / `[expr]` chains — no recursion into
        // parseConditionExpression which would loop for non-braced inputs).
        if case .identifier = peek().type, hasAssignOperatorBeforeBoundary() {
            let saved = current
            if let lhs = try? parseAssignableLHS(),
               check(.plusEquals) || check(.minusEquals)
                || check(.starEquals) || check(.slashEquals) || check(.equals) {
                let opToken = advance()
                let op: CompoundOp
                switch opToken.type {
                case .plusEquals: op = .plusAssign
                case .minusEquals: op = .minusAssign
                case .starEquals: op = .mulAssign
                case .slashEquals: op = .divAssign
                case .equals: op = .assign
                default: op = .assign
                }
                skipNewlines()
                let value = try parseExpression()
                if case .variable(let name) = lhs {
                    return .compoundAssignment(variable: name, op: op, value: value)
                }
                return .propertyAssignment(target: lhs, op: op, value: value)
            }
            current = saved
        }

        // if/else conditional view
        if check(.keyword(.if)) {
            return try parseIfElse()
        }

        // Expression statement
        return try parseExpression()
    }

    /// Parse `if condition { body } else { body }`
    private func parseIfElse() throws -> ViewNode {
        _ = advance() // consume "if"
        skipNewlines()

        // Handle `if let x = expr { ... }` — treat as `if expr != nil`.
        // Also handle `if let x = a, let y = b, cond { ... }` — multi-condition.
        // Swift 5.7 shorthand `if let foo { ... }` (no `= rhs`) is equivalent to
        // `if let foo = foo { ... }` — predicate becomes `foo != nil`.
        if check(.keyword(.let)) || check(.keyword(.var)) {
            // Track each `let name = expr` clause so we can prepend the
            // bindings as assignments to the then-body. Without this the
            // then-body sees `name` as undefined, e.g.
            //   `if let y = doc.first_publish_year { return "\(y)" }`
            // would interpolate "nil" because `y` was never bound.
            var bindings: [(name: String, value: ViewNode)] = []

            _ = advance() // consume let/var
            var bindingName: String? = nil
            if case .identifier(let name) = peek().type {
                bindingName = name
                _ = advance() // consume variable name
            }
            let valueExpr: ViewNode
            if check(.equals) {
                _ = advance() // consume =
                valueExpr = try parseConditionExpression()
            } else if let name = bindingName {
                // Shorthand: `if let foo { … }` — same-name unwrap.
                valueExpr = .variable(name)
            } else {
                valueExpr = try parseConditionExpression()
            }
            if let name = bindingName {
                bindings.append((name: name, value: valueExpr))
            }
            // Combine each condition clause into an AND chain; each `let x = y`
            // contributes a `y != nil` predicate.
            var condition: ViewNode = .binary(left: valueExpr, op: .notEqual, right: .literal(.nil))
            skipNewlines()
            while check(.comma) {
                _ = advance()
                skipNewlines()
                if check(.keyword(.let)) || check(.keyword(.var)) {
                    _ = advance()
                    var extraName: String? = nil
                    if case .identifier(let n) = peek().type {
                        extraName = n
                        _ = advance()
                    }
                    let extraValue: ViewNode
                    if check(.equals) {
                        _ = advance()
                        extraValue = try parseConditionExpression()
                    } else if let n = extraName {
                        extraValue = .variable(n)
                    } else {
                        extraValue = try parseConditionExpression()
                    }
                    if let n = extraName {
                        bindings.append((name: n, value: extraValue))
                    }
                    let extra: ViewNode = .binary(left: extraValue, op: .notEqual, right: .literal(.nil))
                    condition = .binary(left: condition, op: .and, right: extra)
                } else {
                    let extra = try parseConditionExpression()
                    condition = .binary(left: condition, op: .and, right: extra)
                }
                skipNewlines()
            }

            skipNewlines()
            guard check(.leftBrace) else {
                throw ParserError.unexpectedToken(peek(), expected: "'{'")
            }
            _ = advance()
            skipNewlines()
            let thenBody = try parseClosureBody()
            skipNewlines()
            guard check(.rightBrace) else {
                throw ParserError.unexpectedToken(peek(), expected: "'}'")
            }
            _ = advance()

            skipNewlines()
            var elseBody: ViewNode? = nil
            if check(.keyword(.else)) {
                _ = advance()
                skipNewlines()
                if check(.keyword(.if)) {
                    elseBody = try parseIfElse()
                } else {
                    guard check(.leftBrace) else {
                        throw ParserError.unexpectedToken(peek(), expected: "'{'")
                    }
                    _ = advance()
                    skipNewlines()
                    elseBody = try parseClosureBody()
                    skipNewlines()
                    guard check(.rightBrace) else {
                        throw ParserError.unexpectedToken(peek(), expected: "'}'")
                    }
                    _ = advance()
                }
            }

            // Wrap the then-body with assignments that bind each `let foo`
            // clause's name to its value-expression result. Skip same-name
            // shorthand (`if let foo` — `foo` is already bound to itself).
            let bindingAssignments: [ViewNode] = bindings.compactMap { binding in
                if case .variable(let v) = binding.value, v == binding.name {
                    return nil // shorthand — no rebinding needed
                }
                return ViewNode.assignment(name: binding.name, isVar: true, value: binding.value)
            }
            let wrappedThenBody: ViewNode
            if bindingAssignments.isEmpty {
                wrappedThenBody = thenBody
            } else if case .block(let stmts) = thenBody {
                wrappedThenBody = .block(bindingAssignments + stmts)
            } else {
                wrappedThenBody = .block(bindingAssignments + [thenBody])
            }

            return .conditional(condition: condition, thenBody: wrappedThenBody, elseBody: elseBody)
        }

        // Parse condition — use parseConditionExpression to avoid parsePrimary consuming the '{' as a trailing closure.
        let condition = try parseConditionExpression()

        skipNewlines()
        guard check(.leftBrace) else {
            throw ParserError.unexpectedToken(peek(), expected: "'{'")
        }
        _ = advance() // {
        skipNewlines()
        let thenBody = try parseClosureBody()
        skipNewlines()
        guard check(.rightBrace) else {
            throw ParserError.unexpectedToken(peek(), expected: "'}'")
        }
        _ = advance() // }

        // Optional else
        skipNewlines()
        var elseBody: ViewNode? = nil
        if check(.keyword(.else)) {
            _ = advance() // consume "else"
            skipNewlines()

            if check(.keyword(.if)) {
                // else if — recurse
                elseBody = try parseIfElse()
            } else {
                guard check(.leftBrace) else {
                    throw ParserError.unexpectedToken(peek(), expected: "'{'")
                }
                _ = advance() // {
                skipNewlines()
                elseBody = try parseClosureBody()
                skipNewlines()
                guard check(.rightBrace) else {
                    throw ParserError.unexpectedToken(peek(), expected: "'}'")
                }
                _ = advance() // }
            }
        }

        return .conditional(condition: condition, thenBody: thenBody, elseBody: elseBody)
    }

    /// Parse a condition expression for if/else/switch/guard, stopping before
    /// `{`, `else`, or a depth-0 `,`. Commas are boundaries so multi-clause
    /// `if let a = x, let b = y` and `guard let a = x, b > 0` parse each clause
    /// as its own expression without getting swallowed by parsePrimary's
    /// trailing-closure grab of `{`.
    private func parseConditionExpression() throws -> ViewNode {
        var condTokens: [Token] = []
        var depth = 0
        while !isAtEnd {
            let t = peek()
            if depth == 0 {
                if case .leftBrace = t.type { break }
                if case .keyword(.else) = t.type { break }
                if case .comma = t.type { break }
            }
            if case .leftParen = t.type { depth += 1 }
            if case .leftBracket = t.type { depth += 1 }
            if case .rightParen = t.type { depth -= 1 }
            if case .rightBracket = t.type { depth -= 1 }
            if case .newline = t.type { _ = advance(); continue }
            condTokens.append(advance())
        }
        condTokens.append(Token(type: .eof))

        let subParser = SwiftParser()
        return try subParser.parse(condTokens)
    }

    /// Skip a top-level func declaration
    private func skipFuncDeclaration() throws -> ViewNode {
        // Delegate to the real parser that captures the body so calls can execute it.
        return try parseFuncDeclaration()
    }

    /// Parse `func name(<params>) [async] [throws] [-> Type] { <body> }`.
    /// Captures name, parameters, and body into a `.functionDecl` node so the
    /// evaluator can register the function and call it later.
    private func parseFuncDeclaration() throws -> ViewNode {
        _ = advance() // consume `func`
        skipNewlines()

        // Function name
        var name = "<anonymous>"
        if case .identifier(let n) = peek().type {
            name = n
            _ = advance()
        }

        // Optional generic parameter list <T, U>
        if check(.lessThan) {
            var depth = 1
            _ = advance()
            while depth > 0 && !isAtEnd {
                if check(.lessThan) { depth += 1 }
                if check(.greaterThan) { depth -= 1 }
                _ = advance()
            }
        }

        // Parameter list
        var parameters: [FunctionParameter] = []
        if check(.leftParen) {
            _ = advance()
            skipNewlines()
            while !check(.rightParen) && !isAtEnd {
                parameters.append(try parseFunctionParameter())
                skipNewlines()
                if check(.comma) { _ = advance(); skipNewlines() }
            }
            if check(.rightParen) { _ = advance() }
        }

        // Optional effect modifiers + return type — all consumed up to `{`.
        var isAsync = false
        var isThrowing = false
        while !check(.leftBrace) && !isAtEnd {
            if check(.keyword(.async)) { isAsync = true; _ = advance(); continue }
            if check(.keyword(.throws)) { isThrowing = true; _ = advance(); continue }
            if case .identifier("rethrows") = peek().type { isThrowing = true; _ = advance(); continue }
            _ = advance()
        }

        // Body
        let body: ViewNode
        if check(.leftBrace) {
            body = try parseBraceBlock()
        } else {
            body = .empty
        }
        return .functionDecl(
            name: name,
            parameters: parameters,
            body: body,
            isAsync: isAsync,
            isThrowing: isThrowing
        )
    }

    /// Parse one parameter in a function declaration.
    /// Forms: `name: T`, `external internal: T`, `_ internal: T`, `name: T = default`.
    private func parseFunctionParameter() throws -> FunctionParameter {
        // First identifier (or `_`)
        var firstName: String? = nil
        if case .identifier(let n) = peek().type {
            firstName = n
            _ = advance()
        }

        var externalLabel: String? = nil
        var internalName: String = firstName ?? "_"

        // If the next token is another identifier before the `:`, we have a
        // two-name parameter (external + internal).
        if case .identifier(let second) = peek().type {
            externalLabel = (firstName == "_") ? nil : firstName
            internalName = second
            _ = advance()
        } else {
            // Single-name form — external label defaults to internal name.
            externalLabel = (firstName == "_") ? nil : firstName
            internalName = firstName ?? "_"
        }

        // Type annotation
        var typeName: String? = nil
        if check(.colon) {
            _ = advance()
            skipNewlines()
            typeName = try parseTypeAnnotationString()
        }

        // Default value — consume and discard (not used at runtime yet)
        if check(.equals) {
            _ = advance()
            skipNewlines()
            _ = try parseExpression()
        }

        return FunctionParameter(
            externalLabel: externalLabel,
            internalName: internalName,
            typeName: typeName
        )
    }

    /// Read a type annotation as a raw source-ish string until a param / return
    /// boundary (`,`, `)`, `=`, `->`, `{`, newline).
    private func parseTypeAnnotationString() throws -> String {
        var depth = 0
        var parts: [String] = []
        while !isAtEnd {
            let t = peek()
            if depth == 0 {
                switch t.type {
                case .comma, .rightParen, .equals, .leftBrace, .newline:
                    return parts.joined()
                case .minus:
                    // `->` is two tokens (minus + greaterThan) — stop before it.
                    if case .greaterThan = peekNext().type { return parts.joined() }
                default: break
                }
            }
            if check(.leftParen) || check(.leftBracket) || check(.lessThan) { depth += 1 }
            if check(.rightParen) || check(.rightBracket) || check(.greaterThan) {
                if depth == 0 { return parts.joined() }
                depth -= 1
            }
            parts.append(t.description)
            _ = advance()
        }
        return parts.joined()
    }
    
    /// Skip an `import Foo` statement
    private func parseImportStatement() throws -> ViewNode {
        _ = advance() // consume "import"
        // Skip everything until newline or EOF
        while !check(.newline) && !isAtEnd {
            _ = advance()
        }
        return .empty
    }

    /// Parse `struct Foo: View { var body: some View { ... } }`
    /// Extracts the view returned by `body` or `previews`.
    private func parseStructDeclaration() throws -> ViewNode {
        _ = advance() // consume "struct"

        // Skip struct name
        var structName = "<unknown>"
        if case .identifier(let name) = peek().type {
            structName = name
            _ = advance()
        }
        print("[SwiftParser] Parsing struct '\(structName)'")

        // Read protocol conformance (`: View`, `: PreviewProvider`, etc.)
        var isPreviewProvider = false
        if check(.colon) {
            _ = advance()
            while !check(.leftBrace) && !isAtEnd {
                if case .identifier(let proto) = peek().type,
                   proto == "PreviewProvider" || proto == "PreviewLayout" {
                    isPreviewProvider = true
                }
                _ = advance()
            }
        }

        // Skip PreviewProvider structs entirely — they're Xcode metadata, not renderable
        if isPreviewProvider {
            print("[SwiftParser] Skipping PreviewProvider struct '\(structName)'")
            if check(.leftBrace) {
                _ = advance()
                var depth = 1
                while depth > 0 && !isAtEnd {
                    if check(.leftBrace) { depth += 1 }
                    if check(.rightBrace) { depth -= 1 }
                    _ = advance()
                }
            }
            return .empty
        }

        guard check(.leftBrace) else {
            throw ParserError.unexpectedToken(peek(), expected: "'{'",
                hint: "expected opening brace for struct '\(structName)' body")
        }
        _ = advance() // consume opening {

        var bodyView: ViewNode? = nil
        var stateProperties: [ViewNode] = []
        // Plan 5: capture function members so they can be hoisted into the
        // runtime function table as `StructName.methodName`.
        var memberFuncs: [ViewNode] = []

        while !isAtEnd {
            skipNewlines()

            // End of struct
            if check(.rightBrace) {
                _ = advance()
                break
            }

            // Skip access control / declaration modifiers before `var`.
            // Property wrappers (@State, @Binding, @MainActor, @ViewBuilder, etc.)
            // arrive as .attribute(_) tokens — consume those too.
            let savedPos = current
            while true {
                if case .attribute = peek().type {
                    _ = advance()
                    skipNewlines()
                    continue
                }
                if case .identifier(let mod) = peek().type,
                   ["static", "private", "public", "internal", "fileprivate", "open",
                    "mutating", "nonmutating", "override"].contains(mod) {
                    _ = advance()
                    skipNewlines()
                    continue
                }
                break
            }

            // Look for `var body` or `var previews`
            if check(.keyword(.var)) || check(.keyword(.let)) {
                let isVar = check(.keyword(.var))
                _ = advance() // consume var/let

                if case .identifier(let propName) = peek().type,
                   propName == "body" || propName == "previews" {
                    print("[SwiftParser] Found '\(propName)' property in struct '\(structName)'")
                    _ = advance() // consume property name

                    // Skip type annotation `: some View`
                    if check(.colon) {
                        _ = advance()
                        while !check(.leftBrace) && !check(.rightBrace) && !isAtEnd {
                            _ = advance()
                        }
                    }

                    // Parse the computed property body
                    if check(.leftBrace) {
                        _ = advance() // consume {
                        skipNewlines()
                        bodyView = try parseClosureBody()
                        print("[SwiftParser] Parsed body view: \(bodyView as Any)")
                        skipNewlines()
                        if check(.rightBrace) {
                            _ = advance() // consume } of computed property
                        }
                        continue
                    } else {
                        print("[SwiftParser] WARNING: Expected '{' after type annotation, got \(peek())")
                    }
                } else if case .identifier(let propName) = peek().type {
                    // Non-body property (e.g. @State private var count = 0)
                    // Try to parse it as a state variable declaration
                    _ = advance() // consume property name

                    // Capture type annotation (used for JSON-decode tag propagation).
                    var capturedType: String? = nil
                    if check(.colon) {
                        _ = advance()
                        var tokens: [String] = []
                        while !check(.equals) && !check(.newline) && !check(.rightBrace) && !check(.leftBrace) && !isAtEnd {
                            if case .identifier(let s) = peek().type { tokens.append(s) }
                            _ = advance()
                        }
                        if let first = tokens.first {
                            capturedType = first
                        }
                    }
                    if let typeName = capturedType {
                        var schema = parsedSchemas[structName] ?? [:]
                        schema[propName] = typeName
                        parsedSchemas[structName] = schema
                    }

                    // Computed property: `var isValid: Bool { ... }` — capture
                    // the getter body as a zero-arg functionDecl so it can be
                    // hoisted as `StructName.propName` and dispatched when code
                    // does `instance.propName` on a tagged decoded object.
                    if check(.leftBrace) {
                        let getterBody = try parseBraceBlock()
                        memberFuncs.append(.functionDecl(
                            name: propName,
                            parameters: [],
                            body: getterBody,
                            isAsync: false,
                            isThrowing: false
                        ))
                        continue
                    }

                    // Parse initial value if present
                    if check(.equals) {
                        _ = advance() // consume =
                        skipNewlines()
                        if let value = try? parseExpression() {
                            let assignment = ViewNode.assignment(name: propName, isVar: isVar, value: value)
                            stateProperties.append(assignment)
                            print("[SwiftParser] Collected state property '\(propName)' = \(value)")
                            continue
                        }
                    }

                    // No initial value (e.g., `let title: String`) — store as init parameter
                    if !isVar {
                        // `let` property without default = init parameter
                        stateProperties.append(.assignment(name: propName, isVar: false, value: .literal(.nil)))
                        print("[SwiftParser] Collected init param '\(propName)' (no default)")
                        continue
                    }
                    // `var prop: T?` (or any optional `var` without `=`) — Swift
                    // initializes optionals to nil. Register so `if let prop` and
                    // bare reads see `.nil` rather than dropping the property
                    // entirely (which would surface as undefined-name reads).
                    stateProperties.append(.assignment(name: propName, isVar: true, value: .literal(.nil)))
                    print("[SwiftParser] Collected optional state property '\(propName)' = nil (no initializer)")
                    continue
                } else {
                    // Not body/previews and not a named property — restore position and skip
                    current = savedPos
                }
            } else if check(.keyword(.func)) {
                // Plan 5: capture the full function declaration so ViewModifier
                // conformances (body(content:)) and other struct methods can be
                // dispatched at runtime.
                let decl = try parseFuncDeclaration()
                memberFuncs.append(decl)
                continue
            } else {
                // Not a var or func — restore any modifier skip
                current = savedPos
            }

            // Skip non-body content: advance to next line or past braced blocks
            if check(.leftBrace) {
                _ = advance()
                var depth = 1
                while depth > 0 && !isAtEnd {
                    if check(.leftBrace) { depth += 1 }
                    if check(.rightBrace) { depth -= 1 }
                    _ = advance()
                }
            } else {
                // Skip tokens until newline or end (i.e., skip one "line" of content)
                while !check(.newline) && !check(.rightBrace) && !isAtEnd {
                    _ = advance()
                }
            }
        }

        if bodyView == nil {
            print("[SwiftParser] WARNING: No body/previews found in struct '\(structName)'")
        }

        // Store this struct for custom view support.
        // Non-state let/var properties become init parameters.
        if let body = bodyView {
            let initProps = stateProperties.compactMap { prop -> String? in
                if case .assignment(let name, false, _) = prop { return name } // let properties = init params
                return nil
            }
            // Prepend @State / optional-var initializers to the stored body
            // as `.stateInit` nodes so that when the struct is inlined at a
            // callsite (e.g. `BookDetailPage(book: book)` as a NavigationLink
            // destination), its @State defaults are committed to the runtime
            // store the first time the inlined view is realized. Init-param
            // assignments (let properties) are excluded — those are filled in
            // by the caller's args during inline expansion.
            let initParamSet = Set(initProps)
            let stateInits: [ViewNode] = stateProperties.compactMap { prop in
                guard case .assignment(let name, true, let value) = prop,
                      !initParamSet.contains(name) else { return nil }
                return .stateInit(name: name, value: value)
            }
            let storedBody: ViewNode = stateInits.isEmpty ? body : .block(stateInits + [body])
            parsedStructs[structName] = ParsedStruct(properties: initProps, body: storedBody)
            print("[SwiftParser] Stored struct '\(structName)' with \(initProps.count) init params: \(initProps), \(stateInits.count) state inits")
        }

        // Plan 5: emit an extensionDeclaration-shaped node so SwiftRunner's
        // registerDeclarations walker hoists each member function into the
        // runtime function table as `StructName.methodName`. This lets
        // `.modifier(Shimmer())` at render time find `Shimmer.body` and invoke it.
        var prelude: [ViewNode] = []
        if !memberFuncs.isEmpty {
            prelude.append(.extensionDeclaration(target: structName, members: memberFuncs))
        }

        // If we collected state properties, wrap them with the body view in a block
        // so that collectVariables() can find the initial values
        let result: ViewNode
        if !stateProperties.isEmpty, let body = bodyView {
            result = .block(prelude + stateProperties + [body])
            print("[SwiftParser] parseStructDeclaration returning block with \(stateProperties.count) state properties + body view + \(memberFuncs.count) methods")
        } else if !prelude.isEmpty && bodyView == nil {
            // e.g. a ViewModifier struct — no body view, just methods.
            result = prelude.count == 1 ? prelude[0] : .block(prelude)
        } else if !prelude.isEmpty, let body = bodyView {
            result = .block(prelude + [body])
        } else {
            result = bodyView ?? .empty
        }
        print("[SwiftParser] parseStructDeclaration returning: \(result)")
        return result
    }

    private func parseVariableDeclaration() throws -> ViewNode {
        let isVar = check(.keyword(.var))
        _ = advance() // consume let/var

        // Tuple destructuring: `let (a, b) = expr` or `let (a, _) = expr`.
        // MVP behavior: bind each named slot to the corresponding index of the
        // evaluated array result. Underscore slots are ignored.
        if check(.leftParen) {
            _ = advance()
            var names: [String?] = []
            while !check(.rightParen) && !isAtEnd {
                if case .identifier(let id) = peek().type {
                    names.append(id == "_" ? nil : id)
                    _ = advance()
                } else {
                    _ = advance()
                }
                if check(.comma) { _ = advance() }
            }
            if check(.rightParen) { _ = advance() }

            guard check(.equals) else {
                throw ParserError.unexpectedToken(peek(), expected: "'='")
            }
            _ = advance()
            skipNewlines()
            let value = try parseExpression()
            return .tupleBinding(names: names, value: value)
        }

        guard case .identifier(let name) = peek().type else {
            throw ParserError.unexpectedToken(peek(), expected: "variable name",
                hint: "'\(isVar ? "var" : "let")' must be followed by a variable name")
        }
        _ = advance() // consume identifier

        // Type annotation (optional, we ignore it).
        var hasTypeAnnotation = false
        if check(.colon) {
            hasTypeAnnotation = true
            _ = advance()
            // Skip type
            while !check(.equals) && !check(.newline) && !isAtEnd {
                _ = advance()
            }
        }

        // Deferred initialization: `let x: T` / `var x: T` with no `=`.
        // This is valid Swift when the variable is assigned on every path
        // before use (definite initialization). The runtime doesn't enforce
        // `let` immutability, so lowering to an assignment of `nil` is safe
        // for both `let` and `var` — subsequent branch assignments just
        // overwrite the binding. A type annotation is still required (bare
        // `let x` is not valid Swift either).
        if !check(.equals) {
            if hasTypeAnnotation {
                return .assignment(name: name, isVar: isVar, value: .literal(.nil))
            }
            throw ParserError.unexpectedToken(peek(), expected: "'='",
                hint: "variable '\(name)' needs an initial value (e.g. \(isVar ? "var" : "let") \(name) = ...)")
        }
        _ = advance() // consume =

        let value = try parseExpression()

        return .assignment(name: name, isVar: isVar, value: value)
    }
    
    // MARK: - Expression Parsing
    
    private func parseExpression() throws -> ViewNode {
        // `try` / `try?` / `try!` / `await` are transparent prefixes at the expression
        // level for now — execution semantics land in Stage 2 (async runtime) and
        // Stage 3/4 (throwing + catch propagation). Consume and continue.
        while check(.keyword(.try)) || check(.keyword(.await)) {
            _ = advance()
            if check(.questionMark) { _ = advance() }
            if check(.not) { _ = advance() }
            skipNewlines()
        }

        let expr = try parseOr()

        // Ternary: expr ? trueExpr : falseExpr
        if check(.questionMark) {
            _ = advance() // consume ?
            skipNewlines()
            let trueExpr = try parseExpression()
            skipNewlines()
            guard check(.colon) else {
                throw ParserError.unexpectedToken(peek(), expected: "':'")
            }
            _ = advance() // consume :
            skipNewlines()
            let falseExpr = try parseExpression()
            return .ternary(condition: expr, trueExpr: trueExpr, falseExpr: falseExpr)
        }

        // Nil coalescing: expr ?? fallback
        if check(.nilCoalescing) {
            _ = advance()
            skipNewlines()
            let fallback = try parseExpression()
            return .ternary(condition: .binary(left: expr, op: .notEqual, right: .literal(.nil)),
                            trueExpr: expr, falseExpr: fallback)
        }

        return expr
    }

    private func parseOr() throws -> ViewNode {
        var left = try parseAnd()
        
        while check(.or) {
            _ = advance()
            let right = try parseAnd()
            left = .binary(left: left, op: .or, right: right)
        }
        
        return left
    }
    
    private func parseAnd() throws -> ViewNode {
        var left = try parseEquality()
        
        while check(.and) {
            _ = advance()
            let right = try parseEquality()
            left = .binary(left: left, op: .and, right: right)
        }
        
        return left
    }
    
    private func parseEquality() throws -> ViewNode {
        var left = try parseComparison()
        
        while check(.equalEqual) || check(.notEqual) {
            let op: BinaryOperator = check(.equalEqual) ? .equal : .notEqual
            _ = advance()
            let right = try parseComparison()
            left = .binary(left: left, op: op, right: right)
        }
        
        return left
    }
    
    private func parseComparison() throws -> ViewNode {
        var left = try parseTerm()

        // Range operators: 0..<5 → .binary(.literal(0), .less, .literal(5))
        // This is a simplification — we reuse .less for ..< and .lessEqual for ...
        if check(.halfOpenRange) {
            _ = advance()
            let right = try parseTerm()
            return .binary(left: left, op: .less, right: right)
        }
        if check(.closedRange) {
            _ = advance()
            let right = try parseTerm()
            return .binary(left: left, op: .lessEqual, right: right)
        }

        while check(.lessThan) || check(.greaterThan) || check(.lessEqual) || check(.greaterEqual) {
            let op: BinaryOperator
            switch peek().type {
            case .lessThan: op = .less
            case .greaterThan: op = .greater
            case .lessEqual: op = .lessEqual
            case .greaterEqual: op = .greaterEqual
            default: op = .less
            }
            _ = advance()
            let right = try parseTerm()
            left = .binary(left: left, op: op, right: right)
        }
        
        return left
    }
    
    private func parseTerm() throws -> ViewNode {
        var left = try parseFactor()
        
        while check(.plus) || check(.minus) {
            let op: BinaryOperator = check(.plus) ? .plus : .minus
            _ = advance()
            let right = try parseFactor()
            left = .binary(left: left, op: op, right: right)
        }
        
        return left
    }
    
    private func parseFactor() throws -> ViewNode {
        var left = try parseUnary()
        
        while check(.star) || check(.slash) || check(.percent) {
            let op: BinaryOperator
            switch peek().type {
            case .star: op = .multiply
            case .slash: op = .divide
            case .percent: op = .modulo
            default: op = .multiply
            }
            _ = advance()
            let right = try parseUnary()
            left = .binary(left: left, op: op, right: right)
        }
        
        return left
    }
    
    private func parseUnary() throws -> ViewNode {
        if check(.minus) || check(.not) {
            let op = peek()
            _ = advance()
            let right = try parseUnary()
            if case .minus = op.type {
                return .binary(left: .literal(.number(0)), op: .minus, right: right)
            } else {
                return .binary(left: .literal(.boolean(true)), op: .notEqual, right: right)
            }
        }
        
        return try parseCall()
    }
    
    private func parseCall() throws -> ViewNode {
        var expr = try parsePrimary()

        while true {
            // Postfix force-unwrap `!` — eat transparently since SwiftRunner has
            // no real optional type (everything is `.nil`-able).
            if check(.not) {
                _ = advance()
                continue
            }

            // Optional chain `?.prop` — only when `?` is tokenized adjacent to
            // the previous token (no whitespace), same line, AND immediately
            // followed by `.`. This disambiguates from the ternary operator,
            // which by convention has whitespace around it (e.g. `flag ? .blue`).
            if check(.questionMark), case .dot = peekNext().type,
               isAdjacentToPrevious() {
                _ = advance() // consume `?`
                // Fall through — next loop iteration sees `.` and handles the
                // property / method call as normal.
                continue
            }

            // `as`, `as?`, `as!` — runtime type casts. SwiftRunner has no real
            // type system, so we consume the cast operator + type name and just
            // leave the underlying expression in place. The downstream nil-check
            // (`guard let`) still works because our `.nil` passes through.
            if case .identifier("as") = peek().type {
                _ = advance()
                if check(.questionMark) || check(.not) { _ = advance() }
                // Consume the target type. Supports:
                //   - Identifier chains:           Foo.Bar.Baz
                //   - Generics on the tail:        Array<Foo>
                //   - Array type literals:         [Foo]
                //   - Dictionary type literals:    [String: Any]
                //   - Trailing optional marker:    Foo?, [String: Any]?
                if check(.leftBracket) {
                    // Swallow a bracketed type literal (`[T]` or `[K: V]`),
                    // tracking depth so nested brackets close cleanly.
                    _ = advance()
                    var depth = 1
                    while depth > 0 && !isAtEnd {
                        if check(.leftBracket) {
                            depth += 1
                        } else if check(.rightBracket) {
                            depth -= 1
                            if depth == 0 { _ = advance(); break }
                        }
                        _ = advance()
                    }
                } else if case .identifier = peek().type {
                    _ = advance()
                    while check(.dot) {
                        _ = advance()
                        if case .identifier = peek().type { _ = advance() } else { break }
                    }
                    // Optional generic params on the tail (e.g. `Array<Foo>`).
                    if check(.lessThan) {
                        _ = advance()
                        var depth = 1
                        while depth > 0 && !isAtEnd {
                            if check(.lessThan) {
                                depth += 1
                            } else if check(.greaterThan) {
                                depth -= 1
                                if depth == 0 { _ = advance(); break }
                            }
                            _ = advance()
                        }
                    }
                }
                // Optional trailing `?` / `!` (e.g. `as? Foo?`).
                if check(.questionMark) || check(.not) { _ = advance() }
                continue
            }

            // Allow modifier chains across newlines:
            //   Text("Hello")
            //       .padding()
            if check(.newline) {
                let saved = current
                skipNewlines()
                if !check(.dot) {
                    current = saved
                    break
                }
                // It's a `.` after newlines — fall through to handle it
            }

            if check(.leftParen) {
                // Function call
                _ = advance()
                var arguments: [Argument] = []
                
                if !check(.rightParen) {
                    repeat {
                        skipNewlines()
                        let arg = try parseArgument()
                        arguments.append(arg)
                        skipNewlines()
                    } while match(.comma)
                }
                
                skipNewlines()
                guard check(.rightParen) else {
                    let viewName: String
                    if case .variable(let n) = expr { viewName = n }
                    else { viewName = "function" }
                    throw ParserError.unexpectedToken(peek(), expected: "')'",
                        hint: "missing closing parenthesis for \(viewName)(...)")
                }
                _ = advance()

                // Handle known view constructors
                if case .variable(let name) = expr {
                    expr = try buildViewNode(name: name, arguments: arguments)
                } else if case .propertyAccess(_, let prop) = expr {
                    // Method call like Color.red
                    expr = .functionCall(name: prop, arguments: arguments)
                } else {
                    expr = .functionCall(name: "unknown", arguments: arguments)
                }
                
            } else if check(.dot) {
                // Property access or modifier
                _ = advance()

                // Accept `.self` (Type.self) as a property named "self" — it's a
                // type reference marker used by `JSONDecoder().decode(T.self, from:)`.
                let name: String
                if case .identifier(let id) = peek().type {
                    name = id
                    _ = advance()
                } else if case .keyword(.self) = peek().type {
                    name = "self"
                    _ = advance()
                } else if case .number(let n) = peek().type {
                    // Numeric index access: `tuple.0`, `tuple.1`
                    name = n == floor(n) ? String(Int(n)) : String(n)
                    _ = advance()
                } else {
                    throw ParserError.unexpectedToken(peek(), expected: "modifier or property name",
                        hint: "expected an identifier after '.'")
                }

                // Check if it's a modifier call
                if check(.leftParen) {
                    // Special case: .toggle() on a variable → compound assignment
                    if name == "toggle", case .variable(let varName) = expr {
                        _ = advance() // (
                        if check(.rightParen) { _ = advance() } // )
                        expr = .compoundAssignment(variable: varName, op: .toggle, value: .empty)
                    // Special case: .append(value) on a variable → string/array concatenation
                    } else if name == "append", case .variable(let varName) = expr {
                        _ = advance() // (
                        var appendArgs: [Argument] = []
                        if !check(.rightParen) {
                            repeat {
                                skipNewlines()
                                appendArgs.append(try parseArgument())
                                skipNewlines()
                            } while match(.comma)
                        }
                        if check(.rightParen) { _ = advance() } // )
                        let appendValue = appendArgs.first?.value ?? .literal(.string(""))
                        expr = .compoundAssignment(variable: varName, op: .plusAssign, value: appendValue)
                    // Special case: .removeAll() on a variable → reset to empty
                    } else if name == "removeAll", case .variable(let varName) = expr {
                        _ = advance() // (
                        if check(.rightParen) { _ = advance() } // )
                        expr = .compoundAssignment(variable: varName, op: .assign, value: .literal(.string("")))
                    } else {
                        // parseModifierOrMethodArgs consumes `( ... )` and returns both
                        // the captured arguments and an optional ViewModifier. If the
                        // modifier is non-nil, apply it; otherwise route the args into
                        // a method call so Plan 2's user-function dispatch can use them.
                        let (modifier, callArgs) = try parseModifierOrMethodArgs(name: name)
                        if let modifier = modifier {
                            expr = applyModifier(to: expr, modifier: modifier)
                        } else {
                            switch expr {
                            case .variable, .propertyAccess, .subscriptAccess, .binding,
                                 .methodCall, .functionCall:
                                expr = .methodCall(object: expr, method: name, arguments: callArgs)
                            default:
                                // It's a view — just skip the unrecognized modifier.
                                print("[SwiftParser] Unknown modifier '.\(name)' — skipping")
                            }
                        }
                    }
                } else {
                    // Check for no-paren modifiers (.bold, .italic, .scaledToFit, etc.)
                    if let modifier = buildModifier(name: name, arguments: []) {
                        expr = applyModifier(to: expr, modifier: modifier)
                    } else {
                        // Property access
                        expr = .propertyAccess(object: expr, property: name)
                    }
                }

            } else if check(.leftBrace) {
                // Trailing closure
                _ = advance()
                skipNewlines()
                let body = try parseClosureBody()
                skipNewlines()
                guard check(.rightBrace) else {
                    throw ParserError.unexpectedToken(peek(), expected: "'}'",
                        hint: "missing closing brace for trailing closure")
                }
                _ = advance()
                
                // If expr is a view constructor, add children
                expr = addTrailingClosure(to: expr, body: body)

                // Check for labeled trailing closures: `} label: { ... }`
                // This handles Button { action } label: { views } syntax (iOS 15+)
                let savedAfterClosure = current
                skipNewlines()
                if case .identifier(let closureLabel) = peek().type, checkNext(.colon) {
                    let labelSaved = current
                    _ = advance() // consume label name
                    _ = advance() // consume :
                    skipNewlines()
                    if check(.leftBrace) {
                        _ = advance() // {
                        skipNewlines()
                        let labelBody = try parseClosureBody()
                        skipNewlines()
                        if check(.rightBrace) {
                            _ = advance() // }
                            expr = addLabeledTrailingClosure(to: expr, label: closureLabel, body: labelBody)
                        }
                    } else {
                        current = labelSaved
                    }
                } else {
                    current = savedAfterClosure
                }

            } else if check(.leftBracket) {
                // Subscript access: expr[index]
                _ = advance() // [
                let index = try parseExpression()
                guard check(.rightBracket) else {
                    throw ParserError.unexpectedToken(peek(), expected: "']'")
                }
                _ = advance() // ]
                expr = .subscriptAccess(object: expr, index: index)

            } else {
                break
            }
        }

        return expr
    }

    private func parsePrimary() throws -> ViewNode {
        skipNewlines()
        
        let token = peek()
        
        switch token.type {
        case .string(let s):
            _ = advance()
            return .literal(.string(s))

        case .interpolatedString(let parts):
            _ = advance()
            let interpolationParts: [StringInterpolationPart] = parts.map { part in
                if part.isExpression {
                    // For expression parts, try to parse the expression text.
                    // Simple case: just a variable name like "count"
                    // Complex case: expression like "count + 1" — parse it
                    if let exprNode = parseInterpolationExpression(part.content) {
                        return .expression(exprNode)
                    }
                    // Fallback: treat as variable reference
                    return .expression(.variable(part.content))
                } else {
                    return .literal(part.content)
                }
            }
            return .stringInterpolation(interpolationParts)

        case .number(let n):
            _ = advance()
            return .literal(.number(n))
            
        case .boolean(let b):
            _ = advance()
            return .literal(.boolean(b))

        case .keyword(.self):
            // `self` at expression level — bind as a variable so modifier chains
            // like `self.modifier(Shimmer())` parse. At runtime `self` resolves
            // (in Stage 5's ViewModifier dispatch) to the receiver view.
            _ = advance()
            return .variable("self")

        case .keyword(.nil):
            _ = advance()
            return .literal(.nil)

        case .bindingIdentifier(let name):
            _ = advance()
            return .binding(name)

        case .identifier(let name):
            _ = advance()
            // NOTE: we deliberately do NOT lower a bare identifier whose name
            // matches a `ColorValue` rawValue (`primary`, `secondary`, `red`,
            // etc.) to a color literal here. Doing so corrupts user variables
            // with the same name — e.g. `let primary = JSONDecoder().decode(…)`
            // followed by `return primary` would return the literal color
            // `.primary` instead of the decoded value. Member-access form
            // `.primary` / `Color.primary` is handled separately (see the
            // `.dot` / `Color.<name>` paths) and remains the correct way to
            // write a color literal.
            // Check for trailing closure (VStack { ... } without parentheses)
            skipNewlines()
            if check(.leftBrace) {
                // This is a view with trailing closure
                let viewNode = try buildViewNode(name: name, arguments: [])
                _ = advance() // {
                skipNewlines()
                let body = try parseClosureBody()
                skipNewlines()
                guard check(.rightBrace) else {
                    throw ParserError.unexpectedToken(peek(), expected: "'}'",
                        hint: "missing closing brace for \(name) { ... }")
                }
                _ = advance()
                var result = addTrailingClosure(to: viewNode, body: body)

                // Check for labeled trailing closure: `} label: { ... }`
                let savedPos = current
                skipNewlines()
                if case .identifier(let closureLabel) = peek().type, checkNext(.colon) {
                    _ = advance() // consume label
                    _ = advance() // consume :
                    skipNewlines()
                    if check(.leftBrace) {
                        _ = advance() // {
                        skipNewlines()
                        let labelBody = try parseClosureBody()
                        skipNewlines()
                        if check(.rightBrace) {
                            _ = advance() // }
                            result = addLabeledTrailingClosure(to: result, label: closureLabel, body: labelBody)
                        }
                    } else {
                        current = savedPos
                    }
                } else {
                    current = savedPos
                }

                return result
            }
            return .variable(name)
            
        case .leftParen:
            _ = advance()
            let expr = try parseExpression()
            // Check for tuple: (expr, expr, ...)
            if check(.comma) {
                var elements: [ViewNode] = [expr]
                while match(.comma) {
                    skipNewlines()
                    elements.append(try parseExpression())
                    skipNewlines()
                }
                guard check(.rightParen) else {
                    throw ParserError.unexpectedToken(peek(), expected: "')'")
                }
                _ = advance()
                return .arrayLiteral(elements) // tuples stored as arrays
            }
            guard check(.rightParen) else {
                throw ParserError.unexpectedToken(peek(), expected: "')'",
                    hint: "missing closing parenthesis for grouped expression")
            }
            _ = advance()
            return expr

        case .leftBracket:
            // Array literal `[a, b, c]` OR dictionary literal `[k: v, k2: v2]`
            // OR empty-dict marker `[:]`. Trailing commas allowed.
            _ = advance() // consume [
            skipNewlines()

            // Empty dictionary literal: `[:]`
            if check(.colon) {
                _ = advance()
                skipNewlines()
                guard check(.rightBracket) else {
                    throw ParserError.unexpectedToken(peek(), expected: "']'")
                }
                _ = advance()
                return .functionCall(name: "_dictLiteral", arguments: [Argument(label: nil, value: .arrayLiteral([]))])
            }

            // Empty array literal: `[]`
            if check(.rightBracket) {
                _ = advance()
                return .arrayLiteral([])
            }

            // Parse first element/key.
            let first = try parseExpression()
            skipNewlines()

            // Dictionary literal: first was followed by `:` → treat as key.
            if check(.colon) {
                _ = advance()
                skipNewlines()
                let firstValue = try parseExpression()
                skipNewlines()
                // Represent dictionary literal as an array of 2-element arrays:
                // `[[k, v], [k2, v2], ...]`. Evaluated downstream into a .object.
                var pairs: [ViewNode] = [.arrayLiteral([first, firstValue])]
                while check(.comma) {
                    _ = advance()
                    skipNewlines()
                    if check(.rightBracket) { break } // trailing comma
                    let k = try parseExpression()
                    skipNewlines()
                    guard check(.colon) else {
                        throw ParserError.unexpectedToken(peek(), expected: "':'",
                            hint: "dictionary key must be followed by ':'")
                    }
                    _ = advance()
                    skipNewlines()
                    let v = try parseExpression()
                    skipNewlines()
                    pairs.append(.arrayLiteral([k, v]))
                }
                guard check(.rightBracket) else {
                    throw ParserError.unexpectedToken(peek(), expected: "']'")
                }
                _ = advance()
                return .functionCall(name: "_dictLiteral", arguments: [Argument(label: nil, value: .arrayLiteral(pairs))])
            }

            // Array literal continuation.
            var elements: [ViewNode] = [first]
            while check(.comma) {
                _ = advance()
                skipNewlines()
                if check(.rightBracket) { break }
                elements.append(try parseExpression())
                skipNewlines()
            }
            guard check(.rightBracket) else {
                throw ParserError.unexpectedToken(peek(), expected: "']'",
                    hint: "unexpected '\(peek().type)' — possibly a mismatched bracket")
            }
            _ = advance()
            return .arrayLiteral(elements)

        case .leftBrace:
            // Inline closure: { ... }
            // Used for action closures like Button(action: { count += 1 }) { ... }
            // and bare closures from stripped #Preview { ... } macros
            _ = advance() // consume {
            skipNewlines()
            let body = try parseClosureBody()
            skipNewlines()
            guard check(.rightBrace) else {
                throw ParserError.unexpectedToken(peek(), expected: "'}'",
                    hint: "missing closing brace for inline closure")
            }
            _ = advance() // consume }
            // Action closures don't produce UI — return the body as-is
            // (it will be .empty or a block of non-view expressions)
            return body

        case .dot:
            // Property access starting with dot (.red, .center, .self, etc.)
            _ = advance()
            let name: String
            if case .identifier(let id) = peek().type {
                name = id
            } else if case .keyword(.self) = peek().type {
                name = "self"
            } else if case .keyword(.nil) = peek().type {
                // `.nil` isn't valid Swift but some callers spell it that way.
                name = "nil"
            } else {
                throw ParserError.unexpectedToken(peek(), expected: "identifier")
            }
            _ = advance()

            // Color values
            if let color = ColorValue(rawValue: name) {
                return .literal(.color(color))
            }
            // Alignment values
            if let _ = Alignment(rawValue: name) {
                return .variable(name)
            }
            return .variable(name)
            
        case .newline:
            _ = advance()
            return .empty
            
        case .eof:
            return .empty
            
        default:
            let hint: String
            switch token.type {
            case .rightBrace:
                hint = "unexpected '}' — possibly a mismatched brace"
            case .rightParen:
                hint = "unexpected ')' — possibly a mismatched parenthesis"
            case .rightBracket:
                hint = "unexpected ']' — possibly a mismatched bracket"
            case .comma:
                hint = "unexpected ',' — possibly a missing argument before comma"
            case .equals:
                hint = "unexpected '=' — assignment not supported here"
            case .keyword(let kw):
                hint = "'\(kw.rawValue)' cannot appear inside an expression"
            default:
                hint = "this token is not recognized as a valid SwiftUI expression"
            }
            throw ParserError.unexpectedToken(token, expected: "expression", hint: hint)
        }
    }

    // MARK: - View Building
    
    private func buildViewNode(name: String, arguments: [Argument]) throws -> ViewNode {
        switch name {
        case "Text":
            if let firstArg = arguments.first?.value {
                // Plain string literal
                if case .literal(.string(let s)) = firstArg {
                    return .text(s)
                }
                // Interpolated string — keep as-is, SwiftRunner will resolve variables
                if case .stringInterpolation = firstArg {
                    return firstArg
                }
                // Variable or expression — wrap as dynamic interpolation so it resolves from state
                switch firstArg {
                case .variable, .binary, .functionCall, .ternary,
                     .propertyAccess, .subscriptAccess, .methodCall, .binding:
                    return .stringInterpolation([.expression(firstArg)])
                default:
                    break
                }
            }
            return .text("")
            
        case "Image":
            if let firstArg = arguments.first {
                if firstArg.label == "systemName" {
                    if case .literal(.string(let s)) = firstArg.value {
                        return .systemImage(s)
                    }
                    // Dynamic systemName (ternary, variable, etc.) — store expression for render-time resolution
                    return .functionCall(name: "Image_systemName", arguments: [firstArg])
                } else if case .literal(.string(let s)) = firstArg.value {
                    return .assetImage(s)
                }
            }
            return .systemImage("photo")
            
        case "Button":
            // Button("Title") { action } — first unlabeled arg is the label string
            // Button(action: { ... }) { label } — action is a closure, label comes from trailing closure
            let actionArg = arguments.first(where: { $0.label == "action" })
            let action = actionArg?.value

            let label: ViewNode
            // If there's an "action:" labeled arg, the label will come from the trailing closure later
            if actionArg != nil {
                label = .text("Button") // placeholder; trailing closure replaces this
            } else if let firstArg = arguments.first?.value {
                if case .literal(.string(let s)) = firstArg {
                    label = .text(s)
                } else {
                    label = firstArg
                }
            } else {
                label = .text("Button")
            }
            return .button(label: label, action: action)
            
        case "VStack":
            let spacing = extractSpacing(from: arguments)
            let alignment = extractAlignment(from: arguments)
            return .vStack(spacing: spacing, alignment: alignment, children: [])
            
        case "HStack":
            let spacing = extractSpacing(from: arguments)
            let alignment = extractAlignment(from: arguments)
            return .hStack(spacing: spacing, alignment: alignment, children: [])
            
        case "ZStack":
            let alignment = extractAlignment(from: arguments)
            return .zStack(alignment: alignment, children: [])
            
        case "ScrollView":
            var axis: Axis? = nil
            var showsIndicators: Bool? = nil
            for arg in arguments {
                if case .variable("horizontal") = arg.value { axis = .horizontal }
                if case .variable("vertical") = arg.value { axis = .vertical }
                if arg.label == "showsIndicators", case .literal(.boolean(let b)) = arg.value {
                    showsIndicators = b
                }
            }
            return .scrollView(axis: axis, showsIndicators: showsIndicators, content: .empty)
            
        case "Circle":
            return .circle
            
        case "Rectangle":
            return .rectangle
            
        case "RoundedRectangle":
            var radius = 10.0
            if let arg = arguments.first(where: { $0.label == "cornerRadius" }),
               case .literal(.number(let r)) = arg.value {
                radius = r
            }
            return .roundedRectangle(cornerRadius: radius)
            
        case "Capsule":
            return .capsule
            
        case "Spacer":
            var minLength: Double? = nil
            if let arg = arguments.first(where: { $0.label == "minLength" }),
               case .literal(.number(let l)) = arg.value {
                minLength = l
            }
            return .spacer(minLength: minLength)
            
        case "Divider":
            return .divider

        case "BarChart", "LineChart":
            // Convenience charts: BarChart(data) / LineChart(data).
            let data = arguments.first?.value ?? .arrayLiteral([])
            return .chart(kind: name == "LineChart" ? .line : .bar, data: data)

        case "ForEach":
            // Parse range argument: ForEach(0..<5) or ForEach(1...10)
            if let firstArg = arguments.first?.value {
                if case .binary(let left, let op, let right) = firstArg,
                   (op == .less || op == .lessEqual) {
                    // This handles the case where ..</.../range got parsed as binary
                    if case .literal(.number(let lo)) = left,
                       case .literal(.number(let hi)) = right {
                        let lower = Int(lo)
                        let upper = op == .less ? Int(hi) - 1 : Int(hi)
                        return .forEach(range: lower...max(upper, lower), variable: "_", body: .empty)
                    }
                }
            }
            // ForEach over a collection: ForEach(items, id: \.self) { item in ... }
            if let firstArg = arguments.first?.value {
                return .forEachCollection(collection: firstArg, variable: "_", body: .empty)
            }
            return .forEach(range: 0...0, variable: "_", body: .empty)

        case "TextField", "SecureField":
            let placeholder: String
            if let first = arguments.first?.value, case .literal(.string(let s)) = first {
                placeholder = s
            } else { placeholder = "" }
            // Extract binding variable: text: $name
            let bindingVar: String
            if let textArg = arguments.first(where: { $0.label == "text" }),
               case .binding(let varName) = textArg.value {
                bindingVar = varName
            } else if arguments.count >= 2, case .binding(let varName) = arguments[1].value {
                bindingVar = varName
            } else { bindingVar = "" }
            return .textField(placeholder: placeholder, variable: bindingVar, isSecure: name == "SecureField")

        case "Toggle":
            let label: String
            if let first = arguments.first?.value, case .literal(.string(let s)) = first {
                label = s
            } else { label = "" }
            let bindingVar: String
            if let isOnArg = arguments.first(where: { $0.label == "isOn" }),
               case .binding(let varName) = isOnArg.value {
                bindingVar = varName
            } else if arguments.count >= 2, case .binding(let varName) = arguments[1].value {
                bindingVar = varName
            } else { bindingVar = "" }
            return .toggle(label: label, variable: bindingVar)

        case "Slider":
            let bindingVar: String
            if let valArg = arguments.first(where: { $0.label == "value" }),
               case .binding(let varName) = valArg.value {
                bindingVar = varName
            } else if let first = arguments.first?.value, case .binding(let varName) = first {
                bindingVar = varName
            } else { bindingVar = "" }
            // Parse range: in: 0...100
            var range: ClosedRange<Double>? = nil
            if let inArg = arguments.first(where: { $0.label == "in" }),
               case .binary(let lo, _, let hi) = inArg.value,
               case .literal(.number(let loN)) = lo, case .literal(.number(let hiN)) = hi {
                range = loN...hiN
            }
            return .slider(variable: bindingVar, range: range)

        case "AsyncImage":
            // Pull the URL expression out of one of:
            //   AsyncImage(url: URL(string: "https://…"))
            //   AsyncImage(url: URL(string: book.coverURL))
            //   AsyncImage(url: "https://…")
            //   AsyncImage("https://…")
            let urlExpr: ViewNode? = {
                if let urlArg = arguments.first(where: { $0.label == "url" }) {
                    if case .functionCall(let fname, let fargs) = urlArg.value,
                       (fname == "URL" || fname == "string"),
                       let stringArg = fargs.first(where: { $0.label == "string" || $0.label == nil }) {
                        return stringArg.value
                    }
                    return urlArg.value
                }
                return arguments.first?.value
            }()

            if case .literal(.string(let urlString)) = urlExpr {
                return .asyncImage(url: urlString)
            }
            if let expr = urlExpr {
                return .asyncImageDynamic(urlExpression: expr)
            }
            return .asyncImage(url: "")

        case "Label":
            let title: String
            let icon: String?
            if let first = arguments.first?.value, case .literal(.string(let s)) = first {
                title = s
            } else { title = "" }
            icon = arguments.first(where: { $0.label == "systemImage" }).flatMap {
                if case .literal(.string(let s)) = $0.value { return s }; return nil
            }
            if let icon = icon {
                return .hStack(spacing: 6, alignment: nil, children: [
                    .systemImage(icon), .text(title)
                ])
            }
            return .text(title)

        case "ProgressView":
            // ProgressView() — indeterminate spinner
            // ProgressView("Loading...") — labeled spinner
            // ProgressView(value: 0.5) — determinate bar
            // ProgressView(value: 0.5, total: 1.0) — determinate with total
            if arguments.isEmpty {
                return .functionCall(name: "ProgressView", arguments: [])
            }
            if let valArg = arguments.first(where: { $0.label == "value" }) {
                // Determinate progress — store as functionCall with args for renderer
                return .functionCall(name: "ProgressView", arguments: arguments)
            }
            if let first = arguments.first?.value, case .literal(.string(let label)) = first {
                // Labeled spinner
                return .functionCall(name: "ProgressView", arguments: arguments)
            }
            return .functionCall(name: "ProgressView", arguments: arguments)

        case "NavigationStack", "NavigationView":
            // Real SwiftUI NavigationStack — children come in via the trailing
            // closure (see `addTrailingClosure`). Wrapping in a real stack
            // (vs. the previous transparent-vStack hack) means
            // NavigationLink, .navigationTitle, etc. work end-to-end.
            return .navigationStack(children: [])

        case "NavigationLink":
            // Two surface forms supported here:
            //   1. NavigationLink("Title", destination: SomeView())
            //      → label is .text("Title"), destination is the arg.
            //   2. NavigationLink(destination: SomeView()) { LabelView }
            //      → destination from arg, label from trailing closure
            //      (the trailing closure path slots `label` in via
            //      `addTrailingClosure`).
            let destinationArg = arguments.first(where: { $0.label == "destination" })?.value
            let valueArg = arguments.first(where: { $0.label == "value" })?.value
            let destination = destinationArg ?? valueArg ?? .empty
            // Form 1: NavigationLink("Title", destination: ...). The first
            // unlabeled arg (a string literal or expression) is the label.
            if let firstUnlabeled = arguments.first(where: { $0.label == nil })?.value {
                let labelView: ViewNode = {
                    if case .literal(.string(let s)) = firstUnlabeled { return .text(s) }
                    if case .stringInterpolation = firstUnlabeled { return firstUnlabeled }
                    return firstUnlabeled
                }()
                return .navigationLink(label: labelView, destination: destination)
            }
            // Form 2: trailing closure provides label — placeholder, filled
            // in by `addTrailingClosure`.
            return .navigationLink(label: .empty, destination: destination)

        case "LazyVStack":
            let spacing = extractSpacing(from: arguments)
            let alignment = extractAlignment(from: arguments)
            return .vStack(spacing: spacing, alignment: alignment, children: [])

        case "LazyVGrid":
            // LazyVGrid(columns: [GridItem(.adaptive(minimum:130))], spacing: 16) { content }
            let cols: [ViewNode] = {
                guard let arg = arguments.first(where: { $0.label == "columns" }) else { return [] }
                if case .arrayLiteral(let elems) = arg.value { return elems }
                return [arg.value]
            }()
            let spacing = extractSpacing(from: arguments)
            return .lazyVGrid(columns: cols, spacing: spacing, content: .empty)

        case "LazyHGrid":
            let rows: [ViewNode] = {
                guard let arg = arguments.first(where: { $0.label == "rows" }) else { return [] }
                if case .arrayLiteral(let elems) = arg.value { return elems }
                return [arg.value]
            }()
            let spacing = extractSpacing(from: arguments)
            return .lazyHGrid(rows: rows, spacing: spacing, content: .empty)

        case "GridItem":
            // GridItem(.adaptive(minimum: 100, maximum: .infinity)), GridItem(.fixed(50)), GridItem(.flexible())
            if let style = parseGridItemStyle(from: arguments) {
                return .gridItem(style: style)
            }
            return .gridItem(style: .flexible)

        case "GeometryReader":
            // Trailing closure attaches the body. We use `"geo"` as the canonical
            // binding name when the user writes `{ geo in … }`.
            return .geometryReader(variable: "geo", body: .empty)

        case "LinearGradient":
            // LinearGradient(colors: [.blue, .green], startPoint: .top, endPoint: .bottom)
            let colors: [ColorValue] = {
                guard let colorsArg = arguments.first(where: { $0.label == "colors" }) else { return [] }
                if case .arrayLiteral(let elems) = colorsArg.value {
                    return elems.compactMap { extractColor(from: $0) }
                }
                return []
            }()
            let start = parseUnitPointArgument(arguments.first(where: { $0.label == "startPoint" })?.value) ?? .top
            let end   = parseUnitPointArgument(arguments.first(where: { $0.label == "endPoint"   })?.value) ?? .bottom
            return .linearGradient(colors: colors, startPoint: start, endPoint: end)

        case "Color":
            // `Color(.systemIndigo)` / `Color(UIColor.blue)` — render as gray fallback.
            return .literal(.color(.gray))

        case "EmptyView":
            return .empty

        case "LazyHStack":
            let spacing = extractSpacing(from: arguments)
            let alignment = extractAlignment(from: arguments)
            return .hStack(spacing: spacing, alignment: alignment, children: [])

        case "Color":
            // Color(red:green:blue:) or Color("name")
            // For now, just return a generic color view
            if let first = arguments.first?.value, case .literal(.string(let name)) = first {
                if let c = ColorValue(rawValue: name) { return .literal(.color(c)) }
            }
            return .literal(.color(.primary))

        case "print":
            return .functionCall(name: "print", arguments: arguments)

        default:
            // Check if this is a custom struct view (e.g., BookCard(title: "X", author: "Y"))
            if let customStruct = parsedStructs[name] {
                // Build a block that assigns each argument to a state variable, then renders the body
                var assignments: [ViewNode] = []
                for arg in arguments {
                    if let label = arg.label {
                        assignments.append(.assignment(name: label, isVar: true, value: arg.value))
                    }
                }
                // Also assign positional args to property names
                for (i, propName) in customStruct.properties.enumerated() where i < arguments.count {
                    if arguments[i].label == nil {
                        assignments.append(.assignment(name: propName, isVar: true, value: arguments[i].value))
                    }
                }
                if assignments.isEmpty {
                    return customStruct.body
                }
                return .block(assignments + [customStruct.body])
            }
            return .functionCall(name: name, arguments: arguments)
        }
    }
    
    private func extractSpacing(from arguments: [Argument]) -> Double? {
        if let arg = arguments.first(where: { $0.label == "spacing" || $0.label == nil }),
           case .literal(.number(let n)) = arg.value {
            return n
        }
        return nil
    }
    
    private func extractAlignment(from arguments: [Argument]) -> Alignment? {
        if let arg = arguments.first(where: { $0.label == "alignment" }),
           case .variable(let name) = arg.value {
            return Alignment(rawValue: name)
        }
        return nil
    }
    
    // MARK: - Modifier Parsing
    
    private func parseModifierCall(name: String) throws -> ViewModifier? {
        return try parseModifierOrMethodArgs(name: name).modifier
    }

    /// Consume `( args )` and try to resolve the token following the dot into a
    /// ViewModifier. Returns both the modifier (if any) and the parsed arguments
    /// so the caller can fall back to a user-defined method call when the name
    /// isn't a known modifier.
    private func parseModifierOrMethodArgs(name: String) throws -> (modifier: ViewModifier?, args: [Argument]) {
        _ = advance() // consume (
        var args: [Argument] = []

        if !check(.rightParen) {
            repeat {
                skipNewlines()
                args.append(try parseArgument())
                skipNewlines()
            } while match(.comma)
        }

        skipNewlines()
        guard check(.rightParen) else {
            throw ParserError.unexpectedToken(peek(), expected: "')'",
                hint: "missing closing parenthesis for modifier .\(name)(...)")
        }
        _ = advance()

        return (buildModifier(name: name, arguments: args), args)
    }
    
    /// Extract a `MaterialValue` from `.ultraThinMaterial`, `Material.ultraThin`, etc.
    /// Extract the variable name backing a `Bool` binding argument, e.g.
    /// `isPresented: $showSheet` → `"showSheet"`. Used by modal modifiers
    /// (`.sheet(isPresented:)`, `.alert(_:isPresented:)`, etc.) to wire a
    /// SwiftUI Binding<Bool> backed by `state.variables[name]`.
    private func extractBoolBindingName(_ arguments: [Argument], label: String) -> String? {
        guard let arg = arguments.first(where: { $0.label == label }) else { return nil }
        if case .binding(let name) = arg.value { return name }
        if case .variable(let name) = arg.value { return name }
        return nil
    }

    private func extractMaterial(from node: ViewNode) -> MaterialValue? {
        switch node {
        case .variable(let name), .propertyAccess(_, let name):
            return MaterialValue(rawValue: name)
        default:
            return nil
        }
    }

    /// For `.buttonStyle(.borderedProminent)` etc. — pull the identifier out of
    /// a `.propertyAccess("_", "borderedProminent")` or `.variable("borderedProminent")`.
    private func extractIdentifier(_ node: ViewNode) -> String? {
        switch node {
        case .variable(let name): return name
        case .propertyAccess(_, let name): return name
        default: return nil
        }
    }

    /// Parse a shape expression (`RoundedRectangle(cornerRadius: 12)`, `Capsule()`, etc.)
    /// into a ShapeType, or nil if unrecognized.
    private func parseShapeArgument(_ node: ViewNode?) -> ShapeType? {
        guard let n = node else { return nil }
        if case .roundedRectangle(let r) = n { return .roundedRectangle(cornerRadius: r) }
        if case .circle = n { return .circle }
        if case .rectangle = n { return .rectangle }
        if case .capsule = n { return .capsule }
        return nil
    }

    /// Cheap peek-ahead: is there an `=` / `+=` / `-=` / `*=` / `/=` at paren/bracket
    /// depth 0 before the next `{`, newline, or EOF from the current cursor position?
    /// Used to decide whether a statement-start identifier is beginning an assignment.
    private func hasAssignOperatorBeforeBoundary() -> Bool {
        var i = current
        var depth = 0
        while i < tokens.count {
            let t = tokens[i].type
            if depth == 0 {
                switch t {
                case .equals, .plusEquals, .minusEquals, .starEquals, .slashEquals:
                    return true
                case .leftBrace, .newline, .semicolon, .eof:
                    return false
                default: break
                }
            }
            switch t {
            case .leftParen, .leftBracket:
                depth += 1
            case .rightParen, .rightBracket:
                depth -= 1
            default: break
            }
            i += 1
        }
        return false
    }

    /// Parse a bounded left-hand side: an identifier followed by any mix of
    /// `.prop` / `[expr]` accessors. Rejects anything else so we don't consume
    /// a full arbitrary expression (which would over-match and recurse).
    private func parseAssignableLHS() throws -> ViewNode {
        guard case .identifier(let rootName) = peek().type else {
            throw ParserError.unexpectedToken(peek(), expected: "assignable identifier")
        }
        _ = advance()
        var node: ViewNode = .variable(rootName)

        while true {
            if check(.dot) {
                _ = advance()
                if case .identifier(let prop) = peek().type {
                    _ = advance()
                    node = .propertyAccess(object: node, property: prop)
                    continue
                }
                if case .keyword(.self) = peek().type {
                    _ = advance()
                    node = .propertyAccess(object: node, property: "self")
                    continue
                }
                // Something unexpected after dot — give up on LHS parsing.
                throw ParserError.unexpectedToken(peek(), expected: "property name")
            }
            if check(.leftBracket) {
                _ = advance()
                let idx = try parseExpression()
                guard check(.rightBracket) else {
                    throw ParserError.unexpectedToken(peek(), expected: "']'")
                }
                _ = advance()
                node = .subscriptAccess(object: node, index: idx)
                continue
            }
            break
        }
        return node
    }

    /// Parse a `.adaptive(minimum:)`, `.fixed(N)`, or `.flexible()` grid item
    /// style out of the first argument of a GridItem(...) call.
    private func parseGridItemStyle(from arguments: [Argument]) -> GridItemStyle? {
        guard let first = arguments.first else { return nil }
        // Cases shaped like `.adaptive(minimum: 130)`, `.fixed(50)`, `.flexible()`
        // parse into propertyAccess(.variable("_"), "adaptive") with call args
        // lost — use a more forgiving match on function calls as well.
        switch first.value {
        case .functionCall(let fname, let fargs):
            return gridStyle(name: fname, args: fargs)
        case .propertyAccess(_, let prop):
            return gridStyle(name: prop, args: [])
        case .methodCall(_, let method, let margs):
            return gridStyle(name: method, args: margs)
        default:
            return nil
        }
    }

    private func gridStyle(name: String, args: [Argument]) -> GridItemStyle? {
        switch name {
        case "adaptive":
            let minimum = args.first(where: { $0.label == "minimum" }).flatMap { numberFromExpr($0.value) } ?? 100
            let maximum = args.first(where: { $0.label == "maximum" }).flatMap { numberFromExpr($0.value) }
            return .adaptive(minimum: minimum, maximum: maximum)
        case "fixed":
            let n = args.first.flatMap { numberFromExpr($0.value) } ?? 50
            return .fixed(n)
        case "flexible":
            return .flexible
        default:
            return nil
        }
    }

    private func numberFromExpr(_ node: ViewNode) -> Double? {
        if case .literal(.number(let n)) = node { return n }
        return nil
    }

    /// Parse a unit-point argument like `.top`, `.bottomTrailing`, etc.
    private func parseUnitPointArgument(_ node: ViewNode?) -> UnitPoint? {
        guard let node = node else { return nil }
        if case .variable(let name) = node { return UnitPoint(rawValue: name) }
        if case .propertyAccess(_, let prop) = node { return UnitPoint(rawValue: prop) }
        return nil
    }

    /// Extract a ColorValue from a ViewNode, handling:
    ///   - .literal(.color(c))           →  e.g. from shorthand `.blue`
    ///   - .propertyAccess("Color", prop) →  e.g. `Color.blue`
    ///   - .variable(name)               →  e.g. bare `blue`
    private func extractColor(from node: ViewNode) -> ColorValue? {
        switch node {
        case .literal(.color(let c)):
            return c
        case .propertyAccess(let obj, let prop):
            if case .variable("Color") = obj {
                return ColorValue(rawValue: prop)
            }
            return nil
        case .variable(let name):
            return ColorValue(rawValue: name)
        default:
            return nil
        }
    }

    /// Check if a ViewNode is a dynamic expression that needs runtime evaluation.
    /// Extract glass effect style and tint from a parsed argument node.
    /// Handles: .regular, .clear, .regular.tint(.blue), .modified(.variable("regular"), [.tint(.blue)])
    private func extractGlassInfo(from node: ViewNode, style: inout GlassStyle, tint: inout ColorValue?) {
        switch node {
        case .variable(let name):
            style = GlassStyle(rawValue: name) ?? .regular
        case .literal(.color(let c)) where c.rawValue == "clear":
            // .clear can be either a glass style or a color — in glassEffect context, it's a style
            style = .clear
        case .modified(let base, let mods):
            // Base is the glass style
            if case .variable(let name) = base {
                style = GlassStyle(rawValue: name) ?? .regular
            }
            // Look for .tint() in the modifier chain
            for mod in mods {
                if case .tint(let c) = mod { tint = c }
            }
        case .functionCall(let name, let args):
            // Direct function call like tint(.blue) — style defaults to .regular
            if name == "tint", let arg = args.first?.value, let c = extractColor(from: arg) {
                tint = c
            }
        case .propertyAccess(let obj, let prop):
            // e.g. .regular.interactive — extract style from deeper node
            extractGlassInfo(from: obj, style: &style, tint: &tint)
            if prop == "interactive" { /* recognized but no effect in preview */ }
        default:
            break
        }
    }

    /// Extract a ShapeType from a parsed node.
    /// Handles: .capsule, .circle, RoundedRectangle(cornerRadius: 16), .rect(cornerRadius: 16)
    private func extractShapeType(from node: ViewNode) -> ShapeType? {
        switch node {
        case .variable(let name):
            switch name.lowercased() {
            case "capsule": return .capsule
            case "circle": return .circle
            case "rectangle": return .rectangle
            default: return nil
            }
        case .capsule: return .capsule
        case .circle: return .circle
        case .rectangle: return .rectangle
        case .roundedRectangle(let r): return .roundedRectangle(cornerRadius: r)
        case .functionCall(let name, let args):
            switch name {
            case "RoundedRectangle", "roundedRectangle":
                if let arg = args.first(where: { $0.label == "cornerRadius" }),
                   case .literal(.number(let r)) = arg.value {
                    return .roundedRectangle(cornerRadius: r)
                }
                return .roundedRectangle(cornerRadius: 10)
            case "rect":
                if let arg = args.first(where: { $0.label == "cornerRadius" }),
                   case .literal(.number(let r)) = arg.value {
                    return .roundedRectangle(cornerRadius: r)
                }
                return .rectangle
            case "Capsule", "capsule": return .capsule
            case "Circle", "circle": return .circle
            default: return nil
            }
        default:
            return nil
        }
    }

    private func parseAnimationType(_ node: ViewNode) -> AnimationType {
        switch node {
        case .variable(let name):
            switch name {
            case "default": return .default
            case "linear": return .linear(duration: nil)
            case "easeIn": return .easeIn(duration: nil)
            case "easeOut": return .easeOut(duration: nil)
            case "easeInOut": return .easeInOut(duration: nil)
            case "spring": return .spring(response: nil, dampingFraction: nil)
            case "bouncy": return .bouncy(duration: nil)
            case "smooth": return .smooth(duration: nil)
            case "snappy": return .snappy(duration: nil)
            case "none": return .none
            default: return .default
            }
        case .functionCall(let name, let args):
            let dur = args.first(where: { $0.label == "duration" || $0.label == nil })
                .flatMap { if case .literal(.number(let n)) = $0.value { return n }; return nil as Double? }
            switch name {
            case "linear": return .linear(duration: dur)
            case "easeIn": return .easeIn(duration: dur)
            case "easeOut": return .easeOut(duration: dur)
            case "easeInOut": return .easeInOut(duration: dur)
            case "spring":
                let resp = args.first(where: { $0.label == "response" })
                    .flatMap { if case .literal(.number(let n)) = $0.value { return n }; return nil as Double? }
                let damp = args.first(where: { $0.label == "dampingFraction" })
                    .flatMap { if case .literal(.number(let n)) = $0.value { return n }; return nil as Double? }
                return .spring(response: resp ?? dur, dampingFraction: damp)
            case "bouncy": return .bouncy(duration: dur)
            case "smooth": return .smooth(duration: dur)
            case "snappy": return .snappy(duration: dur)
            default: return .default
            }
        case .literal(.nil):
            return .none
        default:
            return .default
        }
    }

    private func parseTransitionType(_ node: ViewNode) -> TransitionType {
        switch node {
        case .variable(let name):
            switch name {
            case "opacity": return .opacity
            case "slide": return .slide
            case "scale": return .scale
            case "identity": return .identity
            default: return .opacity
            }
        case .functionCall(let name, let args):
            if name == "move", let edgeArg = args.first?.value, case .variable(let e) = edgeArg,
               let edge = EdgeValue(rawValue: e) {
                return .move(edge: edge)
            }
            return .opacity
        default:
            return .opacity
        }
    }

    private func isDynamicExpression(_ node: ViewNode) -> Bool {
        switch node {
        case .ternary, .binary, .variable, .binding: return true
        default: return false
        }
    }

    private func buildModifier(name: String, arguments: [Argument]) -> ViewModifier? {
        // Plan 5 capstone: `.modifier(SomeViewModifier())` — capture the type name
        // so the renderer can dispatch to the user-defined `<TypeName>.body(content:)`.
        if name == "modifier", let first = arguments.first {
            if case .functionCall(let typeName, _) = first.value {
                return .userModifier(typeName: typeName)
            }
            if case .variable(let typeName) = first.value {
                return .userModifier(typeName: typeName)
            }
        }

        switch name {
        case "font":
            if let arg = arguments.first?.value {
                let parsed = parseFont(arg)
                // Only use dynamic if parseFont fell through to .body default AND the arg is dynamic
                if case .body = parsed, isDynamicExpression(arg) {
                    return .dynamic(name: "font", argument: arg)
                }
                return .font(parsed)
            }
            return .font(.body)

        case "foregroundColor", "foregroundStyle":
            if let arg = arguments.first?.value {
                if let c = extractColor(from: arg) {
                    return name == "foregroundColor" ? .foregroundColor(c) : .foregroundStyle(c)
                }
                if isDynamicExpression(arg) { return .dynamic(name: name, argument: arg) }
            }
            return nil

        case "frame":
            var width: Double? = nil
            var height: Double? = nil
            var maxWidth: Double? = nil
            var maxHeight: Double? = nil
            // Track expression-valued dims so we can fall through to the
            // render-time evaluator when a literal isn't provided. This
            // matters for patterns like `.frame(width: coverWidth, height: coverHeight)`
            // where the dimensions are state-stored constants.
            var widthExpr: ViewNode? = nil
            var heightExpr: ViewNode? = nil
            var maxWidthExpr: ViewNode? = nil
            var maxHeightExpr: ViewNode? = nil
            for arg in arguments {
                switch arg.label {
                case "width":
                    if case .literal(.number(let n)) = arg.value { width = n }
                    else { widthExpr = arg.value }
                case "height":
                    if case .literal(.number(let n)) = arg.value { height = n }
                    else { heightExpr = arg.value }
                case "maxWidth":
                    if case .literal(.number(let n)) = arg.value { maxWidth = n }
                    else if case .variable("infinity") = arg.value { maxWidth = .infinity }
                    else { maxWidthExpr = arg.value }
                case "maxHeight":
                    if case .literal(.number(let n)) = arg.value { maxHeight = n }
                    else if case .variable("infinity") = arg.value { maxHeight = .infinity }
                    else { maxHeightExpr = arg.value }
                default:
                    break
                }
            }
            // If ANY dimension is expression-valued, switch to dynamicFrame so
            // the renderer evaluates each at render time. Static-literal
            // dimensions wrap as `.literal(.number(n))` so the same code path
            // handles both.
            let hasExpr = widthExpr != nil || heightExpr != nil || maxWidthExpr != nil || maxHeightExpr != nil
            if hasExpr {
                func toExpr(_ literal: Double?, _ expr: ViewNode?) -> ViewNode? {
                    if let n = literal { return .literal(.number(n)) }
                    return expr
                }
                return .dynamicFrame(
                    width: toExpr(width, widthExpr),
                    height: toExpr(height, heightExpr),
                    maxWidth: toExpr(maxWidth, maxWidthExpr),
                    maxHeight: toExpr(maxHeight, maxHeightExpr)
                )
            }
            return .frame(width: width, height: height, maxWidth: maxWidth, maxHeight: maxHeight, alignment: nil)

        case "background":
            if let arg = arguments.first?.value {
                // Plan 7: `.background(.ultraThinMaterial, in: RoundedRectangle(…))`
                if let material = extractMaterial(from: arg) {
                    let shape = parseShapeArgument(arguments.first(where: { $0.label == "in" })?.value)
                    return .materialBackground(material: material, shape: shape)
                }
                if let c = extractColor(from: arg) { return .background(c) }
                if isDynamicExpression(arg) { return .dynamic(name: "background", argument: arg) }
            }
            return nil

        case "buttonStyle":
            if let arg = arguments.first?.value, let style = extractIdentifier(arg),
               let v = ButtonStyleValue(rawValue: style) {
                return .buttonStyle(v)
            }
            return nil

        case "textFieldStyle":
            if let arg = arguments.first?.value, let style = extractIdentifier(arg),
               let v = TextFieldStyleValue(rawValue: style) {
                return .textFieldStyle(v)
            }
            return nil

        case "controlSize":
            if let arg = arguments.first?.value, let size = extractIdentifier(arg),
               let v = ControlSizeValue(rawValue: size) {
                return .controlSize(v)
            }
            return nil

        case "refreshable":
            // `.refreshable { await foo() }` — trailing closure becomes the action
            // via the existing trailing-closure modifier path (see addTrailingClosure).
            return .refreshable(.empty)
            
        case "cornerRadius":
            if let arg = arguments.first?.value {
                if case .literal(.number(let r)) = arg { return .cornerRadius(r) }
                if isDynamicExpression(arg) { return .dynamic(name: "cornerRadius", argument: arg) }
            }
            return nil
            
        case "opacity":
            if let arg = arguments.first?.value {
                if case .literal(.number(let o)) = arg { return .opacity(o) }
                if isDynamicExpression(arg) { return .dynamic(name: "opacity", argument: arg) }
            }
            return nil
            
        case "fontWeight":
            if let arg = arguments.first?.value, case .variable(let w) = arg,
               let weight = FontWeight(rawValue: w) {
                return .fontWeight(weight)
            }
            return nil

        case "bold":
            return .bold

        case "italic":
            return .italic

        case "lineLimit":
            if let arg = arguments.first?.value,
               case .literal(.number(let n)) = arg {
                return .lineLimit(Int(n))
            }
            return nil

        case "multilineTextAlignment":
            if let arg = arguments.first?.value, case .variable(let a) = arg,
               let alignment = TextAlignmentValue(rawValue: a) {
                return .multilineTextAlignment(alignment)
            }
            return nil

        case "fill":
            if let arg = arguments.first?.value {
                if let c = extractColor(from: arg) { return .fill(c) }
                if isDynamicExpression(arg) { return .dynamic(name: "fill", argument: arg) }
            }
            return nil

        case "stroke":
            var color: ColorValue = .primary
            var lineWidth = 1.0
            if let first = arguments.first?.value, let c = extractColor(from: first) {
                color = c
            }
            if let lw = arguments.first(where: { $0.label == "lineWidth" }),
               case .literal(.number(let w)) = lw.value {
                lineWidth = w
            } else if arguments.count >= 2, arguments[1].label == nil,
                      case .literal(.number(let w)) = arguments[1].value {
                lineWidth = w
            }
            return .stroke(color, lineWidth: lineWidth)

        case "clipped":
            return .clipped

        case "dragToMove":
            return .dragToMove

        case "overlay":
            // .overlay(content) with explicit argument
            if let arg = arguments.first?.value {
                return .overlay(arg)
            }
            return nil

        case "border":
            if arguments.count >= 2,
               let c = extractColor(from: arguments[0].value),
               case .literal(.number(let w)) = arguments.last?.value {
                return .border(c, width: w)
            }
            if let c = extractColor(from: arguments.first?.value ?? .empty) {
                return .border(c, width: 1)
            }
            return nil

        case "fixedSize":
            if arguments.isEmpty { return .fixedSize(horizontal: true, vertical: true) }
            var h = true, v = true
            for arg in arguments {
                if arg.label == "horizontal", case .literal(.boolean(let b)) = arg.value { h = b }
                if arg.label == "vertical", case .literal(.boolean(let b)) = arg.value { v = b }
            }
            return .fixedSize(horizontal: h, vertical: v)

        case "aspectRatio":
            var ratio: Double? = nil
            var mode: ContentMode = .fit
            if let first = arguments.first?.value, case .literal(.number(let r)) = first { ratio = r }
            for arg in arguments {
                if arg.label == "contentMode", case .variable(let m) = arg.value {
                    if m == "fill" { mode = .fill }
                }
            }
            return .aspectRatio(ratio, contentMode: mode)

        case "resizable":
            return .resizable

        case "scaledToFit":
            return .scaledToFit

        case "scaledToFill":
            return .scaledToFill

        case "offset":
            var x = 0.0, y = 0.0
            for arg in arguments {
                if arg.label == "x", case .literal(.number(let n)) = arg.value { x = n }
                if arg.label == "y", case .literal(.number(let n)) = arg.value { y = n }
            }
            return .offset(x: x, y: y)

        case "shadow":
            var radius = 5.0, x = 0.0, y = 0.0
            for arg in arguments {
                if arg.label == "radius", case .literal(.number(let n)) = arg.value { radius = n }
                if arg.label == "x", case .literal(.number(let n)) = arg.value { x = n }
                if arg.label == "y", case .literal(.number(let n)) = arg.value { y = n }
            }
            if let first = arguments.first, first.label == nil,
               case .literal(.number(let r)) = first.value { radius = r }
            return .shadow(radius: radius, x: x, y: y)

        case "clipShape":
            if let arg = arguments.first?.value {
                switch arg {
                case .functionCall(let name, _), .variable(let name):
                    switch name.lowercased() {
                    case "circle": return .clipShape(.circle)
                    case "capsule": return .clipShape(.capsule)
                    case "rectangle": return .clipShape(.rectangle)
                    default: break
                    }
                case .circle: return .clipShape(.circle)
                case .capsule: return .clipShape(.capsule)
                case .rectangle: return .clipShape(.rectangle)
                case .roundedRectangle(let r): return .clipShape(.roundedRectangle(cornerRadius: r))
                default: break
                }
            }
            return nil

        case "hidden":
            return .hidden

        case "strikethrough":
            let color = arguments.first.flatMap { extractColor(from: $0.value) }
            return .strikethrough(color)

        case "underline":
            let color = arguments.first.flatMap { extractColor(from: $0.value) }
            return .underline(color)

        case "lineSpacing":
            if let arg = arguments.first?.value, case .literal(.number(let n)) = arg {
                return .lineSpacing(n)
            }
            return nil

        case "truncationMode":
            if let arg = arguments.first?.value, case .variable(let m) = arg,
               let mode = TruncationModeValue(rawValue: m) {
                return .truncationMode(mode)
            }
            return nil

        case "minimumScaleFactor":
            if let arg = arguments.first?.value, case .literal(.number(let n)) = arg {
                return .minimumScaleFactor(n)
            }
            return nil

        case "textCase":
            if let arg = arguments.first?.value, case .variable(let c) = arg,
               let tc = TextCaseValue(rawValue: c) {
                return .textCase(tc)
            }
            return nil

        case "kerning":
            if let arg = arguments.first?.value, case .literal(.number(let n)) = arg {
                return .kerning(n)
            }
            return nil

        case "renderingMode":
            if let arg = arguments.first?.value, case .variable(let m) = arg,
               let mode = RenderingModeValue(rawValue: m) {
                return .renderingMode(mode)
            }
            return nil

        case "zIndex":
            if let arg = arguments.first?.value, case .literal(.number(let n)) = arg {
                return .zIndex(n)
            }
            return nil

        case "rotationEffect":
            // .rotationEffect(.degrees(45)) or .rotationEffect(Angle(degrees: 45))
            if let arg = arguments.first?.value {
                if case .literal(.number(let n)) = arg { return .rotationEffect(n) }
                if case .functionCall(let name, let args) = arg,
                   (name == "degrees" || name == "Angle"),
                   let inner = args.first?.value, case .literal(.number(let n)) = inner {
                    return .rotationEffect(n)
                }
            }
            return nil

        case "scaleEffect":
            if let arg = arguments.first?.value, case .literal(.number(let n)) = arg {
                return .scaleEffect(n)
            }
            return nil

        case "blur":
            if arguments.first?.label == "radius",
               case .literal(.number(let n)) = arguments.first?.value {
                return .blur(n)
            }
            if let arg = arguments.first?.value, case .literal(.number(let n)) = arg {
                return .blur(n)
            }
            return nil

        case "brightness":
            if let arg = arguments.first?.value, case .literal(.number(let n)) = arg {
                return .brightness(n)
            }
            return nil

        case "contrast":
            if let arg = arguments.first?.value, case .literal(.number(let n)) = arg {
                return .contrast(n)
            }
            return nil

        case "saturation":
            if let arg = arguments.first?.value, case .literal(.number(let n)) = arg {
                return .saturation(n)
            }
            return nil

        case "grayscale":
            if let arg = arguments.first?.value, case .literal(.number(let n)) = arg {
                return .grayscale(n)
            }
            return nil

        case "tint":
            if let arg = arguments.first?.value {
                if let c = extractColor(from: arg) { return .tint(c) }
                if isDynamicExpression(arg) { return .dynamic(name: "tint", argument: arg) }
            }
            return nil

        case "allowsHitTesting":
            if let arg = arguments.first?.value, case .literal(.boolean(let b)) = arg {
                return .allowsHitTesting(b)
            }
            return nil

        case "onAppear":
            return .onAppear(nil) // action from trailing closure

        case "onDisappear":
            return .onDisappear(nil) // action from trailing closure

        case "onChange":
            // Extract observed variable from `of:` argument
            var observedVar: String? = nil
            if let ofArg = arguments.first(where: { $0.label == "of" }) {
                if case .variable(let name) = ofArg.value { observedVar = name }
                else if case .binding(let name) = ofArg.value { observedVar = name }
            }
            // Store the variable; action comes from trailing closure
            return .onChange(variable: observedVar, action: .empty)

        case "task":
            // `.task(id: <expr>) { body }` — capture the ID expression now and
            // let `addTrailingClosure` plug in the body when the trailing
            // closure is parsed. Renderer maps to SwiftUI's `view.task(id:)`,
            // which auto-cancels the previous task when the ID's value changes.
            if let idArg = arguments.first(where: { $0.label == "id" }) {
                return .taskActionWithID(idExpression: idArg.value, action: .empty)
            }
            // Bare `.task(...)` with no `id:` falls through to the no-args
            // path (handled by the trailing-closure modifier dispatch below).
            return nil

        // MARK: - Modal modifiers
        //
        // `.sheet(isPresented: $flag) { content }` and friends. We extract the
        // bool variable name from `isPresented:` here and let `addTrailingClosure`
        // slot in the trailing closure as `content`. The renderer wires each
        // modifier to its real SwiftUI counterpart with a Binding<Bool>.

        case "sheet":
            if let bindingName = extractBoolBindingName(arguments, label: "isPresented") {
                return .sheet(isPresentedVar: bindingName, content: .empty)
            }
            return nil

        case "fullScreenCover":
            if let bindingName = extractBoolBindingName(arguments, label: "isPresented") {
                return .fullScreenCover(isPresentedVar: bindingName, content: .empty)
            }
            return nil

        case "alert":
            // Two args we care about: positional title (string literal) and
            // `isPresented: $flag`. The trailing closure is the actions block;
            // an optional `message: { Text(...) }` is supplied as a labeled
            // trailing closure (see `addLabeledTrailingClosure`).
            let title: String = {
                if let firstUnlabeled = arguments.first(where: { $0.label == nil })?.value,
                   case .literal(.string(let s)) = firstUnlabeled {
                    return s
                }
                return ""
            }()
            if let bindingName = extractBoolBindingName(arguments, label: "isPresented") {
                return .alert(title: title, isPresentedVar: bindingName, actions: .empty, message: nil)
            }
            return nil

        case "combined":
            // .transition(.scale.combined(with: .opacity)) — just skip, keep the base
            return nil

        case "animation":
            if let arg = arguments.first?.value {
                let anim = parseAnimationType(arg)
                return .animation(anim)
            }
            return .animation(.default)

        case "transition":
            if let arg = arguments.first?.value {
                let trans = parseTransitionType(arg)
                return .transition(trans)
            }
            return .transition(.opacity)

        case "glassEffect":
            var style: GlassStyle = .regular
            var tint: ColorValue? = nil
            var shape: ShapeType? = nil

            // Parse first argument: .regular, .clear, .regular.tint(.blue), etc.
            if let firstArg = arguments.first, firstArg.label == nil {
                extractGlassInfo(from: firstArg.value, style: &style, tint: &tint)
            }

            // Parse `in:` shape argument
            if let inArg = arguments.first(where: { $0.label == "in" }) {
                shape = extractShapeType(from: inArg.value)
            }

            return .glassEffect(style: style, tint: tint, shape: shape)

        case "interactive":
            // Part of Glass method chain — not a standalone modifier, just skip
            return nil

        case "ignoresSafeArea", "edgesIgnoringSafeArea":
            return .ignoresSafeArea

        case "colorMultiply":
            if let arg = arguments.first?.value, let c = extractColor(from: arg) {
                return .colorMultiply(c)
            }
            return nil

        case "colorInvert":
            return .colorInvert

        case "compositingGroup":
            return .compositingGroup

        case "mask":
            if let arg = arguments.first?.value {
                return .mask(arg)
            }
            return nil

        case "onLongPressGesture":
            // Handled via trailing closure in addTrailingClosure
            return nil

        case "contentShape":
            return .contentShape

        case "layoutPriority":
            if let arg = arguments.first?.value, case .literal(.number(let n)) = arg {
                return .layoutPriority(n)
            }
            return nil

        case "position":
            var x = 0.0, y = 0.0
            for arg in arguments {
                if arg.label == "x", case .literal(.number(let n)) = arg.value { x = n }
                if arg.label == "y", case .literal(.number(let n)) = arg.value { y = n }
            }
            return .position(x: x, y: y)

        case "strokeBorder":
            var color: ColorValue = .primary
            var lineWidth = 1.0
            if let first = arguments.first?.value, let c = extractColor(from: first) {
                color = c
            }
            if let lw = arguments.first(where: { $0.label == "lineWidth" }),
               case .literal(.number(let w)) = lw.value {
                lineWidth = w
            } else if arguments.count >= 2, arguments[1].label == nil,
                      case .literal(.number(let w)) = arguments[1].value {
                lineWidth = w
            }
            return .strokeBorder(color, lineWidth: lineWidth)

        case "trim":
            var from = 0.0, to = 1.0
            for arg in arguments {
                if arg.label == "from", case .literal(.number(let n)) = arg.value { from = n }
                if arg.label == "to", case .literal(.number(let n)) = arg.value { to = n }
            }
            return .trim(from: from, to: to)

        case "id":
            if let arg = arguments.first?.value, case .literal(.string(let s)) = arg {
                return .id(s)
            }
            return nil

        case "tag":
            if let arg = arguments.first?.value, case .literal(.string(let s)) = arg {
                return .tag(s)
            }
            return nil

        case "disabled":
            if let arg = arguments.first?.value,
               case .literal(.boolean(let b)) = arg {
                return .disabled(b)
            }
            return .disabled(true)

        case "navigationTitle":
            if let arg = arguments.first?.value,
               case .literal(.string(let s)) = arg {
                return .navigationTitle(s)
            }
            return nil

        case "padding":
            // Enhanced: handle per-edge padding
            if arguments.isEmpty {
                return .padding(.all(16))
            }
            // .padding(.horizontal, 16) or .padding(.vertical, 8)
            if arguments.count >= 1, let first = arguments.first {
                if first.label == nil, case .variable(let edge) = first.value {
                    let amount: Double = arguments.count >= 2 ?
                        (arguments[1].value == .literal(.number(0)) ? 0 :
                         { if case .literal(.number(let n)) = arguments[1].value { return n }; return 16 }()) : 16
                    switch edge {
                    case "horizontal": return .padding(.horizontal(amount))
                    case "vertical": return .padding(.vertical(amount))
                    case "top": return .padding(PaddingInsets(top: amount))
                    case "bottom": return .padding(PaddingInsets(bottom: amount))
                    case "leading": return .padding(PaddingInsets(leading: amount))
                    case "trailing": return .padding(PaddingInsets(trailing: amount))
                    default: break
                    }
                }
            }
            if let arg = arguments.first?.value,
               case .literal(.number(let n)) = arg {
                return .padding(.all(n))
            }
            return .padding(.all(16))

        case "keyboardType":
            if let arg = arguments.first?.value, case .variable(let v) = arg,
               let kt = KeyboardTypeValue(rawValue: v) {
                return .keyboardType(kt)
            }
            return nil

        case "textContentType":
            if let arg = arguments.first?.value, case .variable(let v) = arg,
               let tc = TextContentTypeValue(rawValue: v) {
                return .textContentType(tc)
            }
            return nil

        case "submitLabel":
            if let arg = arguments.first?.value, case .variable(let v) = arg,
               let sl = SubmitLabelValue(rawValue: v) {
                return .submitLabel(sl)
            }
            return nil

        case "autocapitalization", "textInputAutocapitalization":
            if let arg = arguments.first?.value, case .variable(let v) = arg,
               let ac = AutocapitalizationValue(rawValue: v) {
                return .autocapitalization(ac)
            }
            return nil

        case "scrollDismissesKeyboard":
            // .scrollDismissesKeyboard(.interactively) / .immediately / .never / .automatic
            if let arg = arguments.first?.value,
               let id = extractIdentifier(arg),
               let mode = ScrollDismissMode(rawValue: id) {
                return .scrollDismissesKeyboard(mode)
            }
            // Default to interactively if we can't extract — matches typical
            // SwiftUI usage on a search-driven scroll view.
            return .scrollDismissesKeyboard(.interactively)

        // Style modifiers — recognized but no visual effect in preview
        case "textFieldStyle", "buttonStyle", "listStyle", "pickerStyle",
             "toggleStyle", "labelStyle", "menuStyle", "progressViewStyle",
             "tabViewStyle", "scrollViewStyle", "indexViewStyle",
             "datePickerStyle", "gaugeStyle", "groupBoxStyle",
             "formStyle", "tableStyle", "controlGroupStyle",
             "symbolRenderingMode", "symbolVariant",
             "accessibilityLabel", "accessibilityHint", "accessibilityValue",
             "accessibilityHidden", "accessibilityIdentifier",
             "environment", "preferredColorScheme",
             "redacted", "unredacted",
             "onSubmit", "focused",
             "disableAutocorrection", "autocorrectionDisabled",
             "listRowBackground", "listRowSeparator",
             "listRowInsets", "swipeActions",
             "searchable", "refreshable",
             "confirmationDialog", "alert",
             "sheet", "fullScreenCover", "popover",
             "toolbar", "toolbarBackground", "navigationBarHidden",
             "navigationBarBackButtonHidden", "tabItem",
             "interactiveDismissDisabled",
             "presentationDetents", "presentationDragIndicator":
            return nil // Silently skip — recognized but not rendered

        default:
            return nil
        }
    }

    /// Parse a string interpolation expression (e.g. the "count" inside \(count))
    /// Returns nil if the expression text is empty or can't be parsed.
    private func parseInterpolationExpression(_ text: String) -> ViewNode? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Tokenize the expression
        do {
            let subLexer = SwiftLexer(source: trimmed)
            let subTokens = try subLexer.tokenize()
            // If it's just a single identifier, return a variable node
            if subTokens.count == 2, // identifier + eof
               case .identifier(let name) = subTokens[0].type {
                return .variable(name)
            }
            // For more complex expressions, try to parse them
            let subParser = SwiftParser()
            let node = try subParser.parse(subTokens)
            return node
        } catch {
            // Fallback to simple variable reference
            return .variable(trimmed)
        }
    }

    private func parseFont(_ node: ViewNode) -> FontStyle {
        if case .variable(let name) = node {
            switch name {
            case "largeTitle": return .largeTitle
            case "title": return .title
            case "title2": return .title2
            case "title3": return .title3
            case "headline": return .headline
            case "subheadline": return .subheadline
            case "body": return .body
            case "callout": return .callout
            case "footnote": return .footnote
            case "caption": return .caption
            case "caption2": return .caption2
            default: return .body
            }
        }
        // Handle .system(size:weight:design:)
        if case .functionCall(let name, let args) = node, name == "system" {
            var size: Double = 17
            var weight: FontWeight? = nil
            var design: FontDesign? = nil
            for arg in args {
                if arg.label == "size" || (arg.label == nil && args.first?.label == nil),
                   case .literal(.number(let n)) = arg.value {
                    size = n
                }
                if arg.label == "weight", case .variable(let w) = arg.value {
                    weight = FontWeight(rawValue: w)
                }
                if arg.label == "design", case .variable(let d) = arg.value {
                    design = FontDesign(rawValue: d)
                }
            }
            return .system(size: size, weight: weight, design: design)
        }
        return .body
    }
    
    private func applyModifier(to view: ViewNode, modifier: ViewModifier) -> ViewNode {
        if case .modified(let innerView, var mods) = view {
            mods.append(modifier)
            return .modified(view: innerView, modifiers: mods)
        }
        return .modified(view: view, modifiers: [modifier])
    }
    
    // MARK: - Closure Parsing
    
    /// Last captured closure parameter name (e.g., "book" from `{ book in ... }`)
    private var lastClosureParam: String? = nil

    private func parseClosureBody() throws -> ViewNode {
        var statements: [ViewNode] = []

        // Handle closure parameter: { identifier in ... } or { _ in ... }
        // Capture THIS closure's param into a local — recursive parses (e.g.
        // nested `isbn.flatMap { … }` inside `docs.map { doc in … }`) will reset
        // `lastClosureParam` and we'd lose ours by the time the caller reads it.
        lastClosureParam = nil
        if case .identifier(let paramName) = peek().type, peekNext().type == .keyword(.in) {
            lastClosureParam = paramName
            _ = advance() // consume parameter name
            _ = advance() // consume 'in'
            skipNewlines()
        }
        let myParam = lastClosureParam

        while !check(.rightBrace) && !isAtEnd {
            skipNewlines()
            if check(.rightBrace) { break }

            let stmt = try parseStatement()
            if case .empty = stmt {
                continue
            }
            statements.append(stmt)
            skipNewlines()
        }

        // Restore THIS closure's param so the caller (e.g. addTrailingClosure)
        // sees it instead of whatever inner closures last set.
        lastClosureParam = myParam

        if statements.count == 1 {
            return statements[0]
        }
        return .block(statements)
    }
    
    /// Turn an AsyncImage + closure-body pair into `.asyncImagePhased` when the
    /// body is a `switch phase { ... }`. Falls back to the plain AsyncImage if the
    /// body isn't shaped like a phase switch.
    private func phasedAsyncImage(urlExpression: ViewNode, closureBody: ViewNode) -> ViewNode {
        // Look for a switch statement at the top of the body.
        var switchNode: ViewNode? = nil
        switch closureBody {
        case .switchStmt:
            switchNode = closureBody
        case .block(let stmts):
            for s in stmts {
                if case .switchStmt = s { switchNode = s; break }
            }
        default:
            break
        }
        guard case .switchStmt(_, let cases, let defaultBody) = switchNode else {
            // No switch — just revert to the non-phased AsyncImage with default rendering.
            if case .literal(.string(let s)) = urlExpression {
                return .asyncImage(url: s)
            }
            return .asyncImageDynamic(urlExpression: urlExpression)
        }

        var emptyBranch: ViewNode? = nil
        var successBranch: ViewNode? = nil
        var failureBranch: ViewNode? = nil
        var imageBinding: String? = nil

        for branch in cases {
            guard case .caseMember(let name, let bindings) = branch.pattern else { continue }
            switch name {
            case "empty":
                emptyBranch = branch.body
            case "success":
                successBranch = branch.body
                imageBinding = bindings.first
            case "failure":
                failureBranch = branch.body
            default:
                break
            }
        }

        // `@unknown default: ...` ends up in defaultBody — use it as a backstop.
        if emptyBranch == nil { emptyBranch = defaultBody }

        return .asyncImagePhased(
            urlExpression: urlExpression,
            emptyBranch: emptyBranch,
            successBranch: successBranch,
            failureBranch: failureBranch,
            imageBinding: imageBinding
        )
    }

    private func addTrailingClosure(to view: ViewNode, body: ViewNode) -> ViewNode {
        let children: [ViewNode]
        if case .block(let stmts) = body {
            children = stmts
        } else {
            children = [body]
        }
        
        switch view {
        case .vStack(let spacing, let alignment, _):
            return .vStack(spacing: spacing, alignment: alignment, children: children)
        case .hStack(let spacing, let alignment, _):
            return .hStack(spacing: spacing, alignment: alignment, children: children)
        case .zStack(let alignment, _):
            return .zStack(alignment: alignment, children: children)
        case .navigationStack(_):
            return .navigationStack(children: children)
        case .navigationLink(let existingLabel, let destination):
            // The trailing closure is the LABEL view if we're in form 2:
            //   NavigationLink(destination: D()) { Label() }
            // It's never the destination — that came in via the named arg.
            // If we already saw a positional-arg label (form 1), keep it.
            if case .empty = existingLabel {
                let labelView = children.count == 1 ? children[0] : body
                return .navigationLink(label: labelView, destination: destination)
            }
            return view
        case .scrollView(let axis, let indicators, _):
            return .scrollView(axis: axis, showsIndicators: indicators, content: body)
        case .button(let label, let existingAction):
            if existingAction != nil {
                // Button(action: { ... }) { label } — trailing closure is the label
                let newLabel = children.count == 1 ? children[0] : body
                return .button(label: newLabel, action: existingAction)
            }
            // Button("Title") { action } — trailing closure is the action
            return .button(label: label, action: body)
        case .forEach(let range, _, _):
            return .forEach(range: range, variable: lastClosureParam ?? "_", body: body)
        case .forEachCollection(let collection, _, _):
            return .forEachCollection(collection: collection, variable: lastClosureParam ?? "_", body: body)

        // Plan 6 containers — attach trailing closure as content
        case .lazyVGrid(let columns, let spacing, _):
            return .lazyVGrid(columns: columns, spacing: spacing, content: body)
        case .lazyHGrid(let rows, let spacing, _):
            return .lazyHGrid(rows: rows, spacing: spacing, content: body)
        case .geometryReader(_, _):
            return .geometryReader(variable: lastClosureParam ?? "geo", body: body)

        // Plan 8 — AsyncImage { phase in switch phase { ... } }. Try to recognize
        // the switch inside the closure body and hoist its branches.
        case .asyncImage(let urlString):
            return phasedAsyncImage(
                urlExpression: .literal(.string(urlString)),
                closureBody: body
            )
        case .asyncImageDynamic(let urlExpression):
            return phasedAsyncImage(urlExpression: urlExpression, closureBody: body)

        // Toggle(isOn: $flag) { label view }
        case .toggle(_, let variable):
            let labelView = children.count == 1 ? children[0] : body
            // We store the label as text for simplicity — extract text if possible
            if case .text(let s) = labelView {
                return .toggle(label: s, variable: variable)
            }
            return .toggle(label: "", variable: variable)

        // ProgressView — trailing closure not standard, but handle gracefully
        case .functionCall(let name, let args) where name == "ProgressView":
            return .functionCall(name: name, arguments: args)

        // Plan 7: `withAnimation(curve) { mutation }` and `Task { body }` —
        // append the trailing closure as a final positional argument so the
        // evaluator can execute it.
        case .functionCall(let name, let args)
            where name == "withAnimation" || name == "Task":
            return .functionCall(name: name, arguments: args + [Argument(label: nil, value: body)])

        // Trailing-closure modifiers: .overlay { content }, .onTapGesture { action }
        case .propertyAccess(let base, let propName):
            switch propName {
            case "overlay":
                return applyModifier(to: base, modifier: .overlay(body))
            case "onTapGesture":
                return applyModifier(to: base, modifier: .onTapGesture(body))
            case "onLongPressGesture":
                return applyModifier(to: base, modifier: .onLongPressGesture(body))
            case "onChange":
                return applyModifier(to: base, modifier: .onChange(variable: nil, action: body))
            case "onAppear":
                return applyModifier(to: base, modifier: .onAppear(body))
            case "onDisappear":
                return applyModifier(to: base, modifier: .onDisappear(body))
            case "task":
                // .task { await … } — runs in a real SwiftUI async context so
                // network fetches inside the body suspend without blocking
                // the main thread (the renderer wires this to `view.task`).
                return applyModifier(to: base, modifier: .taskAction(body))
            case "refreshable":
                // Real pull-to-refresh — body runs when the user drags down.
                return applyModifier(to: base, modifier: .refreshable(body))
            case "mask":
                return applyModifier(to: base, modifier: .mask(body))

            // View-only modifiers we don't yet wire to real SwiftUI behavior.
            // We swallow the closure and return the receiver unchanged, so the
            // chain stays a view node (vs. wrapping in `.methodCall` below,
            // which would make the entire view invisible).
            //
            // Without this, `TextField(...).onSubmit { … }` ended up as a
            // .methodCall at the top of the view tree, and the renderer
            // dropped it as a non-view — that's why the search bar in the
            // user's LibraryApp.swift never appeared.
            case "onSubmit":
                return applyModifier(to: base, modifier: .onSubmitAction(body))

            // Other view-only modifiers we don't yet wire to real SwiftUI behavior.
            // Swallow the closure and return the receiver unchanged so the chain
            // stays a view node.
            case "onMoveCommand",
                 "onPasteCommand",
                 "onCopyCommand",
                 "onCutCommand",
                 "onContinueUserActivity",
                 "onOpenURL",
                 "onReceive",
                 "gesture",
                 "highPriorityGesture",
                 "simultaneousGesture",
                 "draggable",
                 "dropDestination",
                 "contextMenu",
                 "confirmationDialog",
                 "popover",
                 "focused",
                 "searchable":
                _ = body
                return base
            default:
                // Treat unknown `receiver.method { … }` as a method call whose
                // sole positional arg is the closure body. This lets collection
                // operations like `docs.map { doc in … }`, `isbn.flatMap { … }`,
                // `items.filter { $0 > 0 }`, `items.compactMap { … }`, etc. preserve
                // their closure instead of silently dropping it. Wrap with the
                // captured closure parameter (set by `parseClosureBody` via
                // `lastClosureParam`) so map/filter callers can bind the
                // iteration variable.
                let wrappedBody: ViewNode
                if let param = lastClosureParam {
                    wrappedBody = .closure(parameters: [param], body: body)
                } else {
                    wrappedBody = body
                }
                return .methodCall(
                    object: base,
                    method: propName,
                    arguments: [Argument(label: nil, value: wrappedBody)]
                )
            }

        // Handle .modified where last modifier needs a trailing closure (e.g., .onChange(of:) { action })
        case .modified(let innerView, var mods):
            if let lastIdx = mods.indices.last {
                switch mods[lastIdx] {
                case .onChange(let variable, .empty):
                    mods[lastIdx] = .onChange(variable: variable, action: body)
                    return .modified(view: innerView, modifiers: mods)
                case .onAppear(nil):
                    mods[lastIdx] = .onAppear(body)
                    return .modified(view: innerView, modifiers: mods)
                case .onDisappear(nil):
                    mods[lastIdx] = .onDisappear(body)
                    return .modified(view: innerView, modifiers: mods)
                case .refreshable(.empty):
                    mods[lastIdx] = .refreshable(body)
                    return .modified(view: innerView, modifiers: mods)
                case .taskActionWithID(let id, .empty):
                    mods[lastIdx] = .taskActionWithID(idExpression: id, action: body)
                    return .modified(view: innerView, modifiers: mods)
                case .sheet(let bindingVar, .empty):
                    mods[lastIdx] = .sheet(isPresentedVar: bindingVar, content: body)
                    return .modified(view: innerView, modifiers: mods)
                case .fullScreenCover(let bindingVar, .empty):
                    mods[lastIdx] = .fullScreenCover(isPresentedVar: bindingVar, content: body)
                    return .modified(view: innerView, modifiers: mods)
                case .alert(let title, let bindingVar, .empty, let message):
                    mods[lastIdx] = .alert(title: title, isPresentedVar: bindingVar, actions: body, message: message)
                    return .modified(view: innerView, modifiers: mods)
                default:
                    break
                }
            }
            return view

        default:
            return view
        }
    }

    /// Handle labeled trailing closures like `Button { action } label: { views }`.
    private func addLabeledTrailingClosure(to view: ViewNode, label closureLabel: String, body: ViewNode) -> ViewNode {
        let content: ViewNode
        if case .block(let stmts) = body, stmts.count == 1 {
            content = stmts[0]
        } else {
            content = body
        }

        switch view {
        case .button(_, let action) where closureLabel == "label":
            return .button(label: content, action: action)

        // Label { Text("title") } icon: { Image(systemName: "star") }
        case .hStack(_, _, let existingChildren) where closureLabel == "icon":
            // First closure was the title, icon: closure is the icon
            return .hStack(spacing: 6, alignment: nil, children: [content] + existingChildren)

        default:
            return view
        }
    }

    // MARK: - Argument Parsing
    
    private func parseArgument() throws -> Argument {
        // Check for labeled argument: `name: value`
        // Also handle keywords used as labels (e.g., `in:`, `for:`, `self:`)
        if checkNext(.colon) {
            let label: String?
            switch peek().type {
            case .identifier(let name):
                label = name
            case .keyword(let kw):
                label = kw.rawValue  // handles `in:`, `for:`, etc.
            default:
                label = nil
            }
            if let label = label {
                _ = advance() // consume label
                _ = advance() // consume :
                let value = try parseExpression()
                return Argument(label: label, value: value)
            }
        }

        let value = try parseExpression()
        return Argument(value: value)
    }
    
    // MARK: - Helpers
    
    private var isAtEnd: Bool {
        if case .eof = peek().type { return true }
        return current >= tokens.count
    }
    
    private func peek() -> Token {
        guard current < tokens.count else {
            return Token(type: .eof)
        }
        return tokens[current]
    }
    
    private func peekNext() -> Token {
        guard current + 1 < tokens.count else {
            return Token(type: .eof)
        }
        return tokens[current + 1]
    }
    
    // MARK: - Plan 1 statement parsers

    /// Parse `switch <expr> { case <pattern>: <body> ... default: <body> }`.
    private func parseSwitchStatement() throws -> ViewNode {
        _ = advance() // consume `switch`
        skipNewlines()
        // Use parseConditionExpression so a trailing `{` isn't swallowed as a
        // trailing closure to the scrutinee — same trick `if` uses.
        let scrutinee = try parseConditionExpression()
        skipNewlines()
        guard check(.leftBrace) else {
            throw ParserError.unexpectedToken(peek(), expected: "'{'",
                hint: "expected opening brace of switch body")
        }
        _ = advance()
        skipNewlines()

        var cases: [SwitchCase] = []
        var defaultBody: ViewNode? = nil

        while !check(.rightBrace) && !isAtEnd {
            // Consume attributes like `@unknown` before `default` / `case`.
            while case .attribute = peek().type { _ = advance(); skipNewlines() }

            if check(.keyword(.case)) {
                _ = advance()
                skipNewlines()
                let pattern = try parseSwitchPattern()
                skipNewlines()
                guard check(.colon) else {
                    throw ParserError.unexpectedToken(peek(), expected: "':'",
                        hint: "expected ':' after case pattern")
                }
                _ = advance()
                skipNewlines()
                let body = try parseCaseBody()
                cases.append(SwitchCase(pattern: pattern, body: body))
            } else if check(.keyword(.default)) {
                _ = advance()
                guard check(.colon) else {
                    throw ParserError.unexpectedToken(peek(), expected: "':'",
                        hint: "expected ':' after default")
                }
                _ = advance()
                skipNewlines()
                defaultBody = try parseCaseBody()
            } else {
                throw ParserError.unexpectedToken(peek(), expected: "'case' or 'default'")
            }
            skipNewlines()
        }
        if check(.rightBrace) { _ = advance() }
        return .switchStmt(scrutinee: scrutinee, cases: cases, defaultBody: defaultBody)
    }

    private func parseSwitchPattern() throws -> SwitchPattern {
        // `.identifier` or `.identifier(let x, let y)`
        if check(.dot) {
            _ = advance()
            guard case .identifier(let name) = peek().type else {
                // Allow `.success(let img)` where `success` is the member — identifier case.
                // If we got something else, report.
                throw ParserError.unexpectedToken(peek(), expected: "enum case name after '.'")
            }
            _ = advance()
            var bindings: [String] = []
            if check(.leftParen) {
                _ = advance()
                while !check(.rightParen) && !isAtEnd {
                    // Optional `let` before each binding
                    if check(.keyword(.let)) || check(.keyword(.var)) { _ = advance() }
                    if case .identifier(let n) = peek().type {
                        bindings.append(n)
                        _ = advance()
                    } else {
                        // Skip unexpected token to avoid infinite loop
                        _ = advance()
                    }
                    if check(.comma) { _ = advance() }
                }
                if check(.rightParen) { _ = advance() }
            }
            return .caseMember(name: name, bindings: bindings)
        }
        // Wildcard `_`
        if case .identifier("_") = peek().type {
            _ = advance()
            return .wildcard
        }
        // Literal pattern — string or number
        let expr = try parseExpression()
        if case .literal(let lit) = expr { return .literal(lit) }
        throw ParserError.unexpectedToken(peek(),
            expected: "case pattern (enum member, literal, or '_')")
    }

    /// Case body ends at the next `case`, `default`, `@attribute` (e.g. @unknown),
    /// or closing `}` of the switch.
    private func parseCaseBody() throws -> ViewNode {
        var stmts: [ViewNode] = []
        while true {
            skipNewlines()
            if check(.keyword(.case)) || check(.keyword(.default))
                || check(.rightBrace) || isAtEnd { break }
            if case .attribute = peek().type { break }
            let s = try parseStatement()
            if case .empty = s { continue }
            stmts.append(s)
        }
        if stmts.count == 1 { return stmts[0] }
        return .block(stmts)
    }

    /// Parse `do { <body> } catch [binding] { <body> }...`
    private func parseDoCatch() throws -> ViewNode {
        _ = advance() // consume `do`
        skipNewlines()
        let body = try parseBraceBlock()
        skipNewlines()
        var clauses: [CatchClause] = []
        while check(.keyword(.catch)) {
            _ = advance()
            skipNewlines()
            var binding: String? = nil
            // Optional `let binding` or bare identifier before the `{`
            if check(.keyword(.let)) { _ = advance() }
            if case .identifier(let name) = peek().type, !check(.leftBrace) {
                binding = name
                _ = advance()
            }
            skipNewlines()
            let catchBody = try parseBraceBlock()
            clauses.append(CatchClause(binding: binding, body: catchBody))
            skipNewlines()
        }
        return .doCatch(body: body, clauses: clauses)
    }

    /// Parse `throw <expr>`.
    private func parseThrowStatement() throws -> ViewNode {
        _ = advance() // consume `throw`
        skipNewlines()
        let expr = try parseExpression()
        return .throwStmt(expr)
    }

    /// Parse `guard let x [= y] else { ... }` or `guard <cond> else { ... }`.
    private func parseGuardStatement() throws -> ViewNode {
        _ = advance() // consume `guard`
        skipNewlines()

        if check(.keyword(.let)) || check(.keyword(.var)) {
            _ = advance()
            skipNewlines()
            guard case .identifier(let name) = peek().type else {
                throw ParserError.unexpectedToken(peek(), expected: "variable name after 'let'")
            }
            _ = advance()
            var value: ViewNode = .variable(name)
            if check(.equals) {
                _ = advance()
                skipNewlines()
                value = try parseExpression()
            }
            skipNewlines()
            // Additional comma-separated conditions: lower to a wrapping
            // `guardExpr` around the original `guardLet` so all clauses must
            // hold. e.g. `guard let x = y, !x.isEmpty else { return }` becomes
            // guardLet(x = y, else) followed by guardExpr(!x.isEmpty, else).
            var extraConditions: [ViewNode] = []
            while check(.comma) {
                _ = advance()
                skipNewlines()
                extraConditions.append(try parseExpression())
                skipNewlines()
            }
            guard check(.keyword(.else)) else {
                throw ParserError.unexpectedToken(peek(), expected: "'else' in guard")
            }
            _ = advance()
            skipNewlines()
            let elseBlock = try parseBraceBlock()
            let guardLet = ViewNode.guardLet(variable: name, value: value, elseBlock: elseBlock)
            if extraConditions.isEmpty { return guardLet }
            let combined = extraConditions.dropFirst().reduce(extraConditions[0]) { acc, c in
                .binary(left: acc, op: .and, right: c)
            }
            return .block([guardLet, .guardExpr(condition: combined, elseBlock: elseBlock)])
        }

        var cond = try parseExpression()
        skipNewlines()
        // Multi-clause guard: `guard A, B, C else { ... }` ≡ `guard A && B && C else { ... }`.
        while check(.comma) {
            _ = advance()
            skipNewlines()
            let next = try parseExpression()
            cond = .binary(left: cond, op: .and, right: next)
            skipNewlines()
        }
        guard check(.keyword(.else)) else {
            throw ParserError.unexpectedToken(peek(), expected: "'else' in guard")
        }
        _ = advance()
        skipNewlines()
        let elseBlock = try parseBraceBlock()
        return .guardExpr(condition: cond, elseBlock: elseBlock)
    }

    /// Parse `defer { <body> }`.
    private func parseDeferBlock() throws -> ViewNode {
        _ = advance() // consume `defer`
        skipNewlines()
        return .deferBlock(try parseBraceBlock())
    }

    /// Parse `enum <Name> [: Conf1, Conf2] { case ...; static func ...() }`.
    private func parseEnumDeclaration() throws -> ViewNode {
        _ = advance() // consume `enum`
        skipNewlines()
        guard case .identifier(let name) = peek().type else {
            throw ParserError.unexpectedToken(peek(), expected: "enum name")
        }
        _ = advance()
        // Skip conformance list
        if check(.colon) {
            _ = advance()
            while !check(.leftBrace) && !isAtEnd { _ = advance() }
        }
        guard check(.leftBrace) else {
            throw ParserError.unexpectedToken(peek(), expected: "'{' to open enum body")
        }
        _ = advance()
        skipNewlines()

        var cases: [EnumCase] = []
        var members: [ViewNode] = []

        while !check(.rightBrace) && !isAtEnd {
            // Consume leading attributes and modifiers.
            while case .attribute = peek().type { _ = advance(); skipNewlines() }
            while case .identifier(let mod) = peek().type,
                  ["static", "private", "public", "internal", "fileprivate", "open",
                   "indirect", "final", "mutating", "nonmutating", "override"].contains(mod) {
                _ = advance(); skipNewlines()
            }

            if check(.keyword(.case)) {
                _ = advance()
                skipNewlines()
                // Comma-separated case list on one line
                while true {
                    guard case .identifier(let caseName) = peek().type else { break }
                    _ = advance()
                    var assoc: [String] = []
                    var raw: ViewNode? = nil
                    if check(.leftParen) {
                        _ = advance()
                        while !check(.rightParen) && !isAtEnd {
                            if case .identifier(let t) = peek().type {
                                assoc.append(t); _ = advance()
                            } else { _ = advance() }
                            if check(.comma) { _ = advance() }
                        }
                        if check(.rightParen) { _ = advance() }
                    } else if check(.equals) {
                        _ = advance()
                        skipNewlines()
                        raw = try parseExpression()
                    }
                    cases.append(EnumCase(name: caseName, associatedTypes: assoc, rawValue: raw))
                    skipNewlines()
                    if check(.comma) { _ = advance(); skipNewlines(); continue }
                    break
                }
            } else if check(.keyword(.func)) {
                members.append(try skipFuncDeclaration())
            } else if check(.keyword(.var)) || check(.keyword(.let)) {
                members.append(try parseStatement())
            } else if check(.rightBrace) {
                break
            } else {
                // Unknown member — advance one token to avoid infinite loop
                _ = advance()
            }
            skipNewlines()
        }
        if check(.rightBrace) { _ = advance() }
        return .enumDeclaration(name: name, cases: cases, members: members)
    }

    /// Parse `extension <Type> [: Conf1, Conf2] { ... }`.
    private func parseExtensionDeclaration() throws -> ViewNode {
        _ = advance() // consume `extension`
        skipNewlines()
        guard case .identifier(let target) = peek().type else {
            throw ParserError.unexpectedToken(peek(), expected: "type name after 'extension'")
        }
        _ = advance()
        if check(.colon) {
            _ = advance()
            while !check(.leftBrace) && !isAtEnd { _ = advance() }
        }
        guard check(.leftBrace) else {
            throw ParserError.unexpectedToken(peek(), expected: "'{' to open extension body")
        }
        _ = advance()
        skipNewlines()

        var members: [ViewNode] = []
        while !check(.rightBrace) && !isAtEnd {
            while case .attribute = peek().type { _ = advance(); skipNewlines() }
            while case .identifier(let mod) = peek().type,
                  ["static", "private", "public", "internal", "fileprivate", "open",
                   "mutating", "nonmutating", "override", "final"].contains(mod) {
                _ = advance(); skipNewlines()
            }
            if check(.rightBrace) { break }
            let m = try parseStatement()
            if case .empty = m { skipNewlines(); continue }
            members.append(m)
            skipNewlines()
        }
        if check(.rightBrace) { _ = advance() }
        return .extensionDeclaration(target: target, members: members)
    }

    /// Parse a `protocol Foo { ... }` declaration by skipping its body entirely.
    /// Protocols have no runtime meaning in SwiftRunner yet.
    private func skipProtocolDeclaration() throws -> ViewNode {
        _ = advance() // consume `protocol`
        while !check(.leftBrace) && !isAtEnd { _ = advance() }
        if check(.leftBrace) {
            _ = advance()
            var depth = 1
            while depth > 0 && !isAtEnd {
                if check(.leftBrace) { depth += 1 }
                if check(.rightBrace) { depth -= 1 }
                _ = advance()
            }
        }
        return .empty
    }

    /// Parse a `{ stmt; stmt; ... }` block — expects the `{` under `peek()`.
    private func parseBraceBlock() throws -> ViewNode {
        guard check(.leftBrace) else {
            throw ParserError.unexpectedToken(peek(), expected: "'{'")
        }
        _ = advance()
        skipNewlines()
        var stmts: [ViewNode] = []
        while !check(.rightBrace) && !isAtEnd {
            let s = try parseStatement()
            if case .empty = s { skipNewlines(); continue }
            stmts.append(s)
            skipNewlines()
        }
        if check(.rightBrace) { _ = advance() }
        if stmts.count == 1 { return stmts[0] }
        return .block(stmts)
    }

    // MARK: - Helpers

    @discardableResult
    private func advance() -> Token {
        let token = peek()
        current += 1
        return token
    }

    private func check(_ type: TokenType) -> Bool {
        peek().type == type
    }

    /// True when the current token sits immediately after the previous token
    /// with no whitespace between them (same line, column N+1 after a column-N
    /// end). Used to distinguish `?.prop` (optional chain, no space before `?`)
    /// from `a ? b : c` (ternary, space before `?`).
    private func isAdjacentToPrevious() -> Bool {
        guard current > 0 else { return false }
        let prev = tokens[current - 1]
        let curr = peek()
        guard prev.line == curr.line else { return false }
        // Tokens record their end column in `column`. Adjacent when curr.column
        // == prev.column + 1 (single-char tokens) — looser check below allows
        // any prev length.
        return curr.column == prev.column + 1
    }
    
    private func checkNext(_ type: TokenType) -> Bool {
        peekNext().type == type
    }
    
    private func match(_ type: TokenType) -> Bool {
        if check(type) {
            _ = advance()
            return true
        }
        return false
    }
    
    private func skipNewlines() {
        while check(.newline) || check(.semicolon) {
            _ = advance()
        }
    }
}
