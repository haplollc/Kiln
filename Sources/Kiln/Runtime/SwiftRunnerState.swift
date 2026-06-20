//
//  SwiftRunnerState.swift
//  SwiftRunner
//

import Foundation
import Combine

/// Reactive state store for SwiftRunner interactive views.
/// When button taps mutate state, @Published triggers SwiftUI to re-render DynamicView.
@MainActor
public final class SwiftRunnerState: ObservableObject {
    @Published public var variables: [String: Value] = [:]

    /// Non-reactive storage for render-time variables (custom view args, loop vars).
    /// Changes here do NOT trigger SwiftUI re-renders, avoiding infinite loops.
    public var renderVariables: [String: Value] = [:]

    // MARK: - Plan 2: user-defined function table
    //
    // Key conventions:
    //   "<name>"                — top-level func
    //   "<TypeName>.<name>"     — static func inside an enum / extension / struct
    //
    // Each entry stores the full `.functionDecl` node so the caller can bind args
    // and execute the body under a fresh parameter scope.
    public var functions: [String: ViewNode] = [:]

    /// Host-injected native functions (registered via `Kiln.register`). Checked
    /// after user-defined functions but before built-ins, so an embedding app can
    /// expose real Apple-framework capabilities (HealthKit, haptics, device info,
    /// Calendar, …) to interpreted code as plain function calls. Keyed by the
    /// call name (bare, e.g. `steps`, or namespaced, e.g. `Health.steps`).
    public static var nativeBridges: [String: ([Value]) -> Value] = [:]

    /// Plan 5 capstone: per-struct field-type schemas (copied from SwiftParser
    /// after parsing). Keyed by `TypeName → FieldName → InnerTypeName` where
    /// `InnerTypeName` is the first identifier in the field's type annotation
    /// (so `[OpenLibraryDoc]?` and `[OpenLibraryDoc]` both map to `OpenLibraryDoc`).
    /// Used by `tagWithSchema` to stamp nested decoded objects with `_type`.
    public var typeSchemas: [String: [String: String]] = [:]

    /// Signal used to unwind an early `return` out of the enclosing function body.
    /// Thrown from `executeWithReturn` and caught by `callUserFunction`.
    struct ReturnSignal: Error { let value: Value }

    /// Stack of `defer` blocks scoped to the currently-executing function call.
    /// Each call frame pushes an empty `[ViewNode]`; `defer { … }` appends to the
    /// top frame; on call exit (normal return, early return, or thrown error) the
    /// frame is popped and its contents are executed in LIFO order — matching
    /// Swift's defer semantics.
    private var deferFrames: [[ViewNode]] = []

    public init(_ initial: [String: Value] = [:]) {
        self.variables = initial
        // Build banner — if you don't see this in the console when the view
        // renders, your app is running a STALE Kuzco build. Clean DerivedData,
        // reset Swift Package caches, and rebuild.
        Self.printBuildBannerOnce()
    }

    private nonisolated(unsafe) static var bannerPrinted = false
    nonisolated private static func printBuildBannerOnce() {
        guard !bannerPrinted else { return }
        bannerPrinted = true
        let line = "[SR] Kuzco/SwiftRunner build: 2026-05-05-navlink-eager-bake — rebuild Kuzco if you don't see this"
        Swift.print(line)
        NSLog("%@", line)
    }

    /// Register a function declaration under `name`, or scoped under `owner.name`
    /// when it was found inside an enum / struct / extension body.
    public func registerFunction(_ decl: ViewNode, owner: String? = nil) {
        guard case .functionDecl(let name, _, _, _, _) = decl else { return }
        let key = owner.map { "\($0).\(name)" } ?? name
        functions[key] = decl
        print("[State] registered func '\(key)'")
    }

    /// Walk a just-parsed `.enumDeclaration` / `.extensionDeclaration` and hoist
    /// any contained function decls into the function table. Called from `execute`.
    private func hoistTypeMembers(ownerName: String, members: [ViewNode]) {
        for m in members {
            if case .functionDecl = m {
                registerFunction(m, owner: ownerName)
            }
        }
    }

    /// Call a registered user function by key, binding `arguments` to its parameters.
    private func callUserFunction(key: String, arguments: [Argument]) -> Value {
        guard let decl = functions[key],
              case .functionDecl(_, let params, let body, _, _) = decl else {
            print("[SR] callUserFunction: '\(key)' NOT FOUND in function table")
            return .nil
        }
        print("[SR] callUserFunction: enter '\(key)' with \(arguments.count) arg(s)")

        // Bind parameters. Save prior values so the call is a local scope for
        // parameter names; other variable writes during the call persist to the
        // enclosing scope (intentional — SwiftRunner has no true lexical scoping).
        var prior: [String: Value?] = [:]
        for (i, param) in params.enumerated() {
            prior[param.internalName] = variables[param.internalName]
            let value: Value
            // Labeled argument match first
            if let external = param.externalLabel,
               let labeled = arguments.first(where: { $0.label == external }) {
                value = evaluate(labeled.value)
            } else if i < arguments.count, arguments[i].label == nil {
                // Positional fallback
                value = evaluate(arguments[i].value)
            } else if i < arguments.count {
                // Mismatched label but positional slot — best effort
                value = evaluate(arguments[i].value)
            } else {
                value = .nil
            }
            variables[param.internalName] = value
        }

        // Push a fresh defer frame for this call. Any `defer { … }` encountered
        // during body execution registers into this frame and runs on exit.
        deferFrames.append([])

        // Execute the body. Return-signal lets early `return <expr>` unwind.
        // Implicit return: if no ReturnSignal fires AND the last statement of
        // the body is an expression, its value becomes the return value (matches
        // Swift's single-expression-function and trailing-expression semantics).
        var result: Value = .nil
        do {
            try executeWithReturn(body)
            result = implicitReturnValue(body)
        } catch let signal as ReturnSignal {
            result = signal.value
        } catch {
            print("[State] user-function '\(key)' threw: \(error)")
        }

        // Run defers in LIFO order — guaranteed to execute even on early return
        // or thrown error. Each defer body runs through `execute` so it observes
        // the current variable state (which is what the user expects: deferred
        // cleanup uses the values at exit, not at registration).
        let defers = deferFrames.removeLast()
        for body in defers.reversed() {
            print("[State] running deferred block for '\(key)'")
            execute(body)
        }

        // Restore parameter slots.
        for (name, oldValue) in prior {
            if let v = oldValue {
                variables[name] = v
            } else {
                variables.removeValue(forKey: name)
            }
        }
        print("[SR] callUserFunction: exit '\(key)' returning: \(result.description.prefix(150))")
        return result
    }

    /// Compute the implicit-return value for a function body — the value of the
    /// last expression if there's no explicit `return`. Returns `.nil` when the
    /// body's trailing statement isn't a value-producing expression.
    private func implicitReturnValue(_ body: ViewNode) -> Value {
        let last: ViewNode = {
            if case .block(let stmts) = body { return stmts.last ?? .empty }
            return body
        }()
        switch last {
        case .methodCall, .functionCall, .propertyAccess, .variable,
             .literal, .binary, .ternary, .stringInterpolation,
             .arrayLiteral, .subscriptAccess, .binding:
            return evaluate(last)
        default:
            return .nil
        }
    }

    // MARK: - Async execution path
    //
    // Mirrors of `execute` / `evaluate` / `callUserFunction` / `executeWithReturn`
    // that suspend at network boundaries via `await`. Called from SwiftUI's
    // real `.task { … }` modifier (see `ViewBuilder.swift::case .taskAction`).
    // The benefit: while the user's code awaits a network fetch, the main
    // thread is FREE — SwiftUI re-renders any pending state changes (so the
    // user actually sees `isLoading=true` placeholders during the fetch
    // instead of a frozen UI).
    //
    // Most ops are synchronous and just delegate to the sync versions.
    // The async-ness lives at the URLSession.shared.data(from:) call site
    // and propagates outward through the user-function call stack so a
    // function whose body awaits (transitively) is itself awaited.

    /// Entry point for `.task` action bodies. Walks the AST async so the
    /// real `await URLSession.shared.data(from:)` in `performAsyncFetch`
    /// suspends without blocking the main thread.
    public func runAsync(_ action: ViewNode) async {
        do {
            try await executeWithReturnAsync(action)
        } catch let signal as ReturnSignal {
            _ = signal // top-level return is a no-op
        } catch {
            print("[State] runAsync threw: \(error)")
        }
    }

    private func executeWithReturnAsync(_ node: ViewNode) async throws {
        switch node {
        case .block(let stmts):
            for s in stmts { try await executeWithReturnAsync(s) }
        case .returnStmt(let expr):
            let value: Value
            if let expr = expr { value = await evaluateAsync(expr) } else { value = .nil }
            throw ReturnSignal(value: value)
        case .deferBlock(let body):
            if !deferFrames.isEmpty {
                deferFrames[deferFrames.count - 1].append(body)
            }
        case .conditional(let cond, let thenBody, let elseBody):
            if (await evaluateAsync(cond)).isTruthy {
                try await executeWithReturnAsync(thenBody)
            } else if let e = elseBody {
                try await executeWithReturnAsync(e)
            }
        case .doCatch(let body, _):
            try await executeWithReturnAsync(body)
        case .guardLet(let name, let valueNode, let elseBlock):
            let v = await evaluateAsync(valueNode)
            if case .nil = v {
                try await executeWithReturnAsync(elseBlock)
            } else {
                variables[name] = v
                renderVariables[name] = v
            }
        case .guardExpr(let cond, let elseBlock):
            if !(await evaluateAsync(cond)).isTruthy {
                try await executeWithReturnAsync(elseBlock)
            }
        case .functionCall, .methodCall:
            // Use async path so URLSession.shared.data calls suspend.
            _ = await evaluateAsync(node)
        case .compoundAssignment(let variable, let op, let valueNode):
            let newValue = await evaluateAsync(valueNode)
            applyCompoundAssignment(variable: variable, op: op, newValue: newValue)
        case .assignment(let name, _, let value):
            let val = await evaluateAsync(value)
            variables[name] = val
            renderVariables[name] = val
        case .tupleBinding(let names, let valueNode):
            let v = await evaluateAsync(valueNode)
            if case .array(let arr) = v {
                for (i, optName) in names.enumerated() {
                    guard let n = optName else { continue }
                    variables[n] = i < arr.count ? arr[i] : .nil
                }
            } else if let first = names.first, let n = first {
                variables[n] = v
            }
        case .propertyAssignment(let target, let op, let valueNode):
            let newValue = await evaluateAsync(valueNode)
            applyPropertyAssignment(target: target, op: op, newValue: newValue)
        default:
            execute(node)
        }
    }

    private func evaluateAsync(_ node: ViewNode) async -> Value {
        switch node {
        case .methodCall(let obj, let method, let args):
            // Type-prefixed user-function dispatch first (e.g. BookService.search).
            if case .variable(let typeName) = obj {
                let key = "\(typeName).\(method)"
                if functions[key] != nil {
                    return await callUserFunctionAsync(key: key, arguments: args)
                }
            }
            let objVal = await evaluateAsync(obj)
            // The single async call we genuinely await:
            // URLSession.shared.data(from: url) — uses the real async API.
            if case .object(let dict) = objVal,
               case .string("URLSession") = dict["_type"] ?? .nil,
               method == "data" {
                let fromArg = args.first(where: { $0.label == "from" })?.value ?? args.first?.value
                guard let expr = fromArg else { return .array([.nil, .nil]) }
                let urlVal = await evaluateAsync(expr)
                var urlString = ""
                if case .object(let urlDict) = urlVal,
                   case .string(let s) = urlDict["string"] ?? .nil {
                    urlString = s
                } else if case .string(let s) = urlVal {
                    urlString = s
                }
                return await Self.performAsyncFetch(urlString: urlString)
            }
            return evaluateMethodCall(obj: objVal, method: method, args: args)

        case .functionCall(let name, let arguments):
            // Async-aware built-ins. Both `Task { … }` and `withAnimation(_) { … }`
            // execute their trailing closure inline. We route through the async
            // executor so awaits inside the body suspend properly instead of
            // falling back to the sync interpreter (which would block main).
            switch name {
            case "Task":
                if let last = arguments.last {
                    do { try await executeWithReturnAsync(last.value) }
                    catch { /* swallow ReturnSignal / other internal errors */ }
                }
                return .nil
            case "withAnimation":
                if let last = arguments.last {
                    do { try await executeWithReturnAsync(last.value) }
                    catch { }
                }
                return .nil
            default:
                break
            }

            if functions[name] != nil {
                return await callUserFunctionAsync(key: name, arguments: arguments)
            }
            // Suffix match (e.g. bare `load()` → `LibraryApp.load`).
            let suffix = ".\(name)"
            let scoped = functions.keys.filter { $0.hasSuffix(suffix) }
            if scoped.count == 1 {
                return await callUserFunctionAsync(key: scoped[0], arguments: arguments)
            }
            // Built-ins: most are sync, but a few (`searchBooks`, etc.) are
            // helpers we don't recurse through. Default to sync path.
            return evaluateFunction(name, arguments: arguments)

        case .ternary(let cond, let trueExpr, let falseExpr):
            return (await evaluateAsync(cond)).isTruthy
                ? (await evaluateAsync(trueExpr))
                : (await evaluateAsync(falseExpr))

        default:
            // Most expression nodes are pure-sync (literals, binary ops,
            // property access) and never await. Falling through is correct
            // and keeps the async path narrow.
            return evaluate(node)
        }
    }

    private func callUserFunctionAsync(key: String, arguments: [Argument]) async -> Value {
        guard let decl = functions[key],
              case .functionDecl(_, let params, let body, _, _) = decl else {
            print("[SR] callUserFunctionAsync: '\(key)' NOT FOUND")
            return .nil
        }
        print("[SR] callUserFunctionAsync: enter '\(key)'")

        var prior: [String: Value?] = [:]
        for (i, param) in params.enumerated() {
            prior[param.internalName] = variables[param.internalName]
            let value: Value
            if let external = param.externalLabel,
               let labeled = arguments.first(where: { $0.label == external }) {
                value = await evaluateAsync(labeled.value)
            } else if i < arguments.count, arguments[i].label == nil {
                value = await evaluateAsync(arguments[i].value)
            } else if i < arguments.count {
                value = await evaluateAsync(arguments[i].value)
            } else {
                value = .nil
            }
            variables[param.internalName] = value
        }

        deferFrames.append([])
        var result: Value = .nil
        do {
            try await executeWithReturnAsync(body)
            result = implicitReturnValue(body)
        } catch let signal as ReturnSignal {
            result = signal.value
        } catch {
            print("[State] async user-function '\(key)' threw: \(error)")
        }
        // Run defers (sync — they typically mutate state synchronously).
        let defers = deferFrames.removeLast()
        for body in defers.reversed() {
            print("[State] running async-deferred block for '\(key)'")
            execute(body)
        }
        // Restore parameter slots.
        for (name, oldValue) in prior {
            if let v = oldValue { variables[name] = v }
            else { variables.removeValue(forKey: name) }
        }
        print("[SR] callUserFunctionAsync: exit '\(key)'")
        return result
    }

    /// Real async URLSession fetch. Uses the same URL-keyed cache as the
    /// synchronous fallback so identical fetches return instantly.
    nonisolated static func performAsyncFetch(urlString: String) async -> Value {
        fetchCacheLock.lock()
        let cached = fetchCache[urlString]
        fetchCacheLock.unlock()
        if let (bytes, status) = cached {
            print("[SR] performAsyncFetch: ✓ cache hit (\(bytes.count) bytes) for \(urlString.prefix(120))")
            return makeFetchTuple(bytes: bytes, status: status)
        }

        print("[SR] performAsyncFetch: URL = \(urlString)")
        guard let url = URL(string: urlString) else {
            print("[SR] performAsyncFetch: ❌ invalid URL string")
            return .array([.nil, .nil])
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            fetchCacheLock.lock()
            fetchCache[urlString] = (data, status)
            fetchCacheLock.unlock()
            print("[SR] performAsyncFetch: ✓ \(data.count) bytes, status \(status)")
            return makeFetchTuple(bytes: data, status: status)
        } catch {
            print("[SR] performAsyncFetch: ❌ \(error)")
            return .array([.nil, .nil])
        }
    }

    /// Apply a compound-assignment op to the variables/renderVariables stores.
    /// Factored out so both sync and async execute paths can share it.
    private func applyCompoundAssignment(variable: String, op: CompoundOp, newValue: Value) {
        let current = variables[variable] ?? .nil
        switch op {
        case .assign:
            variables[variable] = newValue
        case .plusAssign:
            if case .number(let lhs) = current, case .number(let rhs) = newValue {
                variables[variable] = .number(lhs + rhs)
            } else {
                variables[variable] = .string(current.description + newValue.description)
            }
        case .minusAssign:
            if case .number(let lhs) = current, case .number(let rhs) = newValue {
                variables[variable] = .number(lhs - rhs)
            }
        case .mulAssign:
            if case .number(let lhs) = current, case .number(let rhs) = newValue {
                variables[variable] = .number(lhs * rhs)
            }
        case .divAssign:
            if case .number(let lhs) = current, case .number(let rhs) = newValue, rhs != 0 {
                variables[variable] = .number(lhs / rhs)
            }
        case .toggle:
            if case .boolean(let b) = current {
                variables[variable] = .boolean(!b)
            }
        }
        if renderVariables[variable] != nil {
            renderVariables[variable] = variables[variable]
        }
    }

    /// Execute a node with return-signal propagation. Used inside user-function bodies.
    private func executeWithReturn(_ node: ViewNode) throws {
        switch node {
        case .block(let stmts):
            for s in stmts { try executeWithReturn(s) }
        case .returnStmt(let expr):
            let value = expr.map { evaluate($0) } ?? .nil
            throw ReturnSignal(value: value)
        case .deferBlock(let body):
            // Register on the topmost defer frame (created by callUserFunction).
            // If we're outside a function call, fall through to the default
            // `execute` path which is a no-op for safety.
            if !deferFrames.isEmpty {
                deferFrames[deferFrames.count - 1].append(body)
            }
        case .conditional(let cond, let thenBody, let elseBody):
            if evaluate(cond).isTruthy {
                try executeWithReturn(thenBody)
            } else if let e = elseBody {
                try executeWithReturn(e)
            }
        case .doCatch(let body, _):
            try executeWithReturn(body)
        case .guardLet(let name, let valueNode, let elseBlock):
            let v = evaluate(valueNode)
            if case .nil = v {
                try executeWithReturn(elseBlock)
            } else {
                variables[name] = v
            }
        case .guardExpr(let cond, let elseBlock):
            if !evaluate(cond).isTruthy {
                try executeWithReturn(elseBlock)
            }
        default:
            execute(node)
        }
    }

    /// Execute an action node (compound assignment, block, toggle, etc.)
    public func execute(_ action: ViewNode) {
        print("[State] execute: \(action)")
        switch action {
        case .compoundAssignment(let variable, let op, let valueNode):
            let current = variables[variable] ?? .nil
            let newValue = evaluate(valueNode)
            switch op {
            case .assign:
                variables[variable] = newValue
            case .plusAssign:
                if case .number(let lhs) = current, case .number(let rhs) = newValue {
                    variables[variable] = .number(lhs + rhs)
                } else {
                    variables[variable] = .string(current.description + newValue.description)
                }
            case .minusAssign:
                if case .number(let lhs) = current, case .number(let rhs) = newValue {
                    variables[variable] = .number(lhs - rhs)
                }
            case .mulAssign:
                if case .number(let lhs) = current, case .number(let rhs) = newValue {
                    variables[variable] = .number(lhs * rhs)
                }
            case .divAssign:
                if case .number(let lhs) = current, case .number(let rhs) = newValue, rhs != 0 {
                    variables[variable] = .number(lhs / rhs)
                }
            case .toggle:
                if case .boolean(let b) = current {
                    variables[variable] = .boolean(!b)
                }
            }
            // Plan 5 capstone fix: keep renderVariables in sync so reads via
            // `.variable(name)` (which prefer renderVariables) see the new value.
            // Without this, `books = mergeBooks(...)` writes `variables[books]`
            // but a stale `renderVariables[books]` would shadow the result.
            if renderVariables[variable] != nil {
                renderVariables[variable] = variables[variable]
            }
            let summary = (variables[variable] ?? .nil).description.prefix(120)
            print("[SR] assign: \(variable) = \(summary)")

        case .block(let statements):
            for stmt in statements {
                execute(stmt)
            }

        // Handle assignment to expression (e.g., requirements[0].isMet = value)
        case .assignment(let name, _, let value):
            let val = evaluate(value)
            variables[name] = val
            renderVariables[name] = val

        case .empty:
            break

        // Allow side-effecting function calls in action contexts (onAppear, onChange,
        // Button actions). The evaluator's function table handles built-ins like
        // `searchBooks`, which kick off network work and write results back into
        // `variables`.
        case .functionCall:
            _ = evaluate(action)
        case .methodCall:
            _ = evaluate(action)

        // MARK: Plan 1 — stubbed-execution cases
        case .switchStmt:
            _ = evaluate(action)
        case .doCatch(let body, _):
            // Catch clauses don't fire until we have real throws (Stage 2/4).
            execute(body)
        case .throwStmt:
            // No-op: no throws machinery yet.
            break
        case .guardLet(let name, let valueNode, let elseBlock):
            let v = evaluate(valueNode)
            if case .nil = v {
                execute(elseBlock)
            } else {
                variables[name] = v
            }
        case .guardExpr(let cond, let elseBlock):
            if !evaluate(cond).isTruthy {
                execute(elseBlock)
            }
        case .deferBlock:
            // defer executes on function-scope exit — no function scopes yet.
            break

        // Hoist methods inside enum/extension bodies into the function table
        // under a "Owner.method" key so call sites like `BookService.search(...)`
        // can dispatch.
        case .enumDeclaration(let name, _, let members):
            hoistTypeMembers(ownerName: name, members: members)
            // Recurse into nested declarations
            for m in members { execute(m) }
        case .extensionDeclaration(let target, let members):
            hoistTypeMembers(ownerName: target, members: members)
            for m in members { execute(m) }

        // Register top-level / nested function declarations in the function table.
        case .functionDecl:
            registerFunction(action)

        // Outside of a user-function body, `return` is a no-op. Inside a user-function
        // body we use `executeWithReturn` which throws ReturnSignal instead.
        case .returnStmt:
            break

        case .tupleBinding(let names, let valueNode):
            let v = evaluate(valueNode)
            if case .array(let arr) = v {
                for (i, optName) in names.enumerated() {
                    guard let n = optName else { continue }
                    variables[n] = i < arr.count ? arr[i] : .nil
                }
            } else if let first = names.first, let n = first {
                variables[n] = v
            }

        case .propertyAssignment(let target, let op, let valueNode):
            let newValue = evaluate(valueNode)
            applyPropertyAssignment(target: target, op: op, newValue: newValue)

        default:
            break
        }
    }

    /// Evaluate a ViewNode expression using current state values
    public func evaluate(_ node: ViewNode) -> Value {
        switch node {
        case .variable(let name):
            return renderVariables[name] ?? variables[name] ?? .nil
        case .literal(let lit):
            switch lit {
            case .number(let n): return .number(n)
            case .string(let s): return .string(s)
            case .boolean(let b): return .boolean(b)
            case .color(let c): return .string(c.rawValue)
            case .nil: return .nil
            }
        case .valueLiteral(let v):
            return v
        case .binary(let left, let op, let right):
            return evaluateBinary(evaluate(left), op, evaluate(right))
        case .stringInterpolation(let parts):
            return .string(resolveInterpolation(parts))
        case .functionCall(let name, let arguments):
            return evaluateFunction(name, arguments: arguments)
        case .ternary(let condition, let trueExpr, let falseExpr):
            return evaluate(condition).isTruthy ? evaluate(trueExpr) : evaluate(falseExpr)
        case .arrayLiteral(let elements):
            return .array(elements.map { evaluate($0) })
        case .binding(let name):
            // $0, $1 etc. as implicit closure params — look up like variables
            return renderVariables[name] ?? variables[name] ?? .nil
        case .subscriptAccess(let obj, let index):
            let objVal = evaluate(obj)
            let idxVal = evaluate(index)
            if case .array(let arr) = objVal, case .number(let n) = idxVal {
                let i = Int(n)
                if i >= 0 && i < arr.count { return arr[i] }
            }
            if case .string(let s) = objVal, case .number(let n) = idxVal {
                let i = Int(n)
                let chars = Array(s)
                if i >= 0 && i < chars.count { return .string(String(chars[i])) }
            }
            return .nil
        case .methodCall(let obj, let method, let args):
            // Plan 2: method calls on a named type route to the user-function table
            // first. `BookService.search(query: "...")` parses as methodCall(
            // object: .variable("BookService"), method: "search") — we try
            // "BookService.search" in the function table before falling back to
            // value-based dispatch.
            if case .variable(let typeName) = obj {
                let key = "\(typeName).\(method)"
                if functions[key] != nil {
                    return callUserFunction(key: key, arguments: args)
                }
                // Host-injected namespaced bridge, e.g. `Health.steps()`.
                if let bridge = Self.nativeBridges[key] {
                    return bridge(args.map { evaluate($0.value) })
                }
            }
            return evaluateMethodCall(obj: evaluate(obj), method: method, args: args)
        case .propertyAccess(let obj, let prop):
            // Handle Color.blue, Color.red, etc.
            if case .variable("Color") = obj, ColorValue(rawValue: prop) != nil {
                return .string(prop)
            }

            // Plan 3: Foundation namespace-style lookups before evaluating obj,
            // since `URLSession`, `URLError`, etc. aren't real variables.
            if case .variable(let rootName) = obj {
                switch (rootName, prop) {
                case ("URLSession", "shared"):
                    return .object(["_type": .string("URLSession")])
                case ("URLError", let code):
                    return .string(code) // `.badServerResponse` etc. — used only for throws
                default: break
                }
            }

            let objVal = evaluate(obj)

            // Plan 3: Foundation property access for tagged objects.
            if case .object(let dict) = objVal,
               case .string(let type) = dict["_type"] ?? .nil {
                switch (type, prop) {
                // URLComponents.url → a URL-shaped object (or .nil on failure)
                case ("URLComponents", "url"):
                    let urlString = Self.buildURLFromComponents(dict)
                    if urlString.isEmpty { return .nil }
                    return .object([
                        "_type": .string("URL"),
                        "string": .string(urlString),
                    ])
                // URL.absoluteString
                case ("URL", "absoluteString"):
                    return dict["string"] ?? .string("")
                // HTTPURLResponse.statusCode
                case ("HTTPURLResponse", "statusCode"):
                    return dict["statusCode"] ?? .number(0)
                default:
                    break
                }
            }

            // Object property access: req.title, req.isMet
            if case .object(let dict) = objVal {
                if let v = dict[prop] { return v }
                // Plan 5 capstone: missing key — try a computed property
                // registered on the object's type (via `_type` tag).
                if case .string(let typeName) = dict["_type"] ?? .nil,
                   let v = invokeComputedProperty(onTagged: dict, typeName: typeName, property: prop) {
                    return v
                }
                // Diagnostic: object has no such key + no computed getter — log it once
                // so callers can see which fields are missing on tagged objects.
                let typeTag: String = {
                    if case .string(let t) = dict["_type"] ?? .nil { return t }
                    return "<untagged>"
                }()
                let availableKeys = dict.keys.sorted().joined(separator: ", ")
                print("[SR] propertyAccess MISS: \(typeTag).\(prop) — keys available: [\(availableKeys.prefix(200))]")
                return .nil
            }
            // Tuple/array index access: value.0, value.1
            if let index = Int(prop), case .array(let arr) = objVal, index >= 0 && index < arr.count {
                return arr[index]
            }
            // Array properties
            if case .array(let arr) = objVal {
                switch prop {
                case "count": return .number(Double(arr.count))
                case "isEmpty": return .boolean(arr.isEmpty)
                case "first": return arr.first ?? .nil
                case "last": return arr.last ?? .nil
                default: break
                }
            }
            // String properties
            if case .string(let s) = objVal {
                switch prop {
                case "count": return .number(Double(s.count))
                case "isEmpty": return .boolean(s.isEmpty)
                case "isNotEmpty": return .boolean(!s.isEmpty)
                case "uppercased": return .string(s.uppercased())
                case "lowercased": return .string(s.lowercased())
                case "containsUppercase": return .boolean(s.contains(where: { $0.isUppercase }))
                case "containsLowercase": return .boolean(s.contains(where: { $0.isLowercase }))
                case "containsNumber", "containsDigit": return .boolean(s.contains(where: { $0.isNumber }))
                default: break
                }
            }
            // Boolean properties
            if case .boolean(let b) = objVal, prop == "description" {
                return .string(b ? "true" : "false")
            }
            return objVal
        case .modified(let view, let modifiers):
            // Handle Color.blue.opacity(0.5) — evaluate the base and apply opacity info
            // For now, evaluate just the base view (the color)
            _ = modifiers // opacity info available but not needed for color resolution
            return evaluate(view)

        // MARK: Plan 1 — switch evaluation
        case .switchStmt(let scrutinee, let cases, let defaultBody):
            let scrutineeValue = evaluate(scrutinee)
            for branch in cases {
                if switchPatternMatches(branch.pattern, value: scrutineeValue) {
                    bindSwitchCaptures(branch.pattern, value: scrutineeValue)
                    return evaluate(branch.body)
                }
            }
            if let d = defaultBody { return evaluate(d) }
            return .nil

        case .doCatch(let body, _):
            return evaluate(body)

        default:
            return .nil
        }
    }

    // MARK: - Plan 3: Foundation method dispatch

    /// Route method calls on Foundation-shaped objects (URL, URLComponents,
    /// URLSession, JSONDecoder, HTTPURLResponse) to real work. Returns nil when
    /// the object isn't one of these, so the generic method dispatch can run.
    private func dispatchFoundationMethod(obj: Value, method: String, args: [Argument]) -> Value? {
        guard case .object(let dict) = obj,
              case .string(let type) = dict["_type"] ?? .nil else {
            return nil
        }

        switch (type, method) {
        // URLSession.shared.data(from: url) → (Data, URLResponse)
        case ("URLSession", "data"):
            let fromArg = args.first(where: { $0.label == "from" })?.value ?? args.first?.value
            guard let expr = fromArg else { return .array([.nil, .nil]) }
            let urlVal = evaluate(expr)
            // Accept either a URL-tagged object or a raw string.
            var urlString = ""
            if case .object(let urlDict) = urlVal,
               case .string(let s) = urlDict["string"] ?? .nil {
                urlString = s
            } else if case .string(let s) = urlVal {
                urlString = s
            }
            return Self.performSyncFetch(urlString: urlString)

        // JSONDecoder().decode(T.self, from: data)
        case ("JSONDecoder", "decode"):
            let fromArg = args.first(where: { $0.label == "from" })?.value
                ?? args.dropFirst().first?.value
            guard let fromExpr = fromArg else {
                print("[SR] JSONDecoder.decode: ❌ no `from:` arg")
                return .nil
            }
            let dataValue = evaluate(fromExpr)
            guard let jsonBytes = Self.bytesFromDataValue(dataValue) else {
                print("[SR] JSONDecoder.decode: ❌ data arg isn't a Data-shaped value: \(dataValue.description.prefix(80))")
                return .nil
            }
            print("[SR] JSONDecoder.decode: decoding \(jsonBytes.count) bytes")
            // Plan 5 capstone: extract type name from the first positional arg
            // so computed properties defined on the type can dispatch at access time.
            let typeName: String? = {
                guard let firstArg = args.first?.value else { return nil }
                if case .propertyAccess(.variable(let name), "self") = firstArg { return name }
                if case .variable(let name) = firstArg { return name }
                return nil
            }()
            do {
                let parsed = try JSONSerialization.jsonObject(with: jsonBytes, options: [.fragmentsAllowed])
                var result = Self.jsonToValue(parsed)
                if let t = typeName {
                    result = tagWithSchema(result, asType: t)
                }
                if case .object(let d) = result {
                    print("[SR] JSONDecoder.decode: ✓ top-level keys = \(d.keys.sorted()), tagged as '\(typeName ?? "?")'")
                } else if case .array(let a) = result {
                    print("[SR] JSONDecoder.decode: ✓ top-level array of \(a.count), tagged as '\(typeName ?? "?")'")
                }
                return result
            } catch {
                print("[SR] JSONDecoder.decode: ❌ JSON parse failed: \(error)")
                return .nil
            }

        // JSONEncoder().encode(value) → Data value (stub — returns bytes of description)
        case ("JSONEncoder", "encode"):
            if let first = args.first {
                let v = evaluate(first.value)
                let s = v.description
                return Self.makeDataValue(Array(s.utf8))
            }
            return .nil

        default:
            break
        }

        // URLComponents — method / property support ".url", ".queryItems" setter,
        // ".url" getter. Property access on the object lands in evaluate's
        // propertyAccess case — we don't handle that here.
        return nil
    }

    /// Produce a Data-like Value: `.object(["_type": "Data", "bytes": <[Value]>])`
    /// so downstream JSONDecoder can recover the bytes.
    private static func makeDataValue(_ bytes: [UInt8]) -> Value {
        .object([
            "_type": .string("Data"),
            "bytes": .array(bytes.map { .number(Double($0)) }),
        ])
    }

    private static func bytesFromDataValue(_ value: Value) -> Data? {
        guard case .object(let dict) = value,
              case .string("Data") = dict["_type"] ?? .nil,
              case .array(let bytesArr) = dict["bytes"] ?? .nil else {
            return nil
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(bytesArr.count)
        for v in bytesArr {
            if case .number(let n) = v { bytes.append(UInt8(truncatingIfNeeded: Int(n))) }
        }
        return Data(bytes)
    }

    /// Tag the value with `typeName` and recursively propagate tags into nested
    /// fields using the registered `typeSchemas`. For each field F in a tagged
    /// object, if the schema records `typeName.F → InnerType`, re-tag the
    /// field value with InnerType (array elements handled inside tagWithSchema
    /// by unwrapping arrays naturally via recursion).
    func tagWithSchema(_ value: Value, asType typeName: String) -> Value {
        switch value {
        case .object(var d):
            d["_type"] = .string(typeName)
            if let fieldSchema = typeSchemas[typeName] {
                for (field, innerType) in fieldSchema {
                    guard let nested = d[field], nested != .nil else { continue }
                    d[field] = tagWithSchema(nested, asType: innerType)
                }
            }
            return .object(d)
        case .array(let arr):
            return .array(arr.map { element in
                tagWithSchema(element, asType: typeName)
            })
        default:
            return value
        }
    }

    /// Plan 5 capstone: look up a zero-arg computed property (`var x: T { … }`)
    /// on a tagged object and invoke it with the object's fields bound as
    /// variables. Returns `.nil` when no matching getter is registered.
    func invokeComputedProperty(onTagged dict: [String: Value], typeName: String, property: String) -> Value? {
        let key = "\(typeName).\(property)"
        guard let decl = functions[key],
              case .functionDecl(_, let params, _, _, _) = decl,
              params.isEmpty else {
            return nil
        }
        // Bind each field of the tagged object as a temporary variable for the
        // getter body's lexical scope, preserving prior values for restoration.
        var prior: [String: Value?] = [:]
        for (k, v) in dict where k != "_type" {
            prior[k] = variables[k]
            variables[k] = v
        }
        let result = callUserFunction(key: key, arguments: [])
        // Restore.
        for (k, v) in prior {
            if let v = v { variables[k] = v } else { variables.removeValue(forKey: k) }
        }
        return result
    }

    /// Recursively convert a JSONSerialization output into a SwiftRunner `Value`.
    private static func jsonToValue(_ any: Any) -> Value {
        if let dict = any as? [String: Any] {
            var out: [String: Value] = [:]
            for (k, v) in dict { out[k] = jsonToValue(v) }
            return .object(out)
        }
        if let arr = any as? [Any] {
            return .array(arr.map(jsonToValue))
        }
        if let s = any as? String { return .string(s) }
        if let n = any as? Int { return .number(Double(n)) }
        if let n = any as? Double { return .number(n) }
        if let n = any as? NSNumber {
            // NSNumber covers bools too — check charValue == 0/1 via objCType if needed
            return .number(n.doubleValue)
        }
        if let b = any as? Bool { return .boolean(b) }
        if any is NSNull { return .nil }
        return .nil
    }

    /// Build a full URL string from a `URLComponents`-shaped object — combines the
    /// base string with the queryItems array.
    private static func buildURLFromComponents(_ dict: [String: Value]) -> String {
        var base = ""
        if case .string(let s) = dict["string"] ?? .nil { base = s }

        var queries: [URLQueryItem] = []
        if case .array(let items) = dict["queryItems"] ?? .nil {
            for item in items {
                if case .object(let qdict) = item,
                   case .string(let name)  = qdict["name"]  ?? .nil,
                   case .string(let value) = qdict["value"] ?? .nil {
                    queries.append(URLQueryItem(name: name, value: value))
                }
            }
        }

        var comps = URLComponents(string: base) ?? URLComponents()
        if !queries.isEmpty {
            comps.queryItems = (comps.queryItems ?? []) + queries
        }
        return comps.url?.absoluteString ?? base
    }

    /// Process-wide cache for `performSyncFetch`. Keyed by URL string. Lives
    /// for the lifetime of the runner so re-mounted views (e.g. switching tabs
    /// in SwiftCodeRunnerSheet) don't re-issue identical network requests
    /// and re-block the main thread.
    private nonisolated(unsafe) static var fetchCache: [String: (Data, Int)] = [:]
    private nonisolated(unsafe) static let fetchCacheLock = NSLock()

    /// Reset the in-memory fetch cache. Useful between SwiftRunner runs.
    public nonisolated static func clearFetchCache() {
        fetchCacheLock.lock()
        fetchCache.removeAll(keepingCapacity: false)
        fetchCacheLock.unlock()
    }

    /// Synchronous fetch — blocks the calling thread via a DispatchSemaphore.
    /// Returns `(Data-shaped Value, HTTPURLResponse-shaped Value)` tuple encoded
    /// as `.array([dataValue, responseValue])`.
    ///
    /// Cached by URL string: identical fetches return instantly. This matters
    /// because `.task` and `.onAppear` actions fire every time a SwiftUI view
    /// re-mounts (e.g. switching tabs in SwiftCodeRunnerSheet), and without
    /// caching, every re-mount blocks the main thread for the full HTTP RTT.
    nonisolated static func performSyncFetch(urlString: String) -> Value {
        // Fast path: cached hit returns immediately, off the main-thread block.
        fetchCacheLock.lock()
        let cached = fetchCache[urlString]
        fetchCacheLock.unlock()
        if let (bytes, status) = cached {
            print("[SR] performSyncFetch: ✓ cache hit (\(bytes.count) bytes) for \(urlString.prefix(120))")
            return makeFetchTuple(bytes: bytes, status: status)
        }

        print("[SR] performSyncFetch: URL = \(urlString)")
        guard let url = URL(string: urlString) else {
            print("[SR] performSyncFetch: ❌ invalid URL string")
            return .array([.nil, .nil])
        }
        let semaphore = DispatchSemaphore(value: 0)
        var resultBytes: Data? = nil
        var resultStatus: Int = 0

        let task = URLSession.shared.dataTask(with: url) { data, response, _ in
            resultBytes = data
            if let http = response as? HTTPURLResponse {
                resultStatus = http.statusCode
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 15)

        if let bytes = resultBytes {
            fetchCacheLock.lock()
            fetchCache[urlString] = (bytes, resultStatus)
            fetchCacheLock.unlock()
        }

        return makeFetchTuple(bytes: resultBytes, status: resultStatus)
    }

    /// Build the `(data, response)` tuple Value the user's `URLSession.shared.data(from:)`
    /// destructuring binding expects. `bytes == nil` means the request failed.
    private nonisolated static func makeFetchTuple(bytes: Data?, status: Int) -> Value {
        let dataValue: Value
        if let bytes = bytes {
            dataValue = .object([
                "_type": .string("Data"),
                "bytes": .array(bytes.map { .number(Double($0)) }),
            ])
        } else {
            dataValue = .nil
        }
        let responseValue: Value = .object([
            "_type": .string("HTTPURLResponse"),
            "statusCode": .number(Double(status)),
        ])
        return .array([dataValue, responseValue])
    }

    // MARK: - Plan 5: Property / subscript chain mutation

    /// Walk an assignable chain rooted at a `.variable(rootName)` and apply
    /// `newValue` (combined with `op` for compound forms) to the leaf slot.
    func applyPropertyAssignment(target: ViewNode, op: CompoundOp, newValue: Value) {
        // Flatten the chain into (rootName, path).
        var path: [PathSegment] = []
        var node: ViewNode = target
        while true {
            switch node {
            case .propertyAccess(let obj, let prop):
                path.insert(.key(prop), at: 0)
                node = obj
            case .subscriptAccess(let obj, let index):
                let idx = evaluate(index)
                if case .number(let n) = idx {
                    path.insert(.index(Int(n)), at: 0)
                } else if case .string(let s) = idx {
                    path.insert(.key(s), at: 0)
                }
                node = obj
            default:
                break
            }
            if case .propertyAccess = node { continue }
            if case .subscriptAccess = node { continue }
            break
        }
        guard case .variable(let rootName) = node else {
            print("[State] propertyAssignment: unsupported root \(node)")
            return
        }

        // For compound ops, read current and combine. `.assign` skips read.
        let effective: Value
        if op == .assign {
            effective = newValue
        } else {
            let current = readPath(rootName: rootName, path: path)
            effective = combineForCompound(current: current, op: op, incoming: newValue)
        }

        // Read from whichever scope currently owns the value — renderVariables
        // takes precedence in `evaluate` via `.variable` lookup, so if it holds
        // a stale copy we must update that too.
        let root = renderVariables[rootName] ?? variables[rootName] ?? .nil
        let updated = writeInto(value: root, path: path, newValue: effective)
        variables[rootName] = updated
        // Keep renderVariables in sync whenever it had a copy — otherwise the
        // stale render-side shadow will be returned by subsequent `.variable`
        // reads and the mutation silently disappears.
        if renderVariables[rootName] != nil {
            renderVariables[rootName] = updated
        }
    }

    private enum PathSegment {
        case key(String)
        case index(Int)
    }

    private func readPath(rootName: String, path: [PathSegment]) -> Value {
        var current = variables[rootName] ?? .nil
        for seg in path {
            switch seg {
            case .key(let k):
                if case .object(let d) = current { current = d[k] ?? .nil }
                else { return .nil }
            case .index(let i):
                if case .array(let a) = current, i >= 0 && i < a.count { current = a[i] }
                else { return .nil }
            }
        }
        return current
    }

    private func writeInto(value: Value, path: [PathSegment], newValue: Value) -> Value {
        guard let first = path.first else { return newValue }
        let rest = Array(path.dropFirst())
        switch first {
        case .key(let k):
            var dict: [String: Value] = {
                if case .object(let d) = value { return d }
                return [:]
            }()
            let existing = dict[k] ?? .nil
            dict[k] = writeInto(value: existing, path: rest, newValue: newValue)
            return .object(dict)
        case .index(let i):
            var arr: [Value] = {
                if case .array(let a) = value { return a }
                return []
            }()
            while arr.count <= i { arr.append(.nil) }
            arr[i] = writeInto(value: arr[i], path: rest, newValue: newValue)
            return .array(arr)
        }
    }

    private func combineForCompound(current: Value, op: CompoundOp, incoming: Value) -> Value {
        switch op {
        case .assign: return incoming
        case .plusAssign:
            if case .number(let a) = current, case .number(let b) = incoming { return .number(a + b) }
            return .string(current.description + incoming.description)
        case .minusAssign:
            if case .number(let a) = current, case .number(let b) = incoming { return .number(a - b) }
            return current
        case .mulAssign:
            if case .number(let a) = current, case .number(let b) = incoming { return .number(a * b) }
            return current
        case .divAssign:
            if case .number(let a) = current, case .number(let b) = incoming, b != 0 { return .number(a / b) }
            return current
        case .toggle:
            if case .boolean(let b) = current { return .boolean(!b) }
            return current
        }
    }

    // MARK: - Switch pattern matching (Plan 1)

    private func switchPatternMatches(_ pattern: SwitchPattern, value: Value) -> Bool {
        switch pattern {
        case .wildcard:
            return true
        case .literal(let lit):
            switch (lit, value) {
            case (.string(let a), .string(let b)): return a == b
            case (.number(let a), .number(let b)): return a == b
            case (.boolean(let a), .boolean(let b)): return a == b
            case (.nil, .nil): return true
            default: return false
            }
        case .caseMember(let name, _):
            // For enum matching we compare the scrutinee's string representation
            // (or object-tagged "_case" field) against the member name. Full typed
            // enum-value matching lands in Stage 4 when we have a type registry.
            if case .string(let s) = value { return s == name }
            if case .object(let dict) = value, case .string(let tag) = dict["_case"] ?? .nil {
                return tag == name
            }
            return false
        }
    }

    private func bindSwitchCaptures(_ pattern: SwitchPattern, value: Value) {
        guard case .caseMember(_, let bindings) = pattern, !bindings.isEmpty else { return }
        // For .caseMember(name: "success", bindings: ["image"]) with a scrutinee that
        // resolves to .object(["_case": "success", "_values": [imageValue]]) — bind
        // each listed name to the corresponding positional value. Stage 4/8 will
        // flesh this out; for now we bind whatever the scrutinee value is to the first
        // binding name if there are no structured associated values.
        if case .object(let dict) = value,
           case .array(let vals) = dict["_values"] ?? .nil {
            for (i, name) in bindings.enumerated() where i < vals.count {
                variables[name] = vals[i]
            }
        } else if let first = bindings.first {
            variables[first] = value
        }
    }

    /// Evaluate a method call on a value (e.g., array.filter, string.contains)
    private func evaluateMethodCall(obj: Value, method: String, args: [Argument]) -> Value {
        // MARK: - Plan 3: Foundation type method dispatch (checked first)
        if let result = dispatchFoundationMethod(obj: obj, method: method, args: args) {
            return result
        }

        switch (obj, method) {
        // Array methods
        case (.array(let arr), "count"):
            return .number(Double(arr.count))
        case (.array(let arr), "isEmpty"):
            return .boolean(arr.isEmpty)
        case (.array(let arr), "contains"):
            if let arg = args.first {
                let target = evaluate(arg.value)
                return .boolean(arr.contains(target))
            }
            // contains with closure: array.contains { $0.isNumber }
            // For closures, evaluate each element with $0 set
            return evaluateClosureMethod(arr: arr, method: "contains", closure: args.first?.value)
        case (.array(let arr), "filter"):
            return evaluateClosureMethod(arr: arr, method: "filter", closure: args.first?.value)
        case (.array(let arr), "allSatisfy"):
            return evaluateClosureMethod(arr: arr, method: "allSatisfy", closure: args.first?.value)
        case (.array(let arr), "map"):
            return evaluateClosureMethod(arr: arr, method: "map", closure: args.first?.value)
        case (.array(let arr), "compactMap"):
            return evaluateClosureMethod(arr: arr, method: "compactMap", closure: args.first?.value)
        case (.array(let arr), "flatMap"):
            return evaluateClosureMethod(arr: arr, method: "flatMap", closure: args.first?.value)
        case (.array(let arr), "forEach"):
            return evaluateClosureMethod(arr: arr, method: "forEach", closure: args.first?.value)
        case (.array(let arr), "first"):
            if args.isEmpty { return arr.first ?? .nil }
            // first(where:) with closure
            return evaluateClosureMethod(arr: arr, method: "first", closure: args.first?.value)
        case (.array(let arr), "reversed"):
            return .array(arr.reversed())
        case (.array(let arr), "sorted"):
            return .array(arr) // simplified — no comparator support
        case (.array(let arr), "joined"):
            // Array of strings → single string with separator
            let sep: String = {
                if let s = args.first(where: { $0.label == "separator" }) ?? args.first,
                   case .string(let str) = evaluate(s.value) { return str }
                return ""
            }()
            let parts: [String] = arr.compactMap {
                if case .string(let s) = $0 { return s }
                return $0.description
            }
            return .string(parts.joined(separator: sep))

        // String methods
        case (.string(let s), "count"):
            return .number(Double(s.count))
        case (.string(let s), "isEmpty"):
            return .boolean(s.isEmpty)
        case (.string(let s), "contains"):
            if let arg = args.first {
                let target = evaluate(arg.value)
                if case .string(let sub) = target { return .boolean(s.contains(sub)) }
            }
            return .boolean(false)
        case (.string(let s), "hasPrefix"):
            if let arg = args.first, case .string(let pre) = evaluate(arg.value) {
                return .boolean(s.hasPrefix(pre))
            }
            return .boolean(false)
        case (.string(let s), "hasSuffix"):
            if let arg = args.first, case .string(let suf) = evaluate(arg.value) {
                return .boolean(s.hasSuffix(suf))
            }
            return .boolean(false)
        case (.string(let s), "uppercased"):
            return .string(s.uppercased())
        case (.string(let s), "lowercased"):
            return .string(s.lowercased())
        case (.string(let s), "trimmingCharacters"):
            return .string(s.trimmingCharacters(in: .whitespacesAndNewlines))
        case (.string(let s), "containsUppercase"):
            return .boolean(s.contains(where: { $0.isUppercase }))
        case (.string(let s), "containsLowercase"):
            return .boolean(s.contains(where: { $0.isLowercase }))
        case (.string(let s), "containsNumber"), (.string(let s), "containsDigit"):
            return .boolean(s.contains(where: { $0.isNumber }))
        case (.string(let s), "isNotEmpty"):
            return .boolean(!s.isEmpty)

        // Number methods
        case (.number(let n), "rounded"):
            return .number(n.rounded())

        default:
            return .nil
        }
    }

    /// Evaluate a closure-based collection method (filter, allSatisfy, contains, map, first)
    private func evaluateClosureMethod(arr: [Value], method: String, closure: ViewNode?) -> Value {
        guard let closure = closure else { return .nil }

        // Unwrap a `.closure(parameters, body)` so we can bind the named
        // iteration variable in addition to `$0`/`0`.
        let (paramName, body): (String?, ViewNode) = {
            if case .closure(let params, let inner) = closure {
                return (params.first, inner)
            }
            return (nil, closure)
        }()

        // Run the closure body for one item, returning its value. Handles both
        // expression-style (`{ $0 > 0 }`) and block-style (`{ doc in let x = …; return … }`) closures.
        // For block bodies we use the return-signal machinery so an explicit
        // `return` produces the value; otherwise the value of the last
        // expression is returned (implicit return).
        func runOneItem(_ item: Value) -> Value {
            // Bind iteration variables. Save prior values to restore after.
            let priorDollar = renderVariables["$0"]
            let priorZero = renderVariables["0"]
            let priorNamed: Value? = paramName.flatMap { renderVariables[$0] }
            renderVariables["$0"] = item
            renderVariables["0"] = item
            if let p = paramName { renderVariables[p] = item }
            defer {
                renderVariables["$0"] = priorDollar
                renderVariables["0"] = priorZero
                if let p = paramName {
                    if let v = priorNamed { renderVariables[p] = v } else { renderVariables.removeValue(forKey: p) }
                }
            }
            return evaluateClosureBody(body)
        }

        switch method {
        case "filter":
            let filtered = arr.filter { runOneItem($0).isTruthy }
            return .array(filtered)

        case "allSatisfy":
            let result = arr.allSatisfy { runOneItem($0).isTruthy }
            return .boolean(result)

        case "contains":
            let result = arr.contains { runOneItem($0).isTruthy }
            return .boolean(result)

        case "map":
            return .array(arr.map { runOneItem($0) })

        case "compactMap":
            return .array(arr.compactMap { item -> Value? in
                let result = runOneItem(item)
                if case .nil = result { return nil }
                return result
            })

        case "flatMap":
            // Flatten one level — Swift's flatMap on Sequence<Sequence>.
            var out: [Value] = []
            for item in arr {
                let result = runOneItem(item)
                if case .array(let sub) = result {
                    out.append(contentsOf: sub)
                } else if case .nil = result {
                    continue
                } else {
                    out.append(result)
                }
            }
            return .array(out)

        case "forEach":
            for item in arr { _ = runOneItem(item) }
            return .nil

        case "first":
            for item in arr {
                if runOneItem(item).isTruthy { return item }
            }
            return .nil

        default:
            return .nil
        }
    }

    /// Evaluate a closure body to a value. Supports:
    ///  - Single expression: returned directly
    ///  - Block of statements: executed in order; explicit `return <expr>` wins,
    ///    otherwise the last expression's value is the implicit return.
    private func evaluateClosureBody(_ body: ViewNode) -> Value {
        if case .block = body {
            do {
                try executeWithReturn(body)
                return implicitReturnValue(body)
            } catch let signal as ReturnSignal {
                return signal.value
            } catch {
                return .nil
            }
        }
        return evaluate(body)
    }

    /// Resolve string interpolation parts to a single string
    public func resolveInterpolation(_ parts: [StringInterpolationPart]) -> String {
        parts.map { part in
            switch part {
            case .literal(let s): return s
            case .expression(let node): return evaluate(node).description
            }
        }.joined()
    }

    // MARK: - Private

    private func evaluateBinary(_ left: Value, _ op: BinaryOperator, _ right: Value) -> Value {
        switch op {
        case .plus:
            if case .number(let l) = left, case .number(let r) = right { return .number(l + r) }
            return .string(left.description + right.description)
        case .minus:
            if case .number(let l) = left, case .number(let r) = right { return .number(l - r) }
            return .nil
        case .multiply:
            if case .number(let l) = left, case .number(let r) = right { return .number(l * r) }
            return .nil
        case .divide:
            if case .number(let l) = left, case .number(let r) = right, r != 0 { return .number(l / r) }
            return .nil
        case .modulo:
            if case .number(let l) = left, case .number(let r) = right, r != 0 {
                return .number(l.truncatingRemainder(dividingBy: r))
            }
            return .nil
        case .equal: return .boolean(left == right)
        case .notEqual: return .boolean(left != right)
        case .less:
            if case .number(let l) = left, case .number(let r) = right { return .boolean(l < r) }
            return .nil
        case .greater:
            if case .number(let l) = left, case .number(let r) = right { return .boolean(l > r) }
            return .nil
        case .lessEqual:
            if case .number(let l) = left, case .number(let r) = right { return .boolean(l <= r) }
            return .nil
        case .greaterEqual:
            if case .number(let l) = left, case .number(let r) = right { return .boolean(l >= r) }
            return .nil
        case .and: return .boolean(left.isTruthy && right.isTruthy)
        case .or: return .boolean(left.isTruthy || right.isTruthy)
        }
    }

    private func evaluateFunction(_ name: String, arguments: [Argument]) -> Value {
        // Plan 2: user-defined functions take precedence over built-ins so
        // `LibraryApp.swift` can call its own `load()`, `BookService.search`, etc.
        if functions[name] != nil {
            return callUserFunction(key: name, arguments: arguments)
        }

        // Fallback: `load()` inside `struct LibraryApp`'s body is registered as
        // `LibraryApp.load` but called bare. If there's exactly one `*.name`
        // match in the function table, dispatch to it.
        let suffix = ".\(name)"
        let scopedMatches = functions.keys.filter { $0.hasSuffix(suffix) }
        if scopedMatches.count == 1 {
            return callUserFunction(key: scopedMatches[0], arguments: arguments)
        }

        // Host-injected native bridges (Kiln.register). Evaluate the args to
        // values and hand them to the embedding app's closure.
        if let bridge = Self.nativeBridges[name] {
            return bridge(arguments.map { evaluate($0.value) })
        }

        switch name {
        case "abs":
            if let first = arguments.first, case .number(let n) = evaluate(first.value) {
                return .number(abs(n))
            }
        case "String":
            if let first = arguments.first { return .string(evaluate(first.value).description) }
        case "Int":
            if let first = arguments.first, case .number(let n) = evaluate(first.value) {
                return .number(floor(n))
            }
        case "Double":
            if let first = arguments.first, case .number(let n) = evaluate(first.value) {
                return .number(n)
            }
        case "UUID":
            return .string(UUID().uuidString)

        case "print":
            // User-code `print(...)` — three sinks so output is visible
            // regardless of where you're looking:
            //   1. Swift.print → Xcode debug console (when attached)
            //   2. NSLog → device console + os_log archive
            //   3. SwiftRunner.shared.consoleOutput → SwiftCodeRunnerSheet's
            //      "Console" tab in the running app, live as runtime fires.
            let pieces: [String] = arguments.map { evaluate($0.value).description }
            let line = pieces.joined(separator: " ")
            Swift.print("[USER] " + line)
            NSLog("[USER] %@", line)
            SwiftRunner.shared.consoleOutput += line + "\n"
            return .nil

        case "_dictLiteral":
            // Synthesized by the parser for `[k: v, k2: v2]`. The sole argument
            // is an array of 2-element `[k, v]` arrays.
            guard let first = arguments.first,
                  case .arrayLiteral(let pairs) = first.value else {
                return .object([:])
            }
            var dict: [String: Value] = [:]
            for pair in pairs {
                guard case .arrayLiteral(let kv) = pair, kv.count == 2 else { continue }
                let key = evaluate(kv[0])
                let value = evaluate(kv[1])
                let keyString: String
                if case .string(let s) = key { keyString = s }
                else { keyString = key.description }
                dict[keyString] = value
            }
            return .object(dict)

        // MARK: - Plan 3/4: Foundation value constructors

        case "URL":
            // URL(string: "...") or URL("...") — tagged object holds the string.
            if let arg = arguments.first(where: { $0.label == "string" }) ?? arguments.first {
                let s = evaluate(arg.value).description
                return .object(["_type": .string("URL"), "string": .string(s)])
            }
            return .nil

        case "URLComponents":
            // URLComponents(string: "...") → object { _type, string, queryItems: [] }
            if let arg = arguments.first(where: { $0.label == "string" }) ?? arguments.first {
                let s = evaluate(arg.value).description
                return .object([
                    "_type": .string("URLComponents"),
                    "string": .string(s),
                    "queryItems": .array([]),
                ])
            }
            return .nil

        case "URLQueryItem":
            let name = arguments.first(where: { $0.label == "name" }).map { evaluate($0.value).description } ?? ""
            let val  = arguments.first(where: { $0.label == "value" }).map { evaluate($0.value).description } ?? ""
            return .object([
                "_type": .string("URLQueryItem"),
                "name": .string(name),
                "value": .string(val),
            ])

        case "URLError":
            // URLError(.badServerResponse) and friends — thrown only; we just capture
            // the message. Not executed at runtime until Stage 4's throw/catch arrives.
            return .object([
                "_type": .string("URLError"),
                "code": .string(arguments.first.map { evaluate($0.value).description } ?? "unknown"),
            ])

        case "JSONDecoder":
            // Marker object — methods on it dispatch in evaluateMethodCall.
            return .object(["_type": .string("JSONDecoder")])

        case "JSONEncoder":
            return .object(["_type": .string("JSONEncoder")])

        case "Task":
            // `Task { body }` — trailing closure is appended as the last arg.
            // We execute it synchronously; real async comes in a later stage.
            if let last = arguments.last {
                execute(last.value)
            }
            return .nil

        case "withAnimation":
            // `withAnimation(curve) { mutation }` — trailing closure is last arg.
            // We execute the body synchronously; the animation curve is captured
            // but not yet applied to the wrapped mutation.
            if let last = arguments.last {
                execute(last.value)
            }
            return .nil
        case "min":
            let nums = arguments.compactMap { arg -> Double? in
                if case .number(let n) = evaluate(arg.value) { return n }
                return nil
            }
            if let result = nums.min() { return .number(result) }
        case "max":
            let nums = arguments.compactMap { arg -> Double? in
                if case .number(let n) = evaluate(arg.value) { return n }
                return nil
            }
            if let result = nums.max() { return .number(result) }

        // MARK: Built-in network functions

        case "searchBooks":
            // Open Library search. Accepts either `searchBooks("harry")` or
            // `searchBooks(query: "harry")`. Writes results to `books` and toggles
            // `isLoading` via the reactive `variables` store.
            print("[searchBooks] evaluateFunction entered, args=\(arguments)")
            let queryValue: Value
            if let q = arguments.first(where: { $0.label == "query" })?.value {
                queryValue = evaluate(q)
                print("[searchBooks] resolved query from label 'query' → \(queryValue)")
            } else if let first = arguments.first {
                queryValue = evaluate(first.value)
                print("[searchBooks] resolved query from first arg → \(queryValue)")
            } else {
                queryValue = .nil
                print("[searchBooks] no args — empty query")
            }
            // Treat real `.nil` as empty — the stringified description of `.nil` is
            // the literal "nil", which would otherwise leak into an API call.
            let query: String = {
                if case .nil = queryValue { return "" }
                return queryValue.description
            }()
            performOpenLibrarySearch(query: query)
            return .nil

        default:
            // Unknown function with labeled args → struct constructor → .object
            if arguments.contains(where: { $0.label != nil }) {
                var dict: [String: Value] = [:]
                for arg in arguments {
                    if let label = arg.label {
                        let v = evaluate(arg.value)
                        dict[label] = v
                        if name == "Book" {
                            print("[SR] Book(\(label):) ← \(v.description.prefix(80))")
                        }
                    }
                }
                if name == "Book" {
                    print("[SR] Book constructor returning: \(Value.object(dict).description.prefix(120))")
                }
                return .object(dict)
            }
        }
        return .nil
    }

    // MARK: - Book search networking

    /// In-flight search task, cancelled whenever a new search starts (debounce).
    private nonisolated(unsafe) static var currentBookSearchTask: URLSessionDataTask?

    /// Monotonic request id so late responses from a cancelled search don't overwrite
    /// the results of a newer one.
    private nonisolated(unsafe) static var bookSearchGeneration: UInt64 = 0

    /// Kick off an Open Library search against `https://openlibrary.org/search.json?q=…`
    /// and, on completion, write an `[Book]`-shaped array into `variables["books"]`.
    /// Also toggles `variables["isLoading"]`, `variables["bookCount"]`, and
    /// `variables["lastError"]` so the view can react to fetch state.
    private func performOpenLibrarySearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[searchBooks] called with query=\"\(query)\" trimmed=\"\(trimmed)\"")

        // Empty query: clear results immediately, skip the network roundtrip.
        guard !trimmed.isEmpty else {
            print("[searchBooks] empty query — clearing results")
            Self.currentBookSearchTask?.cancel()
            Self.currentBookSearchTask = nil
            self.variables["books"] = .array([])
            self.variables["bookCount"] = .number(0)
            self.variables["isLoading"] = .boolean(false)
            self.variables["lastError"] = .string("")
            return
        }

        Self.currentBookSearchTask?.cancel()
        Self.bookSearchGeneration &+= 1
        let generation = Self.bookSearchGeneration

        self.variables["isLoading"] = .boolean(true)
        self.variables["lastError"] = .string("")

        var comps = URLComponents(string: "https://openlibrary.org/search.json")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "fields", value: "*,availability"),
            URLQueryItem(name: "limit", value: "20"),
        ]
        guard let url = comps.url else { return }

        print("[searchBooks] firing request: \(url)")
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            print("[searchBooks] response received — data=\(data?.count ?? -1) bytes, error=\(error?.localizedDescription ?? "nil"), status=\((response as? HTTPURLResponse)?.statusCode ?? -1)")
            Task { @MainActor in
                guard let self = self else {
                    print("[searchBooks] self is nil — aborting")
                    return
                }
                // Skip stale responses superseded by a newer query.
                guard generation == Self.bookSearchGeneration else {
                    print("[searchBooks] stale response (gen \(generation) vs current \(Self.bookSearchGeneration)) — dropping")
                    return
                }

                if let error = error as NSError?, error.code != NSURLErrorCancelled {
                    print("[searchBooks] network error: \(error.localizedDescription)")
                    self.variables["lastError"] = .string(error.localizedDescription)
                    self.variables["isLoading"] = .boolean(false)
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let docs = json["docs"] as? [[String: Any]] else {
                    print("[searchBooks] JSON parse failed or no 'docs' array")
                    self.variables["books"] = .array([])
                    self.variables["bookCount"] = .number(0)
                    self.variables["isLoading"] = .boolean(false)
                    return
                }
                print("[searchBooks] parsed \(docs.count) docs")

                // Track ISBNs so we can enrich with the bibkeys API in a second call.
                var isbnsToEnrich: [String] = []

                let books: [Value] = docs.prefix(15).map { doc in
                    var dict: [String: Value] = [:]
                    dict["title"] = .string((doc["title"] as? String) ?? "Untitled")
                    if let names = doc["author_name"] as? [String], let first = names.first {
                        dict["author"] = .string(first)
                    } else {
                        dict["author"] = .string("Unknown author")
                    }
                    if let year = doc["first_publish_year"] as? Int {
                        dict["year"] = .string(String(year))
                    } else {
                        dict["year"] = .string("—")
                    }
                    // First ISBN becomes the book's identity for enrichment and for
                    // the cover URL (ISBN-based covers are more consistent than cover_i).
                    let firstIsbn = (doc["isbn"] as? [String])?.first ?? ""
                    dict["isbn"] = .string(firstIsbn)
                    if !firstIsbn.isEmpty {
                        isbnsToEnrich.append(firstIsbn)
                        dict["coverURL"] = .string("https://covers.openlibrary.org/b/isbn/\(firstIsbn)-M.jpg")
                    } else if let coverId = doc["cover_i"] as? Int {
                        dict["coverURL"] = .string("https://covers.openlibrary.org/b/id/\(coverId)-M.jpg")
                    } else {
                        dict["coverURL"] = .string("")
                    }
                    // Defaults so the view can bind safely before enrichment completes.
                    dict["publisher"] = .string("")
                    dict["pages"] = .string("")
                    return .object(dict)
                }

                self.variables["books"] = .array(books)
                self.variables["bookCount"] = .number(Double(books.count))
                self.variables["isLoading"] = .boolean(false)
                print("[searchBooks] wrote \(books.count) books to state")

                // Kick off second call: enrich each book with publisher / pages / larger cover.
                if !isbnsToEnrich.isEmpty {
                    self.performBibkeysEnrichment(isbns: isbnsToEnrich, generation: generation)
                }
            }
        }
        Self.currentBookSearchTask = task
        task.resume()
    }

    /// Second Open Library API call: `https://openlibrary.org/api/books?bibkeys=ISBN:…&format=json&jscmd=data`
    /// returns per-ISBN edition data (publisher, pages, larger cover URL). We merge
    /// those fields into the existing `variables["books"]` so the view updates in place.
    private func performBibkeysEnrichment(isbns: [String], generation: UInt64) {
        let bibkeys = isbns.map { "ISBN:\($0)" }.joined(separator: ",")
        var comps = URLComponents(string: "https://openlibrary.org/api/books")!
        comps.queryItems = [
            URLQueryItem(name: "bibkeys", value: bibkeys),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "jscmd", value: "data"),
        ]
        guard let url = comps.url else { return }
        print("[bibkeys] firing request: \(url)")

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            Task { @MainActor in
                guard let self = self else { return }
                guard generation == Self.bookSearchGeneration else {
                    print("[bibkeys] stale response — dropping")
                    return
                }
                if let error = error as NSError?, error.code != NSURLErrorCancelled {
                    print("[bibkeys] network error: \(error.localizedDescription)")
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("[bibkeys] JSON parse failed")
                    return
                }
                print("[bibkeys] parsed \(json.count) enrichment entries")

                // Merge enrichment into existing books array by ISBN.
                guard case .array(let existing) = self.variables["books"] ?? .nil else { return }
                let enriched: [Value] = existing.map { bookVal in
                    guard case .object(var dict) = bookVal,
                          case .string(let isbn) = dict["isbn"] ?? .nil,
                          !isbn.isEmpty,
                          let entry = json["ISBN:\(isbn)"] as? [String: Any] else {
                        return bookVal
                    }
                    if let publishers = entry["publishers"] as? [[String: Any]],
                       let name = publishers.first?["name"] as? String {
                        dict["publisher"] = .string(name)
                    }
                    if let pages = entry["number_of_pages"] as? Int {
                        dict["pages"] = .string("\(pages) pages")
                    }
                    if let cover = entry["cover"] as? [String: Any],
                       let large = (cover["large"] as? String) ?? (cover["medium"] as? String) {
                        dict["coverURL"] = .string(large)
                    }
                    return .object(dict)
                }
                self.variables["books"] = .array(enriched)
                print("[bibkeys] merged enrichment into books")
            }
        }
        task.resume()
    }
}
