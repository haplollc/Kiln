//
//  KEValue.swift
//  Kiln engine 2
//
//  Runtime values. Structs, arrays, dictionaries and enums are Swift value
//  types here too, so copying a `KV` copies the data the way Swift does.
//  Classes are reference objects that tell the views reading them when they
//  change. Int and Double stay distinct so `remaining / 60` divides like Swift.
//

import SwiftUI
import Combine

struct KERuntimeError: Error, CustomStringConvertible {
    let message: String
    var line: Int = 0
    var description: String { line > 0 ? "Line \(line): \(message)" : message }
}

/// A thrown Swift error (`throw MyError.bad`), carried as a value.
struct KEThrown: Error { let value: KV }

indirect enum KV {
    case void
    case nilValue
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([KV])
    case dict([KV: KV])
    case set(Set<KV>)
    case tuple([KV], [String?])
    case range(KV, KV, closed: Bool)          // a bound is .nilValue when one-sided
    case structV(KStructValue)
    case enumV(KEnumValue)
    case object(KObject)
    case function(KFunction)
    case type(KTypeValue)
    case view(KView)
    case binding(KBinding)
    case native(KNative)

    var isNil: Bool { if case .nilValue = self { return true }; return false }

    var asBool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var asInt: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d) where d.isFinite: return Int(d)
        default: return nil
        }
    }
    var asDouble: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }
    var asString: String? { if case .string(let s) = self { return s }; return nil }
    var asArray: [KV]? {
        switch self {
        case .array(let a): return a
        case .set(let s): return Array(s)
        default: return nil
        }
    }

    /// The user type of a struct, enum or object value.
    var userType: KType? {
        switch self {
        case .structV(let s): return s.type
        case .enumV(let e): return e.type
        case .object(let o): return o.type
        default: return nil
        }
    }

    var typeName: String {
        switch self {
        case .void: return "Void"
        case .nilValue: return "nil"
        case .bool: return "Bool"
        case .int: return "Int"
        case .double: return "Double"
        case .string: return "String"
        case .array: return "Array"
        case .dict: return "Dictionary"
        case .set: return "Set"
        case .tuple: return "Tuple"
        case .range: return "Range"
        case .structV(let s): return s.type.name
        case .enumV(let e): return e.type.name
        case .object(let o): return o.type.name
        case .function: return "Function"
        case .type(let t): return t.name + ".Type"
        case .view: return "View"
        case .binding: return "Binding"
        case .native(let n): return n.kindName
        }
    }
}

// MARK: - Equality & hashing (Swift's synthesized Equatable/Hashable)

extension KV: Hashable {
    static func == (a: KV, b: KV) -> Bool {
        switch (a, b) {
        case (.void, .void), (.nilValue, .nilValue): return true
        case (.bool(let x), .bool(let y)): return x == y
        case (.int(let x), .int(let y)): return x == y
        case (.double(let x), .double(let y)): return x == y
        case (.int(let x), .double(let y)): return Double(x) == y
        case (.double(let x), .int(let y)): return x == Double(y)
        case (.string(let x), .string(let y)): return x == y
        case (.array(let x), .array(let y)): return x == y
        case (.dict(let x), .dict(let y)): return x == y
        case (.set(let x), .set(let y)): return x == y
        case (.tuple(let x, _), .tuple(let y, _)): return x == y
        case (.range(let a1, let b1, let c1), .range(let a2, let b2, let c2)): return a1 == a2 && b1 == b2 && c1 == c2
        case (.structV(let x), .structV(let y)): return x.type === y.type && x.fields == y.fields
        case (.enumV(let x), .enumV(let y)): return x.type === y.type && x.caseName == y.caseName && x.payload == y.payload
        case (.enumV(let x), .native(.implicit(let name, _))): return x.caseName == name
        case (.native(.implicit(let name, _)), .enumV(let y)): return y.caseName == name
        case (.object(let x), .object(let y)): return x === y
        case (.function(let x), .function(let y)): return x === y
        case (.type(let x), .type(let y)): return x.name == y.name
        case (.binding(let x), .binding(let y)): return x === y
        case (.view(let x), .view(let y)): return x === y
        case (.native(let x), .native(let y)): return x == y
        default: return false
        }
    }

    func hash(into h: inout Hasher) {
        switch self {
        case .void: h.combine(0)
        case .nilValue: h.combine(1)
        case .bool(let b): h.combine(b)
        case .int(let i): h.combine(Double(i))
        case .double(let d): h.combine(d)
        case .string(let s): h.combine(s)
        case .array(let a): h.combine(a)
        case .dict(let d): h.combine(d.count)
        case .set(let s): h.combine(s)
        case .tuple(let t, _): h.combine(t)
        case .range(let a, let b, let c): h.combine(a); h.combine(b); h.combine(c)
        case .structV(let s):
            h.combine(s.type.name)
            for k in s.fields.keys.sorted() { h.combine(k); h.combine(s.fields[k]!) }
        case .enumV(let e): h.combine(e.caseName); h.combine(e.payload)
        case .object(let o): h.combine(ObjectIdentifier(o))
        case .function(let f): h.combine(ObjectIdentifier(f))
        case .type(let t): h.combine(t.name)
        case .binding(let b): h.combine(ObjectIdentifier(b))
        case .view(let v): h.combine(ObjectIdentifier(v))
        case .native(let n): h.combine(n)
        }
    }
}

// MARK: - Value types

struct KStructValue {
    let type: KType
    var fields: [String: KV]
}

struct KEnumValue {
    let type: KType
    let caseName: String
    var payload: [KV]
    var payloadLabels: [String?] = []
}

/// A class instance. Writes notify every view that read it (ObservableObject,
/// @Observable and plain classes alike: views re-render when they change).
final class KObject {
    let type: KType
    var fields: [String: KV]
    let changed = PassthroughSubject<Void, Never>()

    init(type: KType, fields: [String: KV]) {
        self.type = type
        self.fields = fields
    }

    func didChange() {
        if Thread.isMainThread { changed.send() }
        else { DispatchQueue.main.async { self.changed.send() } }
    }
}

enum KTypeValue {
    case user(KType)
    case builtin(String)

    var name: String {
        switch self {
        case .user(let t): return t.name
        case .builtin(let n): return n
        }
    }
}

/// A variable's storage. Closures capture boxes, so a captured variable is
/// shared the way Swift captures by reference. A box can instead forward to a
/// getter/setter (a @Binding, an @AppStorage key, a ForEach `$item`).
final class KBox {
    private var stored: KV
    var getter: (() -> KV)?
    var setter: ((KV) -> Void)?
    /// Called after every write — the owning view re-renders.
    var onChange: (() -> Void)?
    var declaredType: KETypeRef?
    let isLet: Bool

    init(_ value: KV, isLet: Bool = false, type: KETypeRef? = nil) {
        self.stored = value
        self.isLet = isLet
        self.declaredType = type
    }

    init(get: @escaping () -> KV, set: @escaping (KV) -> Void) {
        self.stored = .void
        self.isLet = false
        self.getter = get
        self.setter = set
    }

    var value: KV {
        get { getter?() ?? stored }
        set {
            if let setter { setter(newValue); return }
            stored = newValue
            onChange?()
        }
    }

    /// Store without notifying (initial values).
    func seed(_ v: KV) { stored = v }
}

/// SwiftUI's Binding: a getter and setter pair to some storage.
final class KBinding {
    let get: () -> KV
    let set: (KV) -> Void
    init(get: @escaping () -> KV, set: @escaping (KV) -> Void) {
        self.get = get
        self.set = set
    }
    static func constant(_ v: KV) -> KBinding { KBinding(get: { v }, set: { _ in }) }
}

/// Lexical scope. Method and body frames carry a `self`.
final class KEnv {
    var vars: [String: KBox] = [:]
    let parent: KEnv?
    var selfContext: KSelfContext?

    init(parent: KEnv?, selfContext: KSelfContext? = nil) {
        self.parent = parent
        self.selfContext = selfContext
    }

    func lookup(_ name: String) -> KBox? {
        var e: KEnv? = self
        while let env = e {
            if let b = env.vars[name] { return b }
            e = env.parent
        }
        return nil
    }

    /// The nearest `self`, if this scope is inside a method or view body.
    var nearestSelf: KSelfContext? {
        var e: KEnv? = self
        while let env = e {
            if let s = env.selfContext { return s }
            e = env.parent
        }
        return nil
    }

    func declare(_ name: String, _ value: KV, isLet: Bool = false, type: KETypeRef? = nil) {
        vars[name] = KBox(value, isLet: isLet, type: type)
    }
}

/// `self` inside a method, computed property or view body.
final class KSelfContext {
    let type: KType
    /// How to read and write `self` (a struct lives somewhere; an object is itself).
    let location: KLocation
    /// For view structs rendered by a host: storage for @State and friends.
    weak var storage: KViewStorage?
    let isStatic: Bool

    init(type: KType, location: KLocation, storage: KViewStorage? = nil, isStatic: Bool = false) {
        self.type = type
        self.location = location
        self.storage = storage
        self.isStatic = isStatic
    }
}

/// Where a value lives, so `habits[i].streak += 1` can write back through a
/// chain of struct copies to the box that owns them.
indirect enum KLocation {
    case box(KBox)
    case member(KLocation, String)
    case index(KLocation, KV)
    case objectField(KObject, String)
    case binding(KBinding)
    case staticMember(KType, String)
    /// A computed location (a property with get/set, a wrapper projection).
    case computed(get: () throws -> KV, set: (KV) throws -> Void)
}

/// A callable: a closure literal, a user function or method bound to its
/// `self`, or a native function.
final class KFunction {
    enum Kind {
        case closure(KEClosure, KEnv)
        case user(KEFuncDecl, KEnv, KSelfContext?)
        case native(String, ([KV], [String?]) throws -> KV)
    }
    let kind: Kind
    init(_ kind: Kind) { self.kind = kind }

    var name: String {
        switch kind {
        case .closure: return "closure"
        case .user(let d, _, _): return d.name
        case .native(let n, _): return n
        }
    }
}
