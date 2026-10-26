//
//  KEAST.swift
//  Kiln engine 2
//
//  The syntax tree for the Swift subset Kiln runs: declarations, statements,
//  expressions and patterns. Nodes are classes (reference identity lets the
//  interpreter cache per-node facts) wrapped in enums for pattern matching.
//

import Foundation

/// A type as written: `Int`, `[Habit]`, `[String: Double]`, `Habit?`,
/// `(Expense) -> Void`, `Binding<Bool>`, `some View`.
indirect enum KETypeRef: Equatable, CustomStringConvertible {
    case named(String, [KETypeRef])
    case array(KETypeRef)
    case dictionary(KETypeRef, KETypeRef)
    case optional(KETypeRef)
    case tuple([KETypeRef])
    case function([KETypeRef], KETypeRef)
    case opaque(KETypeRef)          // some View / any View

    var description: String {
        switch self {
        case .named(let n, let a): return a.isEmpty ? n : "\(n)<\(a.map(\.description).joined(separator: ", "))>"
        case .array(let e): return "[\(e)]"
        case .dictionary(let k, let v): return "[\(k): \(v)]"
        case .optional(let w): return "\(w)?"
        case .tuple(let t): return "(\(t.map(\.description).joined(separator: ", ")))"
        case .function(let p, let r): return "(\(p.map(\.description).joined(separator: ", "))) -> \(r)"
        case .opaque(let t): return "some \(t)"
        }
    }

    /// The type with optionals, `some`, and `Binding<…>` peeled off.
    var core: KETypeRef {
        switch self {
        case .optional(let w): return w.core
        case .opaque(let t): return t.core
        default: return self
        }
    }

    var name: String? {
        if case .named(let n, _) = core { return n }
        return nil
    }

    var isOptional: Bool { if case .optional = self { return true }; return false }
}

struct KEArg {
    var label: String?
    var value: KEExpr
}

final class KEClosure {
    struct Param { var name: String; var type: KETypeRef? }
    var params: [Param]
    var body: [KEStmt]
    /// `{ a, b in }` was written; otherwise `$0`, `$1` are the parameters.
    var hasExplicitParams: Bool
    let line: Int
    init(params: [Param], body: [KEStmt], hasExplicitParams: Bool, line: Int) {
        self.params = params
        self.body = body
        self.hasExplicitParams = hasExplicitParams
        self.line = line
    }
}

enum KEStringSegment {
    case text(String)
    case interp([KEArg])     // `\(value)` or `\(value, specifier: "%.2f")`
}

indirect enum KEExpr {
    case int(Int)
    case double(Double)
    case string([KEStringSegment])
    case bool(Bool)
    case nilLit
    case ident(String, line: Int)
    case implicitMember(String, line: Int)              // .red, .focus
    case member(KEExpr, String, line: Int)              // a.b
    case optionalChain(KEExpr)                          // a? — marks the start of a ?. chain
    case call(KEExpr, [KEArg], line: Int)               // f(x, y: z) — trailing closures appended as args
    case subscriptAccess(KEExpr, [KEArg], line: Int)
    case closure(KEClosure)
    case prefix(String, KEExpr)                         // !x, -x, &x
    case postfix(String, KEExpr)                        // x!, x...
    case binary(String, KEExpr, KEExpr, line: Int)
    case ternary(KEExpr, KEExpr, KEExpr)
    case array([KEExpr])
    case dictionary([(KEExpr, KEExpr)])
    case tuple([(String?, KEExpr)])
    case keyPath(root: String?, [String])               // \.name, \Habit.name, \.self
    case cast(KEExpr, String, KETypeRef)                // as, as?, as!, is
    case tryExpr(String, KEExpr)                        // try, try?, try!
    case awaitExpr(KEExpr)
    case selfRef(line: Int)
    case typeExpr(KETypeRef)                            // [Habit], Set<Int> used as a value
    case ifExpr([KECondition], [KEStmt], [KEStmt])      // Swift 5.9 if-expression
    case switchExpr(KEExpr, [KESwitchCase])
    case assign(String, KEExpr, KEExpr, line: Int)      // a = b / a += b inside closures used as expressions

    var line: Int {
        switch self {
        case .ident(_, let l), .implicitMember(_, let l), .member(_, _, let l), .call(_, _, let l),
             .subscriptAccess(_, _, let l), .binary(_, _, _, let l), .selfRef(let l), .assign(_, _, _, let l): return l
        case .closure(let c): return c.line
        case .optionalChain(let e), .prefix(_, let e), .postfix(_, let e), .cast(let e, _, _),
             .tryExpr(_, let e), .awaitExpr(let e): return e.line
        case .ternary(let c, _, _): return c.line
        default: return 0
        }
    }
}

enum KECondition {
    case expr(KEExpr)
    case optionalBinding(KEPattern, KEExpr)       // if let x = y / if var x = y / if let x
    case casePattern(KEPattern, KEExpr)           // if case .a(let x) = y
    case available                                 // #available(…) — always true
}

indirect enum KEPattern {
    case wildcard
    case binding(String, isVar: Bool)              // let x / var x / x (inside a binding pattern)
    case tuple([KEPattern])
    case enumCase(type: String?, name: String, [KEPattern])   // .some(let x), Kind.a(let y)
    case expression(KEExpr)                        // a value to match with ~=
    case optional(KEPattern)                       // x?
    case typeCheck(KETypeRef)                      // is Int
    case cast(KEPattern, KETypeRef)                // let x as Int
}

struct KESwitchCase {
    var patterns: [(KEPattern, KEExpr?)]           // pattern + optional `where`
    var body: [KEStmt]
    var isDefault: Bool
}

struct KECatch {
    var pattern: KEPattern?
    var body: [KEStmt]
}

indirect enum KEStmt {
    case expr(KEExpr)
    case variable(KEVarDecl)
    case assign(String, KEExpr, KEExpr, line: Int)     // op, target, value
    case ifStmt([KECondition], [KEStmt], KEElse?)
    case guardStmt([KECondition], [KEStmt])
    case switchStmt(KEExpr, [KESwitchCase])
    case forIn(KEPattern, KEExpr, KEExpr?, [KEStmt], label: String?)
    case whileStmt([KECondition], [KEStmt], label: String?)
    case repeatWhile([KEStmt], KEExpr, label: String?)
    case returnStmt(KEExpr?, line: Int)
    case breakStmt(String?)
    case continueStmt(String?)
    case fallthroughStmt
    case throwStmt(KEExpr)
    case doCatch([KEStmt], [KECatch])
    case deferStmt([KEStmt])
    case declaration(KEDecl)
}

indirect enum KEElse {
    case block([KEStmt])
    case elseIf(KEStmt)
}

struct KEAttribute {
    var name: String
    var args: [KEArg]
}

final class KEVarDecl {
    var pattern: KEPattern
    var name: String { if case .binding(let n, _) = pattern { return n }; return "_" }
    var isLet: Bool
    var isStatic: Bool
    var type: KETypeRef?
    var initial: KEExpr?
    var attributes: [KEAttribute]
    var getter: [KEStmt]?
    var setter: (String, [KEStmt])?
    var willSet: (String, [KEStmt])?
    var didSet: (String, [KEStmt])?
    var isLazy: Bool
    let line: Int
    init(pattern: KEPattern, isLet: Bool, isStatic: Bool, type: KETypeRef?, initial: KEExpr?,
         attributes: [KEAttribute], getter: [KEStmt]?, setter: (String, [KEStmt])?,
         willSet: (String, [KEStmt])?, didSet: (String, [KEStmt])?, isLazy: Bool, line: Int) {
        self.pattern = pattern; self.isLet = isLet; self.isStatic = isStatic; self.type = type
        self.initial = initial; self.attributes = attributes; self.getter = getter; self.setter = setter
        self.willSet = willSet; self.didSet = didSet; self.isLazy = isLazy; self.line = line
    }

    var isComputed: Bool { getter != nil }
    var wrapper: String? { attributes.first(where: { Self.wrappers.contains($0.name) })?.name }
    var wrapperAttribute: KEAttribute? { attributes.first(where: { Self.wrappers.contains($0.name) }) }
    static let wrappers: Set<String> = ["State", "Binding", "StateObject", "ObservedObject", "EnvironmentObject",
                                        "Environment", "Published", "AppStorage", "SceneStorage", "FocusState",
                                        "Namespace", "GestureState", "Bindable"]
}

struct KEParam {
    var label: String?        // external label; nil when written `_`
    var name: String          // internal name
    var type: KETypeRef?
    var defaultValue: KEExpr?
    var isInout: Bool
    var isVariadic: Bool
}

final class KEFuncDecl {
    var name: String
    var params: [KEParam]
    var returnType: KETypeRef?
    var body: [KEStmt]
    var isStatic: Bool
    var isMutating: Bool
    var attributes: [KEAttribute]
    let line: Int
    init(name: String, params: [KEParam], returnType: KETypeRef?, body: [KEStmt], isStatic: Bool,
         isMutating: Bool, attributes: [KEAttribute], line: Int) {
        self.name = name; self.params = params; self.returnType = returnType; self.body = body
        self.isStatic = isStatic; self.isMutating = isMutating; self.attributes = attributes; self.line = line
    }
    var isViewBuilder: Bool { attributes.contains { $0.name == "ViewBuilder" } || returnType.map(KEFuncDecl.isViewType) ?? false }
    static func isViewType(_ t: KETypeRef) -> Bool {
        if case .opaque(let inner) = t, let n = inner.name { return ["View", "ChartContent", "ToolbarContent", "Scene"].contains(n) }
        return false
    }
    /// Labels as callers write them: `total(for:)`.
    var signature: String { name + "(" + params.map { ($0.label ?? "_") + ":" }.joined() + ")" }
}

struct KEEnumCase {
    var name: String
    var associated: [(String?, KETypeRef)]
    var rawValue: KEExpr?
}

enum KETypeKind: String { case structType = "struct", classType = "class", enumType = "enum",
                          protocolType = "protocol", extensionType = "extension", actorType = "actor" }

final class KETypeDecl {
    var kind: KETypeKind
    var name: String
    var inherits: [String]
    var properties: [KEVarDecl] = []
    var methods: [KEFuncDecl] = []
    var inits: [KEFuncDecl] = []         // name "init"; returnType unused; failable via attributes ["Failable"]
    var cases: [KEEnumCase] = []
    var nested: [KETypeDecl] = []
    var subscripts: [KEFuncDecl] = []
    var attributes: [KEAttribute]
    let line: Int
    init(kind: KETypeKind, name: String, inherits: [String], attributes: [KEAttribute], line: Int) {
        self.kind = kind; self.name = name; self.inherits = inherits; self.attributes = attributes; self.line = line
    }
}

enum KEDecl {
    case type(KETypeDecl)
    case function(KEFuncDecl)
    case typeAlias(String, KETypeRef)
    case importDecl(String)
}

/// A parsed source file.
struct KEProgram {
    var types: [KETypeDecl] = []
    var functions: [KEFuncDecl] = []
    var globals: [KEStmt] = []            // top-level statements (`let emojis = …`, expressions)
    var previews: [[KEStmt]] = []         // #Preview { … } bodies
    var imports: [String] = []
}
