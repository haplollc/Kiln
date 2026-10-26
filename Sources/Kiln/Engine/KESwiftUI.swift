//
//  KESwiftUI.swift
//  Kiln engine 2
//
//  The SwiftUI side of the value model: native values (colors, fonts, dates,
//  format styles, timers) and view descriptions — the tree a view body
//  evaluates to, which KERenderer turns into real SwiftUI views.
//

import SwiftUI

/// Wraps a reference (or a non-Hashable value) with identity equality.
final class KRef<T>: Hashable {
    let value: T
    init(_ value: T) { self.value = value }
    static func == (a: KRef<T>, b: KRef<T>) -> Bool { a === b }
    func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }
}

/// A grid column or row: GridItem(.flexible(), spacing: 12).
struct KGridItem: Hashable {
    enum Size: Hashable { case flexible(Double, Double), fixed(Double), adaptive(Double, Double) }
    var size: Size
    var spacing: Double?
    var alignment: String?
}

/// A format style: .currency(code:), .number, .percent, .dateTime …
struct KFormat: Hashable {
    enum Kind: Hashable { case currency(String), number, percent, dateTime, date(String, String), relative, list }
    var kind: Kind
    var fraction: ClosedRange<Int>?
    var components: [String] = []      // dateTime.hour().minute()
    var grouping = true
}

struct KStrokeStyle: Hashable {
    var lineWidth: Double = 1
    var lineCap: String = "butt"
    var lineJoin: String = "miter"
    var dash: [Double] = []
}

enum KNative: Hashable {
    case color(Color)
    case font(Font)
    case date(Date)
    case uuid(UUID)
    case angle(Double)                     // degrees
    case implicit(String, [KV])            // `.segmented`, `.title`, `.degrees(90)` before interpretation
    case keyPath([String])
    case indexSet(IndexSet)
    case url(URL)
    case gridItem(KGridItem)
    case format(KFormat)
    case strokeStyle(KStrokeStyle)
    case animation(KRef<Animation?>)
    case timer(KRef<KTimerBox>)
    case publisher(Double)                 // Timer.publish(every:)
    case dismiss(KRef<() -> Void>)         // @SwiftUI.Environment(\.dismiss)
    case asyncPhase(String, KRef<Image?>)  // AsyncImage phase: empty / success / failure
    case object(String, KRef<AnyObject>)   // DateFormatter, NumberFormatter, Calendar, UserDefaults, DispatchQueue …
    case size(Double, Double)              // CGSize
    case point(Double, Double)             // CGPoint
    case transition(String, [KV])
    case shape(KRef<AnyShape>)
    case path(KRef<KPathBox>)
    case rect(Double, Double, Double, Double)  // CGRect x, y, width, height

    var kindName: String {
        switch self {
        case .color: return "Color"
        case .font: return "Font"
        case .date: return "Date"
        case .uuid: return "UUID"
        case .angle: return "Angle"
        case .implicit(let n, _): return "." + n
        case .keyPath: return "KeyPath"
        case .indexSet: return "IndexSet"
        case .url: return "URL"
        case .gridItem: return "GridItem"
        case .format: return "FormatStyle"
        case .strokeStyle: return "StrokeStyle"
        case .animation: return "Animation"
        case .timer: return "Timer"
        case .publisher: return "Publisher"
        case .dismiss: return "DismissAction"
        case .asyncPhase: return "AsyncImagePhase"
        case .object(let n, _): return n
        case .size: return "CGSize"
        case .point: return "CGPoint"
        case .transition: return "AnyTransition"
        case .shape: return "Shape"
        case .path: return "Path"
        case .rect: return "CGRect"
        }
    }

    /// For `switch phase { case .success(let image): … }`.
    var caseName: String? {
        if case .asyncPhase(let n, _) = self { return n }
        return nil
    }

    var payload: KV? {
        if case .asyncPhase("success", let img) = self, let image = img.value { return .view(.image(image)) }
        return nil
    }

    @MainActor func describe(_ interp: KInterpreter) -> String {
        switch self {
        case .date(let d): return d.formatted(date: .abbreviated, time: .shortened)
        case .uuid(let u): return u.uuidString
        case .url(let u): return u.absoluteString
        case .implicit(let n, let a): return "." + n + (a.isEmpty ? "" : "(" + a.map { interp.describe($0) }.joined(separator: ", ") + ")")
        case .size(let w, let h): return "(\(w), \(h))"
        case .point(let x, let y): return "(\(x), \(y))"
        case .angle(let d): return "\(d)°"
        case .object("Error", let ref): return (ref.value as? NSError)?.localizedDescription ?? "Error"
        default: return kindName
        }
    }
}

/// A SwiftUI Path built by interpreted code (`var p = Path(); p.move(to:)`).
final class KPathBox {
    var path = Path()
}

/// A Foundation Timer whose block runs interpreted code.
final class KTimerBox {
    var timer: Timer?
    func invalidate() { timer?.invalidate(); timer = nil }
}

struct KModifier {
    var name: String
    var args: [KV]
    var labels: [String?]
    var line: Int

    func arg(_ label: String?) -> KV? {
        if let i = labels.firstIndex(where: { $0 == label }) { return args[i] }
        return nil
    }
    var first: KV? { args.first }
    func unlabeled(_ n: Int) -> KV? {
        let u = zip(labels, args).filter { $0.0 == nil }.map(\.1)
        return n < u.count ? u[n] : nil
    }
}

/// What a view body evaluates to.
final class KView {
    enum Kind {
        case primitive(String, [KV], [String?], line: Int)
        case custom(KStructValue)
        case modified(KView, KModifier)
        case group([KView])
        case conditional(Bool, [KView])
        case switchBranch(Int, [KView])
        case textConcat(KView, KView)
        case image(Image)
        case empty
        case error(String)
    }
    let kind: Kind
    init(_ kind: Kind) { self.kind = kind }

    static func primitive(_ name: String, _ args: [KV], _ labels: [String?], line: Int) -> KView { KView(.primitive(name, args, labels, line: line)) }
    static func custom(_ s: KStructValue) -> KView { KView(.custom(s)) }
    static func modified(_ v: KView, _ m: KModifier) -> KView { KView(.modified(v, m)) }
    static func group(_ v: [KView]) -> KView { v.count == 1 ? v[0] : KView(.group(v)) }
    static func conditional(_ b: Bool, _ v: [KView]) -> KView { KView(.conditional(b, v)) }
    static func switchBranch(_ i: Int, _ v: [KView]) -> KView { KView(.switchBranch(i, v)) }
    static func textConcat(_ a: KView, _ b: KView) -> KView { KView(.textConcat(a, b)) }
    static func image(_ i: Image) -> KView { KView(.image(i)) }
    static let empty = KView(.empty)
    static func error(_ m: String) -> KView { KView(.error(m)) }

    var primitiveName: String? {
        switch kind {
        case .primitive(let n, _, _, _): return n
        case .modified(let base, _): return base.primitiveName
        default: return nil
        }
    }

    /// The args of the underlying primitive.
    func primitiveArg(_ label: String?) -> KV? {
        switch kind {
        case .primitive(_, let args, let labels, _):
            if let i = labels.firstIndex(where: { $0 == label }) { return args[i] }
            return nil
        case .modified(let base, _): return base.primitiveArg(label)
        default: return nil
        }
    }

    /// Flatten groups and conditionals (Picker rows, toolbar items, chart marks).
    var flattened: [KView] {
        switch kind {
        case .group(let vs), .conditional(_, let vs), .switchBranch(_, let vs): return vs.flatMap(\.flattened)
        case .empty: return []
        default: return [self]
        }
    }

    /// A modifier applied anywhere in this view's own modifier chain.
    func modifier(_ name: String) -> KModifier? {
        if case .modified(let base, let m) = kind { return m.name == name ? m : base.modifier(name) }
        return nil
    }

    /// The view with `name` modifiers removed (e.g. `.tag` handled by a Picker).
    func removing(_ name: String) -> KView {
        if case .modified(let base, let m) = kind {
            let b = base.removing(name)
            return m.name == name ? b : .modified(b, m)
        }
        return self
    }
}
