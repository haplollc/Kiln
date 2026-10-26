//
//  KEEngine.swift
//  Kiln engine 2
//
//  Entry points: compile a source file, find the view to show, run it, and
//  validate it headlessly. Kiln.run / Kiln.validate try this engine first and
//  fall back to the original interpreter for its guided dialect (GameCanvas,
//  onTick, Storage, …) or anything this engine can't parse.
//

import SwiftUI

@MainActor
enum KilnEngine {

    /// What to render: a view type, an App, a preview block, or bare views.
    enum Root {
        case view(KType)
        case app(KType)
        case preview([KEStmt])
        case staticPreview(KType)
        case snippet([KEStmt])
    }

    struct Compiled {
        let interp: KInterpreter
        let root: Root
    }

    enum Failure: Error {
        case syntax(String)
        case noView(String)
    }

    /// Code written for the original interpreter's guided dialect.
    static func isLegacyDialect(_ code: String) -> Bool {
        ["GameCanvas(", ".onTick(", ".onSwipe", ".dragToMove", "BarChart(", "LineChart(", "Storage.save", "Storage.load",
         "Map(latitude", "Map(markers"].contains { code.contains($0) }
    }

    static func compile(_ code: String) throws -> Compiled {
        let program: KEProgram
        do {
            program = try KEParser.parse(code)
        } catch let e as KESyntaxError {
            throw Failure.syntax(formatSyntaxError(e, code))
        }
        let interp = try KInterpreter(program: program)
        interp.consoleSink = { SwiftRunner.shared.consoleOutput = $0 }
        guard let root = findRoot(program, interp, code) else {
            let views = program.types.filter { $0.inherits.contains("View") }.map(\.name)
            if views.isEmpty {
                throw Failure.noView("No SwiftUI view found. Write a `struct ContentView: View { var body: some View { … } }`.")
            }
            throw Failure.noView("Couldn't tell which view to show among \(views.joined(separator: ", ")). Name the main one ContentView.")
        }
        return Compiled(interp: interp, root: root)
    }

    static func formatSyntaxError(_ e: KESyntaxError, _ code: String) -> String {
        let lines = code.components(separatedBy: "\n")
        var out = "Line \(e.line): \(e.message)"
        if e.line > 0, e.line <= lines.count {
            out += "\n  \(e.line) | \(lines[e.line - 1].trimmingCharacters(in: .whitespaces))"
        }
        return out
    }

    static func findRoot(_ program: KEProgram, _ interp: KInterpreter, _ code: String) -> Root? {
        if let t = interp.type(named: "ContentView"), t.isView { return .view(t) }
        if let app = program.types.first(where: { $0.inherits.contains("App") || $0.attributes.contains { $0.name == "main" } }),
           let t = interp.type(named: app.name) { return .app(t) }
        if let p = program.previews.last { return .preview(p) }
        if let pp = program.types.first(where: { $0.inherits.contains("PreviewProvider") }), let t = interp.type(named: pp.name) {
            return .staticPreview(t)
        }
        // The view no other view uses: the screen the code builds up to.
        let views = program.types.filter { $0.inherits.contains("View") && $0.kind == .structType }
        if !views.isEmpty {
            let unused = views.filter { v in
                let uses = code.components(separatedBy: v.name + "(").count - 1 + code.components(separatedBy: v.name + " {").count - 1
                return uses == 0 || (uses == 1 && code.contains("\(v.name)()") && code.contains("#Preview"))
            }
            let pick = (unused.isEmpty ? views : unused).max { a, b in
                let sa = a.properties.count + a.methods.count, sb = b.properties.count + b.methods.count
                return sa == sb ? a.line < b.line : sa < sb
            }
            if let pick, let t = interp.type(named: pick.name) { return .view(t) }
        }
        let snippet = program.globals.filter { if case .expr = $0 { return true }; if case .ifStmt = $0 { return true }; return false }
        if !snippet.isEmpty { return .snippet(program.globals) }
        return nil
    }

    // MARK: - Run

    /// nil means "use the original interpreter".
    static func run(_ code: String) -> KilnResult? {
        if isLegacyDialect(code) { return nil }
        do {
            let compiled = try compile(code)
            let view = AnyView(KRootView(compiled: compiled))
            return KilnResult(view: view, consoleOutput: compiled.interp.console, errors: [])
        } catch let f as Failure {
            switch f {
            case .syntax(let m), .noView(let m): return KilnResult(view: nil, consoleOutput: "", errors: [m])
            }
        } catch {
            return KilnResult(view: nil, consoleOutput: "", errors: ["\(error)"])
        }
    }

    // MARK: - Validate

    static func validate(_ code: String, ticks: Int, fuel: Int) -> KilnValidation? {
        if isLegacyDialect(code) { return nil }
        let compiled: Compiled
        do {
            compiled = try compile(code)
        } catch let f as Failure {
            switch f {
            case .syntax(let m), .noView(let m): return KilnValidation(errors: [m], warnings: [], renderedContent: false, hasView: false)
            }
        } catch {
            return KilnValidation(errors: ["\(error)"], warnings: [], renderedContent: false, hasView: false)
        }
        let interp = compiled.interp
        interp.budget = fuel
        let probe = KProbe(interp: interp, ticks: ticks)
        probe.run(compiled.root)
        return KilnValidation(errors: interp.errors, warnings: interp.warnings,
                              renderedContent: probe.renderedContent, hasView: true)
    }

    /// The root's view description (for the probe and the root view).
    static func rootViews(_ root: Root, _ interp: KInterpreter) throws -> [KView] {
        switch root {
        case .view(let t), .app(let t):
            let v = try interp.entry { try interp.instantiate(t, args: [], labels: [], line: 0) }
            if case .structV(let s) = v { return [.custom(s)] }
            return []
        case .preview(let stmts):
            return try interp.entry { try interp.evalBuilder(stmts, KEnv(parent: interp.globalEnv)) }
        case .staticPreview(let t):
            let v = try interp.entry { try interp.staticValue(t, "previews") }
            return KBuiltins.asViews(v, interp)
        case .snippet(let stmts):
            return try interp.entry { try interp.evalBuilder(stmts, KEnv(parent: interp.globalEnv)) }
        }
    }
}

/// Holds the interpreter for the lifetime of the shown view.
struct KRootView: View {
    let compiled: KilnEngine.Compiled
    @StateObject private var refresher = KRootRefresher()

    var body: some View {
        _ = refresher.version
        compiled.interp.onGlobalChange = { [weak refresher] in refresher?.bump() }
        return rootContent
    }

    @ViewBuilder
    private var rootContent: some View {
        switch compiled.root {
        case .app(let t), .view(let t):
            if case .structV(let s)? = try? compiled.interp.entry({ try compiled.interp.instantiate(t, args: [], labels: [], line: 0) }) {
                if t.isApp {
                    KHostView(value: s, interp: compiled.interp)
                } else {
                    KHostView(value: s, interp: compiled.interp)
                }
            } else {
                KErrorView(message: compiled.interp.errors.first ?? "Couldn't create \(t.name)")
            }
        default:
            let views = (try? KilnEngine.rootViews(compiled.root, compiled.interp)) ?? []
            KRenderer(interp: compiled.interp).render(.group(views))
        }
    }
}

@MainActor
final class KRootRefresher: ObservableObject {
    @Published var version = 0
    func bump() { version += 1 }
}

// MARK: - Probe

/// Headless validation: evaluate every view, build every row and closure, and
/// fire each action once, without mounting SwiftUI.
@MainActor
final class KProbe {
    let interp: KInterpreter
    let ticks: Int
    var renderedContent = false
    private var actions: [(KFunction, [KV])] = []
    private var visitedTypes = 0

    init(interp: KInterpreter, ticks: Int) {
        self.interp = interp
        self.ticks = ticks
    }

    static let visible: Set<String> = ["Text", "Image", "Label", "Button", "Toggle", "Slider", "Stepper", "TextField",
        "SecureField", "TextEditor", "Picker", "DatePicker", "ProgressView", "Circle", "Rectangle", "RoundedRectangle",
        "Capsule", "Ellipse", "Color", "LinearGradient", "RadialGradient", "AngularGradient", "Chart", "Gauge", "Link",
        "ContentUnavailableView", "AsyncImage", "ColorPicker", "Menu", "LabeledContent"]

    static let actionLabels: Set<String> = ["action", "perform", "onIncrement", "onDecrement", "onCommit", "onDismiss"]
    static let actionModifiers: Set<String> = ["onTapGesture", "onAppear", "task", "onChange", "onReceive", "onSubmit",
        "refreshable", "onLongPressGesture", "onDelete", "onMove", "onDisappear"]

    func run(_ root: KilnEngine.Root) {
        do {
            let views = try KilnEngine.rootViews(root, interp)
            views.forEach { walk($0, depth: 0) }
        } catch {
            interp.report(error)
        }
        // Fire every action once (onReceive timers `ticks` times).
        var fired = 0
        while !actions.isEmpty, fired < 400 {
            let (f, args) = actions.removeFirst()
            fired += 1
            do { _ = try interp.entry { try interp.call(f, args, args.map { _ in nil }) } }
            catch { interp.report(error) }
        }
    }

    func walk(_ v: KView, depth: Int) {
        guard depth < 60 else { return }
        switch v.kind {
        case .group(let vs), .conditional(_, let vs), .switchBranch(_, let vs):
            vs.forEach { walk($0, depth: depth + 1) }
        case .textConcat, .image:
            renderedContent = true
        case .custom(let s):
            visitedTypes += 1
            guard visitedTypes < 300 else { return }
            let ctx = KSelfContext(type: s.type, location: .box(KBox(.structV(s))), storage: probeStorage(s))
            let env = KEnv(parent: interp.globalEnv, selfContext: ctx)
            guard let body = s.type.computed["body"] else { return }
            do {
                let result = try interp.entry { try interp.runAccessor(body.getter ?? [], env: env, returns: body.type) }
                KBuiltins.asViews(result, interp).forEach { walk($0, depth: depth + 1) }
            } catch {
                interp.report(error)
            }
        case .primitive(let name, let args, let labels, _):
            if Self.visible.contains(name) { renderedContent = true }
            let a = KArgs(args: args, labels: labels)
            if name == "ForEach" || name == "List" && a.first.map({ if case .function = $0 { return false }; return true }) == true {
                for row in KRenderer(interp: interp).forEachRows(a) {
                    row.views.forEach { walk($0, depth: depth + 1) }
                }
                return
            }
            for (i, arg) in args.enumerated() {
                guard case .function(let f) = arg else { continue }
                let label = labels[i]
                if let l = label, Self.actionLabels.contains(l) { actions.append((f, [])); continue }
                if name == "Button", label == nil, i == 1 || (i == 0 && args.count > 1 && labels[1] == "label") {
                    actions.append((f, [])); continue
                }
                var sample: [KV] = []
                if name == "GeometryReader" { sample = [.tuple([.native(.size(393, 852))], ["size"])] }
                if name == "AsyncImage" { sample = [.native(.asyncPhase("empty", KRef(nil)))] }
                if name == "TimelineView" { sample = [.tuple([.native(.date(Date()))], ["date"])] }
                if name == "ScrollViewReader" { continue }
                do {
                    let views = try interp.entry { try interp.callBuilder(f, sample) }
                    views.forEach { walk($0, depth: depth + 1) }
                } catch {
                    interp.report(error)
                }
            }
        case .modified(let base, let m):
            walk(base, depth: depth + 1)
            if Self.actionModifiers.contains(m.name), case .function(let f)? = m.args.last {
                switch m.name {
                case "onReceive": for _ in 0..<max(1, ticks) { actions.append((f, [.native(.date(Date()))])) }
                case "onDelete": actions.append((f, [.native(.indexSet(IndexSet(integer: 0)))]))
                case "onChange":
                    let n = KRenderer(interp: interp).closureParamCount(.function(f))
                    let v = m.arg("of") ?? .nilValue
                    actions.append((f, n == 0 ? [] : (n == 1 ? [v] : [v, v])))
                default: actions.append((f, []))
                }
                return
            }
            for (i, arg) in m.args.enumerated() {
                guard case .function(let f) = arg else {
                    if case .view(let inner) = arg { walk(inner, depth: depth + 1) }
                    continue
                }
                if m.labels[i] == "item" { continue }
                do {
                    let views = try interp.entry { try interp.callBuilder(f, []) }
                    views.forEach { walk($0, depth: depth + 1) }
                } catch {
                    interp.report(error)
                }
            }
        case .empty, .error:
            break
        }
    }

    private var storages: [KViewStorage] = []

    private func probeStorage(_ s: KStructValue) -> KViewStorage {
        let storage = KViewStorage()
        storage.prepare(s, interp)
        storages.append(storage)
        return storage
    }
}
