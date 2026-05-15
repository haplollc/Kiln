//
//  ViewBuilder.swift
//  SwiftRunner
//
//  Created by Claw on 2/21/26.
//

import SwiftUI

/// Renders ViewNode AST to SwiftUI views
@MainActor
public struct DynamicViewBuilder {
    
    /// Build a SwiftUI view from a ViewNode (backward-compatible, no state)
    public static func build(_ node: ViewNode) -> AnyView {
        buildNode(node, state: nil)
    }

    /// Build a SwiftUI view from a ViewNode with reactive state
    public static func build(_ node: ViewNode, state: SwiftRunnerState) -> AnyView {
        buildNode(node, state: state)
    }

    // MARK: - Core Builder

    static func buildNode(_ node: ViewNode, state: SwiftRunnerState?) -> AnyView {
        switch node {
        case .text(let content):
            return AnyView(Text(content))

        case .systemImage(let name):
            return AnyView(Image(systemName: name))

        case .assetImage(let name):
            return AnyView(Image(name))

        case .button(let label, let action):
            return AnyView(
                Button(action: {
                    if let action = action, let state = state {
                        state.execute(action)
                    }
                }) {
                    buildNode(label, state: state)
                }
            )

        case .vStack(let spacing, let alignment, let children):
            return AnyView(
                VStack(alignment: mapAlignment(alignment), spacing: spacing.map { CGFloat($0) }) {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        buildNode(child, state: state)
                    }
                }
            )

        case .hStack(let spacing, let alignment, let children):
            return AnyView(
                HStack(alignment: mapVerticalAlignment(alignment), spacing: spacing.map { CGFloat($0) }) {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        buildNode(child, state: state)
                    }
                }
            )

        case .zStack(let alignment, let children):
            return AnyView(
                ZStack(alignment: mapZAlignment(alignment)) {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        buildNode(child, state: state)
                    }
                }
            )

        case .scrollView(let axis, let showsIndicators, let content):
            let indicators = showsIndicators ?? true
            if axis == .horizontal {
                return AnyView(ScrollView(.horizontal, showsIndicators: indicators) { buildNode(content, state: state) })
            }
            return AnyView(ScrollView(.vertical, showsIndicators: indicators) { buildNode(content, state: state) })

        case .navigationStack(let children):
            // Real SwiftUI NavigationStack so child NavigationLinks push
            // destinations and `.navigationTitle` shows in the bar.
            return AnyView(
                NavigationStack {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        buildNode(child, state: state)
                    }
                }
            )

        case .navigationLink(let label, let destination):
            // Build the LABEL eagerly so each cell's row contents reflect the
            // current ForEach iteration's binding. Snapshot the per-cell
            // `renderVariables` (the ForEach loop variable like `book`) so we
            // can restore it just before the destination is realized.
            //
            // Build the DESTINATION inside SwiftUI's closure so it is
            // re-evaluated whenever state changes — without this, async
            // mutations made by the destination's own `.task` (like setting
            // `work` after fetching) wouldn't surface in the view because
            // the destination's view tree was frozen at the moment the row
            // was constructed (when `work` was still nil). The snapshot
            // restore happens at realization time, so the captured cell
            // binding survives long after the outer ForEach has moved on.
            let labelView = buildNode(label, state: state)
            let cellSnapshot: [String: Value] = state?.renderVariables ?? [:]
            return AnyView(
                NavigationLink {
                    NavigationDestinationView(
                        node: destination,
                        snapshot: cellSnapshot,
                        state: state
                    )
                } label: {
                    labelView
                }
            )

        case .circle: return AnyView(Circle())
        case .rectangle: return AnyView(Rectangle())
        case .roundedRectangle(let cornerRadius): return AnyView(RoundedRectangle(cornerRadius: cornerRadius))
        case .capsule: return AnyView(Capsule())

        case .spacer(let minLength):
            if let minLength = minLength {
                return AnyView(Spacer(minLength: minLength))
            }
            return AnyView(Spacer())

        case .divider:
            return AnyView(Divider())

        case .forEach(let range, let variable, let body):
            return AnyView(
                ForEach(Array(range), id: \.self) { index in
                    let _ = {
                        guard let state = state else { return }
                        let value: Value = .number(Double(index))
                        if variable != "_" { state.renderVariables[variable] = value }
                        // Always bind `$0` so closures written without an
                        // explicit `index in` parameter still work.
                        state.renderVariables["0"] = value
                    }()
                    buildNode(body, state: state)
                }
            )

        case .forEachCollection(let collection, let variable, let body):
            if let state = state {
                let collectionValue = state.evaluate(collection)
                if case .array(let items) = collectionValue {
                    return AnyView(
                        ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                            let _ = {
                                if variable != "_" { state.renderVariables[variable] = item }
                                // Always bind `$0` (current item) and `$1`
                                // (current index) so closures without an
                                // explicit `item in` parameter still work.
                                // This is what `ForEach(books) { BookCard(book: $0) }`
                                // relies on.
                                state.renderVariables["0"] = item
                                state.renderVariables["1"] = .number(Double(offset))
                            }()
                            buildNode(body, state: state)
                        }
                    )
                }
            }
            return AnyView(EmptyView())

        case .textField(let placeholder, let variable, let isSecure):
            if let state = state, !variable.isEmpty {
                let binding = Binding<String>(
                    get: { state.variables[variable]?.description ?? "" },
                    set: { state.variables[variable] = .string($0) }
                )
                if isSecure {
                    return AnyView(SecureField(placeholder, text: binding))
                }
                return AnyView(TextField(placeholder, text: binding))
            }
            if isSecure {
                return AnyView(SecureField(placeholder, text: .constant("")))
            }
            return AnyView(TextField(placeholder, text: .constant("")))

        case .toggle(let label, let variable):
            if let state = state, !variable.isEmpty {
                return AnyView(Toggle(label, isOn: boolBinding(for: variable, state: state)))
            }
            return AnyView(Toggle(label, isOn: .constant(false)))

        case .slider(let variable, let range):
            if let state = state, !variable.isEmpty {
                let binding = Binding<Double>(
                    get: {
                        if case .number(let n) = state.variables[variable] { return n }
                        return 0
                    },
                    set: { state.variables[variable] = .number($0) }
                )
                if let range = range {
                    return AnyView(Slider(value: binding, in: range))
                }
                return AnyView(Slider(value: binding))
            }
            return AnyView(Slider(value: .constant(0.5)))

        case .asyncImage(let urlString):
            if let url = URL(string: urlString) {
                return AnyView(
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .failure:
                            Image(systemName: "photo.badge.exclamationmark")
                                .foregroundColor(.secondary)
                        case .empty:
                            ProgressView()
                        @unknown default:
                            ProgressView()
                        }
                    }
                )
            }
            return AnyView(Image(systemName: "photo").foregroundColor(.secondary))

        case .asyncImageDynamic(let urlExpression):
            let urlString: String = {
                guard let state = state else { return "" }
                let value = state.evaluate(urlExpression)
                return value.description
            }()
            if let url = URL(string: urlString), !urlString.isEmpty {
                return AnyView(
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .failure:
                            Image(systemName: "photo.badge.exclamationmark")
                                .foregroundColor(.secondary)
                        case .empty:
                            ProgressView()
                        @unknown default:
                            ProgressView()
                        }
                    }
                )
            }
            return AnyView(Image(systemName: "photo").foregroundColor(.secondary))

        case .binding:
            return AnyView(EmptyView()) // binding refs aren't views

        case .modified(let view, let modifiers):
            return buildModified(view: view, modifiers: modifiers, state: state)

        case .block(let statements):
            let meaningful = statements.filter { if case .empty = $0 { return false }; return true }

            // Freeze assignment RHS values NOW (at view construction time) so
            // they survive intact when this block is later realized — possibly
            // after the outer scope has moved on (next ForEach iteration) or
            // vanished entirely (NavigationLink destination realized on tap,
            // by which point the outer ForEach has long since finished and
            // `renderVariables["book"]` points at the last iteration's value).
            //
            // Each assignment node is rewritten with a `.valueLiteral` payload
            // holding the captured `Value`. When the assignment later runs
            // inside the inner ForEach below, it commits that frozen value
            // to `state.renderVariables`, restoring this block's per-instance
            // scope right before its sibling view statements read from it.
            //
            // This is what makes `NavigationLink(destination: BookDetailPage(book: book))`
            // inside `ForEach(books) { book in ... }` actually navigate to the
            // tapped book rather than to whichever book the loop ended on.
            var rewritten: [ViewNode] = []
            if let state = state {
                for stmt in meaningful {
                    if case .assignment(let name, let isVar, let value) = stmt {
                        let frozen = state.evaluate(value)
                        rewritten.append(.assignment(
                            name: name,
                            isVar: isVar,
                            value: .valueLiteral(frozen)
                        ))
                        // Also commit to renderVariables now, so any callers
                        // that read from state before the inner ForEach has
                        // run (e.g. computed-view-body lookups during sibling
                        // construction) still see the per-instance binding.
                        state.renderVariables[name] = frozen
                    } else {
                        rewritten.append(stmt)
                    }
                }
            } else {
                rewritten = meaningful
            }

            if rewritten.isEmpty { return AnyView(EmptyView()) }
            if rewritten.count == 1 { return buildNode(rewritten[0], state: state) }
            return AnyView(
                VStack(spacing: 0) {
                    ForEach(Array(rewritten.enumerated()), id: \.offset) { _, stmt in
                        buildNode(stmt, state: state)
                    }
                }
            )

        case .stringInterpolation(let parts):
            if let state = state {
                return AnyView(Text(state.resolveInterpolation(parts)))
            }
            // Fallback: static resolution
            let resolved = parts.map { part -> String in
                switch part {
                case .literal(let text): return text
                case .expression(let expr):
                    if case .variable(let name) = expr { return name }
                    if case .literal(.string(let s)) = expr { return s }
                    if case .literal(.number(let n)) = expr {
                        return n == floor(n) ? String(Int(n)) : String(n)
                    }
                    return "?"
                }
            }.joined()
            return AnyView(Text(resolved))

        case .literal(let value):
            switch value {
            case .string(let s): return AnyView(Text(s))
            case .number(let n): return AnyView(Text("\(n)"))
            case .boolean(let b): return AnyView(Text(b ? "true" : "false"))
            case .color(let c): return AnyView(mapColorValue(c).frame(maxWidth: .infinity, maxHeight: .infinity))
            case .nil: return AnyView(EmptyView())
            }

        case .ternary(let condition, let trueExpr, let falseExpr):
            if let state = state {
                let condVal = state.evaluate(condition)
                return condVal.isTruthy ? buildNode(trueExpr, state: state) : buildNode(falseExpr, state: state)
            }
            return buildNode(trueExpr, state: state)

        case .conditional(let condition, let thenBody, let elseBody):
            if let state = state {
                let condVal = state.evaluate(condition)
                if condVal.isTruthy {
                    return buildNode(thenBody, state: state)
                } else if let elseBody = elseBody {
                    return buildNode(elseBody, state: state)
                } else {
                    return AnyView(EmptyView())
                }
            }
            return buildNode(thenBody, state: state)

        case .compoundAssignment:
            return AnyView(EmptyView())

        case .functionCall(let name, let arguments):
            // Dynamic Image(systemName: ternary/variable)
            if name == "Image_systemName", let arg = arguments.first {
                if let state = state {
                    let resolved = state.evaluate(arg.value)
                    return AnyView(Image(systemName: resolved.description))
                }
                return AnyView(Image(systemName: "photo"))
            }
            // Handle known view function calls that aren't in the enum
            if name == "ProgressView" {
                if let valArg = arguments.first(where: { $0.label == "value" }),
                   case .literal(.number(let val)) = valArg.value {
                    let total = arguments.first(where: { $0.label == "total" })
                        .flatMap { if case .literal(.number(let t)) = $0.value { return t }; return nil as Double? } ?? 1.0
                    return AnyView(ProgressView(value: val, total: total))
                }
                if let first = arguments.first, first.label == nil,
                   case .literal(.string(let label)) = first.value {
                    return AnyView(ProgressView(label))
                }
                return AnyView(ProgressView())
            }
            return AnyView(EmptyView())

        case .assignment(let name, _, let value):
            // Evaluate at render time (used for custom view arguments).
            // Use renderVariables to avoid triggering @Published re-render loops.
            if let state = state {
                state.renderVariables[name] = state.evaluate(value)
            }
            return AnyView(EmptyView())

        case .stateInit(let name, let value):
            // @State-style init-once: only commit the default if neither store
            // already has a value for this name. Subsequent realizations of
            // the same inlined view leave the user's mutations intact.
            if let state = state,
               state.variables[name] == nil,
               state.renderVariables[name] == nil {
                state.variables[name] = state.evaluate(value)
            }
            return AnyView(EmptyView())

        case .variable(let name):
            // A bare identifier referenced as a view (e.g. `header` / `content`
            // in `VStack { header; content }`) — look up a computed `some View`
            // property on the enclosing struct. If the function table has a
            // unique `*.name` zero-arg match, render its body.
            if let state = state,
               let bodyNode = computedViewBody(named: name, state: state) {
                return buildNode(bodyNode, state: state)
            }
            return AnyView(EmptyView())
        case .empty, .binary, .propertyAccess, .arrayLiteral, .subscriptAccess, .methodCall, .valueLiteral:
            return AnyView(EmptyView())
        // Note: .stateInit is a render-time side-effect node, handled above.

        // MARK: Plan 1/2 — declaration/statement nodes don't render by themselves.
        // They produce side effects (registering types, executing stmts) or are
        // handled by their enclosing scope. In the renderer they just vanish.
        case .switchStmt, .doCatch, .throwStmt, .guardLet, .guardExpr,
             .deferBlock, .enumDeclaration, .extensionDeclaration,
             .functionDecl, .returnStmt, .tupleBinding, .propertyAssignment,
             .closure:
            return AnyView(EmptyView())

        // MARK: Plan 6 — layout containers
        case .lazyVGrid(let columns, let spacing, let content):
            return AnyView(buildLazyVGrid(columns: columns, spacing: spacing, content: content, state: state))
        case .lazyHGrid(let rows, let spacing, let content):
            return AnyView(buildLazyHGrid(rows: rows, spacing: spacing, content: content, state: state))
        case .gridItem:
            // GridItem values are consumed by LazyVGrid/LazyHGrid — stand-alone they render nothing.
            return AnyView(EmptyView())
        case .geometryReader(let varName, let body):
            return AnyView(
                GeometryReader { geo in
                    let _ = state.map { s in
                        s.renderVariables[varName] = .object([
                            "size": .object([
                                "width":  .number(Double(geo.size.width)),
                                "height": .number(Double(geo.size.height)),
                            ]),
                        ])
                    }
                    buildNode(body, state: state)
                }
            )
        case .linearGradient(let colors, let startPoint, let endPoint):
            return AnyView(
                LinearGradient(
                    colors: colors.map { mapColorValue($0) },
                    startPoint: mapUnitPoint(startPoint),
                    endPoint: mapUnitPoint(endPoint)
                )
            )

        // MARK: Plan 8 — phased AsyncImage
        case .asyncImagePhased(let urlExpression, let emptyBranch, let successBranch, let failureBranch, let imageBinding):
            return AnyView(buildPhasedAsyncImage(
                urlExpression: urlExpression,
                emptyBranch: emptyBranch,
                successBranch: successBranch,
                failureBranch: failureBranch,
                imageBinding: imageBinding,
                state: state
            ))
        }
    }

    // MARK: - Plan 6 helpers

    private static func buildLazyVGrid(columns: [ViewNode], spacing: Double?, content: ViewNode, state: SwiftRunnerState?) -> some View {
        let gridItems = columns.compactMap { mapGridItem($0) }
        let children: [ViewNode]
        if case .block(let stmts) = content { children = stmts }
        else { children = [content] }
        return LazyVGrid(columns: gridItems.isEmpty ? [GridItem(.flexible())] : gridItems,
                         spacing: spacing.map { CGFloat($0) }) {
            ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                buildNode(child, state: state)
            }
        }
    }

    private static func buildLazyHGrid(rows: [ViewNode], spacing: Double?, content: ViewNode, state: SwiftRunnerState?) -> some View {
        let gridItems = rows.compactMap { mapGridItem($0) }
        let children: [ViewNode]
        if case .block(let stmts) = content { children = stmts }
        else { children = [content] }
        return LazyHGrid(rows: gridItems.isEmpty ? [GridItem(.flexible())] : gridItems,
                        spacing: spacing.map { CGFloat($0) }) {
            ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                buildNode(child, state: state)
            }
        }
    }

    private static func mapGridItem(_ node: ViewNode) -> GridItem? {
        guard case .gridItem(let style) = node else { return nil }
        switch style {
        case .adaptive(let minimum, let maximum):
            let max = maximum.map { CGFloat($0) } ?? .infinity
            return GridItem(.adaptive(minimum: CGFloat(minimum), maximum: max))
        case .fixed(let n):
            return GridItem(.fixed(CGFloat(n)))
        case .flexible:
            return GridItem(.flexible())
        }
    }

    private static func mapUnitPoint(_ point: UnitPoint) -> SwiftUI.UnitPoint {
        switch point {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        case .center: return .center
        }
    }

    // MARK: - Plan 8 helpers

    private static func buildPhasedAsyncImage(
        urlExpression: ViewNode,
        emptyBranch: ViewNode?,
        successBranch: ViewNode?,
        failureBranch: ViewNode?,
        imageBinding: String?,
        state: SwiftRunnerState?
    ) -> some View {
        let urlString: String = {
            guard let s = state else { return "" }
            let value = s.evaluate(urlExpression)
            if case .object(let d) = value, case .string(let u) = d["string"] ?? .nil { return u }
            return value.description
        }()
        let url = URL(string: urlString)

        return AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                if let branch = emptyBranch {
                    buildNode(branch, state: state)
                } else {
                    AnyView(ProgressView())
                }
            case .success(let image):
                if let branch = successBranch {
                    // If the success branch references the image binding (e.g.
                    // `image.resizable()`), we render the actual SwiftUI Image.
                    // For richer in-branch modifier application, Plan 8's follow-up
                    // work would inject the image into the interpreter scope.
                    buildPhasedSuccess(branch: branch, image: image, binding: imageBinding, state: state)
                } else {
                    AnyView(image.resizable().aspectRatio(contentMode: .fit))
                }
            case .failure:
                if let branch = failureBranch {
                    buildNode(branch, state: state)
                } else {
                    AnyView(Image(systemName: "photo").foregroundStyle(.gray))
                }
            @unknown default:
                AnyView(EmptyView())
            }
        }
    }

    /// Render the success branch. If the branch is `.variable(imageBinding)` or
    /// a modifier chain starting at that binding, splice in the real SwiftUI
    /// Image. Otherwise fall back to rendering the branch as interpreted,
    /// ignoring the image reference.
    private static func buildPhasedSuccess(branch: ViewNode, image: Image, binding: String?, state: SwiftRunnerState?) -> AnyView {
        // Common patterns:
        //   image                       → just the image
        //   image.resizable()           → modifier chain on image
        //   image.resizable()...clipShape(...) → modifier chain
        // We walk a chain of `.modified` wrapping `.variable(binding)` and apply
        // the modifiers to the SwiftUI Image directly.
        if let binding = binding {
            if let rendered = applyModifiersToImage(branch: branch, binding: binding, image: image, state: state) {
                return rendered
            }
        }
        return AnyView(buildNode(branch, state: state))
    }

    private static func applyModifiersToImage(branch: ViewNode, binding: String, image: Image, state: SwiftRunnerState?) -> AnyView? {
        // Walk the modifier chain inside-out, collecting modifiers in
        // application order (innermost first). The chain
        //   image.resizable().aspectRatio(.fit).clipShape(rounded)
        // parses as
        //   .modified(.modified(.modified(.variable("image"), [.resizable]),
        //                       [.aspectRatio]),
        //             [.clipShape])
        // so we walk OUTSIDE→INSIDE and prepend to keep semantic order.
        var modifiers: [ViewModifier] = []
        var node = branch
        while case .modified(let inner, let mods) = node {
            modifiers.insert(contentsOf: mods, at: 0)
            node = inner
        }
        guard case .variable(let name) = node, name == binding else { return nil }

        // Apply `.resizable()` directly on the SwiftUI Image (it returns Image,
        // and many subsequent modifiers like .aspectRatio rely on the resized
        // image), then apply the remaining modifiers via the per-modifier
        // helper used everywhere else in the renderer. The previous
        // implementation built `.empty.overlay(innerView)` which gave a
        // zero-size container and caused the loaded cover image to be
        // invisible.
        let hasResizable = modifiers.contains {
            if case .resizable = $0 { return true } else { return false }
        }
        var view: AnyView = hasResizable ? AnyView(image.resizable()) : AnyView(image)
        for mod in modifiers {
            if case .resizable = mod { continue }
            view = applyModifier(to: view, modifier: mod, state: state)
        }
        return view
    }

    private static func buildModified(view: ViewNode, modifiers: [ViewModifier], state: SwiftRunnerState?) -> AnyView {
        // Plan 5 capstone: if the modifier list contains `.userModifier(typeName)`,
        // expand each one by substituting `content` references inside the user-defined
        // `<typeName>.body(content:)` with the receiver ViewNode. This unfolds
        // ViewModifier-based effects (like `Shimmer`) into a concrete ViewNode tree
        // the regular renderer can handle.
        if modifiers.contains(where: { if case .userModifier = $0 { return true } else { return false } }) {
            var currentNode: ViewNode = view
            var pending: [ViewModifier] = []
            for mod in modifiers {
                if case .userModifier(let typeName) = mod {
                    if !pending.isEmpty {
                        currentNode = .modified(view: currentNode, modifiers: pending)
                        pending = []
                    }
                    if let state = state,
                       let decl = state.functions["\(typeName).body"],
                       case .functionDecl(_, let params, let body, _, _) = decl {
                        let contentName = params.first?.internalName ?? "content"
                        currentNode = substituteContent(in: body, name: contentName, with: currentNode)
                    }
                    // If the function isn't registered (e.g. SwiftUI's own modifiers
                    // used with `.modifier(SomeSystemModifier())`), drop the modifier.
                } else {
                    pending.append(mod)
                }
            }
            if !pending.isEmpty {
                currentNode = .modified(view: currentNode, modifiers: pending)
            }
            return buildNode(currentNode, state: state)
        }

        // Handle shape fill/stroke and image resizable BEFORE type-erasing,
        // since these require knowledge of the concrete type.
        var fillColor = modifiers.compactMap { if case .fill(let c) = $0 { return c }; return nil as ColorValue? }.first
        // Check for dynamic fill (ternary color expression)
        if fillColor == nil, let state = state {
            if let dynamicFill = modifiers.compactMap({ if case .dynamic(let n, let arg) = $0, n == "fill" { return arg }; return nil as ViewNode? }).first {
                let value = state.evaluate(dynamicFill)
                if case .string(let colorName) = value, let c = ColorValue(rawValue: colorName) {
                    fillColor = c
                }
            }
        }
        let strokeInfo = modifiers.compactMap { if case .stroke(let c, let w) = $0 { return (c, w) }; return nil as (ColorValue, Double)? }.first
        let strokeBorderInfo = modifiers.compactMap { if case .strokeBorder(let c, let w) = $0 { return (c, w) }; return nil as (ColorValue, Double)? }.first
        let trimInfo = modifiers.compactMap { if case .trim(let from, let to) = $0 { return (from, to) }; return nil as (Double, Double)? }.first
        let hasResizable = modifiers.contains { if case .resizable = $0 { return true }; return false }
        let hasScaledToFit = modifiers.contains { if case .scaledToFit = $0 { return true }; return false }
        let hasScaledToFill = modifiers.contains { if case .scaledToFill = $0 { return true }; return false }
        let hasShapeMod = fillColor != nil || strokeInfo != nil || strokeBorderInfo != nil || trimInfo != nil

        var currentView: AnyView

        // Build shapes with fill/stroke/trim applied at the concrete type level
        if hasShapeMod {
            currentView = buildShapeView(view, fill: fillColor, stroke: strokeInfo,
                                         strokeBorder: strokeBorderInfo, trim: trimInfo)
        } else if hasResizable {
            currentView = buildResizableImage(view, fit: hasScaledToFit, fill: hasScaledToFill)
        } else {
            currentView = buildNode(view, state: state)
        }

        // Apply remaining modifiers, skipping ones already handled above
        for modifier in modifiers {
            switch modifier {
            case .fill, .stroke, .strokeBorder, .trim, .resizable, .scaledToFit, .scaledToFill:
                if hasShapeMod || hasResizable { continue }
            case .userModifier:
                // Handled by the pre-pass at the top of buildModified.
                continue
            case .dynamic(let n, _) where n == "fill":
                if hasShapeMod { continue }
                fallthrough
            default:
                currentView = applyModifier(to: currentView, modifier: modifier, state: state)
            }
        }
        return currentView
    }

    /// Plan 7: apply a material background, optionally clipped to a shape.
    private static func applyMaterialBackground(view: AnyView, material: MaterialValue, shape: ShapeType?) -> AnyView {
        let m: Material = {
            switch material {
            case .ultraThin:  return .ultraThinMaterial
            case .thin:       return .thinMaterial
            case .regular:    return .regularMaterial
            case .thick:      return .thickMaterial
            case .ultraThick: return .ultraThickMaterial
            case .bar:        return .bar
            }
        }()
        if let shape = shape {
            switch shape {
            case .circle:
                return AnyView(view.background(m, in: Circle()))
            case .rectangle:
                return AnyView(view.background(m, in: Rectangle()))
            case .capsule:
                return AnyView(view.background(m, in: Capsule()))
            case .roundedRectangle(let cornerRadius):
                return AnyView(view.background(m, in: RoundedRectangle(cornerRadius: cornerRadius)))
            }
        }
        return AnyView(view.background(m))
    }

    /// Look up a computed `some View` property by name. Returns the body ViewNode
    /// if there's a unique zero-arg `*.name` match in the function table.
    private static func computedViewBody(named name: String, state: SwiftRunnerState) -> ViewNode? {
        // Direct match first (rare for views, but cheap).
        if let decl = state.functions[name],
           case .functionDecl(_, let params, let body, _, _) = decl, params.isEmpty {
            return body
        }
        let suffix = ".\(name)"
        let matches = state.functions.keys.filter { $0.hasSuffix(suffix) }
        guard matches.count == 1, let decl = state.functions[matches[0]] else { return nil }
        if case .functionDecl(_, let params, let body, _, _) = decl, params.isEmpty {
            return body
        }
        return nil
    }

    /// Recursively substitute every `.variable(name)` inside `node` with `replacement`.
    /// Used by `.userModifier(...)` expansion so `content` references in the user's
    /// ViewModifier body become the actual receiver view node.
    private static func substituteContent(in node: ViewNode, name: String, with replacement: ViewNode) -> ViewNode {
        func s(_ n: ViewNode) -> ViewNode { substituteContent(in: n, name: name, with: replacement) }
        switch node {
        case .variable(let n) where n == name:
            return replacement
        case .modified(let v, let mods):
            return .modified(view: s(v), modifiers: mods)
        case .block(let stmts):
            return .block(stmts.map(s))
        case .vStack(let sp, let al, let children):
            return .vStack(spacing: sp, alignment: al, children: children.map(s))
        case .hStack(let sp, let al, let children):
            return .hStack(spacing: sp, alignment: al, children: children.map(s))
        case .zStack(let al, let children):
            return .zStack(alignment: al, children: children.map(s))
        case .scrollView(let axis, let ind, let content):
            return .scrollView(axis: axis, showsIndicators: ind, content: s(content))
        case .conditional(let cond, let thenBody, let elseBody):
            return .conditional(condition: cond, thenBody: s(thenBody), elseBody: elseBody.map(s))
        case .methodCall(let obj, let method, let args):
            return .methodCall(object: s(obj), method: method, arguments: args)
        case .propertyAccess(let obj, let prop):
            return .propertyAccess(object: s(obj), property: prop)
        case .functionCall(let name, let args):
            let newArgs = args.map { Argument(label: $0.label, value: s($0.value)) }
            return .functionCall(name: name, arguments: newArgs)
        case .lazyVGrid(let cols, let sp, let content):
            return .lazyVGrid(columns: cols, spacing: sp, content: s(content))
        case .lazyHGrid(let rows, let sp, let content):
            return .lazyHGrid(rows: rows, spacing: sp, content: s(content))
        case .forEach(let range, let v, let body):
            return .forEach(range: range, variable: v, body: s(body))
        case .forEachCollection(let coll, let v, let body):
            return .forEachCollection(collection: coll, variable: v, body: s(body))
        default:
            return node
        }
    }

    /// Build a shape with fill/stroke/strokeBorder/trim applied at the concrete type level.
    private static func buildShapeView(
        _ view: ViewNode,
        fill: ColorValue?,
        stroke: (ColorValue, Double)?,
        strokeBorder: (ColorValue, Double)? = nil,
        trim: (Double, Double)? = nil
    ) -> AnyView {
        let fc: Color? = fill.map { mapColorValue($0) }
        let sc: (Color, Double)? = stroke.map { (mapColorValue($0.0), $0.1) }
        let sbc: (Color, Double)? = strokeBorder.map { (mapColorValue($0.0), $0.1) }

        // Helper to apply modifiers to a shape
        func applyToShape<S: InsettableShape>(_ shape: S) -> AnyView {
            if let (from, to) = trim {
                let trimmed = shape.trim(from: from, to: to)
                if let (sc, sw) = sc { return AnyView(trimmed.stroke(sc, lineWidth: sw)) }
                if let fc = fc { return AnyView(trimmed.fill(fc)) }
                return AnyView(trimmed.stroke(Color.primary, lineWidth: 1))
            }
            if let fc = fc, let (sc, sw) = sc {
                return AnyView(shape.fill(fc).overlay(shape.stroke(sc, lineWidth: sw)))
            }
            if let fc = fc { return AnyView(shape.fill(fc)) }
            if let (sc, sw) = sc { return AnyView(shape.stroke(sc, lineWidth: sw)) }
            if let (sbc, sw) = sbc { return AnyView(shape.strokeBorder(sbc, lineWidth: sw)) }
            return AnyView(shape)
        }

        switch view {
        case .circle: return applyToShape(Circle())
        case .rectangle: return applyToShape(Rectangle())
        case .roundedRectangle(let r): return applyToShape(RoundedRectangle(cornerRadius: r))
        case .capsule: return applyToShape(Capsule())
        default:
            if let fc = fc { return AnyView(fc) }
            return AnyView(EmptyView())
        }
    }

    /// Build an Image with .resizable() and optional scaling applied at the concrete type level.
    private static func buildResizableImage(_ view: ViewNode, fit: Bool, fill: Bool) -> AnyView {
        switch view {
        case .systemImage(let name):
            let img = Image(systemName: name).resizable()
            if fit { return AnyView(img.scaledToFit()) }
            if fill { return AnyView(img.scaledToFill()) }
            return AnyView(img)
        case .assetImage(let name):
            let img = Image(name).resizable()
            if fit { return AnyView(img.scaledToFit()) }
            if fill { return AnyView(img.scaledToFill()) }
            return AnyView(img)
        default:
            return AnyView(EmptyView())
        }
    }

    private static func applyModifier(to view: AnyView, modifier: ViewModifier, state: SwiftRunnerState?) -> AnyView {
        switch modifier {
        case .font(let style):
            return AnyView(view.font(mapFont(style)))
        case .fontWeight(let weight):
            return AnyView(view.fontWeight(mapFontWeight(weight)))
        case .foregroundColor(let color):
            return AnyView(view.foregroundColor(mapColorValue(color)))
        case .foregroundStyle(let color):
            return AnyView(view.foregroundStyle(mapColorValue(color)))
        case .padding(let insets):
            return AnyView(view.padding(SwiftUI.EdgeInsets(
                top: insets.top, leading: insets.leading,
                bottom: insets.bottom, trailing: insets.trailing
            )))
        case .frame(let width, let height, let maxWidth, let maxHeight, _):
            if maxWidth != nil || maxHeight != nil {
                return AnyView(view.frame(
                    minWidth: nil, idealWidth: nil,
                    maxWidth: maxWidth.map { CGFloat($0) },
                    minHeight: nil, idealHeight: nil,
                    maxHeight: maxHeight.map { CGFloat($0) }
                ))
            }
            return AnyView(view.frame(
                width: width.map { CGFloat($0) },
                height: height.map { CGFloat($0) }
            ))
        case .dynamicFrame(let widthExpr, let heightExpr, let maxWidthExpr, let maxHeightExpr):
            // Evaluate each dimension expression at render time. Variables
            // captured from the struct's `let coverWidth: CGFloat = 56`
            // resolve via state.variables; literal-wrapped dims behave as
            // they would in the static `.frame` branch.
            func resolve(_ expr: ViewNode?) -> CGFloat? {
                guard let e = expr, let s = state else { return nil }
                let v = s.evaluate(e)
                if case .number(let n) = v { return CGFloat(n) }
                if case .string("infinity") = v { return .infinity }
                return nil
            }
            let w = resolve(widthExpr)
            let h = resolve(heightExpr)
            let mw = resolve(maxWidthExpr)
            let mh = resolve(maxHeightExpr)
            if mw != nil || mh != nil {
                return AnyView(view.frame(
                    minWidth: nil, idealWidth: nil, maxWidth: mw,
                    minHeight: nil, idealHeight: nil, maxHeight: mh
                ))
            }
            return AnyView(view.frame(width: w, height: h))
        case .background(let color):
            return AnyView(view.background(mapColorValue(color)))
        case .cornerRadius(let radius):
            return AnyView(view.cornerRadius(radius))
        case .clipShape(let shape):
            return applyClipShape(to: view, shape: shape)
        case .opacity(let value):
            return AnyView(view.opacity(value))
        case .shadow(let radius, let x, let y):
            return AnyView(view.shadow(radius: radius, x: x, y: y))
        case .overlay(let overlayNode):
            return AnyView(view.overlay(buildNode(overlayNode, state: state)))
        case .border(let color, let width):
            return AnyView(view.border(mapColorValue(color), width: width))
        case .fixedSize(let horizontal, let vertical):
            return AnyView(view.fixedSize(horizontal: horizontal, vertical: vertical))
        case .aspectRatio(let ratio, let mode):
            return AnyView(view.aspectRatio(
                ratio.map { CGFloat($0) },
                contentMode: mode == .fit ? .fit : .fill
            ))
        case .onTapGesture(let action):
            if let state = state {
                return AnyView(view.onTapGesture { state.execute(action) })
            }
            return AnyView(view.onTapGesture {})
        case .disabled(let isDisabled):
            return AnyView(view.disabled(isDisabled))
        case .bold:
            return AnyView(view.bold())
        case .italic:
            return AnyView(view.italic())
        case .lineLimit(let n):
            return AnyView(view.lineLimit(n))
        case .multilineTextAlignment(let alignment):
            switch alignment {
            case .leading: return AnyView(view.multilineTextAlignment(.leading))
            case .center: return AnyView(view.multilineTextAlignment(.center))
            case .trailing: return AnyView(view.multilineTextAlignment(.trailing))
            }
        case .fill(let color):
            return AnyView(mapColorValue(color))
        case .stroke(let color, let lineWidth):
            return AnyView(view.overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(mapColorValue(color), lineWidth: lineWidth)
            ))
        case .clipped:
            return AnyView(view.clipped())
        case .resizable:
            // resizable() only works on Image — return view as-is for non-images
            return view
        case .scaledToFit:
            return AnyView(view.scaledToFit())
        case .scaledToFill:
            return AnyView(view.scaledToFill())
        case .offset(let x, let y):
            return AnyView(view.offset(x: x, y: y))
        case .hidden:
            return AnyView(view.hidden())
        case .navigationTitle(let title):
            return AnyView(view.navigationTitle(title))
        case .strikethrough(let color):
            if let c = color { return AnyView(view.strikethrough(true, color: mapColorValue(c))) }
            return AnyView(view.strikethrough())
        case .underline(let color):
            if let c = color { return AnyView(view.underline(true, color: mapColorValue(c))) }
            return AnyView(view.underline())
        case .lineSpacing(let spacing):
            return AnyView(view.lineSpacing(spacing))
        case .truncationMode(let mode):
            switch mode {
            case .head: return AnyView(view.truncationMode(.head))
            case .tail: return AnyView(view.truncationMode(.tail))
            case .middle: return AnyView(view.truncationMode(.middle))
            }
        case .minimumScaleFactor(let factor):
            return AnyView(view.minimumScaleFactor(factor))
        case .textCase(let tc):
            switch tc {
            case .uppercase: return AnyView(view.textCase(.uppercase))
            case .lowercase: return AnyView(view.textCase(.lowercase))
            }
        case .kerning(let k):
            return AnyView(view.kerning(k))
        case .renderingMode:
            return view // rendering mode needs Image concrete type
        case .zIndex(let z):
            return AnyView(view.zIndex(z))
        case .rotationEffect(let degrees):
            return AnyView(view.rotationEffect(.degrees(degrees)))
        case .scaleEffect(let scale):
            return AnyView(view.scaleEffect(scale))
        case .blur(let radius):
            return AnyView(view.blur(radius: radius))
        case .brightness(let amount):
            return AnyView(view.brightness(amount))
        case .contrast(let amount):
            return AnyView(view.contrast(amount))
        case .saturation(let amount):
            return AnyView(view.saturation(amount))
        case .grayscale(let amount):
            return AnyView(view.grayscale(amount))
        case .tint(let color):
            return AnyView(view.tint(mapColorValue(color)))
        case .allowsHitTesting(let enabled):
            return AnyView(view.allowsHitTesting(enabled))
        case .onAppear(let action):
            if let action = action, let state = state {
                return AnyView(view.onAppear {
                    print("[SR] onAppear fired — running action")
                    state.execute(action)
                    print("[SR] onAppear action returned")
                })
            }
            return AnyView(view.onAppear {})
        case .taskAction(let action):
            // Real SwiftUI .task — runs in an async context so awaits inside
            // the user's code (URLSession.shared.data, etc.) suspend the Task
            // instead of blocking the main thread. The interpreter walks the
            // action body via `runAsync`, which dispatches to the async
            // network path when it encounters URLSession.shared.data(from:).
            if let state = state {
                return AnyView(view.task {
                    print("[SR] .task fired — running action async")
                    await state.runAsync(action)
                    print("[SR] .task action returned")
                })
            }
            return view
        case .taskActionWithID(let idExpression, let action):
            // `.task(id: <expr>) { … }` — SwiftUI's identity-tracking variant.
            // When the evaluated ID changes between renders, SwiftUI cancels
            // the previous task before running this one. That gives us free
            // request cancellation for live-search patterns: typing fast
            // produces an ID change per keystroke, and only the latest task's
            // network fetch survives. URLSession.shared.data also propagates
            // cancellation through the suspension point.
            if let state = state {
                let idValue = state.evaluate(idExpression).description
                return AnyView(view.task(id: idValue) {
                    print("[SR] .task(id:) fired with id='\(idValue.prefix(80))'")
                    await state.runAsync(action)
                })
            }
            return view
        case .onSubmitAction(let action):
            // Wire SwiftUI's real `.onSubmit { … }` so pressing return on a
            // focused TextField triggers the action. The body usually wraps
            // an async call (e.g. `Task { await load() }`), so we kick it
            // off in a detached Task that delegates to `runAsync` — the
            // network call inside suspends without blocking the main thread.
            if let state = state {
                return AnyView(view.onSubmit {
                    print("[SR] .onSubmit fired")
                    Task { @MainActor in
                        await state.runAsync(action)
                    }
                })
            }
            return view
        case .onDisappear(let action):
            if let action = action, let state = state {
                return AnyView(view.onDisappear { state.execute(action) })
            }
            return AnyView(view.onDisappear {})
        case .onChange(let variable, let action):
            if let state = state {
                if let varName = variable {
                    // Watch the specific variable's value and run the action
                    // when it changes. The action runs through `runAsync` in
                    // a fresh Task so live-search re-fetches don't block main.
                    let currentValue = state.variables[varName]?.description ?? ""
                    return AnyView(view.onChange(of: currentValue) { _ in
                        Task { @MainActor in
                            await state.runAsync(action)
                        }
                    })
                } else {
                    return AnyView(view.onAppear {
                        Task { @MainActor in
                            await state.runAsync(action)
                        }
                    })
                }
            }
            return view
        case .animation(let animType):
            return AnyView(view.animation(mapAnimation(animType), value: UUID()))
        case .transition(let transType):
            return AnyView(view.transition(mapTransition(transType)))
        case .ignoresSafeArea:
            return AnyView(view.ignoresSafeArea())
        case .colorMultiply(let color):
            return AnyView(view.colorMultiply(mapColorValue(color)))
        case .colorInvert:
            return AnyView(view.colorInvert())
        case .compositingGroup:
            return AnyView(view.compositingGroup())
        case .mask(let maskNode):
            return AnyView(view.mask(buildNode(maskNode, state: state)))
        case .userModifier:
            // Expanded via substitution in buildModified's pre-pass.
            return view

        // MARK: Plan 7 — iOS chrome modifiers
        case .materialBackground(let material, let shape):
            return applyMaterialBackground(view: view, material: material, shape: shape)
        case .buttonStyle(let style):
            switch style {
            case .bordered:         return AnyView(view.buttonStyle(.bordered))
            case .borderedProminent:return AnyView(view.buttonStyle(.borderedProminent))
            case .plain:            return AnyView(view.buttonStyle(.plain))
            case .borderless:       return AnyView(view.buttonStyle(.borderless))
            case .automatic:        return AnyView(view.buttonStyle(.automatic))
            }
        case .textFieldStyle(let style):
            switch style {
            case .plain:         return AnyView(view.textFieldStyle(.plain))
            case .roundedBorder: return AnyView(view.textFieldStyle(.roundedBorder))
            case .automatic:     return AnyView(view.textFieldStyle(.automatic))
            }
        case .controlSize(let size):
            switch size {
            case .mini:       return AnyView(view.controlSize(.mini))
            case .small:      return AnyView(view.controlSize(.small))
            case .regular:    return AnyView(view.controlSize(.regular))
            case .large:      return AnyView(view.controlSize(.large))
            case .extraLarge: return AnyView(view.controlSize(.extraLarge))
            }
        case .refreshable(let action):
            if let state = state {
                return AnyView(view.refreshable {
                    await MainActor.run { state.execute(action) }
                })
            }
            return view
        case .onLongPressGesture(let action):
            if let state = state {
                return AnyView(view.onLongPressGesture { state.execute(action) })
            }
            return AnyView(view.onLongPressGesture {})
        case .contentShape:
            return AnyView(view.contentShape(Rectangle()))
        case .layoutPriority(let priority):
            return AnyView(view.layoutPriority(priority))
        case .position(let x, let y):
            return AnyView(view.position(x: x, y: y))
        case .strokeBorder:
            // strokeBorder needs InsettableShape concrete type — handled in buildModified for shapes
            return view
        case .trim:
            // trim needs Shape concrete type — handled in buildModified for shapes
            return view
        case .keyboardType(let kt):
            #if canImport(UIKit)
            let mapped: UIKeyboardType
            switch kt {
            case .default: mapped = .default
            case .asciiCapable: mapped = .asciiCapable
            case .numbersAndPunctuation: mapped = .numbersAndPunctuation
            case .URL: mapped = .URL
            case .numberPad: mapped = .numberPad
            case .phonePad: mapped = .phonePad
            case .namePhonePad: mapped = .namePhonePad
            case .emailAddress: mapped = .emailAddress
            case .decimalPad: mapped = .decimalPad
            case .twitter: mapped = .twitter
            case .webSearch: mapped = .webSearch
            case .asciiCapableNumberPad: mapped = .asciiCapableNumberPad
            }
            return AnyView(view.keyboardType(mapped))
            #else
            return view
            #endif
        case .textContentType(let tc):
            #if canImport(UIKit)
            let mapped: UITextContentType
            switch tc {
            case .emailAddress: mapped = .emailAddress
            case .telephoneNumber: mapped = .telephoneNumber
            case .URL: mapped = .URL
            case .username: mapped = .username
            case .password: mapped = .password
            case .newPassword: mapped = .newPassword
            case .oneTimeCode: mapped = .oneTimeCode
            case .name: mapped = .name
            case .givenName: mapped = .givenName
            case .familyName: mapped = .familyName
            case .postalCode: mapped = .postalCode
            case .creditCardNumber: mapped = .creditCardNumber
            default: mapped = .name
            }
            return AnyView(view.textContentType(mapped))
            #else
            return view
            #endif
        case .submitLabel(let sl):
            switch sl {
            case .done: return AnyView(view.submitLabel(.done))
            case .go: return AnyView(view.submitLabel(.go))
            case .send: return AnyView(view.submitLabel(.send))
            case .join: return AnyView(view.submitLabel(.join))
            case .route: return AnyView(view.submitLabel(.route))
            case .search: return AnyView(view.submitLabel(.search))
            case .return: return AnyView(view.submitLabel(.return))
            case .next: return AnyView(view.submitLabel(.next))
            case .continue: return AnyView(view.submitLabel(.continue))
            }
        case .autocapitalization(let ac):
            #if canImport(UIKit)
            switch ac {
            case .none: return AnyView(view.textInputAutocapitalization(.never))
            case .words: return AnyView(view.textInputAutocapitalization(.words))
            case .sentences: return AnyView(view.textInputAutocapitalization(.sentences))
            case .allCharacters: return AnyView(view.textInputAutocapitalization(.characters))
            }
            #else
            return view
            #endif
        case .scrollDismissesKeyboard(let mode):
            // SwiftUI's `.scrollDismissesKeyboard(_:)` is iOS 16+/macOS 13+.
            // No-op on older platforms. Most useful for live-search ScrollViews
            // where the keyboard should drop as the user scrolls results.
            switch mode {
            case .automatic:      return AnyView(view.scrollDismissesKeyboard(.automatic))
            case .immediately:    return AnyView(view.scrollDismissesKeyboard(.immediately))
            case .interactively:  return AnyView(view.scrollDismissesKeyboard(.interactively))
            case .never:          return AnyView(view.scrollDismissesKeyboard(.never))
            }

        // MARK: Modal modifiers
        //
        // Each modal is wired to a SwiftUI Binding<Bool> backed by
        // `state.variables[varName]`. Toggling the variable from any code
        // path (button action, navigation, etc.) presents or dismisses the
        // modal exactly like real SwiftUI.

        case .sheet(let isPresentedVar, let content):
            guard let state = state else { return view }
            let binding = boolBinding(for: isPresentedVar, state: state)
            return AnyView(
                view.sheet(isPresented: binding) {
                    buildNode(content, state: state)
                }
            )

        case .fullScreenCover(let isPresentedVar, let content):
            #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            guard let state = state else { return view }
            let binding = boolBinding(for: isPresentedVar, state: state)
            return AnyView(
                view.fullScreenCover(isPresented: binding) {
                    buildNode(content, state: state)
                }
            )
            #else
            // No fullScreenCover on macOS — fall back to a regular sheet.
            guard let state = state else { return view }
            let binding = boolBinding(for: isPresentedVar, state: state)
            return AnyView(
                view.sheet(isPresented: binding) {
                    buildNode(content, state: state)
                }
            )
            #endif

        case .alert(let title, let isPresentedVar, let actions, _):
            guard let state = state else { return view }
            let binding = boolBinding(for: isPresentedVar, state: state)
            return AnyView(
                view.alert(title, isPresented: binding) {
                    buildNode(actions, state: state)
                }
            )
        case .glassEffect(let style, let tint, let shape):
            return applyGlassEffect(to: view, style: style, tint: tint, shape: shape)
        case .dynamic(let name, let argument):
            return applyDynamicModifier(name: name, argument: argument, to: view, state: state)
        case .id, .tag:
            return view
        }
    }

    /// Evaluate a dynamic modifier argument at render time and apply the appropriate SwiftUI modifier.
    private static func applyDynamicModifier(name: String, argument: ViewNode, to view: AnyView, state: SwiftRunnerState?) -> AnyView {
        guard let state = state else { return view }
        let value = state.evaluate(argument)

        switch name {
        case "foregroundColor", "foregroundStyle":
            if let color = resolveColor(from: value) {
                return AnyView(view.foregroundColor(color))
            }
        case "background":
            if let color = resolveColor(from: value) {
                return AnyView(view.background(color))
            }
        case "fill":
            // fill on type-erased view — use foregroundStyle as approximation
            if let color = resolveColor(from: value) {
                return AnyView(view.foregroundStyle(color))
            }
        case "tint":
            if let color = resolveColor(from: value) {
                return AnyView(view.tint(color))
            }
        case "opacity":
            if case .number(let n) = value { return AnyView(view.opacity(n)) }
        case "cornerRadius":
            if case .number(let n) = value { return AnyView(view.cornerRadius(n)) }
        case "font":
            if case .string(let fontName) = value {
                let fontMap: [String: Font] = [
                    "largeTitle": .largeTitle, "title": .title, "title2": .title2, "title3": .title3,
                    "headline": .headline, "subheadline": .subheadline, "body": .body,
                    "callout": .callout, "footnote": .footnote, "caption": .caption, "caption2": .caption2
                ]
                if let font = fontMap[fontName] { return AnyView(view.font(font)) }
            }
        case "padding":
            if case .number(let n) = value { return AnyView(view.padding(n)) }
        default:
            break
        }
        return view
    }

    /// Resolve a Value to a SwiftUI Color.
    private static func resolveColor(from value: Value) -> Color? {
        if case .string(let colorName) = value {
            if let c = ColorValue(rawValue: colorName) {
                return mapColorValue(c)
            }
        }
        return nil
    }
    
    private static func applyClipShape(to view: AnyView, shape: ShapeType) -> AnyView {
        switch shape {
        case .circle:
            return AnyView(view.clipShape(Circle()))
        case .rectangle:
            return AnyView(view.clipShape(Rectangle()))
        case .roundedRectangle(let radius):
            return AnyView(view.clipShape(RoundedRectangle(cornerRadius: radius)))
        case .capsule:
            return AnyView(view.clipShape(Capsule()))
        }
    }
    
    /// Apply glass effect: real .glassEffect() on iOS 26+, .ultraThinMaterial fallback on older.
    private static func applyGlassEffect(to view: AnyView, style: GlassStyle, tint: ColorValue?, shape: ShapeType?) -> AnyView {
        let tintColor: Color? = tint.map { mapColorValue($0) }

        if #available(iOS 26.0, macOS 26.0, *) {
            let glass: Glass
            switch style {
            case .regular:
                glass = tintColor != nil ? .regular.tint(tintColor!) : .regular
            case .clear:
                glass = tintColor != nil ? .clear.tint(tintColor!) : .clear
            case .identity:
                glass = .identity
            }

            switch shape {
            case .circle:
                return AnyView(view.glassEffect(glass, in: .circle))
            case .capsule, .none:
                return AnyView(view.glassEffect(glass, in: .capsule))
            case .rectangle:
                return AnyView(view.glassEffect(glass, in: .rect))
            case .roundedRectangle(let r):
                return AnyView(view.glassEffect(glass, in: .rect(cornerRadius: r)))
            }
        }

        // Fallback for iOS < 26: use .ultraThinMaterial background with shape
        switch shape {
        case .circle:
            let styled = view.background(.ultraThinMaterial, in: Circle())
            return tintColor != nil ? AnyView(styled.tint(tintColor!)) : AnyView(styled)
        case .capsule, .none:
            let styled = view.background(.ultraThinMaterial, in: Capsule())
            return tintColor != nil ? AnyView(styled.tint(tintColor!)) : AnyView(styled)
        case .rectangle:
            let styled = view.background(.ultraThinMaterial, in: Rectangle())
            return tintColor != nil ? AnyView(styled.tint(tintColor!)) : AnyView(styled)
        case .roundedRectangle(let r):
            let styled = view.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: r))
            return tintColor != nil ? AnyView(styled.tint(tintColor!)) : AnyView(styled)
        }
    }

    private static func mapAnimation(_ anim: AnimationType) -> Animation? {
        switch anim {
        case .default: return .default
        case .linear(let dur):
            return dur != nil ? .linear(duration: dur!) : .linear
        case .easeIn(let dur):
            return dur != nil ? .easeIn(duration: dur!) : .easeIn
        case .easeOut(let dur):
            return dur != nil ? .easeOut(duration: dur!) : .easeOut
        case .easeInOut(let dur):
            return dur != nil ? .easeInOut(duration: dur!) : .easeInOut
        case .spring(let response, let damping):
            return .spring(response: response ?? 0.5, dampingFraction: damping ?? 0.825)
        case .bouncy(let dur):
            if #available(iOS 17.0, *) {
                return dur != nil ? .bouncy(duration: dur!) : .bouncy
            }
            return .spring(response: dur ?? 0.5, dampingFraction: 0.6)
        case .smooth(let dur):
            if #available(iOS 17.0, *) {
                return dur != nil ? .smooth(duration: dur!) : .smooth
            }
            return .easeInOut(duration: dur ?? 0.5)
        case .snappy(let dur):
            if #available(iOS 17.0, *) {
                return dur != nil ? .snappy(duration: dur!) : .snappy
            }
            return .easeOut(duration: dur ?? 0.5)
        case .none:
            return nil
        }
    }

    private static func mapTransition(_ trans: TransitionType) -> AnyTransition {
        switch trans {
        case .opacity: return .opacity
        case .slide: return .slide
        case .scale: return .scale
        case .move(let edge):
            switch edge {
            case .top: return .move(edge: .top)
            case .bottom: return .move(edge: .bottom)
            case .leading: return .move(edge: .leading)
            case .trailing: return .move(edge: .trailing)
            }
        case .identity: return .identity
        }
    }

    // MARK: - Mapping Helpers

    /// Build a SwiftUI `Binding<Bool>` backed by `state.variables[name]`.
    /// Reads return `false` when the variable is unset or non-bool, writes
    /// store a `.boolean(_)` value. Used by Toggle, .sheet, .fullScreenCover,
    /// and .alert to drive presentation through interpreter state.
    @MainActor
    private static func boolBinding(for name: String, state: SwiftRunnerState) -> Binding<Bool> {
        Binding<Bool>(
            get: { state.variables[name]?.isTruthy ?? false },
            set: { state.variables[name] = .boolean($0) }
        )
    }

    private static func mapAlignment(_ alignment: Alignment?) -> HorizontalAlignment {
        guard let alignment = alignment else { return .center }
        switch alignment {
        case .leading, .topLeading, .bottomLeading: return .leading
        case .trailing, .topTrailing, .bottomTrailing: return .trailing
        default: return .center
        }
    }
    
    private static func mapVerticalAlignment(_ alignment: Alignment?) -> VerticalAlignment {
        guard let alignment = alignment else { return .center }
        switch alignment {
        case .top, .topLeading, .topTrailing: return .top
        case .bottom, .bottomLeading, .bottomTrailing: return .bottom
        default: return .center
        }
    }
    
    private static func mapZAlignment(_ alignment: Alignment?) -> SwiftUI.Alignment {
        guard let alignment = alignment else { return .center }
        switch alignment {
        case .leading: return .leading
        case .trailing: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        case .center: return .center
        }
    }
    
    private static func mapFont(_ style: FontStyle) -> Font {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption
        case .caption2: return .caption2
        case .system(let size, let weight, let design):
            var font = Font.system(size: size)
            if let weight = weight {
                font = font.weight(mapFontWeight(weight))
            }
            if let design = design {
                switch design {
                case .default: break
                case .serif: font = Font.system(size: size, design: .serif)
                case .rounded: font = Font.system(size: size, design: .rounded)
                case .monospaced: font = Font.system(size: size, design: .monospaced)
                }
            }
            return font
        }
    }
    
    private static func mapFontWeight(_ weight: FontWeight) -> Font.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
    
    private static func mapColorValue(_ color: ColorValue) -> Color {
        switch color {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .white: return .white
        case .black: return .black
        case .gray: return .gray
        case .clear: return .clear
        case .primary: return .primary
        case .secondary: return .secondary
        }
    }
}

// MARK: - Navigation destination wrapper

/// Re-builds a `NavigationLink` destination subtree on every render, after
/// first restoring the per-cell `renderVariables` snapshot captured at the
/// moment the row was constructed. Used so the destination view stays in
/// sync with `state.variables` mutations (e.g. the destination's own
/// `.task` setting `@State` after a network fetch) while preserving the
/// outer-`ForEach` binding (`book`, `item`, etc.) that would otherwise be
/// gone by the time the user taps.
@MainActor
struct NavigationDestinationView: View {
    let node: ViewNode
    let snapshot: [String: Value]
    @ObservedObject var state: SwiftRunnerState

    /// Per-instance @State backup. Populated in `.onAppear` with the outer
    /// (caller's) value for each name declared as `.stateInit` in the
    /// destination's body. Restored on `.onDisappear` so popping back
    /// returns the outer scope to exactly the state it was in before the
    /// destination was pushed.
    @State private var outerBackup: [String: Value?] = [:]

    init(node: ViewNode, snapshot: [String: Value], state: SwiftRunnerState?) {
        self.node = node
        self.snapshot = snapshot
        // The destination is only displayed via a NavigationLink that owns
        // a SwiftRunnerState somewhere upstream — `state` is force-unwrapped
        // when present at construction site. If absent (shouldn't happen at
        // runtime), we fall back to a fresh empty state so the view tree
        // still has something to render.
        self._state = ObservedObject(initialValue: state ?? SwiftRunnerState())
        // NOTE: do NOT mutate `state.variables` here. SwiftUI evaluates
        // NavigationLink destination closures eagerly when constructing
        // visible cells, and any @Published mutation in init triggers a
        // re-render loop. Per-instance @State setup happens in onAppear.
    }

    var body: some View {
        // Restore the captured per-cell bindings so the destination's body
        // resolves `book`/`item`/etc. to the row the user actually tapped,
        // not whatever the outer ForEach landed on last. Done as a let-IIFE
        // because SwiftUI body builders forbid statements.
        let _: Void = {
            for (k, v) in snapshot { state.renderVariables[k] = v }
        }()
        return DynamicViewBuilder.buildNode(node, state: state)
            .onAppear {
                // Back up the outer scope's value for every @State name
                // declared by this destination's struct, then clear those
                // keys so the inlined `.stateInit` defaults take effect
                // on the next render. This gives SwiftUI-style per-push
                // @State semantics on top of the runner's single global
                // `state.variables` store.
                guard outerBackup.isEmpty else { return }
                let names = NavigationDestinationView.stateInitNames(in: node)
                var backup: [String: Value?] = [:]
                for name in names {
                    backup[name] = state.variables[name]  // capture even .nil/missing
                    state.variables.removeValue(forKey: name)
                    state.renderVariables.removeValue(forKey: name)
                }
                outerBackup = backup
            }
            .onDisappear {
                // Restore the outer scope exactly. Missing keys (where the
                // outer scope didn't have the var at all) are removed
                // again to keep the dict shape consistent.
                for (name, original) in outerBackup {
                    if let v = original {
                        state.variables[name] = v
                    } else {
                        state.variables.removeValue(forKey: name)
                    }
                }
                outerBackup = [:]
            }
    }

    /// Walks the destination AST and returns every `.stateInit` name.
    /// Used to know which keys to back up / restore.
    static func stateInitNames(in node: ViewNode) -> [String] {
        var names: [String] = []
        func walk(_ n: ViewNode) {
            switch n {
            case .stateInit(let name, _):
                names.append(name)
            case .block(let stmts):
                stmts.forEach(walk)
            case .modified(let v, _):
                walk(v)
            default:
                break
            }
        }
        walk(node)
        return names
    }
}

// MARK: - Result Type

/// The result of running Swift code
public struct RunResult {
    /// The rendered view (if any)
    public let view: AnyView?
    
    /// Console output from print statements
    public let consoleOutput: String
    
    /// Any errors that occurred
    public let errors: [String]
    
    /// Whether the result has a renderable view
    public var hasView: Bool { view != nil }
    
    public init(view: AnyView? = nil, consoleOutput: String = "", errors: [String] = []) {
        self.view = view
        self.consoleOutput = consoleOutput
        self.errors = errors
    }
}
