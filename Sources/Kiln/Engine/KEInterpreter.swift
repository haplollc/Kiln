//
//  KEInterpreter.swift
//  Kiln engine 2
//
//  Evaluates a parsed program: types and their members, statements,
//  expressions, patterns, calls and assignments. View construction and the
//  standard library live in KEBuiltins / KESwiftUI; rendering in KERenderer.
//

import SwiftUI

/// A declared user type with its members (extensions merged in).
final class KType {
    let name: String
    let kind: KETypeKind
    var stored: [KEVarDecl] = []
    var computed: [String: KEVarDecl] = [:]
    var staticDecls: [String: KEVarDecl] = [:]
    var staticBoxes: [String: KBox] = [:]
    var methods: [String: [KEFuncDecl]] = [:]
    var staticMethods: [String: [KEFuncDecl]] = [:]
    var inits: [KEFuncDecl] = []
    var cases: [KEEnumCase] = []
    var conformances: Set<String> = []
    var subscripts: [KEFuncDecl] = []
    var nested: [String: KType] = [:]
    var attributes: [KEAttribute] = []

    init(name: String, kind: KETypeKind) {
        self.name = name
        self.kind = kind
    }

    var isView: Bool { conformances.contains("View") }
    var isShape: Bool { conformances.contains("Shape") || conformances.contains("InsettableShape") }
    var isApp: Bool { conformances.contains("App") }
    var isClass: Bool { kind == .classType || kind == .actorType }
    var isEnum: Bool { kind == .enumType }
    var rawType: String? { ["String", "Int", "Double", "Character", "Float", "UInt"].first { conformances.contains($0) } }

    func storedDecl(_ name: String) -> KEVarDecl? { stored.first { $0.name == name } }

    func wrapper(of name: String) -> String? { storedDecl(name)?.wrapper }

    func propertyType(_ name: String) -> KETypeRef? {
        storedDecl(name)?.type ?? computed[name]?.type
    }

    func method(_ name: String, labels: [String?]? = nil) -> KEFuncDecl? {
        KInterpreter.pick(methods[name] ?? [], labels: labels)
    }

    func staticMethod(_ name: String, labels: [String?]? = nil) -> KEFuncDecl? {
        KInterpreter.pick(staticMethods[name] ?? [], labels: labels)
    }

    func enumCase(_ name: String) -> KEEnumCase? { cases.first { $0.name == name } }
}

/// Members added by `extension` to a built-in type (View, Color, Double, …).
final class KBuiltinExtension {
    var computed: [String: KEVarDecl] = [:]
    var staticDecls: [String: KEVarDecl] = [:]
    var staticBoxes: [String: KBox] = [:]
    var methods: [String: [KEFuncDecl]] = [:]
    var staticMethods: [String: [KEFuncDecl]] = [:]
    var inits: [KEFuncDecl] = []
}

enum KFlow {
    case normal
    case ret(KV)
    case brk(String?)
    case cont(String?)
    case fall
}

/// Records the class instances a view body reads, so the view can re-render
/// when any of them changes.
final class KReadTracker {
    var objects: [ObjectIdentifier: KObject] = [:]
}

@MainActor
final class KInterpreter {
    let program: KEProgram
    private(set) var types: [String: KType] = [:]
    var builtinExtensions: [String: KBuiltinExtension] = [:]
    let globalEnv = KEnv(parent: nil)
    var functions: [String: [KEFuncDecl]] = [:]

    var console = "" { didSet { consoleSink?(console) } }
    /// Mirrors console output to the host (Haplo AI's Console tab).
    var consoleSink: ((String) -> Void)?
    /// Set when an `init?` body executes `return nil`.
    var returnedNil = false
    var errors: [String] = []
    var warnings: [String] = []
    private var seen = Set<String>()

    /// Steps left before the current entry (a body, an action) is stopped.
    var fuel = Int.max
    /// Nested interpreted calls right now. Bounded well below the native
    /// stack (iOS gives the main thread 1 MB), so runaway recursion is reported.
    var callDepth = 0
    let maxCallDepth = 160
    var budget = 4_000_000
    /// Random numbers for the program: seeded by Kiln.randomSeed, else the system's.
    var rng = KilnRandom(seed: Kiln.randomSeed)
    var readTracker: KReadTracker?
    /// A global variable changed: re-render everything.
    var onGlobalChange: (() -> Void)?

    init(program: KEProgram) throws {
        self.program = program
        register(program.types, parent: nil)
        for t in program.types where t.kind == .extensionType { applyExtension(t) }
        for t in program.types { applyNestedExtensions(t) }
        for f in program.functions { functions[f.name, default: []].append(f) }
        fuel = budget
        for stmt in program.globals {
            do {
                if case .variable(let decl) = stmt { try declareGlobal(decl) }
                else { _ = try exec1(stmt, globalEnv) }
            } catch {
                report(error)
            }
        }
    }

    // MARK: - Diagnostics

    func report(_ error: Error) {
        let msg: String
        switch error {
        case let e as KERuntimeError: msg = e.description
        case let e as KESyntaxError: msg = e.description
        case let t as KEThrown: msg = "Uncaught error: \(describe(t.value))"
        default: msg = "\(error)"
        }
        if seen.insert(msg).inserted { errors.append(msg) }
    }

    func warn(_ message: String) {
        if seen.insert(message).inserted { warnings.append(message) }
    }

    func fail(_ message: String, _ line: Int = 0) -> KERuntimeError {
        KERuntimeError(message: message, line: line)
    }

    @inline(__always) func tick() throws {
        fuel -= 1
        if fuel < 0 {
            fuel = budget
            throw fail("This code ran too long and was stopped (an endless loop?).")
        }
    }

    /// Run `body` with a fresh step budget.
    func entry<T>(_ body: () throws -> T) rethrows -> T {
        let saved = fuel
        fuel = budget
        defer { fuel = max(saved, 0) }
        return try body()
    }

    // MARK: - Types

    private var declSource: [String: ObjectIdentifier] = [:]

    private func register(_ decls: [KETypeDecl], parent: KType?) {
        for d in decls where d.kind != .extensionType && d.kind != .protocolType {
            let full = parent.map { "\($0.name).\(d.name)" } ?? d.name
            var t = types[full] ?? KType(name: full, kind: d.kind)
            if let prior = declSource[full], prior != ObjectIdentifier(d) {
                t = KType(name: full, kind: d.kind)       // redeclared: replace, don't merge
                if types[d.name]?.name == full { types[d.name] = t }
            }
            declSource[full] = ObjectIdentifier(d)
            types[full] = t
            if types[d.name] == nil || parent == nil { types[d.name] = t }      // short name for nested types
            parent?.nested[d.name] = t
            absorb(d, into: t)
            register(d.nested, parent: t)
        }
    }

    private func absorb(_ d: KETypeDecl, into t: KType) {
        t.conformances.formUnion(d.inherits)
        t.attributes += d.attributes
        if d.attributes.contains(where: { $0.name == "Observable" }) { t.conformances.insert("ObservableObject") }
        for p in d.properties {
            if p.isStatic { t.staticDecls[p.name] = p }
            else if p.isComputed { t.computed[p.name] = p }
            else if d.kind == .extensionType { t.computed[p.name] = p }   // extensions can't add storage
            else { t.stored.append(p) }
        }
        for m in d.methods {
            if m.isStatic { t.staticMethods[m.name, default: []].append(m) }
            else { t.methods[m.name, default: []].append(m) }
        }
        t.inits += d.inits
        t.cases += d.cases
        t.subscripts += d.subscripts
    }

    private func applyExtension(_ d: KETypeDecl) {
        if let t = types[d.name] {
            absorb(d, into: t)
            register(d.nested, parent: t)
            return
        }
        // Extension on a built-in type: View, Color, Double, Array, …
        let key = d.name.split(separator: ".").last.map(String.init) ?? d.name
        let ext = builtinExtensions[key] ?? KBuiltinExtension()
        builtinExtensions[key] = ext
        for p in d.properties {
            if p.isStatic { ext.staticDecls[p.name] = p } else { ext.computed[p.name] = p }
        }
        for m in d.methods {
            if m.isStatic { ext.staticMethods[m.name, default: []].append(m) } else { ext.methods[m.name, default: []].append(m) }
        }
        ext.inits += d.inits
        register(d.nested, parent: nil)
    }

    private func applyNestedExtensions(_ d: KETypeDecl) {
        for n in d.nested where n.kind == .extensionType { applyExtension(n) }
        for n in d.nested { applyNestedExtensions(n) }
    }

    func type(named name: String) -> KType? { types[name] }

    /// The user type a type reference names, if any.
    func userType(_ ref: KETypeRef?) -> KType? {
        guard let ref, let n = ref.core.name else { return nil }
        return types[n]
    }

    /// Pick an overload by argument labels (falls back to the first).
    nonisolated static func pick(_ decls: [KEFuncDecl], labels: [String?]?) -> KEFuncDecl? {
        guard decls.count > 1, let labels else { return decls.first }
        let exact = decls.first { d in
            let required = d.params.filter { $0.defaultValue == nil }
            return labels.count >= required.count && labels.count <= d.params.count &&
                zip(d.params, labels).allSatisfy { $0.label == $1 || ($0.label == nil && $1 == nil) }
        }
        return exact ?? decls.first { $0.params.count == labels.count } ?? decls.first
    }

    private func declareGlobal(_ decl: KEVarDecl) throws {
        if decl.isComputed {
            let getter = decl
            globalEnv.vars[decl.name] = KBox(get: { [unowned self] in
                (try? self.runAccessor(getter.getter ?? [], env: KEnv(parent: self.globalEnv), returns: getter.type)) ?? .nilValue
            }, set: { _ in })
            return
        }
        let value = try decl.initial.map { try eval($0, globalEnv, decl.type) } ?? .nilValue
        try bindPattern(decl.pattern, value, in: globalEnv, isLet: decl.isLet, type: decl.type)
        if case .binding(let n, _) = decl.pattern, let box = globalEnv.vars[n] {
            box.onChange = { [weak self] in self?.onGlobalChange?() }
        }
    }

    // MARK: - Statements

    func exec(_ stmts: [KEStmt], _ env: KEnv) throws -> KFlow {
        var defers: [[KEStmt]] = []
        defer {
            for d in defers.reversed() { _ = try? exec(d, KEnv(parent: env)) }
        }
        for s in stmts {
            if case .deferStmt(let body) = s { defers.append(body); continue }
            let f = try exec1(s, env)
            if case .normal = f { continue }
            return f
        }
        return .normal
    }

    func exec1(_ s: KEStmt, _ env: KEnv) throws -> KFlow {
        try tick()
        switch s {
        case .expr(let e):
            _ = try eval(e, env)
            return .normal

        case .variable(let decl):
            if decl.isComputed {
                let d = decl
                env.vars[decl.name] = KBox(get: { [unowned self] in
                    (try? self.runAccessor(d.getter ?? [], env: KEnv(parent: env), returns: d.type)) ?? .nilValue
                }, set: { _ in })
                return .normal
            }
            let value = try decl.initial.map { try eval($0, env, decl.type) } ?? .nilValue
            try bindPattern(decl.pattern, value, in: env, isLet: decl.isLet, type: decl.type)
            return .normal

        case .assign(let op, let target, let value, let line):
            try assign(op, target, value, env, line)
            return .normal

        case .ifStmt(let conds, let then, let elseClause):
            let scope = KEnv(parent: env)
            if try conditions(conds, scope) { return try exec(then, scope) }
            switch elseClause {
            case .block(let b)?: return try exec(b, KEnv(parent: env))
            case .elseIf(let s)?: return try exec1(s, env)
            case nil: return .normal
            }

        case .guardStmt(let conds, let elseBody):
            if try conditions(conds, env) { return .normal }
            return try exec(elseBody, KEnv(parent: env))

        case .switchStmt(let subject, let cases):
            let value = try eval(subject, env)
            return try runSwitch(value, cases, env)

        case .forIn(let pattern, let seq, let whereClause, let body, let label):
            let items = try sequence(try eval(seq, env))
            for item in items {
                try tick()
                let scope = KEnv(parent: env)
                guard try match(pattern, item, scope, binding: true) else { continue }
                if let w = whereClause, !(truthy(try eval(w, scope))) { continue }
                switch try exec(body, scope) {
                case .brk(let l) where l == nil || l == label: return .normal
                case .cont(let l) where l == nil || l == label: continue
                case .normal: continue
                case let other: return other
                }
            }
            return .normal

        case .whileStmt(let conds, let body, let label):
            while true {
                try tick()
                let scope = KEnv(parent: env)
                guard try conditions(conds, scope) else { break }
                switch try exec(body, scope) {
                case .brk(let l) where l == nil || l == label: return .normal
                case .cont(let l) where l == nil || l == label: continue
                case .normal: continue
                case let other: return other
                }
            }
            return .normal

        case .repeatWhile(let body, let cond, let label):
            repeat {
                try tick()
                switch try exec(body, KEnv(parent: env)) {
                case .brk(let l) where l == nil || l == label: return .normal
                case .cont(let l) where l == nil || l == label: break
                case .normal: break
                case let other: return other
                }
            } while truthy(try eval(cond, env))
            return .normal

        case .returnStmt(let e, _):
            if case .nilLit? = e { returnedNil = true }
            return .ret(try e.map { try eval($0, env, currentReturnType) } ?? .void)

        case .breakStmt(let l): return .brk(l)
        case .continueStmt(let l): return .cont(l)
        case .fallthroughStmt: return .fall

        case .throwStmt(let e):
            throw KEThrown(value: try eval(e, env))

        case .doCatch(let body, let catches):
            do {
                return try exec(body, KEnv(parent: env))
            } catch let thrown as KEThrown {
                return try runCatch(catches, thrown.value, env, rethrow: thrown)
            } catch let err as KERuntimeError where !catches.isEmpty && !err.message.hasPrefix("This code ran too long") {
                return try runCatch(catches, KBuiltins.errorValue(err.message), env, rethrow: err)
            }

        case .deferStmt(let body):
            _ = try exec(body, KEnv(parent: env))
            return .normal

        case .declaration(let d):
            switch d {
            case .function(let f):
                env.declare(f.name, .function(KFunction(.user(f, env, env.nearestSelf))))
            case .type(let t):
                register([t], parent: nil)
                if t.kind == .extensionType { applyExtension(t) }
            default: break
            }
            return .normal
        }
    }

    /// The declared return type of the function being executed (for `return .red`).
    var currentReturnType: KETypeRef?

    private func runCatch(_ catches: [KECatch], _ error: KV, _ env: KEnv, rethrow: Error) throws -> KFlow {
        guard let c = catches.first else { throw rethrow }
        let scope = KEnv(parent: env)
        if case .binding(let n, _)? = c.pattern { scope.declare(n, error) } else { scope.declare("error", error) }
        return try exec(c.body, scope)
    }

    func runSwitch(_ value: KV, _ cases: [KESwitchCase], _ env: KEnv) throws -> KFlow {
        var falling = false
        for c in cases {
            let scope = KEnv(parent: env)
            var hit = falling || c.isDefault
            if !hit {
                for (pattern, whereClause) in c.patterns {
                    let trial = KEnv(parent: env)
                    if try match(pattern, value, trial, binding: false),
                       try whereClause.map({ truthy(try eval($0, trial)) }) ?? true {
                        scope.vars = trial.vars
                        hit = true
                        break
                    }
                }
            }
            guard hit else { continue }
            let f = try exec(c.body, scope)
            if case .fall = f { falling = true; continue }
            if case .brk(nil) = f { return .normal }
            return f
        }
        return .normal
    }

    func conditions(_ conds: [KECondition], _ env: KEnv) throws -> Bool {
        for c in conds {
            switch c {
            case .expr(let e):
                if !truthy(try eval(e, env)) { return false }
            case .optionalBinding(let pattern, let e):
                let v = try eval(e, env)
                if v.isNil { return false }
                try bindPattern(pattern, v, in: env, isLet: true, type: nil)
            case .casePattern(let pattern, let e):
                if !(try match(pattern, try eval(e, env), env, binding: false)) { return false }
            case .available:
                continue
            }
        }
        return true
    }

    func truthy(_ v: KV) -> Bool {
        switch v {
        case .bool(let b): return b
        case .nilValue: return false
        default: return true
        }
    }

    func bindPattern(_ pattern: KEPattern, _ value: KV, in env: KEnv, isLet: Bool, type: KETypeRef?) throws {
        switch pattern {
        case .binding(let name, _):
            if name == "_" { return }
            env.vars[name] = KBox(coerce(value, to: type), isLet: isLet, type: type)
        case .wildcard:
            return
        case .tuple(let ps):
            guard case .tuple(let vals, _) = value, vals.count == ps.count else {
                throw fail("Can't unpack \(describe(value)) into \(ps.count) values")
            }
            for (p, v) in zip(ps, vals) { try bindPattern(p, v, in: env, isLet: isLet, type: nil) }
        default:
            _ = try match(pattern, value, env, binding: true)
        }
    }

    // MARK: - Patterns

    func match(_ pattern: KEPattern, _ value: KV, _ env: KEnv, binding: Bool) throws -> Bool {
        switch pattern {
        case .wildcard:
            return true
        case .binding(let name, _):
            if name != "_" { env.declare(name, value) }
            return true
        case .tuple(let ps):
            guard case .tuple(let vals, _) = value, vals.count == ps.count else { return false }
            for (p, v) in zip(ps, vals) where !(try match(p, v, env, binding: binding)) { return false }
            return true
        case .optional(let inner):
            if value.isNil { return false }
            return try match(inner, value, env, binding: binding)
        case .enumCase(_, let name, let subs):
            switch value {
            case .enumV(let e):
                guard e.caseName == name else { return false }
                if subs.isEmpty { return true }
                for (i, p) in subs.enumerated() where i < e.payload.count {
                    if !(try match(p, e.payload[i], env, binding: binding)) { return false }
                }
                return true
            case .nilValue:
                return name == "none"
            case .native(.implicit(let n, let args)):
                guard n == name else { return false }
                for (i, p) in subs.enumerated() where i < args.count {
                    if !(try match(p, args[i], env, binding: binding)) { return false }
                }
                return true
            default:
                if name == "some", let p = subs.first { return try match(p, value, env, binding: binding) }
                // AsyncImage phases and similar natives match by case name.
                if case .native(let n) = value, n.caseName == name {
                    if let p = subs.first, let payload = n.payload { return try match(p, payload, env, binding: binding) }
                    return true
                }
                return false
            }
        case .expression(let e):
            let target = try eval(e, env, typeRef(of: value))
            if case .range = target { return rangeContains(target, value) }
            if case .function(let f) = target { return truthy(try call(f, [value], [nil])) }
            return target == value
        case .typeCheck(let t):
            return conforms(value, t)
        case .cast(let inner, let t):
            guard conforms(value, t) else { return false }
            return try match(inner, value, env, binding: binding)
        }
    }

    func typeRef(of v: KV) -> KETypeRef? {
        switch v {
        case .structV(let s): return .named(s.type.name, [])
        case .enumV(let e): return .named(e.type.name, [])
        case .object(let o): return .named(o.type.name, [])
        case .int: return .named("Int", [])
        case .double: return .named("Double", [])
        case .string: return .named("String", [])
        case .native(.color): return .named("Color", [])
        default: return nil
        }
    }

    func conforms(_ v: KV, _ t: KETypeRef) -> Bool {
        guard let n = t.core.name else { return true }
        switch (v, n) {
        case (.int, "Int"), (.double, "Double"), (.double, "CGFloat"), (.string, "String"), (.bool, "Bool"),
             (.array, "Array"), (.dict, "Dictionary"): return true
        case (.int, _), (.double, _), (.string, _), (.bool, _): return false
        default:
            if let ut = v.userType { return ut.name == n || ut.conformances.contains(n) }
            return true
        }
    }

    // MARK: - Assignment

    func assign(_ op: String, _ target: KEExpr, _ valueExpr: KEExpr, _ env: KEnv, _ line: Int) throws {
        if case .ident("_", _) = target { _ = try eval(valueExpr, env); return }
        if case .tuple(let parts) = target, op == "=" {
            let v = try eval(valueExpr, env)
            guard case .tuple(let vals, _) = v, vals.count == parts.count else { throw fail("Tuple assignment needs \(parts.count) values", line) }
            let locs = try parts.map { try lvalue($0.1, env) }
            for (loc, val) in zip(locs, vals) { try write(loc, val) }
            return
        }
        let loc = try lvalue(target, env)
        let expected = declaredType(of: loc)
        if op == "=" {
            try write(loc, coerce(try eval(valueExpr, env, expected), to: expected))
            return
        }
        let current = try read(loc)
        let rhs = try eval(valueExpr, env, expected ?? typeRef(of: current))
        let binOp = String(op.dropLast())
        let result: KV
        if binOp == "??" { result = current.isNil ? rhs : current }
        else { result = try arithmetic(binOp, current, rhs, line) }
        try write(loc, result)
    }

    func declaredType(of loc: KLocation) -> KETypeRef? {
        switch loc {
        case .box(let b): return b.declaredType
        case .member(let base, let name):
            if let t = (try? read(base))?.userType { return t.propertyType(name) }
            return nil
        case .objectField(let o, let name): return o.type.propertyType(name)
        case .staticMember(let t, let name): return t.staticDecls[name]?.type
        case .index(let base, _):
            if case .array(let e)? = declaredType(of: base)?.core { return e }
            if case .dictionary(_, let v)? = declaredType(of: base)?.core { return v }
            return nil
        default: return nil
        }
    }

    func lvalue(_ e: KEExpr, _ env: KEnv) throws -> KLocation {
        switch e {
        case .ident(let name, let line):
            if let box = env.lookup(name) { return .box(box) }
            if let ctx = env.nearestSelf, let loc = try selfMemberLocation(ctx, name) { return loc }
            if let box = globalEnv.vars[name] { return .box(box) }
            throw fail("Cannot find '\(name)' in scope", line)
        case .selfRef(let line):
            guard let ctx = env.nearestSelf else { throw fail("'self' used outside of a type", line) }
            return ctx.location
        case .member(let base, let name, _):
            if case .selfRef = base, let ctx = env.nearestSelf, !ctx.isStatic, let loc = try selfMemberLocation(ctx, name) {
                return loc
            }
            if case .ident(let tn, _) = base, env.lookup(tn) == nil, let t = types[tn], !(env.nearestSelf.map { (try? selfMemberLocation($0, tn)) != nil } ?? false) {
                return .staticMember(t, name)
            }
            let baseLoc = try lvalue(base, env)
            return try memberLocation(baseLoc, name)
        case .subscriptAccess(let base, let args, let line):
            let baseLoc = try lvalue(base, env)
            guard let first = args.first else { throw fail("Subscript needs an index", line) }
            let idx = try eval(first.value, env)
            if let d = args.first(where: { $0.label == "default" }) {
                let def = try eval(d.value, env)
                return .computed(get: { [unowned self] in
                    let v = try self.subscriptGet(try self.read(baseLoc), [idx], [nil], line)
                    return v.isNil ? def : v
                }, set: { [unowned self] v in
                    try self.write(.index(baseLoc, idx), v)
                })
            }
            return .index(baseLoc, idx)
        case .optionalChain(let inner), .postfix("!", let inner):
            return try lvalue(inner, env)
        case .call(let callee, let args, _) where args.isEmpty:
            return try lvalue(callee, env)
        default:
            // A value that isn't stored anywhere: writes go nowhere.
            let v = try eval(e, env)
            let box = KBox(v)
            return .box(box)
        }
    }

    /// `name` read or written as a member of `self` (implicit self).
    func selfMemberLocation(_ ctx: KSelfContext, _ name: String) throws -> KLocation? {
        let t = ctx.type
        if ctx.isStatic {
            if t.staticDecls[name] != nil { return .staticMember(t, name) }
            return nil
        }
        if let storage = ctx.storage, let box = storage.box(name) { return .box(box) }
        if let p = t.computed[name] {
            // Run the getter with this same `self` (and its @State storage).
            return .computed(get: { [unowned self] in
                try self.runAccessor(p.getter ?? [], env: KEnv(parent: self.globalEnv, selfContext: ctx), returns: p.type)
            }, set: { [unowned self] v in
                guard let setter = p.setter else { throw self.fail("'\(name)' is a get-only property") }
                let env = KEnv(parent: self.globalEnv, selfContext: ctx)
                env.declare(setter.0, v)
                _ = try self.exec(setter.1, env)
            })
        }
        if t.storedDecl(name) != nil {
            return try memberLocation(ctx.location, name)
        }
        if t.staticDecls[name] != nil { return .staticMember(t, name) }
        return nil
    }

    func memberLocation(_ base: KLocation, _ name: String) throws -> KLocation {
        let value = try read(base)
        switch value {
        case .object(let o):
            return .objectField(o, name)
        case .structV(let s):
            if s.type.wrapper(of: name) == "Binding", case .binding(let b)? = s.fields[name] { return .binding(b) }
            return .member(base, name)
        case .binding(let b):
            return .member(.binding(b), name)
        default:
            return .member(base, name)
        }
    }

    func read(_ loc: KLocation) throws -> KV {
        switch loc {
        case .box(let b): return b.value
        case .binding(let b): return b.get()
        case .member(let base, let name): return try member(try read(base), name, line: 0)
        case .index(let base, let idx): return try subscriptGet(try read(base), [idx], [nil], 0)
        case .objectField(let o, let name):
            readTracker?.objects[ObjectIdentifier(o)] = o
            if let v = o.fields[name] { return unwrapField(o.type, name, v) }
            return try member(.object(o), name, line: 0)
        case .staticMember(let t, let name): return try staticValue(t, name)
        case .computed(let get, _): return try get()
        }
    }

    func write(_ loc: KLocation, _ newValue: KV) throws {
        switch loc {
        case .box(let b):
            b.value = coerce(newValue, to: b.declaredType)
        case .binding(let b):
            b.set(newValue)
        case .objectField(let o, let name):
            if let p = o.type.computed[name], let setter = p.setter {
                try runSetter(setter, value: newValue, selfLoc: .box(KBox(.object(o))), type: o.type)
                return
            }
            if case .binding(let b)? = o.fields[name] { b.set(newValue); return }
            let decl = o.type.storedDecl(name)
            let old = o.fields[name] ?? .nilValue
            let v = coerce(newValue, to: decl?.type)
            if let ws = decl?.willSet { try runObserver(ws, v, selfLoc: .box(KBox(.object(o))), type: o.type) }
            o.fields[name] = v
            o.didChange()
            if let ds = decl?.didSet { try runObserver(ds, old, selfLoc: .box(KBox(.object(o))), type: o.type) }
        case .staticMember(let t, let name):
            _ = try staticValue(t, name)
            t.staticBoxes[name]?.value = newValue
        case .computed(_, let set):
            try set(newValue)
        case .index(let base, let idx):
            var container = try read(base)
            switch container {
            case .array(var arr):
                guard let i = idx.asInt, i >= 0, i < arr.count else {
                    throw fail("Index \(describe(idx)) is out of range (count \(arr.count))")
                }
                arr[i] = newValue
                container = .array(arr)
            case .dict(var d):
                if newValue.isNil { d.removeValue(forKey: idx) } else { d[idx] = newValue }
                container = .dict(d)
            case .structV(let s) where !s.type.subscripts.isEmpty:
                throw fail("Assigning through a custom subscript on \(s.type.name) isn't supported")
            default:
                throw fail("Can't assign into a subscript of \(describe(container))")
            }
            try write(base, container)
        case .member(let base, let name):
            let container = try read(base)
            switch container {
            case .structV(var s):
                if let p = s.type.computed[name] {
                    guard let setter = p.setter else { throw fail("'\(name)' is a get-only property") }
                    try runSetter(setter, value: newValue, selfLoc: base, type: s.type)
                    return
                }
                if case .binding(let b)? = s.fields[name], s.type.wrapper(of: name) == "Binding" { b.set(newValue); return }
                let decl = s.type.storedDecl(name)
                let old = s.fields[name] ?? .nilValue
                let v = coerce(newValue, to: decl?.type)
                if let ws = decl?.willSet { try runObserver(ws, v, selfLoc: base, type: s.type) }
                s.fields[name] = v
                try write(base, .structV(s))
                if let ds = decl?.didSet { try runObserver(ds, old, selfLoc: base, type: s.type) }
            case .object(let o):
                try write(.objectField(o, name), newValue)
            case .tuple(var vals, let labels):
                if let i = Int(name), i < vals.count { vals[i] = newValue }
                else if let i = labels.firstIndex(of: name) { vals[i] = newValue }
                else { throw fail("Tuple has no element '\(name)'") }
                try write(base, .tuple(vals, labels))
            case .binding(let b):
                // `$habit.name = …` style: write the member inside the bound value.
                let box = KBox(b.get())
                try write(.member(.box(box), name), newValue)
                b.set(box.value)
            case .nilValue:
                return   // optional chaining on nil: no-op
            case .native(let n) where KBuiltins.setNativeMember(n, name, newValue):
                return   // a Foundation object (DateFormatter, JSONDecoder, URLComponents …) is a reference
            default:
                throw fail("Can't set '\(name)' on \(describe(container))")
            }
        }
    }

    private func runSetter(_ setter: (String, [KEStmt]), value: KV, selfLoc: KLocation, type: KType) throws {
        let env = KEnv(parent: globalEnv, selfContext: KSelfContext(type: type, location: selfLoc))
        env.declare(setter.0, value)
        _ = try exec(setter.1, env)
    }

    private func runObserver(_ obs: (String, [KEStmt]), _ value: KV, selfLoc: KLocation, type: KType) throws {
        let env = KEnv(parent: globalEnv, selfContext: KSelfContext(type: type, location: selfLoc))
        env.declare(obs.0, value)
        _ = try exec(obs.1, env)
    }

    // MARK: - Coercion

    /// Swift's literal typing and implicit members at a typed destination:
    /// `let x: Double = 5`, `mode = .shortBreak`, `category: .food`.
    func coerce(_ v: KV, to t: KETypeRef?) -> KV {
        guard let t else { return v }
        switch (v, t.core) {
        case (.int(let i), .named(let n, _)) where ["Double", "CGFloat", "Float", "TimeInterval"].contains(n):
            return .double(Double(i))
        case (.native(.implicit(let name, let args)), .named(let n, _)):
            if let ut = types[n] {
                if let resolved = try? implicitOn(ut, name, args.isEmpty ? nil : args) { return resolved }
            }
            if let resolved = KBuiltins.implicit(name, args, expectedType: n) { return resolved }
            return v
        case (.array(let items), .array(let elem)):
            return .array(items.map { coerce($0, to: elem) })
        case (.dict(let d), .dictionary(let kt, let vt)):
            var out: [KV: KV] = [:]
            for (k, val) in d { out[coerce(k, to: kt)] = coerce(val, to: vt) }
            return .dict(out)
        case (.array(let items), .named("Set", let args)):
            return .set(Set(items.map { coerce($0, to: args.first) }))
        default:
            return v
        }
    }

    /// `.name` / `.name(args)` on a user type: an enum case, a static member or method.
    func implicitOn(_ t: KType, _ name: String, _ args: [KV]?, labels: [String?] = []) throws -> KV? {
        if let c = t.enumCase(name) {
            return .enumV(KEnumValue(type: t, caseName: c.name, payload: args ?? [], payloadLabels: labels))
        }
        if args == nil, t.staticDecls[name] != nil { return try staticValue(t, name) }
        if let m = t.staticMethod(name) {
            return try invoke(m, args: args ?? [], labels: labels, selfContext: KSelfContext(type: t, location: .box(KBox(.type(.user(t)))), isStatic: true), parent: globalEnv)
        }
        if name == "init" { return try instantiate(t, args: args ?? [], labels: labels, line: 0) }
        return nil
    }

    // MARK: - Statics

    func staticValue(_ t: KType, _ name: String) throws -> KV {
        if let box = t.staticBoxes[name] { return box.value }
        guard let decl = t.staticDecls[name] else {
            if let c = t.enumCase(name) { return .enumV(KEnumValue(type: t, caseName: c.name, payload: [])) }
            throw fail("Type '\(t.name)' has no member '\(name)'")
        }
        let ctx = KSelfContext(type: t, location: .box(KBox(.type(.user(t)))), isStatic: true)
        if decl.isComputed {
            return try runAccessor(decl.getter ?? [], env: KEnv(parent: globalEnv, selfContext: ctx), returns: decl.type)
        }
        let value = try decl.initial.map { try eval($0, KEnv(parent: globalEnv, selfContext: ctx), decl.type) } ?? .nilValue
        let box = KBox(coerce(value, to: decl.type), type: decl.type)
        box.onChange = { [weak self] in self?.onGlobalChange?() }
        t.staticBoxes[name] = box
        return box.value
    }

    // MARK: - Functions

    /// Run a getter body: a single expression returns its value; a view body
    /// with several statements collects views like a result builder.
    func runAccessor(_ body: [KEStmt], env: KEnv, returns: KETypeRef?) throws -> KV {
        let saved = currentReturnType
        currentReturnType = returns
        defer { currentReturnType = saved }
        if body.count == 1, case .expr(let e) = body[0] { return coerce(try eval(e, env, returns), to: returns) }
        if let r = returns, KEFuncDecl.isViewType(r), !containsReturn(body) {
            return .view(KView.group(try evalBuilder(body, env)))
        }
        if body.count == 1, case .switchStmt = body[0], let r = returns, KEFuncDecl.isViewType(r) {
            return .view(KView.group(try evalBuilder(body, env)))
        }
        switch try exec(body, env) {
        case .ret(let v): return coerce(v, to: returns)
        default: return .void
        }
    }

    func containsReturn(_ stmts: [KEStmt]) -> Bool {
        for s in stmts {
            switch s {
            case .returnStmt: return true
            case .ifStmt(_, let t, let e):
                if containsReturn(t) { return true }
                if case .block(let b)? = e, containsReturn(b) { return true }
                if case .elseIf(let s)? = e, containsReturn([s]) { return true }
            case .switchStmt(_, let cases):
                if cases.contains(where: { containsReturn($0.body) }) { return true }
            case .guardStmt(_, let b): if containsReturn(b) { return true }
            default: continue
            }
        }
        return false
    }

    /// Call a user function or method with evaluated arguments.
    func invoke(_ decl: KEFuncDecl, args: [KV], labels: [String?], selfContext: KSelfContext?, parent: KEnv) throws -> KV {
        try tick()
        callDepth += 1
        defer { callDepth -= 1 }
        if callDepth > maxCallDepth {
            throw fail("Too much recursion: \(decl.name)() kept calling itself.")
        }
        let env = KEnv(parent: parent, selfContext: selfContext)
        try bindParameters(decl.params, args: args, labels: labels, into: env, name: decl.name)
        let saved = currentReturnType
        currentReturnType = decl.returnType
        defer { currentReturnType = saved }
        let body = decl.body
        if body.count == 1, case .expr(let e) = body[0], decl.returnType != nil || decl.isViewBuilder {
            return coerce(try eval(e, env, decl.returnType), to: decl.returnType)
        }
        if decl.isViewBuilder && !containsReturn(body) {
            return .view(KView.group(try evalBuilder(body, env)))
        }
        switch try exec(body, env) {
        case .ret(let v): return coerce(v, to: decl.returnType)
        default: return .void
        }
    }

    func bindParameters(_ params: [KEParam], args: [KV], labels: [String?], into env: KEnv, name: String) throws {
        var used = Array(repeating: false, count: args.count)
        var next = 0
        for (pi, p) in params.enumerated() {
            if p.isVariadic {
                var rest: [KV] = []
                while next < args.count, labels[next] == nil || labels[next] == p.label { rest.append(args[next]); used[next] = true; next += 1 }
                env.declare(p.name, .array(rest))
                continue
            }
            var found: Int? = nil
            if next < args.count, labels[next] == p.label { found = next }
            else if let i = labels.indices.first(where: { !used[$0] && labels[$0] == p.label && $0 >= next }) { found = i }
            else if next < args.count, !used[next], p.defaultValue == nil, (labels[next] == nil || p.label == nil) {
                found = next   // lenient: positional match despite a label mismatch
            } else if next < args.count, !used[next], p.defaultValue == nil, params.count - pi == args.count - next {
                found = next
            }
            if let i = found {
                used[i] = true
                next = i + 1
                var v = coerce(args[i], to: p.type)
                if p.isInout, case .binding(let b) = v {
                    env.vars[p.name] = KBox(get: { b.get() }, set: { b.set($0) })
                    continue
                }
                if case .function = v {} else if p.type.map(isFunctionType) == true, case .nilValue = v { v = .nilValue }
                env.vars[p.name] = KBox(v, isLet: !p.isInout, type: p.type)
            } else if let d = p.defaultValue {
                env.declare(p.name, coerce(try eval(d, env, p.type), to: p.type), type: p.type)
            } else {
                throw fail("Missing argument '\(p.label ?? p.name)' in call to \(name)")
            }
        }
    }

    private func isFunctionType(_ t: KETypeRef) -> Bool { if case .function = t.core { return true }; return false }

    /// Call any callable value.
    func call(_ f: KFunction, _ args: [KV], _ labels: [String?]) throws -> KV {
        switch f.kind {
        case .native(_, let fn):
            return try fn(args, labels)
        case .user(let decl, let env, let ctx):
            return try invoke(decl, args: args, labels: labels, selfContext: ctx, parent: env)
        case .closure(let c, let captured):
            try tick()
            callDepth += 1
            defer { callDepth -= 1 }
            if callDepth > maxCallDepth { throw fail("Too much recursion in a closure.") }
            let env = KEnv(parent: captured)
            bindClosureParams(c, args, env)
            if c.body.count == 1, case .expr(let e) = c.body[0] { return try eval(e, env) }
            switch try exec(c.body, env) {
            case .ret(let v): return v
            default: return .void
            }
        }
    }

    func bindClosureParams(_ c: KEClosure, _ args: [KV], _ env: KEnv) {
        if c.hasExplicitParams {
            if c.params.count == 1, args.count > 1 {
                // `{ pair in … }` receiving several values gets a tuple.
                env.declare(c.params[0].name, .tuple(args, Array(repeating: nil, count: args.count)))
                return
            }
            for (i, p) in c.params.enumerated() where p.name != "_" {
                var v: KV = i < args.count ? args[i] : .nilValue
                if c.params.count > 1, args.count == 1, case .tuple(let vals, _) = args[0], i < vals.count { v = vals[i] }
                if p.name.hasPrefix("$"), case .binding(let b) = v {
                    // `ForEach($items) { $item in }`: `$item` is the binding, `item` its value.
                    env.declare(p.name, v)
                    env.vars[String(p.name.dropFirst())] = KBox(get: { b.get() }, set: { b.set($0) })
                } else {
                    env.declare(p.name, coerce(v, to: p.type))
                }
            }
        } else {
            for (i, a) in args.enumerated() { env.declare("$\(i)", a) }
            if args.count == 1, case .tuple(let vals, _) = args[0] {
                for (i, a) in vals.enumerated() where i > 0 { env.declare("$\(i)", a) }
            }
        }
    }

    /// Run a closure as a result builder: the views its statements produce.
    func callBuilder(_ f: KFunction, _ args: [KV] = []) throws -> [KView] {
        switch f.kind {
        case .closure(let c, let captured):
            let env = KEnv(parent: captured)
            bindClosureParams(c, args, env)
            return try evalBuilder(c.body, env)
        default:
            let v = try call(f, args, args.map { _ in nil })
            return KBuiltins.asViews(v, self)
        }
    }

    // MARK: - Result builders

    func evalBuilder(_ stmts: [KEStmt], _ env: KEnv) throws -> [KView] {
        var out: [KView] = []
        for s in stmts {
            try tick()
            switch s {
            case .expr(let e):
                let v = try eval(e, env)
                out.append(contentsOf: KBuiltins.asViews(v, self))
            case .ifStmt(let conds, let then, let elseClause):
                let scope = KEnv(parent: env)
                if try conditions(conds, scope) {
                    out.append(.conditional(true, try evalBuilder(then, scope)))
                } else {
                    switch elseClause {
                    case .block(let b)?: out.append(.conditional(false, try evalBuilder(b, KEnv(parent: env))))
                    case .elseIf(let st)?: out.append(.conditional(false, try evalBuilder([st], env)))
                    case nil: out.append(.conditional(false, []))
                    }
                }
            case .switchStmt(let subject, let cases):
                let value = try eval(subject, env)
                var produced: [KView] = []
                var falling = false
                for (ci, c) in cases.enumerated() {
                    let scope = KEnv(parent: env)
                    var hit = falling || c.isDefault
                    if !hit {
                        for (pattern, w) in c.patterns {
                            let trial = KEnv(parent: env)
                            if try match(pattern, value, trial, binding: false), try w.map({ truthy(try eval($0, trial)) }) ?? true {
                                scope.vars = trial.vars; hit = true; break
                            }
                        }
                    }
                    guard hit else { continue }
                    produced = try evalBuilder(c.body, scope)
                    out.append(.switchBranch(ci, produced))
                    falling = false
                    break
                }
                _ = falling
            case .forIn(let pattern, let seq, let whereClause, let body, _):
                // Not legal SwiftUI, but models write it: treat as ForEach.
                for item in try sequence(try eval(seq, env)) {
                    let scope = KEnv(parent: env)
                    guard try match(pattern, item, scope, binding: true) else { continue }
                    if let w = whereClause, !truthy(try eval(w, scope)) { continue }
                    out.append(contentsOf: try evalBuilder(body, scope))
                }
            case .returnStmt(let e, _):
                if let e { out.append(contentsOf: KBuiltins.asViews(try eval(e, env), self)) }
                return out
            default:
                let f = try exec1(s, env)
                if case .ret(let v) = f { out.append(contentsOf: KBuiltins.asViews(v, self)); return out }
            }
        }
        return out
    }

    // MARK: - Sequences

    func sequence(_ v: KV) throws -> [KV] {
        switch v {
        case .array(let a): return a
        case .set(let s): return Array(s)
        case .dict(let d):
            return d.map { .tuple([$0.key, $0.value], ["key", "value"]) }
        case .range(let lo, let hi, let closed):
            guard let l = lo.asInt, let h = hi.asInt else {
                if let l = lo.asDouble, let h = hi.asDouble {
                    var out: [KV] = []
                    var x = l
                    while closed ? x <= h : x < h { out.append(.int(Int(x))); x += 1 }
                    return out
                }
                throw fail("Can't loop over \(describe(v))")
            }
            if closed ? h < l : h < l { return [] }
            if h - l > 1_000_000 { throw fail("That range is too large to loop over") }
            return (closed ? Array(l...h) : Array(l..<h)).map { .int($0) }
        case .string(let s): return s.map { .string(String($0)) }
        case .nilValue: return []
        default:
            throw fail("Can't loop over \(describe(v))")
        }
    }

    func rangeContains(_ r: KV, _ v: KV) -> Bool {
        guard case .range(let lo, let hi, let closed) = r else { return false }
        if let x = v.asDouble {
            let l = lo.asDouble ?? -.infinity, h = hi.asDouble ?? .infinity
            return x >= l && (closed ? x <= h : x < h)
        }
        if let s = v.asString, let l = lo.asString, let h = hi.asString { return s >= l && (closed ? s <= h : s < h) }
        return false
    }

    // MARK: - Description

    func describe(_ v: KV, quoted: Bool = false) -> String {
        switch v {
        case .void: return "()"
        case .nilValue: return "nil"
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return String(describing: d)
        case .string(let s): return quoted ? "\"\(s)\"" : s
        case .array(let a): return "[" + a.map { describe($0, quoted: true) }.joined(separator: ", ") + "]"
        case .set(let s): return "[" + s.map { describe($0, quoted: true) }.joined(separator: ", ") + "]"
        case .dict(let d):
            if d.isEmpty { return "[:]" }
            return "[" + d.map { "\(describe($0.key, quoted: true)): \(describe($0.value, quoted: true))" }.joined(separator: ", ") + "]"
        case .tuple(let t, let labels):
            return "(" + t.enumerated().map { i, x in (labels.indices.contains(i) && labels[i] != nil ? labels[i]! + ": " : "") + describe(x, quoted: true) }.joined(separator: ", ") + ")"
        case .range(let a, let b, let closed): return "\(describe(a))\(closed ? "..." : "..<")\(describe(b))"
        case .structV(let s):
            let parts = s.type.stored.compactMap { d -> String? in
                guard let f = s.fields[d.name] else { return nil }
                return "\(d.name): \(describe(f, quoted: true))"
            }
            return "\(s.type.name)(\(parts.joined(separator: ", ")))"
        case .enumV(let e):
            if e.payload.isEmpty { return e.caseName }
            return "\(e.caseName)(\(e.payload.map { describe($0, quoted: true) }.joined(separator: ", ")))"
        case .object(let o): return o.type.name
        case .function: return "(Function)"
        case .type(let t): return t.name
        case .view: return "View"
        case .binding(let b): return "Binding(\(describe(b.get(), quoted: true)))"
        case .native(let n): return n.describe(self)
        }
    }
}
