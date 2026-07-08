//
//  KilnProbe.swift
//  Kiln
//
//  Headless render + interaction probe used by `Kiln.validate`. `Kiln.run`
//  only CONSTRUCTS a DynamicView wrapper — the real work (evaluating the body,
//  running helper functions, firing handlers) happens lazily when SwiftUI
//  mounts the view, AFTER run() returns. So a render-time crash, a blank
//  screen, or a handler that throws all pass the old `errors + hasView` check.
//
//  This probe closes that gap WITHOUT a live SwiftUI mount: it walks the parsed
//  view tree the way the renderer does, eagerly evaluates every expression the
//  renderer would (so helper functions run and their failures land in
//  `state.runtimeErrors`), fires the lifecycle + interaction handlers
//  (onAppear / onTapGesture / onTick / onSwipe / Button actions), and reports
//  whether any visible content was actually produced. The interpreter runs on a
//  bounded fuel budget (armed by the caller), so an infinite loop becomes a
//  reported error instead of a hang.
//
//  Network-driven handlers (.task / .onSubmit / .refreshable) are deliberately
//  NOT fired — they can block on a synchronous URL fetch, and games/UI (the
//  apps this validates) don't need them to prove they render.
//

import Foundation

@MainActor
enum KilnProbe {

    /// Exercise `ast` against `state` and return whether it produced visible
    /// content. Runtime problems are recorded on `state` (runtimeErrors /
    /// runtimeWarnings) as a side effect.
    static func exercise(ast: ViewNode, state: SwiftRunnerState, ticks: Int) -> Bool {
        var content = 0

        // 1) Fire onAppear first — many apps (especially games) initialize their
        //    @State here, and shapes/rows depend on it.
        fireLifecycle(ast, state: state)

        // 2) Eager render pass: evaluate what the renderer would, counting content.
        walkRender(ast, state: state, content: &content)

        // If we already blew the budget, stop — the error is recorded.
        guard !state.fuelExhausted else { return content > 0 }

        // 3) Interaction pass: tap / swipe / tick the app so input handlers run
        //    (these catch bugs that only fire on touch — e.g. a handler that
        //    reads an undefined var or divides by zero).
        fireInteractions(ast, state: state, ticks: max(0, ticks))

        // 4) Re-render after interaction so post-mutation failures surface and a
        //    game that only draws once state advances still counts as content.
        if !state.fuelExhausted {
            walkRender(ast, state: state, content: &content)
        }

        return content > 0
    }

    // MARK: - Render walk (eager expression evaluation + content detection)

    private static func walkRender(_ node: ViewNode, state: SwiftRunnerState, content: inout Int) {
        if state.fuelExhausted { return }
        switch node {
        // Containers — recurse into children.
        case .vStack(_, _, let children), .hStack(_, _, let children),
             .zStack(_, let children), .navigationStack(let children):
            for c in children { walkRender(c, state: state, content: &content) }
        case .scrollView(_, _, let inner):
            walkRender(inner, state: state, content: &content)
        case .block(let stmts):
            for s in stmts { walkRender(s, state: state, content: &content) }
        case .lazyVGrid(_, _, let inner), .lazyHGrid(_, _, let inner):
            walkRender(inner, state: state, content: &content)
        case .geometryReader(_, let body):
            walkRender(body, state: state, content: &content)

        // Modified view — walk the base, then any sub-views a modifier carries.
        case .modified(let view, let modifiers):
            walkRender(view, state: state, content: &content)
            for m in modifiers { walkModifierViews(m, state: state, content: &content) }

        // Conditionals — evaluate the condition (flushes errors) and walk both
        // branches so a fault in either surfaces.
        case .conditional(let cond, let thenBody, let elseBody):
            _ = state.evaluate(cond)
            walkRender(thenBody, state: state, content: &content)
            if let e = elseBody { walkRender(e, state: state, content: &content) }

        // ForEach — evaluate the collection, then build a bounded number of rows
        // (binding the loop var) so per-row helper failures surface without
        // materializing thousands of rows.
        case .forEachCollection(let collection, let variable, let body):
            let items = arrayValue(state.evaluate(collection))
            walkRows(items, variable: variable, body: body, state: state, content: &content)
        case .forEach(let range, let variable, let body):
            let items = range.prefix(64).map { Value.number(Double($0)) }
            walkRows(Array(items), variable: variable, body: body, state: state, content: &content)

        // GameCanvas — evaluate the shapes array (runs helper functions like
        // cells()); a non-empty result is real drawn content.
        case .gameCanvas(let shapesExpr):
            if case .array(let shapes) = state.evaluate(shapesExpr), !shapes.isEmpty {
                content += shapes.count
            }
        case .chart(_, let data):
            if !arrayValue(state.evaluate(data)).isEmpty { content += 1 }

        // Buttons — the label is visible content; the action is fired later.
        case .button(let label, _):
            walkRender(label, state: state, content: &content)

        case .navigationLink(let label, _):
            walkRender(label, state: state, content: &content)

        // Leaf views that are always visible.
        case .text(let s):
            if !s.isEmpty { content += 1 }
        case .systemImage, .assetImage, .circle, .rectangle, .roundedRectangle,
             .capsule, .divider, .toggle, .slider, .textField, .linearGradient,
             .asyncImage, .asyncImageDynamic, .asyncImagePhased:
            content += 1

        // A bare function call in a VIEW position is almost always an
        // unsupported SwiftUI container (List/Form/TabView/…): the parser turns
        // it into a no-op call and DROPS its children, so it renders blank. Flag
        // it explicitly with the supported replacement — otherwise it silently
        // vanishes (and passes if any sibling drew something).
        case .functionCall(let name, _):
            if let fix = Self.unsupportedViewFix(name) {
                state.reportError("`\(name)` isn't a supported view in Kiln, so it renders nothing. \(fix)")
            } else {
                let v = state.evaluate(node)
                if isVisibleValue(v) { content += 1 }
            }

        // Value-in-view-position (Text(score), Text(name), interpolation, etc.) —
        // evaluate; a non-empty result renders as text.
        case .variable, .binary, .propertyAccess, .subscriptAccess,
             .methodCall, .stringInterpolation, .ternary, .valueLiteral:
            let v = state.evaluate(node)
            if isVisibleValue(v) { content += 1 }

        default:
            break
        }
    }

    /// Maps a common unsupported SwiftUI container view to its Kiln replacement,
    /// or nil if `name` isn't a known-unsupported view. These parse to a dropped
    /// no-op call today, so a model gets no signal without this.
    private static func unsupportedViewFix(_ name: String) -> String? {
        switch name {
        case "List", "Form":
            return "Use a `ScrollView { ForEach(items, id: \\.self) { item in … } }` instead."
        case "Section", "Group", "GroupBox", "DisclosureGroup":
            return "Drop it and put the child views directly in a VStack."
        case "TabView":
            return "Kiln has no tabs — show one screen, or make a custom tab bar from HStack + Buttons that switch a @State selection."
        case "Picker":
            return "Use a row of Buttons (or a Menu-free custom control) that set a @State value."
        case "NavigationView":
            return "Use `NavigationStack { … }` (NavigationView isn't supported)."
        case "Menu", "DatePicker", "Stepper", "ColorPicker", "Table", "Gauge", "Grid":
            return "It's not in Kiln's view subset — rebuild this part with VStack/HStack/ZStack/ScrollView/ForEach/Button."
        default:
            return nil
        }
    }

    /// Recurse into sub-views a modifier carries (overlay, background material
    /// shape, mask, modal content, alert actions/message) so faults there surface.
    private static func walkModifierViews(_ m: ViewModifier, state: SwiftRunnerState, content: inout Int) {
        switch m {
        case .overlay(let v), .mask(let v):
            walkRender(v, state: state, content: &content)
        case .sheet(_, let v), .fullScreenCover(_, let v):
            // Modal content isn't visible until presented, so DON'T count it as
            // initial content — but do walk it to flush render-time errors.
            var ignored = 0
            walkRender(v, state: state, content: &ignored)
        case .alert(_, _, let actions, let message):
            var ignored = 0
            walkRender(actions, state: state, content: &ignored)
            if let message { walkRender(message, state: state, content: &ignored) }
        default:
            break
        }
    }

    /// Build up to 64 rows of a ForEach body, binding the loop variable each time
    /// (mirrors the renderer's eager row build so per-row helper errors surface).
    private static func walkRows(_ items: [Value], variable: String, body: ViewNode,
                                 state: SwiftRunnerState, content: inout Int) {
        for item in items.prefix(64) {
            if state.fuelExhausted { break }
            state.bindLoopVariable(variable, item)
            walkRender(body, state: state, content: &content)
        }
    }

    // MARK: - Lifecycle + interaction firing

    /// Walk the tree and run every onAppear handler (initializes @State).
    private static func fireLifecycle(_ node: ViewNode, state: SwiftRunnerState) {
        forEachModifier(node) { m in
            if case .onAppear(let action?) = m { state.runAction(action) }
        }
    }

    /// Walk the tree and fire input handlers: taps, swipes (all four directions),
    /// long-presses, ticks (run `ticks` times), and Button actions.
    private static func fireInteractions(_ node: ViewNode, state: SwiftRunnerState, ticks: Int) {
        // Button actions live on the view node, not a modifier.
        forEachButton(node) { action in
            if state.fuelExhausted { return }
            state.runAction(action)
        }
        forEachModifier(node) { m in
            if state.fuelExhausted { return }
            switch m {
            case .onTapGesture(let action), .onLongPressGesture(let action):
                state.runAction(action)
            case .onTick(_, let action):
                for _ in 0..<ticks {
                    if state.fuelExhausted { break }
                    state.runAction(action)
                }
            case .onSwipe(let closure):
                fireSwipe(closure, state: state)
            default:
                break
            }
        }
    }

    /// Invoke an onSwipe closure once per direction, binding its parameter — the
    /// same recipe KilnSwipe uses at runtime.
    private static func fireSwipe(_ closure: ViewNode, state: SwiftRunnerState) {
        for dir in ["up", "down", "left", "right"] {
            if state.fuelExhausted { break }
            if case .closure(let params, let body) = closure {
                if let p = params.first { state.renderVariables[p] = .string(dir) }
                state.runAction(body)
            } else {
                state.runAction(closure)
            }
        }
    }

    // MARK: - Generic tree traversal

    /// Call `body` for every ViewModifier anywhere in the tree.
    private static func forEachModifier(_ node: ViewNode, _ body: (ViewModifier) -> Void) {
        for child in childViews(node) { forEachModifier(child, body) }
        if case .modified(_, let mods) = node {
            for m in mods {
                body(m)
                // Descend into sub-views a modifier carries.
                for v in modifierChildViews(m) { forEachModifier(v, body) }
            }
        }
    }

    /// Call `body` with the action of every Button in the tree.
    private static func forEachButton(_ node: ViewNode, _ body: (ViewNode) -> Void) {
        if case .button(_, let action?) = node { body(action) }
        for child in childViews(node) { forEachButton(child, body) }
    }

    /// The child VIEW nodes to recurse into for traversal. Deliberately excludes
    /// expression payloads (shapes/collections/conditions) — those are handled by
    /// walkRender's evaluation, not by structural recursion.
    private static func childViews(_ node: ViewNode) -> [ViewNode] {
        switch node {
        case .vStack(_, _, let c), .hStack(_, _, let c), .zStack(_, let c),
             .navigationStack(let c):
            return c
        case .scrollView(_, _, let inner), .lazyVGrid(_, _, let inner),
             .lazyHGrid(_, _, let inner), .geometryReader(_, let inner):
            return [inner]
        case .block(let stmts):
            return stmts
        case .modified(let view, _):
            return [view]
        case .button(let label, _):
            return [label]
        case .conditional(_, let thenBody, let elseBody):
            return elseBody.map { [thenBody, $0] } ?? [thenBody]
        case .forEach(_, _, let body), .forEachCollection(_, _, let body):
            return [body]
        case .navigationLink(let label, let dest):
            return [label, dest]
        default:
            return []
        }
    }

    /// Sub-views a modifier carries (for handler discovery inside overlays/modals).
    private static func modifierChildViews(_ m: ViewModifier) -> [ViewNode] {
        switch m {
        case .overlay(let v), .mask(let v), .sheet(_, let v), .fullScreenCover(_, let v):
            return [v]
        case .alert(_, _, let actions, let message):
            return message.map { [actions, $0] } ?? [actions]
        default:
            return []
        }
    }

    // MARK: - Value helpers

    private static func arrayValue(_ v: Value) -> [Value] {
        if case .array(let a) = v { return a }
        return []
    }

    /// A value that would render as visible text (non-nil, non-empty string).
    private static func isVisibleValue(_ v: Value) -> Bool {
        switch v {
        case .nil: return false
        case .string(let s): return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return true
        }
    }
}
