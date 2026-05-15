//
//  SwiftRunner.swift
//  SwiftRunner
//
//  Created by Claw on 2/21/26.
//

import SwiftUI

/// Main API for running Swift code and rendering SwiftUI views
@MainActor
public final class SwiftRunner: ObservableObject {
    
    /// Shared instance
    public static let shared = SwiftRunner()
    
    /// Console output buffer
    @Published public var consoleOutput: String = ""
    
    /// Any errors from the last run
    @Published public var errors: [String] = []
    
    /// Whether the last run produced a view
    @Published public var hasView: Bool = false
    
    /// The parsed AST (for debugging)
    public var lastAST: ViewNode?

    /// The post-dedup, post-stripEmpty view AST that was actually rendered
    /// on the most recent `run(_:)`. Exposed for tests to assert which view
    /// branch deduplication picked when the source contains multiple structs.
    public var cleanASTForTesting: ViewNode?

    /// The post-dedup AST passed to `registerDeclarations`. Exposed for tests
    /// to assert that user functions / enums / extensions survive dedup so the
    /// runtime function table gets populated.
    public var dedupedASTForTesting: ViewNode?
    
    private let lexer = SwiftLexer(source: "")
    private let parser = SwiftParser()
    
    private init() {}
    
    /// Run Swift code and return the result
    public func run(_ code: String) -> RunResult {
        consoleOutput = ""
        errors = []
        hasView = false
        lastAST = nil
        cleanASTForTesting = nil
        dedupedASTForTesting = nil
        // Drop the fetch cache so a new code block doesn't see stale URL hits
        // from the previous run. Within a single run, identical URLs (e.g.
        // re-fired .onAppear when a tab toggles) still return cached data.
        SwiftRunnerState.clearFetchCache()

        print("[SwiftRunner] run() called with code (\(code.count) chars):")
        print("[SwiftRunner] ---BEGIN CODE---")
        print(code)
        print("[SwiftRunner] ---END CODE---")

        do {
            // Tokenize
            let lexer = SwiftLexer(source: code)
            let tokens = try lexer.tokenize()
            print("[SwiftRunner] Lexer produced \(tokens.count) tokens")
            for (i, tok) in tokens.enumerated() {
                print("[SwiftRunner]   token[\(i)] = \(tok) (line \(tok.line))")
            }

            // Parse
            var ast = try parser.parse(tokens)
            lastAST = ast

            // Deduplicate: when a #Preview calls a custom struct, the struct body
            // appears twice (once from struct parsing, once from preview instantiation).
            // Keep only the last view-producing statement (the preview result).
            ast = deduplicatePreview(ast, parsedStructs: parser.parsedStructs)
            dedupedASTForTesting = ast

            print("[SwiftRunner] Parser produced AST: \(ast)")

            // Evaluate expressions and collect print output
            var output = ""
            evaluateForConsole(ast, output: &output)
            consoleOutput = output

            // Separate state variable declarations from view content
            let (stateVars, viewAST) = separateState(ast)
            print("[SwiftRunner] State vars: \(stateVars)")
            print("[SwiftRunner] View AST: \(viewAST)")

            // Strip .empty from top-level AST
            let cleanAST = stripEmpty(viewAST)
            cleanASTForTesting = cleanAST
            print("[SwiftRunner] Clean AST: \(cleanAST)")

            // Check if the AST represents a view
            let isView = isViewNode(cleanAST)
            print("[SwiftRunner] isViewNode = \(isView)")

            if isView {
                hasView = true
                let state = SwiftRunnerState(stateVars)
                // Plan 2: hoist any user-defined functions, enum static funcs,
                // and extension methods from the original AST into the state's
                // function table so call sites like `BookService.search(...)` and
                // `load()` can dispatch at runtime.
                registerDeclarations(ast, state: state)
                // Plan 5 capstone: propagate struct field-type schemas so
                // JSONDecoder can deep-tag nested decoded values with `_type`
                // and computed properties dispatch on inner elements too.
                state.typeSchemas = parser.parsedSchemas
                let view = AnyView(DynamicView(ast: cleanAST, state: state))
                print("[SwiftRunner] View built with state: \(stateVars)")
                return RunResult(view: view, consoleOutput: output, errors: [])
            } else {
                print("[SwiftRunner] AST is NOT a view node — returning nil view")
                return RunResult(view: nil, consoleOutput: output, errors: [])
            }

        } catch let error as LexerError {
            let msg = formatError(error.localizedDescription, line: error.line, sourceCode: code)
            print("[SwiftRunner] LexerError: \(msg)")
            errors = [msg]
            return RunResult(view: nil, consoleOutput: "", errors: [msg])

        } catch let error as ParserError {
            let msg = formatError(error.localizedDescription, line: error.line, sourceCode: code)
            print("[SwiftRunner] ParserError: \(msg)")
            errors = [msg]
            return RunResult(view: nil, consoleOutput: "", errors: [msg])

        } catch {
            let msg = error.localizedDescription
            print("[SwiftRunner] Unknown error: \(msg)")
            errors = [msg]
            return RunResult(view: nil, consoleOutput: "", errors: [msg])
        }
    }

    /// Separate state variable declarations from view content.
    /// Recursively collects all assignments from nested blocks.
    /// Returns (state variables as Value dict, remaining view AST).
    /// When code has struct declarations + #Preview, both produce view ASTs.
    /// Keep only the LAST view-producing top-level statement (Swift convention
    /// puts the main view / `#Preview` block at the bottom of the file) and
    /// gather all state declarations from any struct blocks along the way.
    ///
    /// History: the previous implementation preferred the *first* view fallback
    /// when no statement contained a custom-view call, which broke files like
    /// LibraryApp.swift where `#Preview { LibraryApp() }` gets inlined (so the
    /// custom-call signal is lost) and the first View struct (PlaceholderCard)
    /// won by accident.
    private func deduplicatePreview(_ node: ViewNode, parsedStructs: [String: ParsedStruct]) -> ViewNode {
        guard case .block(let statements) = node, statements.count > 1 else { return node }

        var stateStatements: [ViewNode] = []
        // Top-level declaration nodes (free functions, enums, extensions) and
        // declarations nested inside struct blocks. These must be preserved
        // through dedup — `registerDeclarations` walks the post-dedup AST to
        // populate the runtime function table, so dropping these breaks all
        // user-function dispatch (`load()`, `BookService.search`, etc.).
        var declarationStatements: [ViewNode] = []
        var lastViewStatement: ViewNode? = nil

        func isDeclaration(_ n: ViewNode) -> Bool {
            switch n {
            case .functionDecl, .enumDeclaration, .extensionDeclaration: return true
            default: return false
            }
        }

        for stmt in statements {
            // Always pull state assignments and declarations out of any block
            // we walk past, regardless of whether we end up rendering it.
            if case .block(let inner) = stmt {
                for child in inner {
                    if case .assignment = child {
                        stateStatements.append(child)
                    } else if isDeclaration(child) {
                        declarationStatements.append(child)
                    }
                }
            }
            if case .assignment = stmt {
                stateStatements.append(stmt)
            }
            if isDeclaration(stmt) {
                declarationStatements.append(stmt)
            }

            // Pick the LAST candidate view-producing statement. A statement
            // qualifies if it's an explicit custom-view call, a struct body
            // block, or a bare view node (e.g. an inlined `{ Foo() }` from a
            // stripped `#Preview`).
            if containsCustomViewCall(stmt, names: Set(parsedStructs.keys)) {
                lastViewStatement = stmt
            } else if case .block = stmt {
                lastViewStatement = stmt
            } else if isViewNode(stmt) {
                lastViewStatement = stmt
            }
        }

        guard let view = lastViewStatement else { return node }

        // Order matters for `registerDeclarations`: declarations first so the
        // function table is populated before any view body references them.
        let prefix = declarationStatements + stateStatements
        if prefix.isEmpty { return view }
        return .block(prefix + [view])
    }

    private func containsCustomViewCall(_ node: ViewNode, names: Set<String>) -> Bool {
        switch node {
        case .block(let stmts):
            return stmts.contains { containsCustomViewCall($0, names: names) }
        case .assignment(_, _, let value):
            return containsCustomViewCall(value, names: names)
        case .functionCall(let name, _):
            return names.contains(name)
        case .vStack(_, _, let children),
             .hStack(_, _, let children),
             .zStack(_, let children),
             .navigationStack(let children):
            return children.contains { containsCustomViewCall($0, names: names) }
        case .modified(let view, _):
            return containsCustomViewCall(view, names: names)
        case .scrollView(_, _, let content):
            return containsCustomViewCall(content, names: names)
        case .lazyVGrid(_, _, let content),
             .lazyHGrid(_, _, let content):
            return containsCustomViewCall(content, names: names)
        case .geometryReader(_, let body):
            return containsCustomViewCall(body, names: names)
        case .conditional(_, let thenBody, let elseBody):
            if containsCustomViewCall(thenBody, names: names) { return true }
            if let e = elseBody { return containsCustomViewCall(e, names: names) }
            return false
        case .forEach(_, _, let body),
             .forEachCollection(_, _, let body):
            return containsCustomViewCall(body, names: names)
        case .button(let label, _):
            return containsCustomViewCall(label, names: names)
        case .navigationLink(let label, let destination):
            // Recurse through both label and destination so a navigation
            // link to a custom-struct view counts as a custom view call.
            return containsCustomViewCall(label, names: names)
                || containsCustomViewCall(destination, names: names)
        default:
            return false
        }
    }

    private func separateState(_ node: ViewNode) -> ([String: Value], ViewNode) {
        var stateVars: [String: Value] = [:]
        let viewAST = collectAndStrip(node, into: &stateVars)
        return (stateVars, viewAST)
    }

    /// Recursively walk the AST, collecting assignments into stateVars
    /// and returning the AST with assignments removed.
    private func collectAndStrip(_ node: ViewNode, into stateVars: inout [String: Value]) -> ViewNode {
        switch node {
        case .assignment(let name, _, let value):
            // Only strip assignments whose values can be statically resolved.
            // Assignments with runtime expressions (ternaries, variables, etc.)
            // stay in the AST for render-time evaluation.
            if case .literal(.nil) = value {
                stateVars[name] = .nil
                return .empty
            }
            let staticValue = nodeToValue(value)
            if case .nil = staticValue {
                // Contains runtime expression — keep in AST
                return node
            }
            stateVars[name] = staticValue
            return .empty

        case .block(let statements):
            var viewStatements: [ViewNode] = []
            for stmt in statements {
                let result = collectAndStrip(stmt, into: &stateVars)
                if case .empty = result { continue }
                viewStatements.append(result)
            }
            if viewStatements.count == 1 { return viewStatements[0] }
            if viewStatements.isEmpty { return .empty }
            return .block(viewStatements)

        default:
            return node
        }
    }

    private func nodeToValue(_ node: ViewNode) -> Value {
        switch node {
        case .literal(.number(let n)): return .number(n)
        case .literal(.string(let s)): return .string(s)
        case .literal(.boolean(let b)): return .boolean(b)
        case .literal(.nil): return .nil
        case .arrayLiteral(let elements): return .array(elements.map { nodeToValue($0) })
        // Handle unary minus: -1 is parsed as binary(0, -, 1)
        case .binary(let left, .minus, let right):
            if case .literal(.number(let l)) = left, l == 0,
               case .literal(.number(let r)) = right {
                return .number(-r)
            }
            return .nil
        default: return .nil
        }
    }

    /// Strip .empty and non-view nodes from the AST so they don't interfere with rendering
    private func stripEmpty(_ node: ViewNode) -> ViewNode {
        switch node {
        case .block(let statements):
            // Keep view nodes and runtime assignments from blocks
            let viewNodes = statements.compactMap { stmt -> ViewNode? in
                let cleaned = stripEmpty(stmt)
                if case .empty = cleaned { return nil }
                // Keep assignments (custom view args evaluated at render time)
                if case .assignment = cleaned { return cleaned }
                // Drop other non-view nodes (functionCalls, etc.)
                if !isViewNode(cleaned) {
                    print("[SwiftRunner] stripEmpty: dropping non-view node: \(cleaned)")
                    return nil
                }
                return cleaned
            }
            if viewNodes.isEmpty { return .empty }
            if viewNodes.count == 1 { return viewNodes[0] }
            return .block(viewNodes)
        default:
            return node
        }
    }

    // MARK: - String Interpolation Resolution

    /// Collect variable initial values from assignment nodes in the AST
    private func collectVariables(_ node: ViewNode, into variables: inout [String: String]) {
        switch node {
        case .assignment(let name, _, let value):
            switch value {
            case .literal(.number(let n)):
                variables[name] = n == floor(n) ? String(Int(n)) : String(n)
            case .literal(.string(let s)):
                variables[name] = s
            case .literal(.boolean(let b)):
                variables[name] = b ? "true" : "false"
            default:
                break
            }
        case .block(let statements):
            for stmt in statements {
                collectVariables(stmt, into: &variables)
            }
        default:
            break
        }
    }

    /// Walk the AST and resolve string interpolation nodes into plain strings
    private func resolveInterpolation(_ node: ViewNode, variables: [String: String]) -> ViewNode {
        switch node {
        case .stringInterpolation(let parts):
            var result = ""
            for part in parts {
                switch part {
                case .literal(let text):
                    result += text
                case .expression(let expr):
                    result += resolveExpressionToString(expr, variables: variables)
                }
            }
            return .literal(.string(result))

        case .text(let s):
            // Text nodes don't have interpolation (already resolved at token level)
            return .text(s)

        case .block(let statements):
            return .block(statements.map { resolveInterpolation($0, variables: variables) })

        case .vStack(let spacing, let alignment, let children):
            return .vStack(spacing: spacing, alignment: alignment,
                           children: children.map { resolveInterpolation($0, variables: variables) })

        case .hStack(let spacing, let alignment, let children):
            return .hStack(spacing: spacing, alignment: alignment,
                           children: children.map { resolveInterpolation($0, variables: variables) })

        case .zStack(let alignment, let children):
            return .zStack(alignment: alignment,
                           children: children.map { resolveInterpolation($0, variables: variables) })

        case .button(let label, let action):
            return .button(label: resolveInterpolation(label, variables: variables), action: action)

        case .modified(let view, let modifiers):
            return .modified(view: resolveInterpolation(view, variables: variables), modifiers: modifiers)

        case .scrollView(let axis, let indicators, let content):
            return .scrollView(axis: axis, showsIndicators: indicators,
                               content: resolveInterpolation(content, variables: variables))

        case .forEach(let range, let variable, let body):
            return .forEach(range: range, variable: variable,
                            body: resolveInterpolation(body, variables: variables))

        case .functionCall(let name, let arguments):
            // Resolve interpolation inside function arguments (e.g. Text("\(count)"))
            let resolvedArgs = arguments.map { arg in
                Argument(label: arg.label, value: resolveInterpolation(arg.value, variables: variables))
            }
            return .functionCall(name: name, arguments: resolvedArgs)

        default:
            return node
        }
    }

    /// Resolve a ViewNode expression to a string using collected variable values
    private func resolveExpressionToString(_ node: ViewNode, variables: [String: String]) -> String {
        switch node {
        case .variable(let name):
            return variables[name] ?? name
        case .literal(.string(let s)):
            return s
        case .literal(.number(let n)):
            return n == floor(n) ? String(Int(n)) : String(n)
        case .literal(.boolean(let b)):
            return b ? "true" : "false"
        case .binary(let left, let op, let right):
            let l = resolveExpressionToString(left, variables: variables)
            let r = resolveExpressionToString(right, variables: variables)
            // Try numeric evaluation
            if let lv = Double(l), let rv = Double(r) {
                let result: Double
                switch op {
                case .plus: result = lv + rv
                case .minus: result = lv - rv
                case .multiply: result = lv * rv
                case .divide: result = rv != 0 ? lv / rv : 0
                case .modulo: result = rv != 0 ? lv.truncatingRemainder(dividingBy: rv) : 0
                default: return "\(l) \(op.rawValue) \(r)"
                }
                return result == floor(result) ? String(Int(result)) : String(result)
            }
            // String concatenation for +
            if op == .plus { return l + r }
            return "\(l) \(op.rawValue) \(r)"
        case .propertyAccess(let obj, let prop):
            return resolveExpressionToString(obj, variables: variables) + "." + prop
        default:
            return ""
        }
    }

    /// Extract @State / @Binding variable initial values directly from source code.
    /// This handles cases where the parser doesn't produce assignment nodes in the AST.
    private func extractStateVariablesFromSource(_ code: String, into variables: inout [String: String]) {
        for line in code.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("@State") || trimmed.hasPrefix("@Binding") ||
                  trimmed.contains("@State ") || trimmed.contains("@Binding ") else { continue }
            guard let equalsIdx = trimmed.range(of: "=") else { continue }

            let beforeEquals = trimmed[..<equalsIdx.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            var afterEquals = trimmed[equalsIdx.upperBound...]
                .trimmingCharacters(in: .whitespaces)

            // Strip trailing line comments
            if let commentRange = afterEquals.range(of: "//") {
                afterEquals = afterEquals[..<commentRange.lowerBound]
                    .trimmingCharacters(in: .whitespaces)
            }

            // Variable name: the word immediately after 'var' or 'let'
            let words = beforeEquals.split(separator: " ").map(String.init)
            guard let kwIdx = words.lastIndex(where: { $0 == "var" || $0 == "let" }),
                  kwIdx + 1 < words.count else { continue }
            var varName = words[kwIdx + 1]
            // Strip trailing colon from type annotation (e.g. "count:" → "count")
            if varName.hasSuffix(":") { varName = String(varName.dropLast()) }
            guard !varName.isEmpty, variables[varName] == nil else { continue }

            // Resolve the value
            if let intVal = Int(afterEquals) {
                variables[varName] = String(intVal)
            } else if let dblVal = Double(afterEquals) {
                variables[varName] = String(dblVal)
            } else if afterEquals == "true" || afterEquals == "false" {
                variables[varName] = afterEquals
            } else if afterEquals.hasPrefix("\"") && afterEquals.hasSuffix("\"") {
                variables[varName] = String(afterEquals.dropFirst().dropLast())
            } else {
                variables[varName] = afterEquals
            }
        }
    }

    /// Check if a node represents a renderable view
    private func isViewNode(_ node: ViewNode) -> Bool {
        switch node {
        case .text, .systemImage, .assetImage, .button,
             .vStack, .hStack, .zStack, .scrollView,
             .circle, .rectangle, .roundedRectangle, .capsule,
             .spacer, .divider, .forEach, .modified,
             .stringInterpolation, .conditional, .ternary,
             .textField, .toggle, .slider, .asyncImage, .asyncImageDynamic,
             .forEachCollection,
             .navigationStack, .navigationLink,
             .lazyVGrid, .lazyHGrid, .geometryReader, .linearGradient,
             .asyncImagePhased, .gridItem:
            return true

        case .block(let statements):
            // A block is a view if at least one statement is a view
            return statements.contains { isViewNode($0) }
            
        case .literal(let value):
            switch value {
            case .color: return true
            default: return false
            }
            
        default:
            return false
        }
    }
    
    /// Evaluate expressions for console output
    /// Plan 2: walk the AST and register every `functionDecl`, `enumDeclaration`,
    /// and `extensionDeclaration` so `load()` / `BookService.search(...)` etc. can
    /// dispatch to user-written bodies at runtime.
    private func registerDeclarations(_ node: ViewNode, state: SwiftRunnerState) {
        switch node {
        case .block(let stmts):
            for s in stmts { registerDeclarations(s, state: state) }
        case .functionDecl:
            state.execute(node)
        case .enumDeclaration, .extensionDeclaration:
            state.execute(node)
        default:
            break
        }
    }

    private func evaluateForConsole(_ node: ViewNode, output: inout String) {
        switch node {
        case .functionCall(let name, let arguments):
            if name == "print" {
                var printOutput: [String] = []
                for arg in arguments {
                    printOutput.append(evaluateToString(arg.value))
                }
                output += printOutput.joined(separator: " ") + "\n"
            }
            
        case .block(let statements):
            for stmt in statements {
                evaluateForConsole(stmt, output: &output)
            }
            
        case .vStack(_, _, let children),
             .hStack(_, _, let children),
             .zStack(_, let children):
            for child in children {
                evaluateForConsole(child, output: &output)
            }
            
        case .modified(let view, _):
            evaluateForConsole(view, output: &output)
            
        default:
            break
        }
    }
    
    /// Evaluate a node to a string (for print statements)
    private func evaluateToString(_ node: ViewNode) -> String {
        switch node {
        case .literal(let value):
            switch value {
            case .string(let s): return s
            case .number(let n): 
                if n == floor(n) {
                    return String(Int(n))
                }
                return String(n)
            case .boolean(let b): return b ? "true" : "false"
            case .color(let c): return c.rawValue
            case .nil: return "nil"
            }
            
        case .binary(let left, let op, let right):
            return evaluateBinary(left, op, right)
            
        case .variable(let name):
            return name
            
        case .text(let s):
            return s
            
        default:
            return ""
        }
    }
    
    private func evaluateBinary(_ left: ViewNode, _ op: BinaryOperator, _ right: ViewNode) -> String {
        let leftVal = evaluateNumeric(left)
        let rightVal = evaluateNumeric(right)
        
        let result: Double
        switch op {
        case .plus: result = leftVal + rightVal
        case .minus: result = leftVal - rightVal
        case .multiply: result = leftVal * rightVal
        case .divide: result = rightVal != 0 ? leftVal / rightVal : 0
        case .modulo: result = rightVal != 0 ? leftVal.truncatingRemainder(dividingBy: rightVal) : 0
        default: 
            // String concatenation
            if case .literal(.string(let ls)) = left,
               case .literal(.string(let rs)) = right {
                return ls + rs
            }
            return "\(evaluateToString(left)) \(op.rawValue) \(evaluateToString(right))"
        }
        
        if result == floor(result) {
            return String(Int(result))
        }
        return String(result)
    }
    
    /// Formats an error message with source line context and a caret pointer
    private func formatError(_ message: String, line: Int?, sourceCode: String) -> String {
        guard let line = line else { return message }

        let sourceLines = sourceCode.components(separatedBy: "\n")
        guard line >= 1, line <= sourceLines.count else { return message }

        var result = message + "\n"

        // Show up to 1 line of surrounding context before the error line
        let startLine = max(1, line - 1)
        for i in startLine...min(line, sourceLines.count) {
            let prefix = i == line ? " → " : "   "
            let lineNum = String(i).padding(toLength: 4, withPad: " ", startingAt: 0)
            result += "\(prefix)\(lineNum)| \(sourceLines[i - 1])\n"
        }

        return result
    }

    private func evaluateNumeric(_ node: ViewNode) -> Double {
        switch node {
        case .literal(.number(let n)):
            return n
        case .binary(let l, let op, let r):
            let lv = evaluateNumeric(l)
            let rv = evaluateNumeric(r)
            switch op {
            case .plus: return lv + rv
            case .minus: return lv - rv
            case .multiply: return lv * rv
            case .divide: return rv != 0 ? lv / rv : 0
            case .modulo: return rv != 0 ? lv.truncatingRemainder(dividingBy: rv) : 0
            default: return 0
            }
        default:
            return 0
        }
    }
}

// MARK: - Convenience Extensions

public extension SwiftRunner {
    
    /// Parse code and return the AST without running
    func parse(_ code: String) throws -> ViewNode {
        let lexer = SwiftLexer(source: code)
        let tokens = try lexer.tokenize()
        return try parser.parse(tokens)
    }
    
    /// Tokenize code and return tokens
    func tokenize(_ code: String) throws -> [Token] {
        let lexer = SwiftLexer(source: code)
        return try lexer.tokenize()
    }

    /// Test helper: expose separateState for unit testing
    func testSeparateState(_ node: ViewNode) -> ([String: Value], ViewNode) {
        return separateState(node)
    }
}
