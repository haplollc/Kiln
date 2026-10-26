//
//  KEModifiers.swift
//  Kiln engine 2
//
//  SwiftUI modifiers with their arguments interpreted, and Swift Charts.
//

import SwiftUI
import Charts

@MainActor
enum KModifiers {

    static func apply(_ m: KModifier, to view: AnyView, base: KView, _ r: KRenderer) -> AnyView {
        let interp = r.interp
        func arg(_ l: String) -> KV? { m.arg(l) }
        let first = m.first
        func d(_ v: KV?) -> CGFloat? { v?.cg }

        switch m.name {
        // Layout
        case "padding":
            if m.args.isEmpty { return AnyView(view.padding()) }
            if let n = first?.asDouble, m.args.count == 1 { return AnyView(view.padding(n)) }
            if case .tuple(let vals, let labels)? = first {   // EdgeInsets(…)
                func v(_ l: String) -> Double { labels.firstIndex(of: l).flatMap { vals[$0].asDouble } ?? 0 }
                return AnyView(view.padding(EdgeInsets(top: v("top"), leading: v("leading"), bottom: v("bottom"), trailing: v("trailing"))))
            }
            let edges = r.edges(first)
            if let n = m.unlabeled(1)?.asDouble { return AnyView(view.padding(edges, n)) }
            return AnyView(view.padding(edges))
        case "frame":
            let w = d(arg("width")), h = d(arg("height"))
            let minW = d(arg("minWidth")), maxW = d(arg("maxWidth")), minH = d(arg("minHeight")), maxH = d(arg("maxHeight"))
            let idealW = d(arg("idealWidth")), idealH = d(arg("idealHeight"))
            let align = r.alignment(arg("alignment"))
            var out = view
            if w != nil || h != nil { out = AnyView(out.frame(width: w, height: h, alignment: align)) }
            if minW != nil || maxW != nil || minH != nil || maxH != nil || idealW != nil || idealH != nil {
                out = AnyView(out.frame(minWidth: minW, idealWidth: idealW, maxWidth: maxW, minHeight: minH, idealHeight: idealH, maxHeight: maxH, alignment: align))
            }
            return out
        case "fixedSize":
            if let hz = arg("horizontal"), let vt = arg("vertical") { return AnyView(view.fixedSize(horizontal: interp.truthy(hz), vertical: interp.truthy(vt))) }
            return AnyView(view.fixedSize())
        case "layoutPriority": return AnyView(view.layoutPriority(d(first) ?? 0))
        case "offset":
            if case .native(.size(let w, let h))? = first { return AnyView(view.offset(x: w, y: h)) }
            return AnyView(view.offset(x: d(arg("x")) ?? 0, y: d(arg("y")) ?? 0))
        case "position":
            if case .native(.point(let x, let y))? = first { return AnyView(view.position(x: x, y: y)) }
            return AnyView(view.position(x: d(arg("x")) ?? 0, y: d(arg("y")) ?? 0))
        case "zIndex": return AnyView(view.zIndex(d(first) ?? 0))
        case "ignoresSafeArea", "edgesIgnoringSafeArea":
            return AnyView(view.ignoresSafeArea(.all, edges: r.edges(arg("edges") ?? first)))
        case "aspectRatio":
            let mode: SwiftUI.ContentMode = { if case .native(.implicit("fill", _))? = arg("contentMode") { return .fill }; return .fit }()
            if let ratio = d(m.unlabeled(0)) { return AnyView(view.aspectRatio(ratio, contentMode: mode)) }
            return AnyView(view.aspectRatio(contentMode: mode))
        case "scaledToFit": return AnyView(view.scaledToFit())
        case "scaledToFill": return AnyView(view.scaledToFill())
        case "resizable", "renderingMode", "interpolation", "antialiased":
            return resizable(base, m, r) ?? view
        case "safeAreaInset":
            let edge: VerticalEdge = { if case .native(.implicit("top", _))? = arg("edge") { return .top }; return .bottom }()
            let content = r.renderContent(m.args.last)
            return AnyView(view.safeAreaInset(edge: edge) { content })

        // Text & fonts
        case "font": if let f = r.font(first) { return AnyView(view.font(f)) }
        case "fontWeight":
            if case .native(.implicit(let w, _))? = first { return AnyView(view.fontWeight(KBuiltins.weight(w))) }
        case "fontDesign":
            if let design = KBuiltins.designOf(first ?? .void) { return AnyView(view.fontDesign(design)) }
        case "bold": return AnyView(view.bold(first.map { interp.truthy($0) } ?? true))
        case "italic": return AnyView(view.italic())
        case "underline": return AnyView(view.underline())
        case "strikethrough": return AnyView(view.strikethrough())
        case "monospaced": return AnyView(view.monospaced())
        case "monospacedDigit": return AnyView(view.monospacedDigit())
        case "kerning": return AnyView(view.kerning(d(first) ?? 0))
        case "tracking": return AnyView(view.tracking(d(first) ?? 0))
        case "lineLimit":
            if case .range(let lo, let hi, _)? = first { return AnyView(view.lineLimit((lo.asInt ?? 1)...(hi.asInt ?? 1))) }
            return AnyView(view.lineLimit(first?.asInt))
        case "lineSpacing": return AnyView(view.lineSpacing(d(first) ?? 0))
        case "multilineTextAlignment":
            let a: TextAlignment = {
                if case .native(.implicit(let n, _))? = first { return n == "center" ? .center : (n == "trailing" ? .trailing : .leading) }
                return .leading
            }()
            return AnyView(view.multilineTextAlignment(a))
        case "minimumScaleFactor": return AnyView(view.minimumScaleFactor(d(first) ?? 1))
        case "truncationMode":
            if case .native(.implicit(let n, _))? = first { return AnyView(view.truncationMode(n == "head" ? .head : (n == "middle" ? .middle : .tail))) }
        case "textCase":
            if case .native(.implicit(let n, _))? = first { return AnyView(view.textCase(n == "lowercase" ? .lowercase : .uppercase)) }
            return AnyView(view.textCase(nil))
        case "textSelection": return AnyView(view.textSelection(.enabled))

        // Color & style
        case "foregroundColor":
            if let c = r.color(first) { return AnyView(view.foregroundColor(c)) }
        case "foregroundStyle":
            if m.args.count >= 2, let a = r.shapeStyle(m.args[0]), let b = r.shapeStyle(m.args[1]) {
                return AnyView(view.foregroundStyle(a, b))
            }
            if let s = r.shapeStyle(first) { return AnyView(view.foregroundStyle(s)) }
        case "tint", "accentColor":
            if let c = r.color(first) { return AnyView(view.tint(c)) }
        case "background":
            return background(view, m, r)
        case "overlay":
            if let fn = m.args.last, r.isFunction(fn) {
                let content = r.renderContent(fn)
                return AnyView(view.overlay(alignment: r.alignment(arg("alignment"))) { content })
            }
            if let s = r.shapeStyle(first), arg("in") != nil, case .view(let sv)? = arg("in"), let chain = r.shapeChain(sv) {
                return AnyView(view.overlay(chain.kind.anyShape.fill(s)))
            }
            if let v = first { return AnyView(view.overlay(alignment: r.alignment(arg("alignment"))) { r.renderList(KBuiltins.asViews(v, interp)) }) }
        case "border":
            let c = r.color(first) ?? .primary
            return AnyView(view.border(c, width: d(arg("width")) ?? 1))
        case "cornerRadius":
            return AnyView(view.clipShape(RoundedRectangle(cornerRadius: d(first) ?? 0)))
        case "clipShape", "contentShape", "mask":
            if m.name == "mask", case .view(let mv)? = m.args.last { return AnyView(view.mask { r.render(mv) }) }
            if let shape = shapeArg(first, r) {
                return m.name == "clipShape" ? AnyView(view.clipShape(shape)) : AnyView(view.contentShape(shape))
            }
            if m.name == "contentShape" { return AnyView(view.contentShape(Rectangle())) }
        case "clipped": return AnyView(view.clipped())
        case "shadow":
            let c = r.color(arg("color")) ?? Color.black.opacity(0.33)
            return AnyView(view.shadow(color: c, radius: d(arg("radius")) ?? 4, x: d(arg("x")) ?? 0, y: d(arg("y")) ?? 0))
        case "opacity": return AnyView(view.opacity(d(first) ?? 1))
        case "blur": return AnyView(view.blur(radius: d(arg("radius") ?? first) ?? 0))
        case "brightness": return AnyView(view.brightness(d(first) ?? 0))
        case "contrast": return AnyView(view.contrast(d(first) ?? 1))
        case "saturation": return AnyView(view.saturation(d(first) ?? 1))
        case "grayscale": return AnyView(view.grayscale(d(first) ?? 0))
        case "hueRotation": return AnyView(view.hueRotation(r.angle(first)))
        case "colorMultiply": if let c = r.color(first) { return AnyView(view.colorMultiply(c)) }
        case "colorInvert": return AnyView(view.colorInvert())
        case "blendMode": return AnyView(view.blendMode(.normal))
        case "compositingGroup": return AnyView(view.compositingGroup())
        case "drawingGroup": return AnyView(view.drawingGroup())
        case "preferredColorScheme":
            if case .native(.implicit(let n, _))? = first { return AnyView(view.preferredColorScheme(n == "dark" ? .dark : .light)) }
            return view

        // Transforms
        case "rotationEffect":
            return AnyView(view.rotationEffect(r.angle(first), anchor: r.unitPoint(arg("anchor")) ?? .center))
        case "rotation3DEffect":
            var axis: (CGFloat, CGFloat, CGFloat) = (0, 1, 0)
            if case .tuple(let vals, let labels)? = arg("axis") {
                func v(_ l: String, _ i: Int) -> Double { labels.firstIndex(of: l).flatMap { vals[$0].asDouble } ?? (i < vals.count ? vals[i].asDouble ?? 0 : 0) }
                axis = (v("x", 0), v("y", 1), v("z", 2))
            }
            return AnyView(view.rotation3DEffect(r.angle(first), axis: axis, perspective: d(arg("perspective")) ?? 1))
        case "scaleEffect":
            if let s = d(m.unlabeled(0)) { return AnyView(view.scaleEffect(s, anchor: r.unitPoint(arg("anchor")) ?? .center)) }
            return AnyView(view.scaleEffect(x: d(arg("x")) ?? 1, y: d(arg("y")) ?? 1, anchor: r.unitPoint(arg("anchor")) ?? .center))

        // Interaction
        case "onTapGesture":
            let run = r.action(m.args.last)
            return AnyView(view.onTapGesture(count: arg("count")?.asInt ?? 1, perform: run))
        case "onLongPressGesture":
            return AnyView(view.onLongPressGesture(perform: r.action(m.args.last)))
        case "disabled": return AnyView(view.disabled(first.map { interp.truthy($0) } ?? true))
        case "hidden": return AnyView(view.hidden())
        case "allowsHitTesting": return AnyView(view.allowsHitTesting(first.map { interp.truthy($0) } ?? true))
        case "onAppear":
            let run = r.action(arg("perform") ?? m.args.last)
            return AnyView(view.onAppear(perform: run))
        case "onDisappear":
            return AnyView(view.onDisappear(perform: r.action(arg("perform") ?? m.args.last)))
        case "task":
            let run = r.action(m.args.last)
            if let id = arg("id") { return AnyView(view.task(id: id) { run() }) }
            return AnyView(view.task { run() })
        case "onChange":
            let value = arg("of") ?? first ?? .void
            guard case .function(let fn)? = m.args.last else { return view }
            let n = r.closureParamCount(.function(fn))
            let initial = arg("initial").map { interp.truthy($0) } ?? false
            return AnyView(view.onChange(of: value, initial: initial) { old, new in
                interp.perform(fn, n == 0 ? [] : (n == 1 ? [new] : [old, new]))
            })
        case "onReceive":
            guard case .function(let fn)? = m.args.last else { return view }
            if case .native(.publisher(let interval))? = first {
                return AnyView(KTimerReceiver(interval: interval, action: { interp.perform(fn, [.native(.date(Date()))]) }, content: view))
            }
            return view
        case "onSubmit": return AnyView(view.onSubmit(r.action(m.args.last)))
        case "refreshable":
            let run = r.action(m.args.last)
            return AnyView(view.refreshable { run() })
        case "swipeActions":
            let content = r.renderContent(m.args.last)
            let edge: HorizontalEdge = { if case .native(.implicit("leading", _))? = arg("edge") { return .leading }; return .trailing }()
            return AnyView(view.swipeActions(edge: edge, allowsFullSwipe: arg("allowsFullSwipe").map { interp.truthy($0) } ?? true) { content })
        case "contextMenu":
            let content = r.renderContent(m.args.last)
            return AnyView(view.contextMenu { content })
        case "gesture", "simultaneousGesture", "highPriorityGesture":
            return view

        // Navigation & presentation
        case "navigationTitle":
            if let s = r.string(first) { return AnyView(view.navigationTitle(s)) }
        case "navigationBarTitleDisplayMode":
            #if os(iOS)
            if case .native(.implicit(let n, _))? = first {
                return AnyView(view.navigationBarTitleDisplayMode(n == "inline" ? .inline : (n == "large" ? .large : .automatic)))
            }
            #endif
            return view
        case "navigationBarHidden", "navigationBarBackButtonHidden":
            return AnyView(view.navigationBarBackButtonHidden(first.map { interp.truthy($0) } ?? true))
        case "navigationDestination":
            return navigationDestination(view, m, r)
        case "sheet", "fullScreenCover", "popover":
            return sheet(view, m, r)
        case "alert":
            return alert(view, m, r)
        case "confirmationDialog":
            guard let b = r.binding(arg("isPresented")) else { return view }
            let actions = r.renderContent(arg("actions") ?? m.unlabeledFunction(0))
            let message = arg("message").map { r.renderContent($0) }
            let title = r.string(first) ?? ""
            if let message {
                return AnyView(view.confirmationDialog(title, isPresented: r.boolBinding(b), titleVisibility: .visible) { actions } message: { message })
            }
            return AnyView(view.confirmationDialog(title, isPresented: r.boolBinding(b), titleVisibility: .visible) { actions })
        case "presentationDetents":
            var detents: Set<PresentationDetent> = []
            for v in first?.asArray ?? [] {
                if case .native(.implicit(let n, let a)) = v {
                    if n == "medium" { detents.insert(.medium) }
                    else if n == "large" { detents.insert(.large) }
                    else if n == "fraction", let f = a.first?.asDouble { detents.insert(.fraction(f)) }
                    else if n == "height", let h = a.first?.asDouble { detents.insert(.height(h)) }
                }
            }
            return AnyView(view.presentationDetents(detents.isEmpty ? [.large] : detents))
        case "presentationDragIndicator": return AnyView(view.presentationDragIndicator(.visible))
        case "searchable":
            guard let b = r.binding(arg("text")) else { return view }
            return AnyView(view.searchable(text: r.stringBinding(b), prompt: r.string(arg("prompt")) ?? "Search"))
        case "tabItem":
            let content = r.renderContent(m.args.last)
            return AnyView(view.tabItem { content })
        case "badge":
            if let n = first?.asInt { return AnyView(view.badge(n)) }
            if let s = first?.asString { return AnyView(view.badge(s)) }

        // Lists & controls
        case "listStyle":
            guard case .native(.implicit(let n, _))? = first else { return view }
            switch n {
            case "plain": return AnyView(view.listStyle(.plain))
            case "inset": return AnyView(view.listStyle(.inset))
            case "sidebar": return AnyView(view.listStyle(.sidebar))
            #if os(iOS)
            case "insetGrouped": return AnyView(view.listStyle(.insetGrouped))
            case "grouped": return AnyView(view.listStyle(.grouped))
            #endif
            default: return view
            }
        case "listRowBackground":
            if let c = r.color(first) { return AnyView(view.listRowBackground(c)) }
            if case .view(let v)? = first { return AnyView(view.listRowBackground(r.render(v))) }
        case "listRowSeparator":
            if case .native(.implicit("hidden", _))? = first { return AnyView(view.listRowSeparator(.hidden)) }
            return view
        case "listRowInsets":
            return AnyView(view.listRowInsets(EdgeInsets()))
        case "scrollContentBackground":
            if case .native(.implicit("hidden", _))? = first { return AnyView(view.scrollContentBackground(.hidden)) }
            return view
        case "scrollIndicators":
            if case .native(.implicit("hidden", _))? = first { return AnyView(view.scrollIndicators(.hidden)) }
            return view
        case "pickerStyle":
            guard case .native(.implicit(let n, _))? = first else { return view }
            switch n {
            case "segmented": return AnyView(view.pickerStyle(.segmented))
            case "menu": return AnyView(view.pickerStyle(.menu))
            case "inline": return AnyView(view.pickerStyle(.inline))
            case "palette": return AnyView(view.pickerStyle(.palette))
            #if os(iOS)
            case "wheel": return AnyView(view.pickerStyle(.wheel))
            case "navigationLink": return AnyView(view.pickerStyle(.navigationLink))
            #endif
            default: return view
            }
        case "toggleStyle":
            if case .native(.implicit("button", _))? = first { return AnyView(view.toggleStyle(.button)) }
            return AnyView(view.toggleStyle(.switch))
        case "buttonStyle":
            guard case .native(.implicit(let n, _))? = first else { return view }
            switch n {
            case "borderedProminent": return AnyView(view.buttonStyle(.borderedProminent))
            case "bordered": return AnyView(view.buttonStyle(.bordered))
            case "borderless": return AnyView(view.buttonStyle(.borderless))
            case "plain": return AnyView(view.buttonStyle(.plain))
            default: return view
            }
        case "buttonBorderShape":
            if case .native(.implicit(let n, _))? = first {
                if n == "capsule" { return AnyView(view.buttonBorderShape(.capsule)) }
                if n == "circle" { return AnyView(view.buttonBorderShape(.circle)) }
                if n == "roundedRectangle" { return AnyView(view.buttonBorderShape(.roundedRectangle)) }
            }
            return view
        case "textFieldStyle":
            if case .native(.implicit("roundedBorder", _))? = first { return AnyView(view.textFieldStyle(.roundedBorder)) }
            if case .native(.implicit("plain", _))? = first { return AnyView(view.textFieldStyle(.plain)) }
            return view
        case "datePickerStyle":
            if case .native(.implicit(let n, _))? = first {
                if n == "graphical" { return AnyView(view.datePickerStyle(.graphical)) }
                if n == "compact" { return AnyView(view.datePickerStyle(.compact)) }
                #if os(iOS)
                if n == "wheel" { return AnyView(view.datePickerStyle(.wheel)) }
                #endif
            }
            return view
        case "labelStyle":
            if case .native(.implicit(let n, _))? = first {
                if n == "iconOnly" { return AnyView(view.labelStyle(.iconOnly)) }
                if n == "titleOnly" { return AnyView(view.labelStyle(.titleOnly)) }
                return AnyView(view.labelStyle(.titleAndIcon))
            }
            return view
        case "progressViewStyle":
            if case .native(.implicit("circular", _))? = first { return AnyView(view.progressViewStyle(.circular)) }
            return AnyView(view.progressViewStyle(.linear))
        case "gaugeStyle":
            #if os(iOS)
            if case .native(.implicit(let n, _))? = first, n.contains("accessoryCircular") { return AnyView(view.gaugeStyle(.accessoryCircular)) }
            #endif
            return view
        case "controlSize":
            guard case .native(.implicit(let n, _))? = first else { return view }
            let sizes: [String: ControlSize] = ["mini": .mini, "small": .small, "regular": .regular, "large": .large, "extraLarge": .extraLarge]
            return AnyView(view.controlSize(sizes[n] ?? .regular))
        case "keyboardType":
            #if os(iOS)
            if case .native(.implicit(let n, _))? = first {
                let types: [String: UIKeyboardType] = ["decimalPad": .decimalPad, "numberPad": .numberPad, "emailAddress": .emailAddress,
                    "phonePad": .phonePad, "URL": .URL, "twitter": .twitter, "asciiCapable": .asciiCapable, "numbersAndPunctuation": .numbersAndPunctuation]
                return AnyView(view.keyboardType(types[n] ?? .default))
            }
            #endif
            return view
        case "textInputAutocapitalization":
            #if os(iOS)
            if case .native(.implicit(let n, _))? = first {
                return AnyView(view.textInputAutocapitalization(n == "never" ? .never : (n == "words" ? .words : (n == "characters" ? .characters : .sentences))))
            }
            #endif
            return view
        case "autocorrectionDisabled": return AnyView(view.autocorrectionDisabled())
        case "submitLabel": return AnyView(view.submitLabel(.done))
        case "imageScale":
            if case .native(.implicit(let n, _))? = first { return AnyView(view.imageScale(n == "large" ? .large : (n == "small" ? .small : .medium))) }
        case "symbolRenderingMode":
            if case .native(.implicit(let n, _))? = first {
                switch n {
                case "multicolor": return AnyView(view.symbolRenderingMode(.multicolor))
                case "hierarchical": return AnyView(view.symbolRenderingMode(.hierarchical))
                case "palette": return AnyView(view.symbolRenderingMode(.palette))
                default: return AnyView(view.symbolRenderingMode(.monochrome))
                }
            }

        // Animation
        case "animation":
            let anim = r.animation(first)
            if let value = arg("value") { return AnyView(view.animation(anim, value: value)) }
            return AnyView(view.animation(anim, value: UUID()))
        case "transition":
            return AnyView(view.transition(transition(first)))
        case "contentTransition":
            if case .native(.implicit(let n, _))? = first, n.hasPrefix("numericText") { return AnyView(view.contentTransition(.numericText())) }
            return AnyView(view.contentTransition(.opacity))
        case "symbolEffect":
            return view

        // Environment
        case "environmentObject":
            guard let obj = first, let typeName = obj.userType?.name else { return view }
            return AnyView(view.transformEnvironment(\.kilnObjects) { $0[typeName] = obj })
        case "environment":
            if case .native(.keyPath(let comps))? = first, comps.last == "colorScheme", case .native(.implicit(let n, _))? = m.args.last {
                return AnyView(view.environment(\.colorScheme, n == "dark" ? .dark : .light))
            }
            return view
        case "id":
            return AnyView(view.id(first ?? .nilValue))

        // Accessibility
        case "accessibilityLabel":
            if let s = r.string(first) { return AnyView(view.accessibilityLabel(Text(s))) }
        case "accessibilityHint":
            if let s = r.string(first) { return AnyView(view.accessibilityHint(Text(s))) }
        case "accessibilityIdentifier":
            if let s = r.string(first) { return AnyView(view.accessibilityIdentifier(s)) }
        case "accessibilityValue", "accessibilityAddTraits", "accessibilityElement", "accessibilityHidden", "help", "privacySensitive",
             "redacted", "sensoryFeedback", "dynamicTypeSize", "headerProminence", "listSectionSeparator", "toolbarBackground",
             "toolbarColorScheme", "dragToMove", "focused", "textContentType", "presentationCornerRadius", "interactiveDismissDisabled",
             "scrollDismissesKeyboard", "scrollTargetBehavior", "scrollTargetLayout", "defaultScrollAnchor", "onHover", "lineStyle":
            return view

        // Charts (applied to the Chart view)
        case "chartLegend":
            if case .native(.implicit("hidden", _))? = first { return AnyView(view.chartLegend(.hidden)) }
            return view
        case "chartXAxis":
            if case .native(.implicit("hidden", _))? = first { return AnyView(view.chartXAxis(.hidden)) }
            return view
        case "chartYAxis":
            if case .native(.implicit("hidden", _))? = first { return AnyView(view.chartYAxis(.hidden)) }
            return view
        case "chartYScale":
            if case .range(let lo, let hi, _)? = arg("domain"), let l = lo.asDouble, let h = hi.asDouble { return AnyView(view.chartYScale(domain: l...h)) }
            return view
        case "chartXScale", "chartForegroundStyleScale", "chartPlotStyle", "chartBackground", "chartOverlay":
            return view
        default:
            interp.warn("The .\(m.name)() modifier isn't supported in Kiln yet, so it was skipped.")
            return view
        }
        return view
    }

    static func resizable(_ base: KView, _ m: KModifier, _ r: KRenderer) -> AnyView? {
        // Image modifiers must reach the Image itself.
        var chain: [KModifier] = []
        var node = base
        while case .modified(let inner, let mm) = node.kind { chain.insert(mm, at: 0); node = inner }
        guard case .primitive(let name, let args, let labels, _) = node.kind, name == "Image" else {
            if case .image(var img) = node.kind {
                if m.name == "resizable" { img = img.resizable() }
                return AnyView(img)
            }
            return nil
        }
        let a = KArgs(args: args, labels: labels)
        var image: Image
        if let s = a["systemName"].flatMap({ r.string($0) }) { image = Image(systemName: s) }
        else if let n = a.first?.asString { image = Kiln.hostImageProvider?(n) ?? Image(n) }
        else { image = Image(systemName: "photo") }
        var applied = chain + [m]
        if let i = applied.firstIndex(where: { $0.name == "resizable" }) { image = image.resizable(); applied.remove(at: i) }
        if let rm = applied.first(where: { $0.name == "renderingMode" }), case .native(.implicit(let n, _))? = rm.first {
            image = image.renderingMode(n == "template" ? .template : .original)
        }
        var out = AnyView(image)
        for mm in applied where mm.name != "renderingMode" && mm.name != "resizable" && mm.name != "interpolation" && mm.name != "antialiased" {
            out = apply(mm, to: out, base: .empty, r)
        }
        return out
    }

    static func shapeArg(_ v: KV?, _ r: KRenderer) -> AnyShape? {
        switch v {
        case .view(let sv)?:
            return r.shapeChain(sv)?.kind.anyShape
        case .native(.implicit(let n, let a))?:
            switch n {
            case "circle": return AnyShape(Circle())
            case "capsule": return AnyShape(Capsule())
            case "rect":
                if let cr = a.first?.asDouble { return AnyShape(RoundedRectangle(cornerRadius: cr)) }
                return AnyShape(Rectangle())
            case "ellipse": return AnyShape(Ellipse())
            default: return nil
            }
        default: return nil
        }
    }

    static func background(_ view: AnyView, _ m: KModifier, _ r: KRenderer) -> AnyView {
        let interp = r.interp
        let first = m.first
        if let fn = m.args.last, r.isFunction(fn), m.labels.last != "in" {
            let content = r.renderContent(fn)
            return AnyView(view.background(alignment: r.alignment(m.arg("alignment"))) { content })
        }
        if let style = r.shapeStyle(first) {
            if let shape = shapeArg(m.arg("in"), r) { return AnyView(view.background(style, in: shape)) }
            if case .native(.color(let c))? = first { return AnyView(view.background(c)) }
            return AnyView(view.background(style))
        }
        if let v = first {
            let views = KBuiltins.asViews(v, interp)
            if !views.isEmpty { return AnyView(view.background(r.renderList(views))) }
        }
        return view
    }

    static func transition(_ v: KV?) -> AnyTransition {
        guard case .native(let n)? = v else { return .opacity }
        var name = "opacity"
        var args: [KV] = []
        if case .implicit(let nm, let a) = n { name = nm; args = a }
        if case .transition(let nm, let a) = n { name = nm; args = a }
        switch name.split(separator: ".").first.map(String.init) ?? name {
        case "scale": return .scale
        case "slide": return .slide
        case "move":
            if case .native(.implicit(let e, _))? = args.first {
                let edges: [String: Edge] = ["top": .top, "bottom": .bottom, "leading": .leading, "trailing": .trailing]
                return .move(edge: edges[e] ?? .bottom)
            }
            return .move(edge: .bottom)
        case "push": return .push(from: .trailing)
        case "identity": return .identity
        default: return .opacity
        }
    }

    static func sheet(_ view: AnyView, _ m: KModifier, _ r: KRenderer) -> AnyView {
        let interp = r.interp
        guard let fn = m.args.last, r.isFunction(fn) else { return view }
        if let b = r.binding(m.arg("item")) {
            let item = Binding<KSheetItem?>(get: { let v = b.get(); return v.isNil ? nil : KSheetItem(value: v) },
                                            set: { b.set($0?.value ?? .nilValue) })
            let onDismiss = r.action(m.arg("onDismiss"))
            if m.name == "fullScreenCover" {
                #if os(iOS)
                return AnyView(view.fullScreenCover(item: item, onDismiss: onDismiss) { it in KLazyView { r.renderContent(fn, [it.value]) } })
                #endif
            }
            return AnyView(view.sheet(item: item, onDismiss: onDismiss) { it in KLazyView { r.renderContent(fn, [it.value]) } })
        }
        guard let b = r.binding(m.arg("isPresented")) else { return view }
        let shown = r.boolBinding(b)
        let onDismiss = r.action(m.arg("onDismiss"))
        _ = interp
        if m.name == "fullScreenCover" {
            #if os(iOS)
            return AnyView(view.fullScreenCover(isPresented: shown, onDismiss: onDismiss) { KLazyView { r.renderContent(fn) } })
            #endif
        }
        return AnyView(view.sheet(isPresented: shown, onDismiss: onDismiss) { KLazyView { r.renderContent(fn) } })
    }

    static func alert(_ view: AnyView, _ m: KModifier, _ r: KRenderer) -> AnyView {
        let interp = r.interp
        guard let b = r.binding(m.arg("isPresented")) ?? r.binding(m.arg("item")) else { return view }
        let shown = Binding<Bool>(get: { let v = b.get(); return v.isNil ? false : interp.truthy(v) },
                                  set: { if !$0 { b.set(b.get().asBool != nil ? .bool(false) : .nilValue) } })
        // Old API: .alert(isPresented:) { Alert(title:message:dismissButton:) }
        if m.labels.contains("content"), case .function(let fn)? = m.args.last,
           let alertValue = try? interp.entry({ try interp.call(fn, [], []) }), case .tuple(let vals, let labels) = alertValue {
            func text(_ l: String) -> String? {
                guard let i = labels.firstIndex(of: l) else { return nil }
                if case .view(let tv) = vals[i] { return r.plainText(tv) }
                return r.string(vals[i])
            }
            let title = text("title") ?? ""
            let message = text("message")
            return AnyView(view.alert(title, isPresented: shown) { Button("OK", role: .cancel) {} } message: {
                if let message { Text(message) }
            })
        }
        let title = r.string(m.first.flatMap { if case .string = $0 { return $0 }; if case .view = $0 { return $0 }; return nil }) ?? ""
        let actionsFn = m.arg("actions") ?? m.unlabeledFunction(0)
        let actions = actionsFn.map { r.renderContent($0) }
        let message = m.arg("message").map { r.renderContent($0) }
        switch (actions, message) {
        case (let a?, let msg?): return AnyView(view.alert(title, isPresented: shown) { a } message: { msg })
        case (let a?, nil): return AnyView(view.alert(title, isPresented: shown) { a })
        case (nil, let msg?): return AnyView(view.alert(title, isPresented: shown) { Button("OK", role: .cancel) {} } message: { msg })
        default: return AnyView(view.alert(title, isPresented: shown) { Button("OK", role: .cancel) {} })
        }
    }

    static func navigationDestination(_ view: AnyView, _ m: KModifier, _ r: KRenderer) -> AnyView {
        guard let fn = m.args.last, r.isFunction(fn) else { return view }
        if let b = r.binding(m.arg("isPresented")) {
            return AnyView(view.navigationDestination(isPresented: r.boolBinding(b)) { KLazyView { r.renderContent(fn) } })
        }
        return AnyView(view.navigationDestination(for: KNavValue.self) { nav in KLazyView { r.renderContent(fn, [nav.value]) } })
    }
}

/// `.sheet(item:)` needs an Identifiable item.
struct KSheetItem: Identifiable {
    let value: KV
    var id: KV { value }
}

extension KModifier {
    func unlabeledFunction(_ n: Int) -> KV? {
        let u = zip(labels, args).filter { $0.0 == nil }.map(\.1).filter { if case .function = $0 { return true }; return false }
        return n < u.count ? u[n] : nil
    }
}

// MARK: - Charts

struct KChartPoint: Identifiable {
    enum Axis: Hashable { case text(String), number(Double), date(Date) }
    let id = UUID()
    let kind: String
    var x: Axis?
    var y: Axis?
    var xLabel = "x"
    var yLabel = "y"
    var angle: Double?
    var color: Color?
    var series: String?
    var seriesLabel = "Series"
    var cornerRadius: Double?

    @MainActor
    init?(view: KView, renderer r: KRenderer) {
        var modifiers: [KModifier] = []
        var node = view
        while case .modified(let inner, let m) = node.kind { modifiers.append(m); node = inner }
        guard case .primitive(let name, let args, let labels, _) = node.kind,
              ["BarMark", "LineMark", "PointMark", "AreaMark", "SectorMark", "RuleMark", "RectangleMark"].contains(name) else { return nil }
        kind = name
        let a = KArgs(args: args, labels: labels)
        func plottable(_ v: KV?) -> (String, Axis)? {
            guard case .native(.implicit("value", let pa))? = v, pa.count >= 2 else { return nil }
            let label = r.string(pa[0]) ?? ""
            switch pa[1] {
            case .int(let i): return (label, .number(Double(i)))
            case .double(let d): return (label, .number(d))
            case .native(.date(let d)): return (label, .date(d))
            default: return (label, .text(r.string(pa[1]) ?? ""))
            }
        }
        if let (l, v) = plottable(a["x"]) { xLabel = l; x = v }
        if let (l, v) = plottable(a["y"]) { yLabel = l; y = v }
        if let (_, v) = plottable(a["angle"]), case .number(let n) = v { angle = n }
        for m in modifiers {
            if m.name == "foregroundStyle" {
                if let by = m.arg("by"), case .native(.implicit("value", let pa)) = by, pa.count >= 2 {
                    seriesLabel = r.string(pa[0]) ?? "Series"
                    series = r.string(pa[1])
                } else if let c = r.color(m.first) {
                    color = c
                }
            }
            if m.name == "cornerRadius" { cornerRadius = m.first?.asDouble }
        }
    }

    var xText: String { if case .text(let s)? = x { return s }; return "" }
    var yText: String { if case .text(let s)? = y { return s }; return "" }
    var xNumber: Double { if case .number(let n)? = x { return n }; return 0 }
    var yNumber: Double { if case .number(let n)? = y { return n }; return 0 }
    var xDate: Date { if case .date(let d)? = x { return d }; return Date() }
    var xIsText: Bool { if case .text? = x { return true }; return false }
    var xIsDate: Bool { if case .date? = x { return true }; return false }
    var yIsText: Bool { if case .text? = y { return true }; return false }
}

struct KChartView: View {
    let points: [KChartPoint]

    var body: some View {
        Chart {
            ForEach(points) { p in
                mark(p)
            }
        }
    }

    @ChartContentBuilder
    func mark(_ p: KChartPoint) -> some ChartContent {
        if p.kind == "SectorMark" {
            SectorMark(angle: .value("Value", p.angle ?? 0), innerRadius: .ratio(0.5), angularInset: 1.5)
                .foregroundStyle(by: .value(p.seriesLabel, p.series ?? "\(p.angle ?? 0)"))
        } else if p.kind == "RuleMark" {
            RuleMark(y: .value(p.yLabel, p.yNumber))
                .foregroundStyle(p.color ?? .red)
        } else if p.xIsText {
            styled(barOrLine(p, x: PlottableValue.value(p.xLabel, p.xText), y: PlottableValue.value(p.yLabel, p.yNumber)), p)
        } else if p.xIsDate {
            styled(barOrLine(p, x: PlottableValue.value(p.xLabel, p.xDate), y: PlottableValue.value(p.yLabel, p.yNumber)), p)
        } else if p.yIsText {
            styled(barOrLine(p, x: PlottableValue.value(p.xLabel, p.xNumber), y: PlottableValue.value(p.yLabel, p.yText)), p)
        } else {
            styled(barOrLine(p, x: PlottableValue.value(p.xLabel, p.xNumber), y: PlottableValue.value(p.yLabel, p.yNumber)), p)
        }
    }

    @ChartContentBuilder
    func barOrLine<X: Plottable, Y: Plottable>(_ p: KChartPoint, x: PlottableValue<X>, y: PlottableValue<Y>) -> some ChartContent {
        switch p.kind {
        case "LineMark": LineMark(x: x, y: y)
        case "PointMark": PointMark(x: x, y: y)
        case "AreaMark": AreaMark(x: x, y: y)
        default: BarMark(x: x, y: y)
        }
    }

    @ChartContentBuilder
    func styled<C: ChartContent>(_ c: C, _ p: KChartPoint) -> some ChartContent {
        if let s = p.series {
            c.foregroundStyle(by: .value(p.seriesLabel, s))
        } else {
            c.foregroundStyle(p.color ?? .accentColor)
        }
    }
}
