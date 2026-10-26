//
//  KEEval.swift
//  Kiln engine 2
//
//  Expression evaluation: names, members, calls, subscripts, operators,
//  initializers. Calls to SwiftUI views and the standard library are routed
//  to KBuiltins.
//

import SwiftUI

extension KInterpreter {

    // MARK: - Expressions

    func eval(_ e: KEExpr, _ env: KEnv, _ expected: KETypeRef? = nil) throws -> KV {
        try tick()
        switch e {
        case .int(let i):
            if let n = expected?.core.name, ["Double", "CGFloat", "Float", "TimeInterval"].contains(n) { return .double(Double(i)) }
            return .int(i)
        case .double(let d): return .double(d)
        case .bool(let b): return .bool(b)
        case .nilLit: return .nilValue
        case .string(let segs): return .string(try stringLiteral(segs, env))
        case .ident(let name, let line): return try lookupIdent(name, env, line)
        case .selfRef(let line):
            guard let ctx = env.nearestSelf else { throw fail("'self' used outside of a type", line) }
            if ctx.isStatic { return .type(.user(ctx.type)) }
            return try read(ctx.location)
        case .implicitMember(let name, _):
            return try implicitMember(name, nil, [], expected)
        case .member(let base, let name, let line):
            if case .selfRef = base, let ctx = env.nearestSelf, !ctx.isStatic, let loc = try selfMemberLocation(ctx, name) {
                return try read(loc)
            }
            if let t = typeExpr(base, env) {
                if let nested = t.nested[name] { return .type(.user(nested)) }
                return try staticMember(t, name, line)
            }
            if case .ident(let bn, _) = base, isBuiltinTypeName(bn, env) {
                if let ext = builtinExtensions[bn], ext.staticDecls[name] != nil { return try builtinStatic(bn, name) }
                return try KBuiltins.staticMember(bn, name, self, line)
            }
            let b = try eval(base, env)
            return try member(b, name, line: line)
        case .optionalChain(let inner):
            return try eval(inner, env, expected)
        case .call(let callee, let args, let line):
            return try evalCall(callee, args, env, line, expected)
        case .subscriptAccess(let base, let args, let line):
            let b = try eval(base, env)
            let idx = try args.map { try eval($0.value, env) }
            if let d = args.firstIndex(where: { $0.label == "default" }) {
                let v = try subscriptGet(b, [idx[0]], [nil], line)
                return v.isNil ? idx[d] : v
            }
            return try subscriptGet(b, idx, args.map(\.label), line)
        case .closure(let c):
            return .function(KFunction(.closure(c, env)))
        case .prefix(let op, let x):
            switch op {
            case "!":
                return .bool(!truthy(try eval(x, env)))
            case "-":
                let v = try eval(x, env, expected)
                switch v {
                case .int(let i): return .int(-i)
                case .double(let d): return .double(-d)
                default: throw fail("Can't negate \(describe(v))")
                }
            case "+": return try eval(x, env, expected)
            case "~": if case .int(let i) = try eval(x, env) { return .int(~i) }; return .void
            case "&":
                // inout: pass a binding to the storage.
                let loc = try lvalue(x, env)
                return .binding(KBinding(get: { [unowned self] in (try? self.read(loc)) ?? .nilValue },
                                         set: { [unowned self] v in try? self.write(loc, v) }))
            case "..<": return .range(.nilValue, try eval(x, env), closed: false)
            case "...": return .range(.nilValue, try eval(x, env), closed: true)
            default: throw fail("Unknown operator \(op)")
            }
        case .postfix(let op, let x):
            let v = try eval(x, env, expected)
            if op == "!" {
                if v.isNil { throw fail("Unexpectedly found nil while unwrapping an Optional value", e.line) }
                return v
            }
            return .range(v, .nilValue, closed: true)
        case .binary(let op, let l, let r, let line):
            return try binary(op, l, r, env, line, expected)
        case .ternary(let c, let t, let f):
            return truthy(try eval(c, env)) ? try eval(t, env, expected) : try eval(f, env, expected)
        case .array(let elems):
            var elemType: KETypeRef? = nil
            if case .array(let et)? = expected?.core { elemType = et }
            if case .named("Set", let a)? = expected?.core { elemType = a.first }
            let vals = try elems.map { coerce(try eval($0, env, elemType), to: elemType) }
            if case .named("Set", _)? = expected?.core { return .set(Set(vals)) }
            return .array(vals)
        case .dictionary(let pairs):
            var kt: KETypeRef? = nil, vt: KETypeRef? = nil
            if case .dictionary(let k, let v)? = expected?.core { kt = k; vt = v }
            var d: [KV: KV] = [:]
            for (k, v) in pairs { d[try eval(k, env, kt)] = coerce(try eval(v, env, vt), to: vt) }
            return .dict(d)
        case .tuple(let elems):
            return .tuple(try elems.map { try eval($0.1, env) }, elems.map(\.0))
        case .keyPath(_, let comps):
            return .native(.keyPath(comps))
        case .cast(let x, let kind, let t):
            let v = try eval(x, env, t)
            switch kind {
            case "is": return .bool(conforms(v, t))
            case "as?": return conforms(v, t) ? coerce(v, to: t) : .nilValue
            default: return coerce(v, to: t)
            }
        case .tryExpr(let kind, let x):
            if kind == "try?" {
                do { return try eval(x, env, expected) }
                catch let err as KERuntimeError where err.message.hasPrefix("This code ran too long") { throw err }
                catch { return .nilValue }
            }
            return try eval(x, env, expected)
        case .awaitExpr(let x):
            return try eval(x, env, expected)
        case .typeExpr(let t):
            if let ut = userType(t) { return .type(.user(ut)) }
            return .type(.builtin(t.description))
        case .ifExpr(let conds, let then, let other):
            let scope = KEnv(parent: env)
            let body = try conditions(conds, scope) ? then : other
            return try blockValue(body, try conditions(conds, KEnv(parent: env)) ? scope : KEnv(parent: env), expected)
        case .switchExpr(let subject, let cases):
            let value = try eval(subject, env)
            for c in cases {
                let scope = KEnv(parent: env)
                var hit = c.isDefault
                if !hit {
                    for (p, w) in c.patterns where try match(p, value, scope, binding: false) {
                        if try w.map({ truthy(try eval($0, scope)) }) ?? true { hit = true; break }
                    }
                }
                if hit { return try blockValue(c.body, scope, expected) }
            }
            return .void
        case .assign(let op, let target, let value, let line):
            try assign(op, target, value, env, line)
            return .void
        }
    }

    /// The value of a block used as an expression (its last expression).
    private func blockValue(_ body: [KEStmt], _ env: KEnv, _ expected: KETypeRef?) throws -> KV {
        guard let last = body.last else { return .void }
        _ = try exec(Array(body.dropLast()), env)
        if case .expr(let e) = last { return try eval(e, env, expected) }
        if case .ret(let v) = try exec1(last, env) { return v }
        return .void
    }

    /// `localized`: the literal is a SwiftUI LocalizedStringKey (a Text, a
    /// Button title …), whose interpolation formats integers with grouping
    /// ("1,400") and floating point with six decimals ("3.500000"), as SwiftUI does.
    func stringLiteral(_ segs: [KEStringSegment], _ env: KEnv, localized: Bool = false) throws -> String {
        var s = ""
        for seg in segs {
            switch seg {
            case .text(let t): s += t
            case .interp(let args):
                guard let first = args.first else { continue }
                let v = try eval(first.value, env)
                if let spec = args.first(where: { $0.label == "specifier" }) {
                    s += KBuiltins.format(try eval(spec.value, env).asString ?? "%@", [v], self)
                } else if let fmt = args.first(where: { $0.label == "format" }) {
                    s += KBuiltins.formatted(v, try eval(fmt.value, env), self)
                } else if args.contains(where: { $0.label == "style" }), case .native(.date(let d)) = v {
                    s += d.formatted(date: .abbreviated, time: .shortened)
                } else if localized, case .int(let i) = v {
                    s += String.localizedStringWithFormat("%lld", i)
                } else if localized, case .double(let d) = v {
                    s += String.localizedStringWithFormat("%lf", d)
                } else {
                    s += describe(v)
                }
            }
        }
        return s
    }

    // MARK: - Names

    func isBuiltinTypeName(_ name: String, _ env: KEnv) -> Bool {
        guard name.first?.isUppercase == true, env.lookup(name) == nil, types[name] == nil else { return false }
        if let ctx = env.nearestSelf, ctx.type.storedDecl(name) != nil || ctx.type.computed[name] != nil { return false }
        return true
    }

    /// The user type an expression names (`Category`, `Outer.Inner`, `Self`).
    func typeExpr(_ e: KEExpr, _ env: KEnv) -> KType? {
        switch e {
        case .ident(let n, _):
            if n == "Self" { return env.nearestSelf?.type }
            guard env.lookup(n) == nil, let t = types[n] else { return nil }
            if let ctx = env.nearestSelf, !ctx.isStatic, ctx.type.storedDecl(n) != nil || ctx.type.computed[n] != nil { return nil }
            return t
        case .member(let b, let n, _):
            if let outer = typeExpr(b, env) { return outer.nested[n] }
            return nil
        case .typeExpr(let t): return userType(t)
        default: return nil
        }
    }

    func lookupIdent(_ name: String, _ env: KEnv, _ line: Int) throws -> KV {
        if let box = env.lookup(name) { return box.value }
        if name.hasPrefix("$"), name.count > 1 {
            let base = String(name.dropFirst())
            if base.first?.isNumber == true { throw fail("'\(name)' used outside of a closure", line) }
            if let ctx = env.nearestSelf, let proj = try projection(ctx, base) { return proj }
            if let box = env.lookup(base) {
                return .binding(KBinding(get: { box.value }, set: { box.value = $0 }))
            }
            throw fail("Cannot find '\(name)' in scope", line)
        }
        if let ctx = env.nearestSelf {
            if let loc = try selfMemberLocation(ctx, name) { return try read(loc) }
            if let m = ctx.type.methods[name]?.first, !ctx.isStatic { return .function(KFunction(.user(m, globalEnv, ctx))) }
            if let m = ctx.type.staticMethods[name]?.first { return .function(KFunction(.user(m, globalEnv, ctx))) }
            if ctx.type.enumCase(name) != nil, ctx.isStatic { return try staticValue(ctx.type, name) }
            // A view struct's `@Environment(\.dismiss)` read before storage exists.
            if let w = ctx.type.wrapper(of: name), w == "Environment" { return KBuiltins.environmentDefault(ctx.type.storedDecl(name)!, self) }
        }
        if let box = globalEnv.vars[name] { return box.value }
        if let fs = functions[name], let f = fs.first { return .function(KFunction(.user(f, globalEnv, nil))) }
        if let t = types[name] { return .type(.user(t)) }
        if let op = KBuiltins.operatorFunction(name, self) { return op }
        if name.first?.isUppercase == true { return .type(.builtin(name)) }
        if let v = KBuiltins.globalConstant(name) { return v }
        throw fail("Cannot find '\(name)' in scope", line)
    }

    /// `$name` inside a view: a Binding to @State storage, the stored Binding, or
    /// a binding to the property itself.
    func projection(_ ctx: KSelfContext, _ name: String) throws -> KV? {
        let t = ctx.type
        guard t.storedDecl(name) != nil || t.computed[name] != nil else { return nil }
        if let storage = ctx.storage, let box = storage.box(name) {
            if case .binding = box.value, t.wrapper(of: name) == "Binding" { return box.value }
            return .binding(KBinding(get: { box.value }, set: { box.value = $0 }))
        }
        let selfValue = try read(ctx.location)
        if case .structV(let s) = selfValue, case .binding(let b)? = s.fields[name] { return .binding(b) }
        if case .object(let o) = selfValue, case .binding(let b)? = o.fields[name] { return .binding(b) }
        let loc = try memberLocation(ctx.location, name)
        return .binding(KBinding(get: { [unowned self] in (try? self.read(loc)) ?? .nilValue },
                                 set: { [unowned self] v in try? self.write(loc, v) }))
    }

    func unwrapField(_ t: KType, _ name: String, _ v: KV) -> KV {
        if case .binding(let b) = v, t.wrapper(of: name) == "Binding" { return b.get() }
        return v
    }

    // MARK: - Members

    func staticMember(_ t: KType, _ name: String, _ line: Int) throws -> KV {
        if name == "allCases", t.isEnum, t.staticDecls["allCases"] == nil {
            return .array(t.cases.filter { $0.associated.isEmpty }.map { .enumV(KEnumValue(type: t, caseName: $0.name, payload: [])) })
        }
        if name == "self" { return .type(.user(t)) }
        if let c = t.enumCase(name), c.associated.isEmpty { return .enumV(KEnumValue(type: t, caseName: c.name, payload: [])) }
        if t.staticDecls[name] != nil { return try staticValue(t, name) }
        if let m = t.staticMethods[name]?.first {
            return .function(KFunction(.user(m, globalEnv, KSelfContext(type: t, location: .box(KBox(.type(.user(t)))), isStatic: true))))
        }
        if let c = t.enumCase(name) {
            // An enum case with a payload used as a function: `.map(Shape.circle)`.
            return .function(KFunction(.native(c.name) { [unowned self] args, labels in
                _ = self
                return .enumV(KEnumValue(type: t, caseName: c.name, payload: args, payloadLabels: labels))
            }))
        }
        if let n = t.nested[name] { return .type(.user(n)) }
        throw fail("Type '\(t.name)' has no member '\(name)'", line)
    }

    func builtinStatic(_ typeName: String, _ name: String) throws -> KV {
        guard let ext = builtinExtensions[typeName] else { throw fail("\(typeName) has no member \(name)") }
        if let box = ext.staticBoxes[name] { return box.value }
        guard let decl = ext.staticDecls[name] else { throw fail("\(typeName) has no member \(name)") }
        if decl.isComputed { return try runAccessor(decl.getter ?? [], env: KEnv(parent: globalEnv), returns: decl.type) }
        let v = try decl.initial.map { try eval($0, globalEnv, decl.type ?? .named(typeName, [])) } ?? .nilValue
        ext.staticBoxes[name] = KBox(v)
        return v
    }

    /// `error.localizedDescription` for an Error you declared: its
    /// `errorDescription` (LocalizedError), else Swift's generic sentence.
    func errorDescription(_ base: KV, _ t: KType) throws -> KV {
        if let p = t.computed["errorDescription"] {
            let env = KEnv(parent: globalEnv, selfContext: KSelfContext(type: t, location: .box(KBox(base))))
            let v = try runAccessor(p.getter ?? [], env: env, returns: p.type)
            if !v.isNil { return v }
        }
        var code = 1
        if case .enumV(let e) = base, let i = t.cases.firstIndex(where: { $0.name == e.caseName }) { code = i }
        return .string("The operation couldn\u{2019}t be completed. (\(t.name) error \(code).)")
    }

    func member(_ base: KV, _ name: String, line: Int) throws -> KV {
        switch base {
        case .structV(let s):
            if let f = s.fields[name] { return unwrapField(s.type, name, f) }
            if let p = s.type.computed[name] {
                let env = KEnv(parent: globalEnv, selfContext: KSelfContext(type: s.type, location: .box(KBox(base))))
                return try runAccessor(p.getter ?? [], env: env, returns: p.type)
            }
            if let m = s.type.methods[name]?.first {
                return .function(KFunction(.user(m, globalEnv, KSelfContext(type: s.type, location: .box(KBox(base))))))
            }
            if name == "self" { return base }
            if s.type.storedDecl(name) != nil { return .nilValue }
            if s.type.isView, let ext = builtinExtensions["View"], let p = ext.computed[name] {
                let env = KEnv(parent: globalEnv, selfContext: KSelfContext(type: s.type, location: .box(KBox(base))))
                return try runAccessor(p.getter ?? [], env: env, returns: p.type)
            }
            if name == "localizedDescription" { return try errorDescription(base, s.type) }
            throw fail("Value of type '\(s.type.name)' has no member '\(name)'", line)
        case .enumV(let e):
            if name == "rawValue" { return try rawValue(e) }
            if name == "self" { return base }
            if let p = e.type.computed[name] {
                let env = KEnv(parent: globalEnv, selfContext: KSelfContext(type: e.type, location: .box(KBox(base))))
                return try runAccessor(p.getter ?? [], env: env, returns: p.type)
            }
            if let m = e.type.methods[name]?.first {
                return .function(KFunction(.user(m, globalEnv, KSelfContext(type: e.type, location: .box(KBox(base))))))
            }
            if name == "id" { return base }
            if let i = e.payloadLabels.firstIndex(of: name), i < e.payload.count { return e.payload[i] }
            if name == "hashValue" { return .int(base.hashValue) }
            if name == "localizedDescription" { return try errorDescription(base, e.type) }
            throw fail("Value of type '\(e.type.name)' has no member '\(name)'", line)
        case .object(let o):
            readTracker?.objects[ObjectIdentifier(o)] = o
            if let f = o.fields[name] { return unwrapField(o.type, name, f) }
            if let p = o.type.computed[name] {
                let env = KEnv(parent: globalEnv, selfContext: KSelfContext(type: o.type, location: .box(KBox(base))))
                return try runAccessor(p.getter ?? [], env: env, returns: p.type)
            }
            if let m = o.type.methods[name]?.first {
                return .function(KFunction(.user(m, globalEnv, KSelfContext(type: o.type, location: .box(KBox(base))))))
            }
            if o.type.storedDecl(name) != nil { return .nilValue }
            if name == "localizedDescription" { return try errorDescription(base, o.type) }
            throw fail("Value of type '\(o.type.name)' has no member '\(name)'", line)
        case .type(.user(let t)):
            return try staticMember(t, name, line)
        case .type(.builtin(let n)):
            if let ext = builtinExtensions[n], ext.staticDecls[name] != nil { return try builtinStatic(n, name) }
            return try KBuiltins.staticMember(n, name, self, line)
        case .binding(let b):
            if name == "wrappedValue" { return b.get() }
            if name == "projectedValue" { return base }
            return .binding(KBinding(get: { [unowned self] in (try? self.member(b.get(), name, line: line)) ?? .nilValue },
                                     set: { [unowned self] v in
                                         let box = KBox(b.get())
                                         try? self.write(.member(.box(box), name), v)
                                         b.set(box.value)
                                     }))
        case .tuple(let vals, let labels):
            if let i = Int(name), i < vals.count { return vals[i] }
            if let i = labels.firstIndex(of: name), i < vals.count { return vals[i] }
            if name == "key", vals.count == 2 { return vals[0] }
            if name == "value", vals.count == 2 { return vals[1] }
            if name == "offset", vals.count == 2 { return vals[0] }
            if name == "element", vals.count == 2 { return vals[1] }
            throw fail("Tuple has no member '\(name)'", line)
        case .nilValue:
            return .nilValue
        default:
            if let ext = builtinExtensions[KBuiltins.extensionKey(base)], let p = ext.computed[name] {
                let ctx = KSelfContext(type: KType(name: base.typeName, kind: .structType), location: .box(KBox(base)))
                return try runAccessor(p.getter ?? [], env: KEnv(parent: globalEnv, selfContext: ctx), returns: p.type)
            }
            return try KBuiltins.member(base, name, self, line)
        }
    }

    func rawValue(_ e: KEnumValue) throws -> KV {
        guard let c = e.type.enumCase(e.caseName) else { return .string(e.caseName) }
        if let raw = c.rawValue { return try eval(raw, globalEnv) }
        if ["Int", "UInt"].contains(e.type.rawType ?? "") {
            var next = 0
            for cc in e.type.cases {
                if let r = cc.rawValue, case .int(let v) = try eval(r, globalEnv) { next = v }
                if cc.name == e.caseName { return .int(next) }
                next += 1
            }
        }
        return .string(e.caseName)
    }

    // MARK: - Subscripts

    func subscriptGet(_ base: KV, _ idx: [KV], _ labels: [String?], _ line: Int) throws -> KV {
        guard let first = idx.first else { throw fail("Subscript needs an index", line) }
        switch base {
        case .array(let a):
            if case .range(let lo, let hi, let closed) = first {
                let l = lo.asInt ?? 0
                var h = hi.asInt ?? (a.count - 1)
                if !closed && !hi.isNil { h -= 1 }
                guard l >= 0, h < a.count, l <= h + 1 else { throw fail("Range out of bounds", line) }
                return .array(l > h ? [] : Array(a[l...h]))
            }
            guard let i = first.asInt else { throw fail("Array index must be a number", line) }
            guard i >= 0, i < a.count else { throw fail("Index out of range: \(i) (the array has \(a.count) item\(a.count == 1 ? "" : "s"))", line) }
            return a[i]
        case .dict(let d):
            return d[first] ?? .nilValue
        case .string(let s):
            if let i = first.asInt {
                guard i >= 0, i < s.count else { throw fail("String index out of range", line) }
                return .string(String(s[s.index(s.startIndex, offsetBy: i)]))
            }
            if case .range(let lo, let hi, let closed) = first {
                let chars = Array(s)
                let l = lo.asInt ?? 0
                var h = hi.asInt ?? (chars.count - 1)
                if !closed && !hi.isNil { h -= 1 }
                guard l >= 0, h < chars.count, l <= h + 1 else { throw fail("Range out of bounds", line) }
                return .string(l > h ? "" : String(chars[l...h]))
            }
            throw fail("Can't subscript a String with \(describe(first))", line)
        case .structV(let s):
            if let sub = s.type.subscripts.first {
                return try invoke(sub, args: idx, labels: labels, selfContext: KSelfContext(type: s.type, location: .box(KBox(base))), parent: globalEnv)
            }
        case .object(let o):
            if let sub = o.type.subscripts.first {
                return try invoke(sub, args: idx, labels: labels, selfContext: KSelfContext(type: o.type, location: .box(KBox(base))), parent: globalEnv)
            }
        case .binding(let b):
            return .binding(KBinding(get: { [unowned self] in (try? self.subscriptGet(b.get(), idx, labels, line)) ?? .nilValue },
                                     set: { [unowned self] v in
                                         let box = KBox(b.get())
                                         try? self.write(.index(.box(box), first), v)
                                         b.set(box.value)
                                     }))
        case .tuple(let vals, _):
            if let i = first.asInt, i < vals.count { return vals[i] }
        case .nilValue:
            return .nilValue
        default:
            break
        }
        throw fail("Can't subscript \(describe(base))", line)
    }

    // MARK: - Operators

    func binary(_ op: String, _ l: KEExpr, _ r: KEExpr, _ env: KEnv, _ line: Int, _ expected: KETypeRef?) throws -> KV {
        switch op {
        case "&&":
            if !truthy(try eval(l, env)) { return .bool(false) }
            return .bool(truthy(try eval(r, env)))
        case "||":
            if truthy(try eval(l, env)) { return .bool(true) }
            return .bool(truthy(try eval(r, env)))
        case "??":
            let a = try eval(l, env, expected)
            return a.isNil ? try eval(r, env, expected ?? typeRef(of: a)) : a
        default: break
        }
        let numericContext = ["+", "-", "*", "/", "%"].contains(op) ? expected : nil
        var a = try eval(l, env, numericContext)
        let b = try eval(r, env, typeRef(of: a) ?? numericContext)
        if case .native(.implicit) = a, let t = typeRef(of: b) { a = coerce(a, to: t) }
        switch op {
        case "==": return .bool(equal(a, coerce(b, to: typeRef(of: a))))
        case "!=": return .bool(!equal(a, coerce(b, to: typeRef(of: a))))
        case "===": return .bool(equal(a, b))
        case "!==": return .bool(!equal(a, b))
        case "<", ">", "<=", ">=": return .bool(try compare(op, a, b, line))
        case "..<": return .range(a, b, closed: false)
        case "...": return .range(a, b, closed: true)
        case "~=": return .bool(rangeContains(a, b) || equal(a, b))
        default: return try arithmetic(op, a, b, line)
        }
    }

    func equal(_ a: KV, _ b: KV) -> Bool { a == b }

    func compare(_ op: String, _ a: KV, _ b: KV, _ line: Int) throws -> Bool {
        let c: Int
        switch (a, b) {
        case (.int(let x), .int(let y)): c = x < y ? -1 : (x > y ? 1 : 0)
        case (.string(let x), .string(let y)): c = x < y ? -1 : (x > y ? 1 : 0)
        case (.native(.date(let x)), .native(.date(let y))): c = x < y ? -1 : (x > y ? 1 : 0)
        case (.enumV(let x), .enumV(let y)) where x.type === y.type:
            if x.type.methods["<"] != nil || x.type.staticMethods["<"] != nil, let f = x.type.staticMethods["<"]?.first {
                let lt = truthy(try invoke(f, args: [a, b], labels: [nil, nil], selfContext: nil, parent: globalEnv))
                let gt = truthy(try invoke(f, args: [b, a], labels: [nil, nil], selfContext: nil, parent: globalEnv))
                c = lt ? -1 : (gt ? 1 : 0)
            } else {
                let ra = try rawValue(x), rb = try rawValue(y)
                if case .int = ra { return try compare(op, ra, rb, line) }
                let ia = x.type.cases.firstIndex { $0.name == x.caseName } ?? 0
                let ib = y.type.cases.firstIndex { $0.name == y.caseName } ?? 0
                c = ia < ib ? -1 : (ia > ib ? 1 : 0)
            }
        case (.tuple(let x, _), .tuple(let y, _)):
            for (p, q) in zip(x, y) where !equal(p, q) { return try compare(op, p, q, line) }
            c = 0
        case (.structV(let s), _) where s.type.staticMethods["<"] != nil:
            let f = s.type.staticMethods["<"]!.first!
            let lt = truthy(try invoke(f, args: [a, b], labels: [nil, nil], selfContext: nil, parent: globalEnv))
            let gt = truthy(try invoke(f, args: [b, a], labels: [nil, nil], selfContext: nil, parent: globalEnv))
            c = lt ? -1 : (gt ? 1 : 0)
        default:
            guard let x = a.asDouble, let y = b.asDouble else { throw fail("Can't compare \(describe(a)) and \(describe(b))", line) }
            c = x < y ? -1 : (x > y ? 1 : 0)
        }
        switch op {
        case "<": return c < 0
        case ">": return c > 0
        case "<=": return c <= 0
        default: return c >= 0
        }
    }

    func arithmetic(_ op: String, _ a: KV, _ b: KV, _ line: Int) throws -> KV {
        switch (a, b) {
        case (.int(let x), .int(let y)):
            switch op {
            case "+": return .int(x &+ y)
            case "-": return .int(x &- y)
            case "*": return .int(x &* y)
            case "/":
                guard y != 0 else { throw fail("Division by zero", line) }
                return .int(x / y)
            case "%":
                guard y != 0 else { throw fail("Division by zero", line) }
                return .int(x % y)
            case "&": return .int(x & y)
            case "|": return .int(x | y)
            case "^": return .int(x ^ y)
            case "<<": return .int(x << y)
            case ">>": return .int(x >> y)
            default: break
            }
        case (.string(let x), .string(let y)) where op == "+": return .string(x + y)
        case (.array(let x), .array(let y)) where op == "+": return .array(x + y)
        case (.array(let x), _) where op == "+": return .array(x + [b])
        case (.view(let x), .view(let y)) where op == "+": return .view(.textConcat(x, y))
        case (.native(.date(let d)), _) where op == "+" || op == "-":
            if let s = b.asDouble { return .native(.date(op == "+" ? d.addingTimeInterval(s) : d.addingTimeInterval(-s))) }
            if case .native(.date(let e)) = b, op == "-" { return .double(d.timeIntervalSince(e)) }
        default:
            if let x = a.asDouble, let y = b.asDouble {
                switch op {
                case "+": return .double(x + y)
                case "-": return .double(x - y)
                case "*": return .double(x * y)
                case "/": return .double(x / y)
                case "%": return .double(fmod(x, y))
                default: break
                }
            }
        }
        if case .structV(let s) = a, let f = s.type.staticMethods[op]?.first {
            return try invoke(f, args: [a, b], labels: [nil, nil], selfContext: nil, parent: globalEnv)
        }
        throw fail("Binary operator '\(op)' can't be applied to \(a.typeName) and \(b.typeName)", line)
    }

    // MARK: - Implicit members

    /// `.name` or `.name(args)`: a case or static member of the expected user
    /// type (or the one user type that has it); otherwise a symbolic value
    /// (`.segmented`, `.title`, `.degrees(90)`) for the consumer to interpret.
    func implicitMember(_ name: String, _ args: [KV]?, _ labels: [String?], _ expected: KETypeRef?) throws -> KV {
        if let ut = userType(expected), let v = try implicitOn(ut, name, args, labels: labels) { return v }
        if expected == nil || userType(expected) == nil {
            let builtinName = expected?.core.name
            if builtinName == nil || builtinName == "Self" {
                let owners = Set(types.values.filter { t in
                    t.enumCase(name) != nil || t.staticDecls[name] != nil || t.staticMethods[name] != nil
                }.map { ObjectIdentifier($0) })
                if owners.count == 1, let t = types.values.first(where: { owners.contains(ObjectIdentifier($0)) }),
                   KBuiltins.implicit(name, args ?? [], expectedType: nil) == nil || t.enumCase(name) != nil,
                   let v = try implicitOn(t, name, args, labels: labels) {
                    return v
                }
            }
            if let ext = builtinName.flatMap({ builtinExtensions[$0] }), ext.staticDecls[name] != nil {
                return try builtinStatic(builtinName!, name)
            }
            if let ext = builtinName.flatMap({ builtinExtensions[$0] }), let m = ext.staticMethods[name]?.first {
                return try invoke(m, args: args ?? [], labels: labels, selfContext: nil, parent: globalEnv)
            }
            if builtinName == nil, let (tn, ext) = builtinExtensions.first(where: { $0.value.staticDecls[name] != nil }) {
                _ = ext
                return try builtinStatic(tn, name)
            }
            if let v = KBuiltins.implicit(name, args ?? [], expectedType: builtinName, labels: labels) { return v }
        }
        return .native(.implicit(name, args ?? []))
    }

    // MARK: - Calls

    func evalArgs(_ args: [KEArg], _ env: KEnv, types paramTypes: [String?: KETypeRef] = [:], positional: [KETypeRef?] = []) throws -> [KV] {
        var out: [KV] = []
        for (i, a) in args.enumerated() {
            let t = paramTypes[a.label] ?? (i < positional.count ? positional[i] : nil)
            out.append(try eval(a.value, env, t))
        }
        return out
    }

    /// Argument values, typed by the parameters they bind to.
    func evalArgs(_ args: [KEArg], _ env: KEnv, params: [KEParam]) throws -> [KV] {
        var out: [KV] = []
        var pi = 0
        for a in args {
            var t: KETypeRef? = nil
            if let j = params.indices.first(where: { $0 >= pi && params[$0].label == a.label }) { t = params[j].type; pi = j + 1 }
            else if pi < params.count { t = params[pi].type; pi += 1 }
            out.append(try eval(a.value, env, t))
        }
        return out
    }

    func evalCall(_ callee: KEExpr, _ argExprs: [KEArg], _ env: KEnv, _ line: Int, _ expected: KETypeRef?) throws -> KV {
        let labels = argExprs.map(\.label)
        do {
            return try evalCallInner(callee, argExprs, labels, env, line, expected)
        } catch var err as KERuntimeError where err.line == 0 {
            err.line = line
            throw err
        }
    }

    private func evalCallInner(_ callee: KEExpr, _ argExprs: [KEArg], _ labels: [String?], _ env: KEnv, _ line: Int, _ expected: KETypeRef?) throws -> KV {
        switch callee {
        case .ident(let name, _):
            if let box = env.lookup(name) {
                return try callValue(box.value, argExprs, env, line)
            }
            if let ctx = env.nearestSelf {
                if !ctx.isStatic, let m = ctx.type.method(name, labels: labels) {
                    let args = try evalArgs(argExprs, env, params: m.params)
                    return try invoke(m, args: args, labels: labels, selfContext: ctx, parent: globalEnv)
                }
                if let m = ctx.type.staticMethod(name, labels: labels) {
                    let args = try evalArgs(argExprs, env, params: m.params)
                    let sctx = KSelfContext(type: ctx.type, location: .box(KBox(.type(.user(ctx.type)))), isStatic: true)
                    return try invoke(m, args: args, labels: labels, selfContext: sctx, parent: globalEnv)
                }
                if let loc = try selfMemberLocation(ctx, name) {
                    return try callValue(try read(loc), argExprs, env, line)
                }
            }
            if let fs = functions[name], let f = Self.pick(fs, labels: labels) {
                let args = try evalArgs(argExprs, env, params: f.params)
                return try invoke(f, args: args, labels: labels, selfContext: nil, parent: globalEnv)
            }
            if let box = globalEnv.vars[name] { return try callValue(box.value, argExprs, env, line) }
            if let t = types[name] { return try construct(t, argExprs, env, line) }
            if let ext = builtinExtensions[name], !ext.inits.isEmpty, let i = Self.pick(ext.inits, labels: labels),
               !KBuiltins.prefersBuiltinInit(name, labels) {
                let args = try evalArgs(argExprs, env, params: i.params)
                return try runBuiltinExtensionInit(name, i, args, labels)
            }
            return try KBuiltins.callGlobal(name, argExprs, env, self, line, expected)

        case .member(let baseExpr, let name, _):
            if let t = typeExpr(baseExpr, env) {
                if let nested = t.nested[name] { return try construct(nested, argExprs, env, line) }
                if let c = t.enumCase(name) {
                    let types = c.associated.map(\.1)
                    let args = try evalArgs(argExprs, env, positional: types)
                    return .enumV(KEnumValue(type: t, caseName: c.name, payload: zip(args, types + Array(repeating: KETypeRef.named("Any", []), count: max(0, args.count - types.count))).map { coerce($0.0, to: $0.1) }, payloadLabels: labels))
                }
                if let m = t.staticMethod(name, labels: labels) {
                    let args = try evalArgs(argExprs, env, params: m.params)
                    let sctx = KSelfContext(type: t, location: .box(KBox(.type(.user(t)))), isStatic: true)
                    return try invoke(m, args: args, labels: labels, selfContext: sctx, parent: globalEnv)
                }
                if name == "init" { return try construct(t, argExprs, env, line) }
                if t.staticDecls[name] != nil { return try callValue(try staticValue(t, name), argExprs, env, line) }
                throw fail("Type '\(t.name)' has no member '\(name)'", line)
            }
            if case .ident(let bn, _) = baseExpr, isBuiltinTypeName(bn, env) {
                if let ext = builtinExtensions[bn], let m = Self.pick(ext.staticMethods[name] ?? [], labels: labels) {
                    let args = try evalArgs(argExprs, env, params: m.params)
                    return try invoke(m, args: args, labels: labels, selfContext: nil, parent: globalEnv)
                }
                return try KBuiltins.callStatic(bn, name, argExprs, env, self, line, expected)
            }
            return try callMethod(baseExpr, name, argExprs, env, line, expected)

        case .implicitMember(let name, _):
            if let ut = userType(expected) {
                if let c = ut.enumCase(name) {
                    let args = try evalArgs(argExprs, env, positional: c.associated.map(\.1))
                    return .enumV(KEnumValue(type: ut, caseName: c.name, payload: args, payloadLabels: labels))
                }
                if let m = ut.staticMethod(name, labels: labels) {
                    let args = try evalArgs(argExprs, env, params: m.params)
                    return try invoke(m, args: args, labels: labels, selfContext: KSelfContext(type: ut, location: .box(KBox(.type(.user(ut)))), isStatic: true), parent: globalEnv)
                }
                if name == "init" { return try construct(ut, argExprs, env, line) }
            }
            let args = try evalArgs(argExprs, env)
            return try implicitMember(name, args, labels, expected)

        case .typeExpr(let t):
            if let ut = userType(t) { return try construct(ut, argExprs, env, line) }
            return try KBuiltins.constructType(t, try evalArgs(argExprs, env), labels, self, line)

        case .array(let elems) where elems.count == 1:
            if case .ident(let n, _) = elems[0], n.first?.isUppercase == true, env.lookup(n) == nil {
                return try KBuiltins.constructType(.array(.named(n, [])), try evalArgs(argExprs, env), labels, self, line)
            }
            if case .array = elems[0] { return try KBuiltins.constructType(.array(.named("Array", [])), try evalArgs(argExprs, env), labels, self, line) }
            return try callValue(try eval(callee, env), argExprs, env, line)

        case .dictionary(let pairs) where pairs.count == 1:
            if case .ident(let n, _) = pairs[0].0, n.first?.isUppercase == true, env.lookup(n) == nil { return .dict([:]) }
            return try callValue(try eval(callee, env), argExprs, env, line)

        case .optionalChain(let inner):
            let f = try eval(inner, env)
            if f.isNil { return .nilValue }
            return try callValue(f, argExprs, env, line)

        default:
            return try callValue(try eval(callee, env), argExprs, env, line)
        }
    }

    func runBuiltinExtensionInit(_ typeName: String, _ decl: KEFuncDecl, _ args: [KV], _ labels: [String?]) throws -> KV {
        // `extension Color { init(hex: String) { … self.init(red:green:blue:) } }`
        let box = KBox(.nilValue)
        let ctx = KSelfContext(type: KType(name: typeName, kind: .structType), location: .box(box))
        _ = try invoke(decl, args: args, labels: labels, selfContext: ctx, parent: globalEnv)
        return box.value
    }

    /// Call a value: a closure, a bound method, a type (an initializer).
    func callValue(_ f: KV, _ argExprs: [KEArg], _ env: KEnv, _ line: Int) throws -> KV {
        let labels = argExprs.map(\.label)
        switch f {
        case .function(let fn):
            var params: [KEParam] = []
            if case .user(let d, _, _) = fn.kind { params = d.params }
            let args = params.isEmpty ? try evalArgs(argExprs, env) : try evalArgs(argExprs, env, params: params)
            return try call(fn, args, labels)
        case .type(.user(let t)):
            return try construct(t, argExprs, env, line)
        case .type(.builtin(let n)):
            return try KBuiltins.callGlobal(n, argExprs, env, self, line, nil)
        case .native(let n):
            return try KBuiltins.callNative(n, try evalArgs(argExprs, env), labels, self, line)
        case .binding(let b):
            return try callValue(b.get(), argExprs, env, line)
        case .nilValue:
            return .nilValue
        default:
            throw fail("\(describe(f)) is not a function", line)
        }
    }

    /// A method call. The receiver is kept as a storage location so mutating
    /// methods (`append`, `toggle`, a `mutating func`) write back.
    func callMethod(_ baseExpr: KEExpr, _ name: String, _ argExprs: [KEArg], _ env: KEnv, _ line: Int, _ expected: KETypeRef?) throws -> KV {
        let labels = argExprs.map(\.label)
        if case .selfRef = baseExpr, let ctx = env.nearestSelf, !ctx.isStatic, let m = ctx.type.method(name, labels: labels) {
            let args = try evalArgs(argExprs, env, params: m.params)
            return try invoke(m, args: args, labels: labels, selfContext: ctx, parent: globalEnv)
        }
        var isChain = false
        if case .optionalChain = baseExpr { isChain = true }
        let loc: KLocation? = isStorage(baseExpr, env) ? try lvalue(baseExpr, env) : nil
        let base = try loc.map { try read($0) } ?? (try eval(baseExpr, env))
        if base.isNil && (isChain || name != "map") { return .nilValue }

        switch base {
        case .structV(let s):
            if let m = s.type.method(name, labels: labels) {
                let args = try evalArgs(argExprs, env, params: m.params)
                let selfLoc = loc ?? .box(KBox(base))
                return try invoke(m, args: args, labels: labels, selfContext: KSelfContext(type: s.type, location: selfLoc), parent: globalEnv)
            }
            if case .function? = s.fields[name] { return try callValue(s.fields[name]!, argExprs, env, line) }
            if s.type.computed[name] != nil || s.fields[name] != nil {
                return try callValue(try member(base, name, line: line), argExprs, env, line)
            }
            if s.type.isView { return try viewMethod(.custom(s), name, argExprs, env, line) }
            if s.type.isShape, let v = KBuiltins.asViews(base, self).first { return try viewMethod(v, name, argExprs, env, line) }
        case .enumV(let e):
            if let m = e.type.method(name, labels: labels) {
                let args = try evalArgs(argExprs, env, params: m.params)
                return try invoke(m, args: args, labels: labels, selfContext: KSelfContext(type: e.type, location: loc ?? .box(KBox(base))), parent: globalEnv)
            }
            if e.type.computed[name] != nil { return try callValue(try member(base, name, line: line), argExprs, env, line) }
        case .object(let o):
            readTracker?.objects[ObjectIdentifier(o)] = o
            if let m = o.type.method(name, labels: labels) {
                let args = try evalArgs(argExprs, env, params: m.params)
                return try invoke(m, args: args, labels: labels, selfContext: KSelfContext(type: o.type, location: .box(KBox(base))), parent: globalEnv)
            }
            if let f = o.fields[name] { return try callValue(f, argExprs, env, line) }
            if o.type.computed[name] != nil { return try callValue(try member(base, name, line: line), argExprs, env, line) }
        case .view(let v):
            return try viewMethod(v, name, argExprs, env, line)
        case .function(let fn) where name == "callAsFunction":
            return try call(fn, try evalArgs(argExprs, env), labels)
        case .type(.user(let t)):
            return try evalCallInner(.member(.typeExpr(.named(t.name, [])), name, line: line), argExprs, labels, env, line, expected)
        default:
            break
        }

        // Methods from `extension` on built-in types (Array, String, Double, View, …).
        let key = KBuiltins.extensionKey(base)
        if let ext = builtinExtensions[key], let m = Self.pick(ext.methods[name] ?? [], labels: labels) {
            let args = try evalArgs(argExprs, env, params: m.params)
            let ctx = KSelfContext(type: KType(name: key, kind: .structType), location: loc ?? .box(KBox(base)))
            return try invoke(m, args: args, labels: labels, selfContext: ctx, parent: globalEnv)
        }
        if KBuiltins.isViewLike(base), KBuiltins.modifierNames.contains(name) || !KBuiltins.hasValueMethod(base, name) {
            if let v = KBuiltins.asViews(base, self).first { return try viewMethod(v, name, argExprs, env, line) }
        }
        let args = try argExprs.map { a -> KV in
            // Closure-typed arguments of standard methods see `$0` as the element.
            try eval(a.value, env, nil)
        }
        let (result, mutated) = try KBuiltins.callMethod(base, name, args, labels, self, line)
        if let mutated {
            guard let loc else { throw fail("Cannot use mutating member '\(name)' on an immutable value", line) }
            try write(loc, mutated)
        }
        return result
    }

    func isStorage(_ e: KEExpr, _ env: KEnv) -> Bool {
        switch e {
        case .ident(let n, _):
            if env.lookup(n) != nil || globalEnv.vars[n] != nil { return true }
            if let ctx = env.nearestSelf, ctx.type.storedDecl(n) != nil || ctx.type.computed[n] != nil || ctx.storage?.box(n) != nil { return true }
            if let ctx = env.nearestSelf, ctx.isStatic, ctx.type.staticDecls[n] != nil { return true }
            return false
        case .member(let b, _, _):
            if typeExpr(b, env) != nil { return true }   // Type.staticVar
            return isStorage(b, env)
        case .subscriptAccess(let b, _, _): return isStorage(b, env)
        case .selfRef: return true
        case .optionalChain(let b), .postfix("!", let b): return isStorage(b, env)
        default: return false
        }
    }

    /// A modifier or a `View` extension method applied to a view.
    func viewMethod(_ v: KView, _ name: String, _ argExprs: [KEArg], _ env: KEnv, _ line: Int) throws -> KV {
        let labels = argExprs.map(\.label)
        if let ext = builtinExtensions["View"], let m = Self.pick(ext.methods[name] ?? [], labels: labels) {
            let args = try evalArgs(argExprs, env, params: m.params)
            let ctx = KSelfContext(type: KType(name: "View", kind: .structType), location: .box(KBox(.view(v))))
            return try invoke(m, args: args, labels: labels, selfContext: ctx, parent: globalEnv)
        }
        if case .custom(let s) = v.kind, let m = s.type.method(name, labels: labels) {
            let args = try evalArgs(argExprs, env, params: m.params)
            return try invoke(m, args: args, labels: labels, selfContext: KSelfContext(type: s.type, location: .box(KBox(.structV(s)))), parent: globalEnv)
        }
        let args = try argExprs.enumerated().map { i, a -> KV in
            if i == 0, a.label == nil, KBuiltins.localizedTitleModifiers.contains(name), case .string(let segs) = a.value {
                return .string(try stringLiteral(segs, env, localized: true))
            }
            return try eval(a.value, env, KBuiltins.modifierArgType(name, a.label))
        }
        return .view(.modified(v, KModifier(name: name, args: args, labels: labels, line: line)))
    }

    // MARK: - Initializers

    func construct(_ t: KType, _ argExprs: [KEArg], _ env: KEnv, _ line: Int) throws -> KV {
        let labels = argExprs.map(\.label)
        if let i = pickInit(t, labels) {
            let args = try evalArgs(argExprs, env, params: i.params)
            return try instantiate(t, args: args, labels: labels, line: line)
        }
        var types: [String?: KETypeRef] = [:]
        for p in memberwiseParams(t) { types[p.name] = p.type }
        if t.isEnum, labels.first == "rawValue", let rt = t.rawType { types["rawValue"] = .named(rt, []) }
        let args = try evalArgs(argExprs, env, types: types, positional: memberwiseParams(t).map(\.type))
        return try instantiate(t, args: args, labels: labels, line: line)
    }

    func pickInit(_ t: KType, _ labels: [String?]) -> KEFuncDecl? {
        guard !t.inits.isEmpty else { return nil }
        let matching = t.inits.filter { d in
            let required = d.params.filter { $0.defaultValue == nil }.count
            return labels.count >= required && labels.count <= d.params.count
        }
        return Self.pick(matching.isEmpty ? [] : matching, labels: labels)
            ?? (t.isClass || t.kind == .enumType ? nil : nil)
    }

    func memberwiseParams(_ t: KType) -> [KEVarDecl] {
        t.stored.filter { p in
            if p.isLet && p.initial != nil { return false }
            if let w = p.wrapper, ["Environment", "EnvironmentObject", "FocusState", "Namespace", "GestureState", "AppStorage", "SceneStorage"].contains(w) { return false }
            return true
        }
    }

    func defaultFields(_ t: KType) throws -> [String: KV] {
        var fields: [String: KV] = [:]
        let env = KEnv(parent: globalEnv, selfContext: KSelfContext(type: t, location: .box(KBox(.type(.user(t)))), isStatic: true))
        for p in t.stored {
            if let initial = p.initial {
                let v = coerce(try eval(initial, env, p.type), to: p.type)
                fields[p.name] = v
                env.declare(p.name, v)
            } else if p.wrapper == "Environment" {
                fields[p.name] = KBuiltins.environmentDefault(p, self)
            } else if p.type?.isOptional == true {
                fields[p.name] = .nilValue
            }
        }
        return fields
    }

    func instantiate(_ t: KType, args: [KV], labels: [String?], line: Int) throws -> KV {
        try tick()
        if t.isEnum {
            if labels.first == "rawValue", let raw = args.first {
                for c in t.cases {
                    let v = try rawValue(KEnumValue(type: t, caseName: c.name, payload: []))
                    if v == raw { return .enumV(KEnumValue(type: t, caseName: c.name, payload: [])) }
                }
                return .nilValue
            }
            if let i = pickInit(t, labels) {
                let box = KBox(.nilValue)
                let r = try invoke(i, args: args, labels: labels, selfContext: KSelfContext(type: t, location: .box(box)), parent: globalEnv)
                if box.value.isNil, r.isNil { return .nilValue }
                return box.value
            }
            throw fail("'\(t.name)' cannot be constructed with these arguments", line)
        }
        let fields = try defaultFields(t)
        if let i = pickInit(t, labels) {
            if t.isClass {
                let obj = KObject(type: t, fields: fields)
                let r = try invoke(i, args: args, labels: labels, selfContext: KSelfContext(type: t, location: .box(KBox(.object(obj)))), parent: globalEnv)
                if i.attributes.contains(where: { $0.name == "Failable" }), r.isNil, returnedNil { returnedNil = false; return .nilValue }
                return .object(obj)
            }
            let box = KBox(.structV(KStructValue(type: t, fields: fields)))
            let r = try invoke(i, args: args, labels: labels, selfContext: KSelfContext(type: t, location: .box(box)), parent: globalEnv)
            if i.attributes.contains(where: { $0.name == "Failable" }), r.isNil, returnedNil { returnedNil = false; return .nilValue }
            return box.value
        }
        // Memberwise.
        var values = fields
        let params = memberwiseParams(t)
        var used = Array(repeating: false, count: args.count)
        var nextPositional = 0
        for p in params {
            var found: Int? = labels.firstIndex(where: { $0 == p.name })
            if let f = found, used[f] { found = nil }
            if found == nil, nextPositional < args.count, labels[nextPositional] == nil, !used[nextPositional] { found = nextPositional }
            if let i = found {
                used[i] = true
                nextPositional = i + 1
                values[p.name] = coerce(args[i], to: p.type)
            } else if values[p.name] == nil {
                if p.wrapper == "Binding" || p.type.map({ if case .function = $0.core { return true }; return false }) == true {
                    values[p.name] = .nilValue
                }
                if p.type?.isOptional != true, p.wrapper == nil, !(p.type.map({ if case .function = $0.core { return true }; return false }) ?? false) {
                    throw fail("Missing argument '\(p.name)' in call to \(t.name)", line)
                }
            }
        }
        if let extra = labels.indices.first(where: { !used[$0] }) {
            warn("Ignored argument '\(labels[extra] ?? "_")' in \(t.name)(…)")
        }
        if t.isClass { return .object(KObject(type: t, fields: values)) }
        return .structV(KStructValue(type: t, fields: values))
    }
}
