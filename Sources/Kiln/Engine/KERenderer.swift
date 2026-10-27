//
//  KERenderer.swift
//  Kiln engine 2
//
//  Turns view descriptions into real SwiftUI. Every interpreted View struct is
//  hosted by a real SwiftUI view (KHostView) whose storage object owns that
//  instance's @State, so SwiftUI's own identity rules decide when state lives
//  and dies — the same as compiled SwiftUI.
//

import SwiftUI
import Combine
import Charts

// MARK: - Host

/// One hosted view's @State, @AppStorage, @StateObject and environment values.
@MainActor
final class KViewStorage: ObservableObject {
    private(set) var boxes: [String: KBox] = [:]
    private var prepared = false
    private var subscriptions: [ObjectIdentifier: AnyCancellable] = [:]

    func box(_ name: String) -> KBox? { boxes[name] }

    func prepare(_ value: KStructValue, _ interp: KInterpreter) {
        guard !prepared else { return }
        prepared = true
        for p in value.type.stored {
            guard let w = p.wrapper else { continue }
            switch w {
            case "State", "StateObject", "FocusState", "GestureState", "SceneStorage", "Namespace":
                let box = KBox(value.fields[p.name] ?? (p.type?.isOptional == true ? .nilValue : .void), type: p.type)
                box.onChange = { [weak self] in self?.objectWillChange.send() }
                boxes[p.name] = box
            case "ObservedObject", "Bindable":
                // Owned when the view creates it itself (`= Model()`); otherwise read from the view value.
                if p.initial != nil {
                    boxes[p.name] = KBox(value.fields[p.name] ?? .nilValue, type: p.type)
                }
            case "AppStorage":
                let key = "kiln.app." + (p.wrapperAttribute?.args.first.flatMap { arg -> String? in
                    if case .string(let segs) = arg.value, case .text(let t)? = segs.first { return t }
                    return nil
                } ?? p.name)
                let fallback = value.fields[p.name] ?? .nilValue
                let box = KBox(get: {
                    guard let stored = UserDefaults.standard.object(forKey: key) else { return fallback }
                    switch fallback {
                    case .int: return .int((stored as? Int) ?? 0)
                    case .double: return .double((stored as? Double) ?? 0)
                    case .bool: return .bool((stored as? Bool) ?? false)
                    default: return .string((stored as? String) ?? "")
                    }
                }, set: { [weak self] v in
                    switch v {
                    case .int(let i): UserDefaults.standard.set(i, forKey: key)
                    case .double(let d): UserDefaults.standard.set(d, forKey: key)
                    case .bool(let b): UserDefaults.standard.set(b, forKey: key)
                    case .string(let s): UserDefaults.standard.set(s, forKey: key)
                    default: break
                    }
                    self?.objectWillChange.send()
                })
                boxes[p.name] = box
            default:
                break
            }
        }
    }

    /// @Environment and @EnvironmentObject values, refreshed every render.
    func setEnvironment(_ value: KStructValue, dismiss: DismissAction, colorScheme: ColorScheme, objects: [String: KV], interp: KInterpreter) {
        for p in value.type.stored {
            if p.wrapper == "Environment" {
                var v = KBuiltins.environmentDefault(p, interp)
                if case .native(.dismiss) = v { v = .native(.dismiss(KRef({ dismiss() }))) }
                if case .keyPath(_, let comps)? = p.wrapperAttribute?.args.first?.value, comps.last == "colorScheme" {
                    v = .native(.implicit(colorScheme == .dark ? "dark" : "light", []))
                }
                boxes[p.name] = KBox(v)
            } else if p.wrapper == "EnvironmentObject", let typeName = p.type?.name, let obj = objects[typeName] {
                boxes[p.name] = KBox(obj)
            }
        }
    }

    /// Re-render when any class instance read by the last body changes.
    func observe(_ objects: [ObjectIdentifier: KObject]) {
        for (id, obj) in objects where subscriptions[id] == nil {
            subscriptions[id] = obj.changed.sink { [weak self] _ in self?.objectWillChange.send() }
        }
    }
}

struct KEnvironmentObjectsKey: EnvironmentKey {
    static let defaultValue: [String: KV] = [:]
}

extension EnvironmentValues {
    var kilnObjects: [String: KV] {
        get { self[KEnvironmentObjectsKey.self] }
        set { self[KEnvironmentObjectsKey.self] = newValue }
    }
}

/// A user View struct, hosted.
struct KHostView: View {
    let value: KStructValue
    let interp: KInterpreter
    @StateObject private var storage = KViewStorage()
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    @SwiftUI.Environment(\.kilnObjects) private var objects

    var body: some View {
        storage.prepare(value, interp)
        storage.setEnvironment(value, dismiss: dismiss, colorScheme: colorScheme, objects: objects, interp: interp)
        let tracker = KReadTracker()
        let content = interp.renderBody(of: value, storage: storage, tracker: tracker)
        storage.observe(tracker.objects)
        return content
    }
}

/// Content evaluated lazily inside SwiftUI (sheet content, navigation
/// destinations): re-evaluates whenever SwiftUI asks for it.
struct KLazyView: View {
    let make: () -> AnyView
    var body: some View { make() }
}

/// A timer that calls back into interpreted code at a fixed interval.
@MainActor
final class KTicker: ObservableObject {
    var action: (() -> Void)?
    private var timer: Timer?
    private var interval: Double = 0

    func start(_ interval: Double) {
        guard timer == nil || self.interval != interval else { return }
        timer?.invalidate()
        self.interval = interval
        timer = Timer.scheduledTimer(withTimeInterval: max(0.01, interval), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.action?() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

struct KTimerReceiver: View {
    let interval: Double
    let action: () -> Void
    let content: AnyView
    @StateObject private var ticker = KTicker()

    var body: some View {
        ticker.action = action
        return content
            .onAppear { ticker.start(interval) }
            .onDisappear { ticker.stop() }
    }
}

/// Shown in place of a part of the view that failed to evaluate.
struct KErrorView: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
            .padding(8)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Body evaluation

extension KInterpreter {
    func renderBody(of value: KStructValue, storage: KViewStorage?, tracker: KReadTracker?) -> AnyView {
        let ctx = KSelfContext(type: value.type, location: .box(KBox(.structV(value))), storage: storage)
        let env = KEnv(parent: globalEnv, selfContext: ctx)
        let saved = readTracker
        readTracker = tracker
        defer { readTracker = saved }
        guard let bodyDecl = value.type.computed["body"] else {
            if value.type.isApp, let scenes = value.type.computed["body"] { _ = scenes }
            return AnyView(KErrorView(message: "\(value.type.name) has no body"))
        }
        do {
            let v = try entry { try runAccessor(bodyDecl.getter ?? [], env: env, returns: bodyDecl.type) }
            return KRenderer(interp: self).render(.group(KBuiltins.asViews(v, self)))
        } catch {
            report(error)
            return AnyView(KErrorView(message: describeError(error)))
        }
    }

    func describeError(_ error: Error) -> String {
        switch error {
        case let e as KERuntimeError: return e.description
        case let t as KEThrown: return "Uncaught error: \(describe(t.value))"
        default: return "\(error)"
        }
    }

    /// Run interpreted code from a UI event (a tap, a timer) with its own budget.
    func perform(_ f: KFunction?, _ args: [KV] = []) {
        guard let f else { return }
        do {
            _ = try entry { try call(f, args, args.map { _ in nil }) }
        } catch {
            report(error)
        }
    }
}

// MARK: - Renderer

@MainActor
struct KRenderer {
    let interp: KInterpreter

    func render(_ v: KView) -> AnyView {
        switch v.kind {
        case .empty: return AnyView(EmptyView())
        case .error(let m): return AnyView(KErrorView(message: m))
        case .group(let vs): return renderList(vs)
        case .conditional(let b, let vs):
            return b ? AnyView(renderList(vs)) : AnyView(renderList(vs).id("else"))
        case .switchBranch(let i, let vs): return AnyView(renderList(vs).id(i))
        case .image(let img): return AnyView(img)
        case .textConcat: return AnyView(text(v) ?? Text(""))
        case .custom(let s): return AnyView(KHostView(value: s, interp: interp))
        case .primitive(let name, let args, let labels, let line):
            return primitive(name, KArgs(args: args, labels: labels), line)
        case .modified(let base, let m):
            return modified(base, m)
        }
    }

    func renderList(_ vs: [KView]) -> AnyView {
        if vs.isEmpty { return AnyView(EmptyView()) }
        if vs.count == 1 { return render(vs[0]) }
        return AnyView(ForEach(Array(vs.enumerated()), id: \.offset) { _, child in render(child) })
    }

    func content(_ f: KV?, _ args: [KV] = []) -> [KView] {
        guard case .function(let fn)? = f else {
            if let f { return KBuiltins.asViews(f, interp) }
            return []
        }
        do { return try interp.entry { try interp.callBuilder(fn, args) } }
        catch {
            interp.report(error)
            return [.error(interp.describeError(error))]
        }
    }

    func renderContent(_ f: KV?, _ args: [KV] = []) -> AnyView { renderList(content(f, args)) }

    func action(_ f: KV?) -> () -> Void {
        guard case .function(let fn)? = f else { return {} }
        return { [interp] in interp.perform(fn) }
    }

    // MARK: Values

    func string(_ v: KV?) -> String? {
        guard let v else { return nil }
        if case .view(let view) = v, let t = text(view) { _ = t; return plainText(view) }
        if case .nilValue = v { return nil }
        return interp.describe(v)
    }

    func plainText(_ v: KView) -> String? {
        if case .primitive("Text", let args, _, _) = v.kind, let first = args.first { return interp.describe(first) }
        if case .modified(let base, _) = v.kind { return plainText(base) }
        return nil
    }

    func double(_ v: KV?) -> Double? { v?.asDouble }

    func color(_ v: KV?) -> Color? {
        switch v {
        case .native(.color(let c))?: return c
        case .native(.implicit(let n, let a))?:
            if let c = KBuiltins.colorNames[n] ?? KBuiltins.systemColors[n] { return c }
            if n.hasSuffix(".opacity"), let base = KBuiltins.colorNames[String(n.dropLast(8))] { return base.opacity(a.first?.asDouble ?? 1) }
            return nil
        case .enumV(let e)?: return KBuiltins.colorNames[e.caseName]
        case .string(let s)?: return KBuiltins.colorNames[s.lowercased()] ?? KBuiltins.hexColor(s)
        case .view(let view)?:
            if case .primitive("Color", let args, _, _) = view.kind { return color(args.first) }
            // `.white.opacity(0.6)`: Color is also a View, so the opacity arrives as a modifier.
            if case .modified(let base, let m) = view.kind, m.name == "opacity", let c = color(.view(base)) {
                return c.opacity(m.first?.asDouble ?? 1)
            }
            return nil
        default: return nil
        }
    }

    func shapeStyle(_ v: KV?) -> AnyShapeStyle? {
        if let c = color(v) { return AnyShapeStyle(c) }
        switch v {
        case .native(.implicit(let n, _))?:
            switch n {
            case "secondary": return AnyShapeStyle(.secondary)
            case "tertiary": return AnyShapeStyle(.tertiary)
            case "quaternary": return AnyShapeStyle(.quaternary)
            case "primary": return AnyShapeStyle(.primary)
            case "tint": return AnyShapeStyle(.tint)
            case "ultraThinMaterial": return AnyShapeStyle(.ultraThinMaterial)
            case "thinMaterial": return AnyShapeStyle(.thinMaterial)
            case "regularMaterial", "material": return AnyShapeStyle(.regularMaterial)
            case "thickMaterial": return AnyShapeStyle(.thickMaterial)
            case "ultraThickMaterial": return AnyShapeStyle(.ultraThickMaterial)
            case "bar": return AnyShapeStyle(.bar)
            case "background": return AnyShapeStyle(.background)
            case "foreground": return AnyShapeStyle(.foreground)
            case "separator": return AnyShapeStyle(.separator)
            default:
                if n.hasSuffix(".gradient"), let c = KBuiltins.colorNames[String(n.dropLast(9))] { return AnyShapeStyle(c.gradient) }
                return nil
            }
        case .view(let view)?:
            return gradient(view).map { AnyShapeStyle($0) }
        default: return nil
        }
    }

    func gradient(_ v: KView) -> AnyShapeStyle? {
        guard case .primitive(let name, let args, let labels, _) = v.kind else { return nil }
        let a = KArgs(args: args, labels: labels)
        let colors = (a["colors"]?.asArray ?? gradientColors(a["gradient"]) ?? []).compactMap { color($0) }
        let stops = colors.isEmpty ? [Color.blue, .purple] : colors
        switch name {
        case "LinearGradient":
            return AnyShapeStyle(LinearGradient(colors: stops, startPoint: unitPoint(a["startPoint"]) ?? .top, endPoint: unitPoint(a["endPoint"]) ?? .bottom))
        case "RadialGradient":
            return AnyShapeStyle(RadialGradient(colors: stops, center: unitPoint(a["center"]) ?? .center,
                                                startRadius: a["startRadius"]?.asDouble ?? 0, endRadius: a["endRadius"]?.asDouble ?? 200))
        case "AngularGradient":
            return AnyShapeStyle(AngularGradient(colors: stops, center: unitPoint(a["center"]) ?? .center))
        case "EllipticalGradient":
            return AnyShapeStyle(EllipticalGradient(colors: stops))
        default: return nil
        }
    }

    func gradientColors(_ v: KV?) -> [KV]? {
        if case .native(.implicit(_, let args))? = v { return args.first?.asArray }
        return nil
    }

    func unitPoint(_ v: KV?) -> SwiftUI.UnitPoint? {
        guard case .native(.implicit(let n, _))? = v else { return nil }
        let map: [String: SwiftUI.UnitPoint] = ["top": .top, "bottom": .bottom, "leading": .leading, "trailing": .trailing, "center": .center,
            "topLeading": .topLeading, "topTrailing": .topTrailing, "bottomLeading": .bottomLeading, "bottomTrailing": .bottomTrailing]
        return map[n]
    }

    func font(_ v: KV?) -> Font? {
        switch v {
        case .native(.font(let f))?: return f
        case .native(.implicit(let n, let a))?:
            if let f = KBuiltins.fontStyles[n] { return f }
            let parts = n.split(separator: ".").map(String.init)
            if let base = parts.first.flatMap({ KBuiltins.fontStyles[$0] }) {
                var f = base
                for p in parts.dropFirst() {
                    switch p {
                    case "bold": f = f.bold()
                    case "italic": f = f.italic()
                    case "monospacedDigit": f = f.monospacedDigit()
                    case "monospaced": f = f.monospaced()
                    case "weight":
                        if case .native(.implicit(let w, _))? = a.first { f = f.weight(KBuiltins.weight(w)) }
                    default: break
                    }
                }
                return f
            }
            return KBuiltins.font(n, a, [])
        default: return nil
        }
    }

    func horizontalAlignment(_ v: KV?) -> HorizontalAlignment {
        guard case .native(.implicit(let n, _))? = v else { return .center }
        switch n {
        case "leading": return .leading
        case "trailing": return .trailing
        case "listRowSeparatorLeading": return .listRowSeparatorLeading
        default: return .center
        }
    }

    func verticalAlignment(_ v: KV?) -> VerticalAlignment {
        guard case .native(.implicit(let n, _))? = v else { return .center }
        switch n {
        case "top": return .top
        case "bottom": return .bottom
        case "firstTextBaseline": return .firstTextBaseline
        case "lastTextBaseline": return .lastTextBaseline
        default: return .center
        }
    }

    func alignment(_ v: KV?) -> SwiftUI.Alignment {
        guard case .native(.implicit(let n, _))? = v else { return .center }
        let map: [String: SwiftUI.Alignment] = ["top": .top, "bottom": .bottom, "leading": .leading, "trailing": .trailing,
            "center": .center, "topLeading": .topLeading, "topTrailing": .topTrailing, "bottomLeading": .bottomLeading,
            "bottomTrailing": .bottomTrailing]
        return map[n] ?? .center
    }

    func edges(_ v: KV?) -> Edge.Set {
        switch v {
        case .native(.implicit(let n, _))?:
            let map: [String: Edge.Set] = ["all": .all, "horizontal": .horizontal, "vertical": .vertical, "top": .top,
                                           "bottom": .bottom, "leading": .leading, "trailing": .trailing]
            return map[n] ?? .all
        case .array(let items)?:
            return items.reduce(into: Edge.Set()) { $0.formUnion(edges($1)) }
        default: return .all
        }
    }

    func angle(_ v: KV?) -> Angle {
        switch v {
        case .native(.angle(let d))?: return .degrees(d)
        case .native(.implicit("degrees", let a))?: return .degrees(a.first?.asDouble ?? 0)
        case .native(.implicit("radians", let a))?: return .radians(a.first?.asDouble ?? 0)
        default: return .degrees(v?.asDouble ?? 0)
        }
    }

    func animation(_ v: KV?) -> Animation? {
        switch v {
        case .native(.animation(let a))?: return a.value
        case .native(.implicit(let n, let a))?:
            let parts = n.split(separator: ".").map(String.init)
            var anim = KBuiltins.animation(parts.first ?? n, a, [])
            for p in parts.dropFirst() where p == "repeatForever" { anim = anim?.repeatForever(autoreverses: true) }
            return anim ?? .default
        case .nilValue?: return nil
        default: return .default
        }
    }

    func binding(_ v: KV?) -> KBinding? {
        if case .binding(let b)? = v { return b }
        return nil
    }

    func stringBinding(_ b: KBinding) -> Binding<String> {
        Binding(get: { b.get().asString ?? (b.get().isNil ? "" : interp.describe(b.get())) }, set: { b.set(.string($0)) })
    }

    func boolBinding(_ b: KBinding) -> Binding<Bool> {
        Binding(get: { interp.truthy(b.get()) }, set: { b.set(.bool($0)) })
    }

    func doubleBinding(_ b: KBinding) -> Binding<Double> {
        let isInt: Bool = { if case .int = b.get() { return true }; return false }()
        return Binding(get: { b.get().asDouble ?? 0 }, set: { b.set(isInt ? .int(Int($0.rounded())) : .double($0)) })
    }

    func range(_ v: KV?) -> ClosedRange<Double>? {
        guard case .range(let lo, let hi, let closed)? = v, let l = lo.asDouble, var h = hi.asDouble else { return nil }
        if !closed, case .int = hi { h -= 1 }
        return l...max(l, h)
    }

    // MARK: Text

    func text(_ v: KView) -> Text? {
        switch v.kind {
        case .primitive("Text", let args, let labels, _):
            return textOf(KArgs(args: args, labels: labels))
        case .textConcat(let a, let b):
            guard let ta = text(a), let tb = text(b) else { return nil }
            return ta + tb
        case .modified(let base, let m):
            guard var t = text(base) else { return nil }
            switch m.name {
            case "bold": t = t.bold(m.first.map { interp.truthy($0) } ?? true)
            case "italic": t = t.italic()
            case "font": if let f = font(m.first) { t = t.font(f) }
            case "fontWeight": if case .native(.implicit(let w, _))? = m.first { t = t.fontWeight(KBuiltins.weight(w)) }
            case "foregroundColor", "foregroundStyle":
                if let c = color(m.first) { t = t.foregroundColor(c) }
                // A gradient or material: Text takes any ShapeStyle (iOS 17).
                else if m.name == "foregroundStyle", let style = shapeStyle(m.first) { t = t.foregroundStyle(style) }
            case "underline": t = t.underline()
            case "strikethrough": t = t.strikethrough()
            case "monospacedDigit": t = t.monospacedDigit()
            case "kerning": t = t.kerning(m.first?.asDouble ?? 0)
            case "baselineOffset": t = t.baselineOffset(m.first?.asDouble ?? 0)
            default: return nil
            }
            return t
        default:
            return nil
        }
    }

    func textOf(_ a: KArgs) -> Text {
        if let lit = a["_literal"]?.asString { return Text(LocalizedStringKey(lit)) }
        if let s = a["verbatim"]?.asString { return Text(verbatim: s) }
        guard let first = a.first else { return Text("") }
        if let style = a["format"] { return Text(verbatim: KBuiltins.formatted(first, style, interp)) }
        if case .native(.date(let d)) = first, case .native(.implicit(let s, _))? = a["style"] {
            switch s {
            case "time": return Text(d, style: .time)
            case "date": return Text(d, style: .date)
            case "relative": return Text(d, style: .relative)
            case "timer": return Text(d, style: .timer)
            case "offset": return Text(d, style: .offset)
            default: return Text(d, style: .date)
            }
        }
        if case .view(let v) = first, let t = text(v) { return t }
        return Text(verbatim: interp.describe(first))
    }

    // MARK: Primitives

    func primitive(_ name: String, _ a: KArgs, _ line: Int) -> AnyView {
        switch name {
        case "Text":
            return AnyView(textOf(a))
        case "Image":
            if let s = a["systemName"].flatMap({ string($0) }) { return AnyView(Image(systemName: s)) }
            if let n = a.first?.asString {
                if let host = Kiln.hostImageProvider?(n) { return AnyView(host) }
                #if canImport(UIKit)
                if UIImage(named: n) == nil {
                    return AnyView(Image(systemName: "photo").foregroundStyle(.secondary))
                }
                #endif
                return AnyView(Image(n))
            }
            return AnyView(Image(systemName: "photo"))
        case "Label":
            if let title = string(a.first), let icon = a["systemImage"].flatMap({ string($0) }) {
                return AnyView(Label(title, systemImage: icon))
            }
            if let title = string(a.first), let img = a["image"].flatMap({ string($0) }) {
                return AnyView(Label(title, image: img))
            }
            return AnyView(Label { renderContent(a["title"] ?? a.unlabeled(0)) } icon: { renderContent(a["icon"] ?? a.unlabeled(1)) })
        case "Button":
            return button(a)
        case "Toggle":
            let b = binding(a["isOn"]) ?? .constant(.bool(false))
            if let title = a.first.flatMap({ if case .string(let s) = $0 { return s }; return nil }) {
                return AnyView(Toggle(title, isOn: boolBinding(b)))
            }
            return AnyView(Toggle(isOn: boolBinding(b)) { renderContent(a.lastFunction) })
        case "Slider":
            let b = binding(a["value"]) ?? .constant(.double(0))
            let r = range(a["in"]) ?? 0...1
            if let step = a["step"]?.asDouble { return AnyView(Slider(value: doubleBinding(b), in: r, step: step)) }
            return AnyView(Slider(value: doubleBinding(b), in: r))
        case "Stepper":
            return stepper(a)
        case "TextField", "SecureField":
            return textField(name, a)
        case "TextEditor":
            let b = binding(a["text"]) ?? .constant(.string(""))
            return AnyView(TextEditor(text: stringBinding(b)))
        case "Picker":
            return picker(a)
        case "DatePicker":
            return datePicker(a)
        case "ColorPicker":
            let b = binding(a["selection"]) ?? .constant(.native(.color(.blue)))
            let cb = Binding<Color>(get: { color(b.get()) ?? .blue }, set: { b.set(.native(.color($0))) })
            return AnyView(ColorPicker(string(a.first) ?? "", selection: cb))
        case "ProgressView":
            if let v = a["value"]?.asDouble {
                let total = a["total"]?.asDouble ?? 1
                if let t = a.first.flatMap({ if case .string(let s) = $0 { return s }; return nil }) {
                    return AnyView(ProgressView(t, value: min(max(v, 0), total), total: total))
                }
                return AnyView(ProgressView(value: min(max(v, 0), total), total: total))
            }
            if let t = a.first.flatMap({ if case .string(let s) = $0 { return s }; return nil }) { return AnyView(ProgressView(t)) }
            return AnyView(ProgressView())
        case "Gauge":
            let v = a["value"]?.asDouble ?? 0
            let r = range(a["in"]) ?? 0...1
            return AnyView(Gauge(value: v, in: r) { renderContent(a.lastFunction) })
        case "Link":
            if let t = string(a.first), case .native(.url(let u))? = a["destination"] { return AnyView(Link(t, destination: u)) }
            return AnyView(Text(string(a.first) ?? ""))
        case "Menu":
            if let t = a.first.flatMap({ if case .string(let s) = $0 { return s }; return nil }) {
                return AnyView(Menu(t) { renderContent(a.firstFunction) })
            }
            return AnyView(Menu { renderContent(a.firstFunction) } label: { renderContent(a["label"]) })
        case "Spacer":
            return AnyView(Spacer(minLength: a["minLength"]?.cg))
        case "Divider":
            return AnyView(Divider())
        case "Color":
            return AnyView(color(a.first) ?? .gray)
        case "Circle", "Rectangle", "RoundedRectangle", "Capsule", "Ellipse", "UnevenRoundedRectangle", "ContainerRelativeShape":
            return AnyView(KShapeKind(name, a).anyShape)
        case "UserShape", "PathShape":
            return AnyView(KShapeKind.custom(customShape(name, a)).anyShape)
        case "LinearGradient", "RadialGradient", "AngularGradient", "EllipticalGradient":
            if let g = gradient(KView.primitive(name, a.args, a.labels, line: line)) { return AnyView(Rectangle().fill(g)) }
            return AnyView(EmptyView())
        case "VStack", "LazyVStack":
            let content = renderContent(a.lastFunction)
            let align = horizontalAlignment(a["alignment"])
            if name == "LazyVStack" { return AnyView(LazyVStack(alignment: align, spacing: a["spacing"]?.cg) { content }) }
            return AnyView(VStack(alignment: align, spacing: a["spacing"]?.cg) { content })
        case "HStack", "LazyHStack":
            let content = renderContent(a.lastFunction)
            let align = verticalAlignment(a["alignment"])
            if name == "LazyHStack" { return AnyView(LazyHStack(alignment: align, spacing: a["spacing"]?.cg) { content }) }
            return AnyView(HStack(alignment: align, spacing: a["spacing"]?.cg) { content })
        case "ZStack":
            return AnyView(ZStack(alignment: alignment(a["alignment"])) { renderContent(a.lastFunction) })
        case "LazyVGrid", "LazyHGrid":
            let items = (a["columns"] ?? a["rows"])?.asArray?.compactMap(gridItem) ?? [GridItem(.flexible())]
            let content = renderContent(a.lastFunction)
            if name == "LazyVGrid" {
                return AnyView(LazyVGrid(columns: items, alignment: horizontalAlignment(a["alignment"]), spacing: a["spacing"]?.cg) { content })
            }
            return AnyView(LazyHGrid(rows: items, alignment: verticalAlignment(a["alignment"]), spacing: a["spacing"]?.cg) { content })
        case "Grid":
            return AnyView(Grid(alignment: alignment(a["alignment"]), horizontalSpacing: a["horizontalSpacing"]?.cg,
                                verticalSpacing: a["verticalSpacing"]?.cg) { renderContent(a.lastFunction) })
        case "GridRow":
            return AnyView(GridRow(alignment: verticalAlignment(a["alignment"])) { renderContent(a.lastFunction) })
        case "ScrollView":
            var axes: SwiftUI.Axis.Set = .vertical
            if case .native(.implicit(let n, _))? = a.first, n == "horizontal" { axes = .horizontal }
            if case .array? = a.first { axes = [SwiftUI.Axis.Set.horizontal, .vertical] }
            let shows = a["showsIndicators"].map { interp.truthy($0) } ?? true
            return AnyView(ScrollView(axes, showsIndicators: shows) { renderContent(a.lastFunction) })
        case "ScrollViewReader":
            return AnyView(ScrollViewReader { proxy in
                renderContent(a.lastFunction, [.native(.object("ScrollViewProxy", KRef(KScrollProxy(proxy))))])
            })
        case "List":
            if let data = a.first, a.lastFunction != nil, a.firstIsUnlabeled, !isFunction(data) {
                let rows = forEachRows(KArgs(args: a.args, labels: a.labels))
                return AnyView(List { ForEach(rows) { row in renderList(row.views) } })
            }
            return AnyView(List { renderContent(a.lastFunction) })
        case "Form":
            return AnyView(Form { renderContent(a.lastFunction) })
        case "Section":
            return section(a)
        case "Group":
            return AnyView(Group { renderContent(a.lastFunction) })
        case "GroupBox":
            if let t = a.first.flatMap({ if case .string(let s) = $0 { return s }; return nil }) {
                return AnyView(GroupBox(t) { renderContent(a.lastFunction) })
            }
            if a["label"] != nil { return AnyView(GroupBox { renderContent(a.firstFunction) } label: { renderContent(a["label"]) }) }
            return AnyView(GroupBox { renderContent(a.lastFunction) })
        case "DisclosureGroup":
            let title = string(a.first) ?? ""
            if let b = binding(a["isExpanded"]) {
                return AnyView(DisclosureGroup(title, isExpanded: boolBinding(b)) { renderContent(a.lastFunction) })
            }
            return AnyView(DisclosureGroup(title) { renderContent(a.lastFunction) })
        case "ControlGroup":
            return AnyView(ControlGroup { renderContent(a.lastFunction) })
        case "NavigationStack", "NavigationView", "NavigationSplitView":
            if name == "NavigationSplitView" {
                return AnyView(NavigationStack { renderContent(a.firstFunction) })
            }
            return AnyView(NavigationStack { renderContent(a.lastFunction) })
        case "NavigationLink":
            return navigationLink(a)
        case "TabView":
            return tabView(a)
        case "GeometryReader":
            let fn = a.lastFunction
            return AnyView(GeometryReader { proxy in
                renderContent(fn, [.tuple([.native(.size(proxy.size.width, proxy.size.height)), .native(.object("GeometryProxy", KRef(NSObject())))], ["size", "proxy"])])
            })
        case "ForEach":
            let rows = forEachRows(a)
            return AnyView(ForEach(rows) { row in renderList(row.views) })
        case "AsyncImage":
            return asyncImage(a)
        case "EmptyView":
            return AnyView(EmptyView())
        case "AnyView":
            return renderList(KBuiltins.asViews(a.first ?? .void, interp))
        case "ViewThatFits":
            return AnyView(ViewThatFits { renderContent(a.lastFunction) })
        case "ContentUnavailableView":
            let title = string(a.first) ?? ""
            let icon = a["systemImage"].flatMap { string($0) } ?? "tray"
            let desc = a["description"].flatMap { v -> Text? in
                if case .view(let t) = v { return text(t) }
                return string(v).map { Text($0) }
            }
            return AnyView(ContentUnavailableView(title, systemImage: icon, description: desc))
        case "LabeledContent":
            // LabeledContent { content } label: { label }
            if let first = a.first, isFunction(first), a.firstIsUnlabeled {
                return AnyView(LabeledContent { renderContent(first) } label: { renderContent(a["label"]) })
            }
            let title = string(a.first) ?? ""
            if let value = a["value"] {
                if let style = a["format"] { return AnyView(LabeledContent(title, value: KBuiltins.formatted(value, style, interp))) }
                return AnyView(LabeledContent(title, value: string(value) ?? ""))
            }
            return AnyView(LabeledContent(title) { renderContent(a.lastFunction) })
        case "EditButton":
            #if os(iOS)
            return AnyView(EditButton())
            #else
            return AnyView(EmptyView())
            #endif
        case "ShareLink":
            return AnyView(Label(string(a.first) ?? "Share", systemImage: "square.and.arrow.up"))
        case "TimelineView":
            let fn = a.lastFunction
            var interval = 1.0
            if case .native(.implicit(_, let pa))? = a.first, let by = pa.last?.asDouble { interval = by }
            return AnyView(TimelineView(.periodic(from: .now, by: interval)) { ctx in
                renderContent(fn, [.tuple([.native(.date(ctx.date))], ["date"])])
            })
        case "Chart":
            return chart(a)
        case "ToolbarItem", "ToolbarItemGroup":
            return renderContent(a.lastFunction)
        case "Path", "Canvas":
            interp.warn("\(name) isn't supported in Kiln yet; it draws nothing.")
            return AnyView(EmptyView())
        case "Tab":
            return renderContent(a.lastFunction)
        case "WindowGroup":
            return renderContent(a.lastFunction)
        default:
            interp.warn("\(name) isn't supported in Kiln yet.")
            return AnyView(EmptyView())
        }
    }

    func isFunction(_ v: KV) -> Bool { if case .function = v { return true }; return false }

    func gridItem(_ v: KV) -> GridItem? {
        guard case .native(.gridItem(let g)) = v else { return nil }
        let size: GridItem.Size
        switch g.size {
        case .flexible(let lo, let hi): size = .flexible(minimum: lo, maximum: hi)
        case .fixed(let w): size = .fixed(w)
        case .adaptive(let lo, let hi): size = .adaptive(minimum: lo, maximum: hi)
        }
        return GridItem(size, spacing: g.spacing.map { CGFloat($0) })
    }

    func button(_ a: KArgs) -> AnyView {
        let title = a.first.flatMap { v -> String? in if case .string(let s) = v, a.firstIsUnlabeled { return s }; return nil }
        var actionFn: KV? = a["action"]
        var labelFn: KV? = a["label"]
        let unlabeledFns = zip(a.args, a.labels).filter { $0.1 == nil && isFunction($0.0) }.map(\.0)
        if actionFn == nil { actionFn = unlabeledFns.first }
        if labelFn == nil, title == nil, unlabeledFns.count > 1 || (a["action"] != nil && !unlabeledFns.isEmpty) {
            labelFn = a["action"] != nil ? unlabeledFns.first : unlabeledFns.dropFirst().first
        }
        var role: ButtonRole? = nil
        if case .native(.implicit(let r, _))? = a["role"] { role = r == "destructive" ? .destructive : (r == "cancel" ? .cancel : nil) }
        let run = action(actionFn)
        if let title {
            if let icon = a["systemImage"].flatMap({ string($0) }) {
                return AnyView(Button(role: role, action: run) { Label(title, systemImage: icon) })
            }
            return AnyView(Button(title, role: role, action: run))
        }
        if let lf = labelFn {
            return AnyView(Button(role: role, action: run) { renderContent(lf) })
        }
        return AnyView(Button(role: role, action: run) { Text(string(a.first) ?? "Button") })
    }

    func stepper(_ a: KArgs) -> AnyView {
        let title = a.first.flatMap { v -> String? in if case .string(let s) = v, a.firstIsUnlabeled { return s }; return nil }
        if let inc = a["onIncrement"] {
            let dec = a["onDecrement"]
            return AnyView(Stepper(title ?? "", onIncrement: action(inc), onDecrement: action(dec)))
        }
        let b = binding(a["value"]) ?? .constant(.int(0))
        let step = (a["step"] ?? a["increment"])?.asDouble ?? 1
        let isInt: Bool = { if case .int = b.get() { return true }; return false }()
        let r = range(a["in"])
        let label: AnyView = title.map { AnyView(Text($0)) } ?? renderContent(a.lastFunction)
        if isInt {
            let ib = Binding<Int>(get: { b.get().asInt ?? 0 }, set: { b.set(.int($0)) })
            if let r {
                return AnyView(Stepper(value: ib, in: Int(r.lowerBound)...Int(r.upperBound), step: Int(step)) { label })
            }
            return AnyView(Stepper(value: ib, step: Int(step)) { label })
        }
        let db = doubleBinding(b)
        if let r { return AnyView(Stepper(value: db, in: r, step: step) { label }) }
        return AnyView(Stepper(value: db, step: step) { label })
    }

    func textField(_ name: String, _ a: KArgs) -> AnyView {
        let placeholder = string(a.first) ?? ""
        if let vb = binding(a["value"]) {
            let style = a["format"]
            let isInt: Bool = { if case .int = vb.get() { return true }; return false }()
            if isInt {
                let ib = Binding<Int>(get: { vb.get().asInt ?? 0 }, set: { vb.set(.int($0)) })
                return AnyView(TextField(placeholder, value: ib, format: .number))
            }
            let db = Binding<Double>(get: { vb.get().asDouble ?? 0 }, set: { vb.set(.double($0)) })
            if case .native(.format(let f))? = style, case .currency(let code) = f.kind {
                return AnyView(TextField(placeholder, value: db, format: .currency(code: code)))
            }
            if case .native(.format(let f))? = style, f.kind == .percent {
                return AnyView(TextField(placeholder, value: db, format: .percent))
            }
            return AnyView(TextField(placeholder, value: db, format: .number))
        }
        let b = binding(a["text"]) ?? .constant(.string(""))
        if name == "SecureField" { return AnyView(SecureField(placeholder, text: stringBinding(b))) }
        if case .native(.implicit("vertical", _))? = a["axis"] {
            return AnyView(TextField(placeholder, text: stringBinding(b), axis: .vertical))
        }
        if let submit = a["onCommit"] {
            let run = action(submit)
            return AnyView(TextField(placeholder, text: stringBinding(b)).onSubmit(run))
        }
        return AnyView(TextField(placeholder, text: stringBinding(b)))
    }

    struct Row: Identifiable {
        let id: KV
        let views: [KView]
    }

    /// The rows of a ForEach / List(data): one per element, with SwiftUI ids.
    func forEachRows(_ a: KArgs) -> [Row] {
        guard let data = a.first else { return [] }
        let fn = a.lastFunction
        var elements: [KV] = []
        var bindingSource: KBinding? = nil
        switch data {
        case .binding(let b):
            bindingSource = b
            elements = (try? interp.sequence(b.get())) ?? []
        default:
            elements = (try? interp.sequence(data)) ?? []
        }
        var ids: [KV] = elements.enumerated().map { i, e in rowID(e, a["id"]) ?? .int(i) }
        if Set(ids).count != ids.count { ids = elements.indices.map { .int($0) } }
        var rows: [Row] = []
        for (i, e) in elements.enumerated() {
            var arg = e
            if let src = bindingSource {
                let id = ids[i]
                let keyPath = a["id"]
                let interp = self.interp
                arg = .binding(KBinding(get: {
                    let current = (try? interp.sequence(src.get())) ?? []
                    if let match = current.enumerated().first(where: { (KRenderer(interp: interp).rowID($0.element, keyPath) ?? .int($0.offset)) == id }) {
                        return match.element
                    }
                    return e
                }, set: { newValue in
                    guard case .array(var current) = src.get() else { return }
                    if let idx = current.indices.first(where: { (KRenderer(interp: interp).rowID(current[$0], keyPath) ?? .int($0)) == id }) {
                        current[idx] = newValue
                        src.set(.array(current))
                    }
                }))
            }
            rows.append(Row(id: ids[i], views: content(fn, [arg])))
        }
        return rows
    }

    func rowID(_ e: KV, _ keyPath: KV?) -> KV? {
        if case .native(.keyPath(let comps))? = keyPath {
            var v = e
            for c in comps where c != "self" { v = (try? interp.member(v, c, line: 0)) ?? .nilValue }
            return v
        }
        switch e {
        case .structV, .object, .enumV:
            if let id = try? interp.member(e, "id", line: 0) { return id }
            return e
        default:
            return e
        }
    }

    func section(_ a: KArgs) -> AnyView {
        let body = renderContent(a.firstFunction ?? a.lastFunction)
        if let title = a.first.flatMap({ v -> String? in if case .string(let s) = v, a.firstIsUnlabeled { return s }; return nil }) {
            return AnyView(Section(title) { body })
        }
        let header = a["header"].map { v -> AnyView in isFunction(v) ? renderContent(v) : renderList(KBuiltins.asViews(v, interp)) }
        let footer = a["footer"].map { v -> AnyView in isFunction(v) ? renderContent(v) : renderList(KBuiltins.asViews(v, interp)) }
        switch (header, footer) {
        case (let h?, let f?): return AnyView(Section { body } header: { h } footer: { f })
        case (let h?, nil): return AnyView(Section { body } header: { h })
        case (nil, let f?): return AnyView(Section { body } footer: { f })
        default: return AnyView(Section { body })
        }
    }

    func picker(_ a: KArgs) -> AnyView {
        let b = binding(a["selection"]) ?? .constant(.nilValue)
        let rows = pickerRows(content(a.lastFunction ?? a["content"]))
        let sel = Binding<KV>(get: {
            let v = b.get()
            return rows.first(where: { $0.0 == v })?.0 ?? v
        }, set: { b.set($0) })
        let title = string(a.first.flatMap { if case .string = $0 { return $0 }; return nil }) ?? ""
        let items = ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            render(row.1).tag(row.0)
        }
        if let lf = a["label"] { return AnyView(Picker(selection: sel) { items } label: { renderContent(lf) }) }
        return AnyView(Picker(title, selection: sel) { items })
    }

    /// Picker rows with their tags: an explicit `.tag`, else the ForEach id.
    func pickerRows(_ views: [KView]) -> [(KV, KView)] {
        var rows: [(KV, KView)] = []
        for v in views.flatMap(\.flattened) {
            if v.primitiveName == "ForEach", case .primitive(_, let args, let labels, _) = v.kind {
                for row in forEachRows(KArgs(args: args, labels: labels)) {
                    for rv in row.views.flatMap(\.flattened) {
                        rows.append((rv.modifier("tag")?.first ?? row.id, rv.removing("tag")))
                    }
                }
            } else {
                let tag = v.modifier("tag")?.first ?? .string(plainText(v) ?? "\(rows.count)")
                rows.append((tag, v.removing("tag")))
            }
        }
        return rows
    }

    func datePicker(_ a: KArgs) -> AnyView {
        let b = binding(a["selection"]) ?? .constant(.native(.date(Date())))
        let db = Binding<Date>(get: { if case .native(.date(let d)) = b.get() { return d }; return Date() },
                               set: { b.set(.native(.date($0))) })
        var comps: DatePickerComponents = [.date, .hourAndMinute]
        if let dc = a["displayedComponents"] {
            comps = []
            let names: [String] = {
                if case .native(.implicit(let n, _)) = dc { return [n] }
                if case .array(let items) = dc { return items.compactMap { if case .native(.implicit(let n, _)) = $0 { return n }; return nil } }
                return []
            }()
            if names.contains("date") { comps.insert(.date) }
            if names.contains("hourAndMinute") { comps.insert(.hourAndMinute) }
            if comps.isEmpty { comps = .date }
        }
        let title = string(a.first) ?? ""
        return AnyView(DatePicker(title, selection: db, displayedComponents: comps))
    }

    func navigationLink(_ a: KArgs) -> AnyView {
        let title = a.first.flatMap { v -> String? in if case .string(let s) = v, a.firstIsUnlabeled { return s }; return nil }
        if let value = a["value"] {
            let label: AnyView = title.map { AnyView(Text($0)) } ?? renderContent(a.lastFunction)
            return AnyView(NavigationLink(value: KNavValue(value: value)) { label })
        }
        let dest = a["destination"]
        let destination = KLazyView {
            if let dest, isFunction(dest) { return renderContent(dest) }
            return renderList(KBuiltins.asViews(dest ?? .void, interp))
        }
        if let title { return AnyView(NavigationLink(title) { destination }) }
        let labelFn = a["label"] ?? a.lastFunction
        return AnyView(NavigationLink { destination } label: { renderContent(labelFn) })
    }

    func tabView(_ a: KArgs) -> AnyView {
        let children = content(a.lastFunction).flatMap(\.flattened)
        let sel = binding(a["selection"])
        let tabs = ForEach(Array(children.enumerated()), id: \.offset) { i, child in
            tabContent(child, index: i)
        }
        if let sel {
            let sb = Binding<KV>(get: { sel.get() }, set: { sel.set($0) })
            return AnyView(TabView(selection: sb) { tabs })
        }
        return AnyView(TabView { tabs })
    }

    func tabContent(_ child: KView, index: Int) -> AnyView {
        if case .primitive("Tab", let args, let labels, _) = child.kind {
            let a = KArgs(args: args, labels: labels)
            let title = string(a.first) ?? "Tab"
            let icon = a["systemImage"].flatMap { string($0) } ?? "circle"
            return AnyView(renderContent(a.lastFunction).tabItem { Label(title, systemImage: icon) }.tag(a["value"] ?? .int(index)))
        }
        let tag = child.modifier("tag")?.first ?? .int(index)
        return AnyView(render(child).tag(tag))
    }

    func asyncImage(_ a: KArgs) -> AnyView {
        var url: URL? = nil
        if case .native(.url(let u))? = a["url"] ?? a.first { url = u }
        if let s = (a["url"] ?? a.first)?.asString { url = URL(string: s) }
        let contentFn = a["content"] ?? a.unlabeledFunction(0)
        let placeholderFn = a["placeholder"]
        guard let contentFn else { return AnyView(AsyncImage(url: url)) }
        if placeholderFn != nil || closureParamCount(contentFn) == 1 && placeholderFn != nil {
            return AnyView(AsyncImage(url: url) { image in
                renderContent(contentFn, [.view(.image(image))])
            } placeholder: {
                renderContent(placeholderFn)
            })
        }
        return AnyView(AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image): renderContent(contentFn, [.native(.asyncPhase("success", KRef(image)))])
            case .failure: renderContent(contentFn, [.native(.asyncPhase("failure", KRef(nil)))])
            default: renderContent(contentFn, [.native(.asyncPhase("empty", KRef(nil)))])
            }
        })
    }

    func closureParamCount(_ f: KV) -> Int {
        if case .function(let fn) = f, case .closure(let c, _) = fn.kind { return c.params.count }
        return 0
    }

    // MARK: Modifiers

    func modified(_ base: KView, _ m: KModifier) -> AnyView {
        switch m.name {
        case "fill", "stroke", "strokeBorder", "trim", "inset", "rotation", "scale":
            if let shape = shapeChain(base) { return shapeModifier(shape, m) }
        case "onDelete", "onMove":
            if base.primitiveName == "ForEach" { return forEachWithEditing(base, m) }
        case "tag":
            return AnyView(render(base).tag(m.first ?? .nilValue))
        case "modifier":
            return customModifier(base, m)
        case "toolbar":
            return toolbar(render(base), m)
        default:
            break
        }
        if let t = text(.modified(base, m)), case .primitive("Text", _, _, _)? = rootPrimitive(base) {
            return AnyView(t)
        }
        return KModifiers.apply(m, to: render(base), base: base, self)
    }

    func rootPrimitive(_ v: KView) -> KView.Kind? {
        if case .modified(let b, _) = v.kind { return rootPrimitive(b) }
        if case .textConcat = v.kind { return .primitive("Text", [], [], line: 0) }
        return v.kind
    }

    func forEachWithEditing(_ base: KView, _ m: KModifier) -> AnyView {
        var deleteFn: KV? = nil, moveFn: KV? = nil
        var node = base
        if m.name == "onDelete" { deleteFn = m.first } else { moveFn = m.first }
        while case .modified(let inner, let mm) = node.kind {
            if mm.name == "onDelete" { deleteFn = deleteFn ?? mm.first }
            if mm.name == "onMove" { moveFn = moveFn ?? mm.first }
            node = inner
        }
        guard case .primitive(_, let args, let labels, _) = node.kind else { return render(base) }
        let rows = forEachRows(KArgs(args: args, labels: labels))
        let interp = self.interp
        var each = AnyView(ForEach(rows) { row in renderList(row.views) })
        if case .function(let df)? = deleteFn {
            each = AnyView(ForEach(rows) { row in renderList(row.views) }
                .onDelete { offsets in interp.perform(df, [.native(.indexSet(offsets))]) })
        }
        if case .function(let mf)? = moveFn {
            each = AnyView(ForEach(rows) { row in renderList(row.views) }
                .onDelete(perform: deleteFn.flatMap { if case .function(let df) = $0 { return { offsets in interp.perform(df, [.native(.indexSet(offsets))]) } }; return nil })
                .onMove { from, to in interp.perform(mf, [.native(.indexSet(from)), .int(to)]) })
        }
        return each
    }

    func customModifier(_ base: KView, _ m: KModifier) -> AnyView {
        guard case .structV(let s)? = m.first, let body = s.type.method("body") else { return render(base) }
        do {
            let ctx = KSelfContext(type: s.type, location: .box(KBox(.structV(s))))
            let v = try interp.entry {
                try interp.invoke(body, args: [.view(base)], labels: ["content"], selfContext: ctx, parent: interp.globalEnv)
            }
            return render(.group(KBuiltins.asViews(v, interp)))
        } catch {
            interp.report(error)
            return render(base)
        }
    }

    func toolbar(_ view: AnyView, _ m: KModifier) -> AnyView {
        guard let fn = m.args.last, isFunction(fn) else { return view }
        let items = content(fn).flatMap(\.flattened)
        var groups: [String: [AnyView]] = [:]
        for item in items {
            if case .primitive(let n, let args, let labels, _) = item.kind, n == "ToolbarItem" || n == "ToolbarItemGroup" {
                let a = KArgs(args: args, labels: labels)
                groups[placementKey(a["placement"]), default: []].append(renderContent(a.lastFunction))
            } else {
                groups["automatic", default: []].append(render(item))
            }
        }
        return AnyView(view.toolbar { KToolbar(groups: groups) })
    }

    func placementKey(_ v: KV?) -> String {
        guard case .native(.implicit(let n, _))? = v else { return "automatic" }
        switch n {
        case "navigationBarTrailing": return "topBarTrailing"
        case "navigationBarLeading": return "topBarLeading"
        default: return n
        }
    }

    func placement(_ v: KV?) -> ToolbarItemPlacement {
        guard case .native(.implicit(let n, _))? = v else { return .automatic }
        switch n {
        #if os(iOS)
        case "topBarTrailing", "navigationBarTrailing": return .topBarTrailing
        case "topBarLeading", "navigationBarLeading": return .topBarLeading
        case "bottomBar": return .bottomBar
        case "keyboard": return .keyboard
        #endif
        case "principal": return .principal
        case "cancellationAction": return .cancellationAction
        case "confirmationAction": return .confirmationAction
        case "destructiveAction": return .destructiveAction
        case "primaryAction": return .primaryAction
        default: return .automatic
        }
    }

    // MARK: Shapes

    /// A shape plus the shape-preserving operations applied to it so far.
    struct ShapeChain {
        var kind: KShapeKind
        var trim: (Double, Double)? = nil
    }

    func shapeChain(_ v: KView) -> ShapeChain? {
        switch v.kind {
        case .primitive(let n, let args, let labels, _):
            if n == "UserShape" || n == "PathShape" {
                return ShapeChain(kind: .custom(customShape(n, KArgs(args: args, labels: labels))))
            }
            guard ["Circle", "Rectangle", "RoundedRectangle", "Capsule", "Ellipse", "UnevenRoundedRectangle", "ContainerRelativeShape"].contains(n) else { return nil }
            return ShapeChain(kind: KShapeKind(n, KArgs(args: args, labels: labels)))
        case .modified(let base, let m) where m.name == "trim":
            guard var chain = shapeChain(base) else { return nil }
            chain.trim = (m.arg("from")?.asDouble ?? 0, m.arg("to")?.asDouble ?? 1)
            return chain
        default:
            return nil
        }
    }

    func shapeModifier(_ chain: ShapeChain, _ m: KModifier) -> AnyView {
        var shape = chain.kind.anyShape
        if let t = chain.trim { shape = AnyShape(shape.trim(from: t.0, to: t.1)) }
        switch m.name {
        case "trim":
            let from = m.arg("from")?.asDouble ?? 0, to = m.arg("to")?.asDouble ?? 1
            return AnyView(AnyShape(shape.trim(from: from, to: to)))
        case "fill":
            if let style = shapeStyle(m.first) { return AnyView(shape.fill(style)) }
            return AnyView(shape.fill(.foreground))
        case "stroke", "strokeBorder":
            let style = shapeStyle(m.unlabeled(0)) ?? AnyShapeStyle(.foreground)
            var ss = StrokeStyle(lineWidth: m.arg("lineWidth")?.asDouble ?? 1)
            if case .native(.strokeStyle(let k))? = m.arg("style") {
                ss = StrokeStyle(lineWidth: k.lineWidth, lineCap: lineCap(k.lineCap), lineJoin: lineJoin(k.lineJoin), dash: k.dash.map { CGFloat($0) })
            }
            if m.name == "strokeBorder", chain.trim == nil { return chain.kind.strokeBorder(style, ss) }
            return AnyView(shape.stroke(style, style: ss))
        default:
            return AnyView(shape)
        }
    }

    func customShape(_ name: String, _ a: KArgs) -> AnyShape {
        if name == "PathShape", case .native(.path(let box))? = a.first { return AnyShape(box.value.path) }
        if case .structV(let s)? = a.first { return AnyShape(KUserShape(value: s, interp: interp)) }
        return AnyShape(Rectangle())
    }

    func lineCap(_ s: String) -> CGLineCap { s == "round" ? .round : (s == "square" ? .square : .butt) }
    func lineJoin(_ s: String) -> CGLineJoin { s == "round" ? .round : (s == "bevel" ? .bevel : .miter) }

    // MARK: Charts

    func chart(_ a: KArgs) -> AnyView {
        var marks: [KView] = []
        if let data = a.first, a.firstIsUnlabeled, !isFunction(data) {
            for e in (try? interp.sequence(data)) ?? [] { marks += content(a.lastFunction, [e]).flatMap(\.flattened) }
        } else {
            for v in content(a.lastFunction).flatMap(\.flattened) {
                if v.primitiveName == "ForEach", case .primitive(_, let args, let labels, _) = v.kind {
                    for row in forEachRows(KArgs(args: args, labels: labels)) { marks += row.views.flatMap(\.flattened) }
                } else {
                    marks.append(v)
                }
            }
        }
        let points = marks.compactMap { KChartPoint(view: $0, renderer: self) }
        return AnyView(KChartView(points: points))
    }
}

/// A NavigationLink(value:) payload.
struct KNavValue: Hashable {
    let value: KV
}

/// ScrollViewProxy held by reference so interpreted code can call scrollTo.
final class KScrollProxy: NSObject {
    let proxy: ScrollViewProxy
    init(_ proxy: ScrollViewProxy) { self.proxy = proxy }
}

/// Positional and labeled arguments of a view constructor.
struct KArgs {
    let args: [KV]
    let labels: [String?]

    subscript(_ label: String) -> KV? {
        if let i = labels.firstIndex(where: { $0 == label }) { return args[i] }
        return nil
    }
    var first: KV? { args.first }
    /// `labels.first == nil` would compare a `String??` and miss `[nil, …]`.
    var firstIsUnlabeled: Bool { (labels.first ?? nil) == nil }
    func unlabeled(_ n: Int) -> KV? {
        let u = zip(labels, args).filter { $0.0 == nil }.map(\.1)
        return n < u.count ? u[n] : nil
    }
    var lastFunction: KV? { args.last(where: { if case .function = $0 { return true }; return false }) }
    var firstFunction: KV? { args.first(where: { if case .function = $0 { return true }; return false }) }
    func unlabeledFunction(_ n: Int) -> KV? {
        let u = zip(labels, args).filter { $0.0 == nil }.map(\.1).filter { if case .function = $0 { return true }; return false }
        return n < u.count ? u[n] : nil
    }
}

/// The concrete shape types, so `strokeBorder` (InsettableShape only) works.
/// A Shape struct written in the interpreted code: its `path(in:)` runs there.
struct KUserShape: Shape {
    let value: KStructValue
    let interp: KInterpreter

    nonisolated func path(in rect: CGRect) -> Path {
        MainActor.assumeIsolated {
            guard let m = value.type.method("path") else { return Path(rect) }
            let ctx = KSelfContext(type: value.type, location: .box(KBox(.structV(value))))
            let r = KV.native(.rect(rect.minX, rect.minY, rect.width, rect.height))
            do {
                let result = try interp.entry { try interp.invoke(m, args: [r], labels: ["in"], selfContext: ctx, parent: interp.globalEnv) }
                if case .native(.path(let box)) = result { return box.value.path }
            } catch {
                interp.report(error)
            }
            return Path()
        }
    }
}

enum KShapeKind {
    case circle, rectangle, capsule, ellipse, container
    case custom(AnyShape)
    case rounded(Double, RoundedCornerStyle)
    case uneven(Double, Double, Double, Double)

    @MainActor
    init(_ name: String, _ a: KArgs) {
        switch name {
        case "Circle": self = .circle
        case "Capsule": self = .capsule
        case "Ellipse": self = .ellipse
        case "ContainerRelativeShape": self = .container
        case "RoundedRectangle":
            var style: RoundedCornerStyle = .circular
            if case .native(.implicit("continuous", _))? = a["style"] { style = .continuous }
            if let r = a["cornerRadius"]?.asDouble { self = .rounded(r, style) }
            else if case .native(.size(let w, _))? = a["cornerSize"] { self = .rounded(w, style) }
            else { self = .rounded(8, style) }
        case "UnevenRoundedRectangle":
            self = .uneven(a["topLeadingRadius"]?.asDouble ?? 0, a["bottomLeadingRadius"]?.asDouble ?? 0,
                           a["bottomTrailingRadius"]?.asDouble ?? 0, a["topTrailingRadius"]?.asDouble ?? 0)
        default: self = .rectangle
        }
    }

    var anyShape: AnyShape {
        switch self {
        case .circle: return AnyShape(Circle())
        case .rectangle: return AnyShape(Rectangle())
        case .capsule: return AnyShape(Capsule())
        case .ellipse: return AnyShape(Ellipse())
        case .container: return AnyShape(ContainerRelativeShape())
        case .custom(let s): return s
        case .rounded(let r, let s): return AnyShape(RoundedRectangle(cornerRadius: r, style: s))
        case .uneven(let tl, let bl, let br, let tr):
            return AnyShape(UnevenRoundedRectangle(topLeadingRadius: tl, bottomLeadingRadius: bl, bottomTrailingRadius: br, topTrailingRadius: tr))
        }
    }

    func strokeBorder(_ style: AnyShapeStyle, _ ss: StrokeStyle) -> AnyView {
        switch self {
        case .circle: return AnyView(Circle().strokeBorder(style, style: ss))
        case .capsule: return AnyView(Capsule().strokeBorder(style, style: ss))
        case .ellipse: return AnyView(Ellipse().strokeBorder(style, style: ss))
        case .rounded(let r, let s): return AnyView(RoundedRectangle(cornerRadius: r, style: s).strokeBorder(style, style: ss))
        default: return AnyView(Rectangle().strokeBorder(style, style: ss))
        }
    }
}

/// Toolbar items grouped by placement (ToolbarContent needs a static shape).
struct KToolbar: ToolbarContent {
    let groups: [String: [AnyView]]

    func items(_ key: String) -> some View {
        ForEach(Array((groups[key] ?? []).enumerated()), id: \.offset) { _, v in v }
    }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) { items("automatic") }
        ToolbarItemGroup(placement: .principal) { items("principal") }
        ToolbarItemGroup(placement: .cancellationAction) { items("cancellationAction") }
        ToolbarItemGroup(placement: .confirmationAction) { items("confirmationAction") }
        ToolbarItemGroup(placement: .destructiveAction) { items("destructiveAction") }
        ToolbarItemGroup(placement: .primaryAction) { items("primaryAction") }
        #if os(iOS)
        ToolbarItemGroup(placement: .topBarLeading) { items("topBarLeading") }
        ToolbarItemGroup(placement: .topBarTrailing) { items("topBarTrailing") }
        ToolbarItemGroup(placement: .bottomBar) { items("bottomBar") }
        #endif
    }
}

extension KV {
    /// A number as CGFloat (SwiftUI's optional CGFloat parameters).
    var cg: CGFloat? { asDouble.map { CGFloat($0) } }
}
