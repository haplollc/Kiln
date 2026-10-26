//
//  KEBuiltins.swift
//  Kiln engine 2
//
//  The standard library and SwiftUI constructors: global functions, built-in
//  types' initializers, static members and methods, formatting, implicit
//  members (`.red`, `.title`, `.degrees(90)`), and the catalog of view names.
//

import SwiftUI

@MainActor
enum KBuiltins {

    // MARK: - Catalog

    static let viewNames: Set<String> = [
        "Text", "Image", "Label", "Button", "Toggle", "Slider", "Stepper", "TextField", "SecureField", "TextEditor",
        "Picker", "DatePicker", "ColorPicker", "ProgressView", "Gauge", "Link", "Menu", "Spacer", "Divider",
        "Circle", "Rectangle", "RoundedRectangle", "Capsule", "Ellipse", "UnevenRoundedRectangle", "ContainerRelativeShape",
        "LinearGradient", "RadialGradient", "AngularGradient", "EllipticalGradient",
        "VStack", "HStack", "ZStack", "LazyVStack", "LazyHStack", "LazyVGrid", "LazyHGrid", "Grid", "GridRow",
        "ScrollView", "ScrollViewReader", "List", "Form", "Section", "Group", "GroupBox", "DisclosureGroup", "ControlGroup",
        "NavigationStack", "NavigationView", "NavigationSplitView", "NavigationLink", "TabView", "Tab",
        "GeometryReader", "ForEach", "AsyncImage", "EmptyView", "AnyView", "ViewThatFits", "ContentUnavailableView",
        "LabeledContent", "ToolbarItem", "ToolbarItemGroup", "ShareLink", "EditButton", "TimelineView",
        "Chart", "BarMark", "LineMark", "PointMark", "AreaMark", "SectorMark", "RuleMark", "RectangleMark",
        "Path", "Canvas",
    ]

    static let modifierNames: Set<String> = [
        "padding", "frame", "font", "fontWeight", "bold", "italic", "foregroundColor", "foregroundStyle", "background",
        "overlay", "cornerRadius", "clipShape", "shadow", "opacity", "onTapGesture", "onAppear", "onDisappear",
        "navigationTitle", "toolbar", "sheet", "alert", "tint", "disabled", "listStyle", "pickerStyle", "buttonStyle",
        "fill", "stroke", "strokeBorder", "trim", "rotationEffect", "scaleEffect", "offset", "animation", "transition",
        "tag", "id", "onChange", "onReceive", "task", "multilineTextAlignment", "lineLimit", "border", "clipped",
        "aspectRatio", "resizable", "scaledToFit", "scaledToFill", "imageScale", "symbolRenderingMode", "keyboardType",
        "textFieldStyle", "monospacedDigit", "monospaced", "controlSize", "contentShape", "onDelete", "onMove",
        "swipeActions", "contextMenu", "fullScreenCover", "confirmationDialog", "navigationBarTitleDisplayMode",
        "rotation3DEffect", "blur", "zIndex", "fixedSize", "layoutPriority", "accessibilityLabel", "accessibilityHint",
        "listRowBackground", "scrollContentBackground", "searchable", "refreshable", "environment", "environmentObject",
        "ignoresSafeArea", "edgesIgnoringSafeArea", "position", "mask", "brightness", "saturation", "grayscale",
        "hidden", "allowsHitTesting", "textCase", "kerning", "tracking", "underline", "strikethrough", "minimumScaleFactor",
        "truncationMode", "lineSpacing", "chartForegroundStyleScale", "foregroundStyle", "contentTransition", "sensoryFeedback",
        "gesture", "simultaneousGesture", "onLongPressGesture", "submitLabel", "onSubmit", "focused", "autocorrectionDisabled",
        "textInputAutocapitalization", "navigationDestination", "presentationDetents", "badge", "tabItem", "frame",
        "safeAreaInset", "scrollIndicators", "listRowSeparator", "listSectionSeparator", "headerProminence",
        "symbolEffect", "labelStyle", "toggleStyle", "datePickerStyle", "progressViewStyle", "gaugeStyle",
        "navigationBarBackButtonHidden", "toolbarBackground", "toolbarColorScheme", "preferredColorScheme",
        "colorScheme", "privacySensitive", "redacted", "dynamicTypeSize", "drawingGroup", "compositingGroup",
        "colorMultiply", "colorInvert", "contrast", "hueRotation", "luminanceToAlpha", "blendMode", "accentColor",
        "foregroundColor", "chartXAxis", "chartYAxis", "chartLegend", "annotation", "interpolationMethod", "symbol",
        "cornerRadius", "lineStyle", "position", "chartXScale", "chartYScale", "modifier", "onHover", "help",
        "accessibilityValue", "accessibilityAddTraits", "accessibilityElement", "accessibilityIdentifier", "dragToMove",
    ]

    static let colorNames: [String: Color] = [
        "red": .red, "orange": .orange, "yellow": .yellow, "green": .green, "mint": .mint, "teal": .teal,
        "cyan": .cyan, "blue": .blue, "indigo": .indigo, "purple": .purple, "pink": .pink, "brown": .brown,
        "white": .white, "gray": .gray, "black": .black, "clear": .clear, "primary": .primary,
        "secondary": .secondary, "accentColor": .accentColor, "grey": .gray,
    ]

    static let fontStyles: [String: Font] = [
        "largeTitle": .largeTitle, "title": .title, "title2": .title2, "title3": .title3, "headline": .headline,
        "subheadline": .subheadline, "body": .body, "callout": .callout, "footnote": .footnote, "caption": .caption,
        "caption2": .caption2,
    ]

    static let systemColors: [String: Color] = [
        "systemBackground": Color(uiColorCompat: "systemBackground"), "secondarySystemBackground": Color(uiColorCompat: "secondarySystemBackground"),
        "tertiarySystemBackground": Color(uiColorCompat: "tertiarySystemBackground"), "systemGroupedBackground": Color(uiColorCompat: "systemGroupedBackground"),
        "secondarySystemGroupedBackground": Color(uiColorCompat: "secondarySystemGroupedBackground"), "systemGray": .gray,
        "systemGray2": Color(uiColorCompat: "systemGray2"), "systemGray3": Color(uiColorCompat: "systemGray3"),
        "systemGray4": Color(uiColorCompat: "systemGray4"), "systemGray5": Color(uiColorCompat: "systemGray5"),
        "systemGray6": Color(uiColorCompat: "systemGray6"), "label": .primary, "secondaryLabel": .secondary,
        "tertiaryLabel": Color(uiColorCompat: "tertiaryLabel"), "separator": Color(uiColorCompat: "separator"),
        "systemBlue": .blue, "systemRed": .red, "systemGreen": .green, "systemOrange": .orange, "systemYellow": .yellow,
        "systemPink": .pink, "systemPurple": .purple, "systemTeal": .teal, "systemIndigo": .indigo, "systemMint": .mint,
        "systemCyan": .cyan, "systemBrown": .brown, "systemFill": Color(uiColorCompat: "systemFill"),
        "secondarySystemFill": Color(uiColorCompat: "secondarySystemFill"), "tertiarySystemFill": Color(uiColorCompat: "tertiarySystemFill"),
    ]

    // MARK: - Views from values

    static func asViews(_ v: KV, _ interp: KInterpreter) -> [KView] {
        switch v {
        case .view(let view): return [view]
        case .structV(let s) where s.type.isView: return [.custom(s)]
        case .native(.color(let c)): return [.primitive("Color", [.native(.color(c))], [nil], line: 0)]
        case .native(.path): return [.primitive("PathShape", [v], [nil], line: 0)]
        case .structV(let s) where s.type.isShape: return [.primitive("UserShape", [v], [nil], line: 0)]
        case .native(.implicit(let n, _)) where colorNames[n] != nil:
            return [.primitive("Color", [.native(.color(colorNames[n]!))], [nil], line: 0)]
        case .enumV(let e) where e.type.isView:
            return []
        default: return []
        }
    }

    static func isViewLike(_ v: KV) -> Bool {
        switch v {
        case .view: return true
        case .structV(let s): return s.type.isView || s.type.isShape
        case .native(.color), .native(.path): return true
        default: return false
        }
    }

    /// Whether `name` is a method of the value itself (Color.opacity) rather than a view modifier.
    static func hasValueMethod(_ base: KV, _ name: String) -> Bool {
        switch base {
        case .native(.color): return ["opacity", "gradient", "mix", "description"].contains(name)
        default: return true
        }
    }

    static func extensionKey(_ v: KV) -> String {
        switch v {
        case .int: return "Int"
        case .double: return "Double"
        case .string: return "String"
        case .bool: return "Bool"
        case .array: return "Array"
        case .dict: return "Dictionary"
        case .set: return "Set"
        case .native(.color): return "Color"
        case .native(.date): return "Date"
        case .native(.font): return "Font"
        case .view: return "View"
        default: return v.typeName
        }
    }

    static func prefersBuiltinInit(_ name: String, _ labels: [String?]) -> Bool {
        // Keep SwiftUI's own Color(red:green:blue:) etc. even if the user also extended Color.
        if name == "Color", labels.first == "red" || labels.first == "hue" || labels.first == "white" || labels == [nil] { return true }
        return false
    }

    // MARK: - Expected argument types (implicit-member resolution)

    static func modifierArgType(_ name: String, _ label: String?) -> KETypeRef? {
        switch name {
        case "font": return .named("Font", [])
        case "foregroundColor", "tint", "accentColor", "listRowBackground", "colorMultiply":
            return .named("Color", [])
        case "foregroundStyle", "fill", "background", "stroke", "strokeBorder", "border", "shadow":
            return label == nil || label == "color" ? .named("ColorOrStyle", []) : nil
        case "animation": return label == nil ? .named("Animation", []) : nil
        case "rotationEffect", "rotation3DEffect", "hueRotation": return label == nil ? .named("Angle", []) : nil
        default: return nil
        }
    }

    static func viewArgType(_ view: String, _ label: String?) -> KETypeRef? {
        switch (view, label) {
        case (_, "colors"?): return .array(.named("Color", []))
        case (_, "color"?): return .named("Color", [])
        case ("Color", nil): return .named("UIColor", [])
        default: return nil
        }
    }

    // MARK: - Implicit members

    static func implicit(_ name: String, _ args: [KV], expectedType: String?, labels: [String?] = []) -> KV? {
        switch expectedType {
        case "Color"?, "ColorOrStyle"?, "UIColor"?:
            if let c = colorNames[name] { return .native(.color(c)) }
            if let c = systemColors[name] { return .native(.color(c)) }
        case "Font"?:
            if let f = font(name, args, labels) { return .native(.font(f)) }
        case "Animation"?:
            if let a = animation(name, args, labels) { return .native(.animation(KRef(a))) }
        case "Angle"?:
            if name == "degrees", let d = args.first?.asDouble { return .native(.angle(d)) }
            if name == "radians", let r = args.first?.asDouble { return .native(.angle(r * 180 / .pi)) }
            if name == "zero" { return .native(.angle(0)) }
        case "Date"?:
            if name == "now" { return .native(.date(Date())) }
            if name == "distantPast" { return .native(.date(.distantPast)) }
            if name == "distantFuture" { return .native(.date(.distantFuture)) }
        case "Double"?, "CGFloat"?, "Float"?:
            if name == "infinity" { return .double(.infinity) }
            if name == "zero" { return .double(0) }
            if name == "pi" { return .double(.pi) }
        default: break
        }
        // Unambiguous names, whatever the context.
        switch name {
        case "infinity": return .double(.infinity)
        case "degrees": if let d = args.first?.asDouble { return .native(.angle(d)) }
        case "radians": if let r = args.first?.asDouble { return .native(.angle(r * 180 / .pi)) }
        case "currency":
            return .native(.format(KFormat(kind: .currency(args.first?.asString ?? Locale.current.currency?.identifier ?? "USD"))))
        case "number": return .native(.format(KFormat(kind: .number)))
        case "percent": return .native(.format(KFormat(kind: .percent)))
        case "dateTime": return .native(.format(KFormat(kind: .dateTime)))
        case "system":
            if let f = font(name, args, labels) { return .native(.font(f)) }
        case "easeInOut", "easeIn", "easeOut", "linear", "spring", "bouncy", "snappy", "smooth", "interactiveSpring", "interpolatingSpring":
            if expectedType == nil || expectedType == "Animation", let a = animation(name, args, labels) { return .native(.animation(KRef(a))) }
        case "now": return .native(.date(Date()))
        default: break
        }
        if expectedType == nil, let c = colorNames[name], name != "primary", name != "secondary" { return .native(.color(c)) }
        return nil
    }

    static func font(_ name: String, _ args: [KV], _ labels: [String?]) -> Font? {
        if let f = fontStyles[name] { return f }
        if name == "system" {
            if let i = labels.firstIndex(of: "size"), let size = args[i].asDouble {
                var f = Font.system(size: size)
                if let w = labels.firstIndex(of: "weight"), case .native(.implicit(let wn, _)) = args[w] {
                    f = Font.system(size: size, weight: weight(wn), design: labels.firstIndex(of: "design").flatMap { designOf(args[$0]) } ?? .default)
                } else if let d = labels.firstIndex(of: "design") {
                    f = Font.system(size: size, design: designOf(args[d]) ?? .default)
                }
                return f
            }
            if let style = args.first, case .native(.implicit(let s, _)) = style, let base = fontStyles[s] {
                var f = base
                if let d = labels.firstIndex(of: "design"), let design = designOf(args[d]) { f = .system(textStyle(s), design: design) }
                if let w = labels.firstIndex(of: "weight"), case .native(.implicit(let wn, _)) = args[w] { f = f.weight(weight(wn)) }
                return f
            }
        }
        if name == "custom", let fam = args.first?.asString {
            let size = labels.firstIndex(of: "size").flatMap { args[$0].asDouble } ?? 17
            return .custom(fam, size: size)
        }
        return nil
    }

    static func textStyle(_ s: String) -> Font.TextStyle {
        switch s {
        case "largeTitle": return .largeTitle
        case "title": return .title
        case "title2": return .title2
        case "title3": return .title3
        case "headline": return .headline
        case "subheadline": return .subheadline
        case "callout": return .callout
        case "footnote": return .footnote
        case "caption": return .caption
        case "caption2": return .caption2
        default: return .body
        }
    }

    static func designOf(_ v: KV) -> Font.Design? {
        guard case .native(.implicit(let d, _)) = v else { return nil }
        switch d {
        case "rounded": return .rounded
        case "monospaced": return .monospaced
        case "serif": return .serif
        default: return .default
        }
    }

    static func weight(_ n: String) -> Font.Weight {
        switch n {
        case "ultraLight": return .ultraLight
        case "thin": return .thin
        case "light": return .light
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        case "heavy": return .heavy
        case "black": return .black
        default: return .regular
        }
    }

    static func animation(_ name: String, _ args: [KV], _ labels: [String?]) -> Animation? {
        func arg(_ l: String) -> Double? { labels.firstIndex(of: l).flatMap { args[$0].asDouble } }
        let duration = arg("duration")
        switch name {
        case "default": return .default
        case "easeInOut": return duration.map { .easeInOut(duration: $0) } ?? .easeInOut
        case "easeIn": return duration.map { .easeIn(duration: $0) } ?? .easeIn
        case "easeOut": return duration.map { .easeOut(duration: $0) } ?? .easeOut
        case "linear": return duration.map { .linear(duration: $0) } ?? .linear
        case "spring", "interactiveSpring", "interpolatingSpring":
            if let r = arg("response") { return .spring(response: r, dampingFraction: arg("dampingFraction") ?? 0.825) }
            if let d = arg("duration") { return .spring(duration: d, bounce: arg("bounce") ?? 0) }
            return .spring()
        case "bouncy": return .bouncy
        case "snappy": return .snappy
        case "smooth": return .smooth
        default: return nil
        }
    }

    static func environmentDefault(_ decl: KEVarDecl, _ interp: KInterpreter) -> KV {
        guard case .keyPath(_, let comps)? = decl.wrapperAttribute?.args.first?.value.keyPathComponents else { return .nilValue }
        switch comps.last ?? "" {
        case "dismiss", "presentationMode": return .native(.dismiss(KRef({})))
        case "colorScheme": return .native(.implicit("light", []))
        case "horizontalSizeClass", "verticalSizeClass": return .native(.implicit("compact", []))
        case "locale": return .native(.object("Locale", KRef(Locale.current as AnyObject)))
        case "calendar": return .native(.object("Calendar", KRef(Calendar.current as AnyObject)))
        default: return .nilValue
        }
    }

    // MARK: - Globals

    static func globalConstant(_ name: String) -> KV? {
        switch name {
        case "pi": return .double(.pi)
        default: return nil
        }
    }

    static func operatorFunction(_ name: String, _ interp: KInterpreter) -> KV? {
        let binaryOps: Set<String> = ["+", "-", "*", "/", "%", "<", ">", "<=", ">=", "==", "!=", "&&", "||"]
        guard binaryOps.contains(name) else { return nil }
        return .function(KFunction(.native(name) { [unowned interp] args, _ in
            guard args.count == 2 else { throw interp.fail("Operator \(name) needs two values") }
            switch name {
            case "<", ">", "<=", ">=": return .bool(try interp.compare(name, args[0], args[1], 0))
            case "==": return .bool(args[0] == args[1])
            case "!=": return .bool(args[0] != args[1])
            case "&&": return .bool(interp.truthy(args[0]) && interp.truthy(args[1]))
            case "||": return .bool(interp.truthy(args[0]) || interp.truthy(args[1]))
            default: return try interp.arithmetic(name, args[0], args[1], 0)
            }
        }))
    }

    static func callGlobal(_ name: String, _ argExprs: [KEArg], _ env: KEnv, _ interp: KInterpreter, _ line: Int, _ expected: KETypeRef?) throws -> KV {
        if name == "Text" {
            var args: [KV] = [], labels: [String?] = []
            for (i, a) in argExprs.enumerated() {
                if i == 0, a.label == nil, case .string(let segs) = a.value {
                    args.append(.string(try interp.stringLiteral(segs, env, localized: true))); labels.append("_literal"); continue
                }
                args.append(try interp.eval(a.value, env)); labels.append(a.label)
            }
            return .view(.primitive("Text", args, labels, line: line))
        }
        if name == "Image", argExprs.first?.label == nil, argExprs.count == 1 {
            let v = try interp.eval(argExprs[0].value, env)
            if case .view = v { return v }   // Image(uiImage:) passthrough
            return .view(.primitive("Image", [v], [nil], line: line))
        }
        if viewNames.contains(name) {
            let args = try argExprs.enumerated().map { i, a -> KV in
                // A string literal title is a LocalizedStringKey: numbers in it are formatted.
                if i == 0, a.label == nil, !assetNamedViews.contains(name), case .string(let segs) = a.value {
                    return .string(try interp.stringLiteral(segs, env, localized: true))
                }
                return try interp.eval(a.value, env, viewArgType(name, a.label))
            }
            return .view(.primitive(name, args, argExprs.map(\.label), line: line))
        }
        if name == "Color" { return try color(argExprs, env, interp, line) }
        let args = try argExprs.map { try interp.eval($0.value, env, globalArgType(name, $0.label)) }
        let labels = argExprs.map(\.label)
        return try callGlobalValues(name, args, labels, interp, line)
    }

    /// Views whose first string is a name (an asset, a URL), not a title.
    static let assetNamedViews: Set<String> = ["Image", "Color", "AsyncImage"]
    /// Modifiers whose first string is a title (LocalizedStringKey).
    static let localizedTitleModifiers: Set<String> = ["navigationTitle", "alert", "confirmationDialog", "badge", "help"]

    static func globalArgType(_ name: String, _ label: String?) -> KETypeRef? {
        switch (name, label) {
        case ("withAnimation", nil): return .named("Animation", [])
        case ("Font", _): return .named("Font", [])
        default: return nil
        }
    }

    static func color(_ argExprs: [KEArg], _ env: KEnv, _ interp: KInterpreter, _ line: Int) throws -> KV {
        let args = try argExprs.map { try interp.eval($0.value, env, $0.label == nil ? .named("UIColor", []) : nil) }
        let labels = argExprs.map(\.label)
        func d(_ l: String) -> Double? { labels.firstIndex(of: l).flatMap { args[$0].asDouble } }
        if let r = d("red"), let g = d("green"), let b = d("blue") {
            return .native(.color(Color(red: r, green: g, blue: b, opacity: d("opacity") ?? d("alpha") ?? 1)))
        }
        if let h = d("hue"), let s = d("saturation"), let b = d("brightness") {
            return .native(.color(Color(hue: h, saturation: s, brightness: b, opacity: d("opacity") ?? 1)))
        }
        if let w = d("white") { return .native(.color(Color(white: w, opacity: d("opacity") ?? 1))) }
        if let first = args.first {
            switch first {
            case .native(.color(let c)): return .native(.color(c))
            case .native(.implicit(let n, _)):
                if let c = systemColors[n] ?? colorNames[n] { return .native(.color(c)) }
            case .string(let s):
                if let hex = hexColor(s) { return .native(.color(hex)) }
                if let c = colorNames[s.lowercased()] { return .native(.color(c)) }
                return .native(.color(Color(s)))
            default: break
            }
        }
        if let hex = labels.firstIndex(of: "hex"), let s = args[hex].asString, let c = hexColor(s) { return .native(.color(c)) }
        if labels.firstIndex(of: "hex") != nil, let n = args.first?.asInt {
            return .native(.color(Color(red: Double((n >> 16) & 0xFF) / 255, green: Double((n >> 8) & 0xFF) / 255, blue: Double(n & 0xFF) / 255)))
        }
        return .native(.color(.gray))
    }

    static func hexColor(_ s: String) -> Color? {
        var h = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        if h.hasPrefix("0x") { h.removeFirst(2) }
        guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
        if h.count == 8 {
            return Color(red: Double((v >> 24) & 0xFF) / 255, green: Double((v >> 16) & 0xFF) / 255,
                         blue: Double((v >> 8) & 0xFF) / 255, opacity: Double(v & 0xFF) / 255)
        }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static func callGlobalValues(_ name: String, _ args: [KV], _ labels: [String?], _ interp: KInterpreter, _ line: Int) throws -> KV {
        func arg(_ l: String) -> KV? { labels.firstIndex(of: l).map { args[$0] } }
        let first = args.first
        switch name {
        case "print", "debugPrint", "NSLog":
            let sep = arg("separator")?.asString ?? " "
            let items = zip(args, labels).filter { $0.1 == nil }.map { interp.describe($0.0) }
            interp.console += items.joined(separator: sep) + (arg("terminator")?.asString ?? "\n")
            return .void
        case "min", "max":
            var vals = zip(args, labels).filter { $0.1 == nil }.map(\.0)
            if vals.count == 1, let a = vals[0].asArray { vals = a }
            guard var best = vals.first else { return .nilValue }
            for v in vals.dropFirst() {
                if try interp.compare(name == "min" ? "<" : ">", v, best, line) { best = v }
            }
            if vals.contains(where: { if case .double = $0 { return true }; return false }), let d = best.asDouble { return .double(d) }
            return best
        case "abs":
            if case .int(let i)? = first { return .int(abs(i)) }
            return .double(abs(first?.asDouble ?? 0))
        case "sqrt", "floor", "ceil", "round", "sin", "cos", "tan", "exp", "log", "log2", "log10", "atan", "asin", "acos", "trunc", "cbrt":
            let x = first?.asDouble ?? 0
            let fns: [String: (Double) -> Double] = ["sqrt": sqrt, "floor": floor, "ceil": ceil, "round": { $0.rounded() },
                "sin": sin, "cos": cos, "tan": tan, "exp": exp, "log": log, "log2": log2, "log10": log10, "atan": atan,
                "asin": asin, "acos": acos, "trunc": trunc, "cbrt": cbrt]
            return .double(fns[name]!(x))
        case "pow": return .double(pow(args[0].asDouble ?? 0, args[1].asDouble ?? 0))
        case "atan2": return .double(atan2(args[0].asDouble ?? 0, args[1].asDouble ?? 0))
        case "hypot": return .double(hypot(args[0].asDouble ?? 0, args[1].asDouble ?? 0))
        case "fmod": return .double(fmod(args[0].asDouble ?? 0, args[1].asDouble ?? 1))
        case "zip":
            let a = try interp.sequence(args[0]), b = try interp.sequence(args[1])
            return .array(zip(a, b).map { .tuple([$0, $1], [nil, nil]) })
        case "stride":
            guard let from = arg("from"), let by = arg("by") else { throw interp.fail("stride needs from:, to:/through:, by:", line) }
            let through = arg("through"), to = arg("to")
            if case .int(let f) = from, case .int(let s) = by, let end = (through ?? to)?.asInt {
                if through != nil { return .array(Array(stride(from: f, through: end, by: s)).map { .int($0) }) }
                return .array(Array(stride(from: f, to: end, by: s)).map { .int($0) })
            }
            let f = from.asDouble ?? 0, s = by.asDouble ?? 1, e = (through ?? to)?.asDouble ?? 0
            if through != nil { return .array(Array(stride(from: f, through: e, by: s)).map { .double($0) }) }
            return .array(Array(stride(from: f, to: e, by: s)).map { .double($0) })
        case "withAnimation":
            guard case .function(let body)? = args.last else { return .void }
            var anim: Animation? = .default
            if args.count > 1 {
                if case .native(.animation(let a)) = args[0] { anim = a.value }
                else if case .native(.implicit(let n, let a)) = args[0] { anim = animation(n, a, []) ?? .default }
                else if case .nilValue = args[0] { anim = nil }
            }
            var result: KV = .void
            var thrown: Error?
            SwiftUI.withAnimation(anim) {
                do { result = try interp.call(body, [], []) } catch { thrown = error }
            }
            if let thrown { throw thrown }
            return result
        case "type":
            return .type(.builtin(first?.typeName ?? "Any"))
        case "fatalError", "preconditionFailure", "assertionFailure":
            throw interp.fail("Fatal error: \(first.map { interp.describe($0) } ?? "")", line)
        case "precondition", "assert":
            if let c = first, !interp.truthy(c) { throw interp.fail("Assertion failed: \(args.count > 1 ? interp.describe(args[1]) : "")", line) }
            return .void
        case "swap":
            if case .binding(let a)? = args.first, case .binding(let b)? = args.last {
                let t = a.get(); a.set(b.get()); b.set(t)
            }
            return .void
        case "repeatElement":
            return .array(Array(repeating: args[0], count: arg("count")?.asInt ?? 0))
        case "Task":
            if case .function(let f)? = args.last {
                DispatchQueue.main.async {
                    do { _ = try interp.entry { try interp.call(f, [], []) } } catch { interp.report(error) }
                }
            }
            return .native(.object("Task", KRef(NSObject())))
        default:
            return try construct(name, args, labels, interp, line)
        }
    }

    // MARK: - Constructors of built-in types

    static func construct(_ name: String, _ args: [KV], _ labels: [String?], _ interp: KInterpreter, _ line: Int) throws -> KV {
        func arg(_ l: String) -> KV? { labels.firstIndex(of: l).map { args[$0] } }
        let first = args.first
        switch name {
        case "Int", "Int64", "Int32", "UInt", "Int16", "Int8":
            switch first {
            case .int(let i)?: return .int(i)
            case .double(let d)?: return d.isFinite ? .int(Int(d)) : .nilValue
            case .string(let s)?: return Int(s.trimmingCharacters(in: .whitespaces)).map { .int($0) } ?? .nilValue
            case .bool(let b)?: return .int(b ? 1 : 0)
            default: return .int(0)
            }
        case "Double", "CGFloat", "Float", "TimeInterval", "Float64":
            switch first {
            case .int(let i)?: return .double(Double(i))
            case .double(let d)?: return .double(d)
            case .string(let s)?: return Double(s.trimmingCharacters(in: .whitespaces)).map { .double($0) } ?? .nilValue
            default: return .double(0)
            }
        case "Bool":
            if case .string(let s)? = first { return s == "true" ? .bool(true) : (s == "false" ? .bool(false) : .nilValue) }
            return .bool(first.map { interp.truthy($0) } ?? false)
        case "String", "Substring", "Character":
            if let f = arg("format")?.asString {
                return .string(format(f, Array(args.dropFirst()), interp))
            }
            if let r = arg("repeating") {
                return .string(String(repeating: interp.describe(r), count: arg("count")?.asInt ?? 0))
            }
            if let d = arg("describing") { return .string(interp.describe(d)) }
            if let d = arg("data") { return dataValue(d).flatMap { String(data: $0, encoding: .utf8) }.map { .string($0) } ?? .nilValue }
            if case .array(let chars)? = first { return .string(chars.map { interp.describe($0) }.joined()) }
            return .string(first.map { interp.describe($0) } ?? "")
        case "UUID":
            if let s = arg("uuidString")?.asString { return UUID(uuidString: s).map { .native(.uuid($0)) } ?? .nilValue }
            return .native(.uuid(UUID()))
        case "Date":
            if let s = arg("timeIntervalSinceNow")?.asDouble { return .native(.date(Date(timeIntervalSinceNow: s))) }
            if let s = arg("timeIntervalSince1970")?.asDouble { return .native(.date(Date(timeIntervalSince1970: s))) }
            if let s = arg("timeIntervalSinceReferenceDate")?.asDouble { return .native(.date(Date(timeIntervalSinceReferenceDate: s))) }
            if let s = arg("timeInterval")?.asDouble, case .native(.date(let d))? = arg("since") { return .native(.date(d.addingTimeInterval(s))) }
            return .native(.date(Date()))
        case "URL":
            if let s = arg("string")?.asString { return URL(string: s).map { .native(.url($0)) } ?? .nilValue }
            if let s = arg("fileURLWithPath")?.asString { return .native(.url(URL(fileURLWithPath: s))) }
            return .nilValue
        case "Set":
            if let f = first { return .set(Set(try interp.sequence(f))) }
            return .set([])
        case "Array", "ContiguousArray", "ArraySlice":
            if let r = arg("repeating") { return .array(Array(repeating: r, count: arg("count")?.asInt ?? 0)) }
            if let f = first { return .array(try interp.sequence(f)) }
            return .array([])
        case "Dictionary":
            if let g = arg("grouping"), case .function(let by)? = arg("by") {
                var d: [KV: KV] = [:]
                var order: [KV] = []
                for item in try interp.sequence(g) {
                    let k = try interp.call(by, [item], [nil])
                    if d[k] == nil { order.append(k); d[k] = .array([]) }
                    if case .array(var a)? = d[k] { a.append(item); d[k] = .array(a) }
                }
                return .dict(d)
            }
            if let u = arg("uniqueKeysWithValues") ?? first {
                var d: [KV: KV] = [:]
                for pair in try interp.sequence(u) { if case .tuple(let t, _) = pair, t.count == 2 { d[t[0]] = t[1] } }
                return .dict(d)
            }
            return .dict([:])
        case "Font":
            if case .native(.font(let f))? = first { return .native(.font(f)) }
            return .native(.font(.body))
        case "Angle":
            if let d = arg("degrees")?.asDouble { return .native(.angle(d)) }
            if let r = arg("radians")?.asDouble { return .native(.angle(r * 180 / .pi)) }
            return .native(.angle(0))
        case "GridItem":
            var item = KGridItem(size: .flexible(10, .infinity), spacing: arg("spacing")?.asDouble)
            if case .native(.implicit(let n, let a))? = first {
                switch n {
                case "fixed": item.size = .fixed(a.first?.asDouble ?? 50)
                case "adaptive": item.size = .adaptive(a.first?.asDouble ?? 80, a.count > 1 ? (a[1].asDouble ?? .infinity) : .infinity)
                default: item.size = .flexible(a.first?.asDouble ?? 10, a.count > 1 ? (a[1].asDouble ?? .infinity) : .infinity)
                }
            }
            return .native(.gridItem(item))
        case "StrokeStyle":
            var s = KStrokeStyle()
            s.lineWidth = arg("lineWidth")?.asDouble ?? 1
            if case .native(.implicit(let c, _))? = arg("lineCap") { s.lineCap = c }
            if case .native(.implicit(let j, _))? = arg("lineJoin") { s.lineJoin = j }
            if let dash = arg("dash")?.asArray { s.dash = dash.compactMap(\.asDouble) }
            return .native(.strokeStyle(s))
        case "CGSize":
            return .native(.size(arg("width")?.asDouble ?? 0, arg("height")?.asDouble ?? 0))
        case "CGPoint":
            return .native(.point(arg("x")?.asDouble ?? 0, arg("y")?.asDouble ?? 0))
        case "CGRect":
            if case .native(.point(let x, let y))? = arg("origin"), case .native(.size(let w, let h))? = arg("size") { return .native(.rect(x, y, w, h)) }
            return .native(.rect(arg("x")?.asDouble ?? 0, arg("y")?.asDouble ?? 0, arg("width")?.asDouble ?? 0, arg("height")?.asDouble ?? 0))
        case "Path":
            let box = KPathBox()
            if case .native(.rect(let x, let y, let w, let h))? = first {
                if labels.first == "ellipseIn" { box.path = Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)) }
                else if let cr = arg("cornerRadius")?.asDouble { box.path = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: cr) }
                else { box.path = Path(CGRect(x: x, y: y, width: w, height: h)) }
            }
            if case .function(let f)? = args.last { _ = try interp.call(f, [.native(.path(KRef(box)))], [nil]) }
            return .native(.path(KRef(box)))
        case "DateFormatter":
            return .native(.object("DateFormatter", KRef(DateFormatter())))
        case "NumberFormatter":
            return .native(.object("NumberFormatter", KRef(NumberFormatter())))
        case "RelativeDateTimeFormatter":
            return .native(.object("RelativeDateTimeFormatter", KRef(RelativeDateTimeFormatter())))
        case "DateComponents":
            return .tuple(args, labels)
        case "Calendar":
            return .native(.object("Calendar", KRef(Calendar.current as NSCalendar)))
        case "IndexSet":
            if let i = first?.asInt { return .native(.indexSet(IndexSet(integer: i))) }
            return .native(.indexSet(IndexSet()))
        case "UIImpactFeedbackGenerator", "UINotificationFeedbackGenerator", "UISelectionFeedbackGenerator":
            return .native(.object("Haptics", KRef(NSObject())))
        case "Animation":
            return .native(.animation(KRef(.default)))
        case "Alert":
            return .tuple(args, labels)
        case "Binding":
            if case .function(let g)? = arg("get"), case .function(let s)? = arg("set") {
                return .binding(KBinding(get: { (try? interp.call(g, [], [])) ?? .nilValue },
                                         set: { v in _ = try? interp.call(s, [v], [nil]) }))
            }
            return .binding(.constant(first ?? .nilValue))
        case "AnyView":
            return first ?? .view(.empty)
        case "Timer":
            return .native(.timer(KRef(KTimerBox())))
        case "Measurement":
            return first ?? .nilValue
        case "Locale", "TimeZone":
            return .native(.object(name, KRef(NSObject())))
        case "JSONDecoder":
            return .native(.object(name, KRef(KDecoderBox())))
        case "JSONEncoder":
            return .native(.object(name, KRef(NSObject())))
        case "URLComponents":
            let c = arg("string")?.asString.flatMap { NSURLComponents(string: $0) }
                ?? (arg("url").flatMap { if case .native(.url(let u)) = $0 { return NSURLComponents(url: u, resolvingAgainstBaseURL: false) }; return nil })
                ?? NSURLComponents()
            return arg("string") != nil && arg("string")?.asString.flatMap({ NSURLComponents(string: $0) }) == nil
                ? .nilValue : .native(.object("URLComponents", KRef(c)))
        case "URLQueryItem":
            return .native(.object("URLQueryItem", KRef(NSURLQueryItem(name: arg("name")?.asString ?? "",
                                                                       value: arg("value").flatMap { $0.isNil ? nil : interp.describe($0) }))))
        case "URLRequest":
            guard let r = request(arg("url") ?? first) else { return .nilValue }
            return .native(.object("URLRequest", KRef(NSMutableURLRequest(url: r.url!))))
        case "Data":
            return .native(.object("Data", KRef(NSData())))
        case "ClosedRange", "Range":
            return first ?? .nilValue
        default:
            if let style = styleName(name) { return .native(.implicit(style, args)) }
            throw interp.fail("Cannot find '\(name)' in scope", line)
        }
    }

    /// `SegmentedPickerStyle()` → `.segmented`, `InsetGroupedListStyle()` → `.insetGrouped`.
    static func styleName(_ name: String) -> String? {
        let suffixes = ["ListStyle", "PickerStyle", "ButtonStyle", "TextFieldStyle", "ToggleStyle", "ProgressViewStyle",
                        "DatePickerStyle", "LabelStyle", "GaugeStyle", "TabViewStyle", "IndexViewStyle", "NavigationViewStyle",
                        "MenuStyle", "GroupBoxStyle", "FormStyle", "ControlGroupStyle", "DisclosureGroupStyle"]
        guard let suffix = suffixes.first(where: { name.hasSuffix($0) && name.count > $0.count }) else { return nil }
        var base = String(name.dropLast(suffix.count))
        if base == "Default" || base == "Automatic" { return "automatic" }
        if base == "Switch" { return "switch" }
        base = base.prefix(1).lowercased() + base.dropFirst()
        return base
    }

    static func constructType(_ t: KETypeRef, _ args: [KV], _ labels: [String?], _ interp: KInterpreter, _ line: Int) throws -> KV {
        switch t.core {
        case .array:
            if let r = labels.firstIndex(of: "repeating") {
                return .array(Array(repeating: args[r], count: labels.firstIndex(of: "count").flatMap { args[$0].asInt } ?? 0))
            }
            if let f = args.first { return .array(try interp.sequence(f)) }
            return .array([])
        case .dictionary: return .dict([:])
        case .named(let n, _):
            if n == "Set" { return .set(Set(try args.first.map { try interp.sequence($0) } ?? [])) }
            return try construct(n, args, labels, interp, line)
        default:
            return .nilValue
        }
    }

    // MARK: - Static members

    static func staticMember(_ typeName: String, _ name: String, _ interp: KInterpreter, _ line: Int) throws -> KV {
        // `String.init`, `Int.init` as functions: `.map(String.init)`.
        if name == "init", ["String", "Int", "Double", "Float", "CGFloat", "Bool", "URL", "UUID", "Character"].contains(typeName) {
            return .function(KFunction(.native(typeName + ".init") { [unowned interp] args, labels in
                try construct(typeName, args, labels, interp, line)
            }))
        }
        switch typeName {
        case "Color", "UIColor", "NSColor":
            if let c = colorNames[name] { return .native(.color(c)) }
            if let c = systemColors[name] { return .native(.color(c)) }
        case "Font":
            if let f = fontStyles[name] { return .native(.font(f)) }
        case "Double", "CGFloat", "Float", "TimeInterval":
            switch name {
            case "pi": return .double(.pi)
            case "infinity": return .double(.infinity)
            case "greatestFiniteMagnitude": return .double(.greatestFiniteMagnitude)
            case "leastNormalMagnitude": return .double(.leastNormalMagnitude)
            case "nan": return .double(.nan)
            case "zero": return .double(0)
            default: break
            }
        case "Int":
            if name == "max" { return .int(.max) }
            if name == "min" { return .int(.min) }
            if name == "zero" { return .int(0) }
        case "Date":
            if name == "now" { return .native(.date(Date())) }
            if name == "distantPast" { return .native(.date(.distantPast)) }
            if name == "distantFuture" { return .native(.date(.distantFuture)) }
        case "Animation":
            if let a = animation(name, [], []) { return .native(.animation(KRef(a))) }
        case "UserDefaults":
            if name == "standard" { return .native(.object("UserDefaults", KRef(UserDefaults.standard))) }
        case "URLSession":
            if name == "shared" { return .native(.object("URLSession", KRef(URLSession.shared))) }
        case "Calendar":
            if name == "current" || name == "autoupdatingCurrent" { return .native(.object("Calendar", KRef(Calendar.current as NSCalendar))) }
        case "DispatchQueue":
            if name == "main" { return .native(.object("DispatchQueue", KRef(DispatchQueue.main))) }
        case "Locale", "TimeZone":
            if name == "current" { return .native(.object(typeName, KRef(NSObject()))) }
        case "UIScreen":
            if name == "main" { return .native(.object("UIScreen", KRef(NSObject()))) }
        case "AnyTransition":
            return .native(.transition(name, []))
        case "Angle":
            if name == "zero" { return .native(.angle(0)) }
        case "CGRect":
            if name == "zero" { return .native(.rect(0, 0, 0, 0)) }
        case "CGPoint":
            if name == "zero" { return .native(.point(0, 0)) }
        case "CGSize":
            if name == "zero" { return .native(.size(0, 0)) }
        case "UnitPoint", "Alignment", "Edge", "HorizontalAlignment", "VerticalAlignment", "TextAlignment", "ContentMode",
             "Visibility", "ColorScheme", "Axis", "SymbolRenderingMode", "Image.Scale":
            return .native(.implicit(name, []))
        case "String":
            if name == "self" { return .type(.builtin("String")) }
        case "UIApplication":
            return .native(.object("UIApplication", KRef(NSObject())))
        default:
            break
        }
        if name == "self" { return .type(.builtin(typeName)) }
        // Treat other members of SwiftUI types symbolically (`.horizontal`, `Edge.Set.all`).
        return .native(.implicit(name, []))
    }

    static func callStatic(_ typeName: String, _ name: String, _ argExprs: [KEArg], _ env: KEnv, _ interp: KInterpreter, _ line: Int, _ expected: KETypeRef?) throws -> KV {
        let args = try argExprs.map { try interp.eval($0.value, env, typeName == "Font" ? nil : nil) }
        let labels = argExprs.map(\.label)
        func arg(_ l: String) -> KV? { labels.firstIndex(of: l).map { args[$0] } }
        switch (typeName, name) {
        case ("Int", "random"), ("Double", "random"), ("CGFloat", "random"), ("Float", "random"):
            guard case .range(let lo, let hi, let closed)? = arg("in") ?? args.first else { return .int(0) }
            if typeName == "Int", let l = lo.asInt, let h = hi.asInt {
                if closed ? l > h : l >= h { throw interp.fail("Int.random(in:) needs a non-empty range", line) }
                return .int(closed ? Int.random(in: l...h, using: &interp.rng) : Int.random(in: l..<h, using: &interp.rng))
            }
            let l = lo.asDouble ?? 0, h = hi.asDouble ?? 1
            return .double(closed ? Double.random(in: l...h, using: &interp.rng) : Double.random(in: l..<h, using: &interp.rng))
        case ("Bool", "random"):
            return .bool(Bool.random(using: &interp.rng))
        case ("Timer", "publish"):
            return .native(.publisher(arg("every")?.asDouble ?? 1))
        case ("Timer", "scheduledTimer"):
            let interval = arg("withTimeInterval")?.asDouble ?? arg("timeInterval")?.asDouble ?? 1
            let repeats = arg("repeats").map { interp.truthy($0) } ?? false
            let box = KTimerBox()
            if case .function(let block)? = args.last {
                let timerValue = KV.native(.timer(KRef(box)))
                box.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
                    MainActor.assumeIsolated {
                        do { _ = try interp.entry { try interp.call(block, [timerValue], [nil]) } } catch { interp.report(error) }
                    }
                }
            }
            return .native(.timer(KRef(box)))
        case ("Font", _):
            if let f = font(name, args, labels) { return .native(.font(f)) }
        case ("Animation", _):
            if let a = animation(name, args, labels) { return .native(.animation(KRef(a))) }
        case ("Color", _), ("UIColor", _):
            if name == "init" { return try color(argExprs, env, interp, line) }
        case ("Task", "sleep"):
            interp.warn("Task.sleep runs without waiting in Kiln.")
            return .void
        case ("Task", "detached"):
            return try callGlobalValues("Task", args, labels, interp, line)
        case ("AnyTransition", _):
            return .native(.transition(name, args))
        case ("Date", "now"):
            return .native(.date(Date()))
        case ("String", "init"), ("Int", "init"), ("Double", "init"):
            return try construct(typeName, args, labels, interp, line)
        case ("DispatchQueue", "global"):
            return .native(.object("DispatchQueue", KRef(DispatchQueue.main)))
        case ("DateFormatter", "localizedString"):
            guard case .native(.date(let d))? = arg("from") ?? args.first else { return .string("") }
            return .string(DateFormatter.localizedString(from: d, dateStyle: arg("dateStyle").map(dateStyle) ?? .none,
                                                         timeStyle: arg("timeStyle").map(dateStyle) ?? .none))
        case ("NumberFormatter", "localizedString"):
            let n = (arg("from") ?? args.first)?.asDouble ?? 0
            let f = NumberFormatter()
            if case .native(.implicit(let s, _))? = arg("number") {
                f.numberStyle = s == "currency" ? .currency : (s == "percent" ? .percent : (s == "decimal" ? .decimal : .none))
            }
            return .string(f.string(from: NSNumber(value: n)) ?? "")
        default:
            break
        }
        if name == "init" { return try construct(typeName, args, labels, interp, line) }
        // Unknown static call on a SwiftUI/Foundation type: a symbolic value.
        return .native(.implicit(name, args))
    }

    // MARK: - Native calls (callable natives)

    static func callNative(_ n: KNative, _ args: [KV], _ labels: [String?], _ interp: KInterpreter, _ line: Int) throws -> KV {
        switch n {
        case .dismiss(let action):
            action.value()
            return .void
        case .implicit(let name, _):
            // `.degrees(…)` stored then called — treat as a fresh implicit member.
            return implicit(name, args, expectedType: nil, labels: labels) ?? .native(.implicit(name, args))
        default:
            throw interp.fail("\(n.kindName) is not a function", line)
        }
    }

    // MARK: - Members of built-in values

    static func member(_ base: KV, _ name: String, _ interp: KInterpreter, _ line: Int) throws -> KV {
        switch base {
        case .string(let s):
            switch name {
            case "count": return .int(s.count)
            case "isEmpty": return .bool(s.isEmpty)
            case "first": return s.first.map { .string(String($0)) } ?? .nilValue
            case "last": return s.last.map { .string(String($0)) } ?? .nilValue
            case "capitalized": return .string(s.capitalized)
            case "localizedCapitalized": return .string(s.localizedCapitalized)
            case "uppercased": return .string(s.uppercased())
            case "lowercased": return .string(s.lowercased())
            case "description": return .string(s)
            case "isNumber": return .bool(s.allSatisfy(\.isNumber))
            case "isLetter": return .bool(s.allSatisfy(\.isLetter))
            case "isUppercase": return .bool(s.allSatisfy(\.isUppercase))
            case "isLowercase": return .bool(s.allSatisfy(\.isLowercase))
            case "isWhitespace": return .bool(s.allSatisfy(\.isWhitespace))
            case "isPunctuation": return .bool(s.allSatisfy(\.isPunctuation))
            case "wholeNumberValue": return s.first?.wholeNumberValue.map { .int($0) } ?? .nilValue
            case "utf8": return .array(s.utf8.map { .int(Int($0)) })
            case "unicodeScalars": return .array(s.unicodeScalars.map { .string(String($0)) })
            case "startIndex": return .int(0)
            case "endIndex": return .int(s.count)
            case "indices": return .array((0..<s.count).map { .int($0) })
            default: break
            }
        case .array(let a):
            switch name {
            case "count": return .int(a.count)
            case "isEmpty": return .bool(a.isEmpty)
            case "first": return a.first ?? .nilValue
            case "last": return a.last ?? .nilValue
            case "indices": return .range(.int(0), .int(a.count), closed: false)
            case "startIndex": return .int(0)
            case "endIndex": return .int(a.count)
            case "description": return .string(interp.describe(base))
            case "lazy": return base
            default: break
            }
        case .set(let s):
            switch name {
            case "count": return .int(s.count)
            case "isEmpty": return .bool(s.isEmpty)
            case "first": return s.first ?? .nilValue
            default: break
            }
        case .dict(let d):
            switch name {
            case "count": return .int(d.count)
            case "isEmpty": return .bool(d.isEmpty)
            case "keys": return .array(Array(d.keys).sorted(by: { interp.describe($0) < interp.describe($1) }))
            case "values": return .array(d.keys.sorted(by: { interp.describe($0) < interp.describe($1) }).map { d[$0]! })
            case "first": return d.first.map { .tuple([$0.key, $0.value], ["key", "value"]) } ?? .nilValue
            default: break
            }
        case .int(let i):
            switch name {
            case "description": return .string(String(i))
            case "magnitude": return .int(i.magnitude > UInt(Int.max) ? Int.max : Int(i.magnitude))
            case "isZero": return .bool(i == 0)
            case "signum": return .int(i.signum())
            default: break
            }
        case .double(let d):
            switch name {
            case "description": return .string(String(describing: d))
            case "magnitude": return .double(d.magnitude)
            case "isNaN": return .bool(d.isNaN)
            case "isFinite": return .bool(d.isFinite)
            case "isInfinite": return .bool(d.isInfinite)
            case "isZero": return .bool(d == 0)
            default: break
            }
        case .bool(let b):
            if name == "description" { return .string(b ? "true" : "false") }
            if name == "toggled" { return .bool(!b) }
        case .range(let lo, let hi, let closed):
            switch name {
            case "lowerBound": return lo
            case "upperBound": return hi
            case "count":
                if let l = lo.asInt, let h = hi.asInt { return .int(max(0, (closed ? h + 1 : h) - l)) }
            case "isEmpty":
                if let l = lo.asInt, let h = hi.asInt { return .bool(closed ? h < l : h <= l) }
            case "first": return lo
            case "last": if let h = hi.asInt { return .int(closed ? h : h - 1) }
            default: break
            }
        case .native(let n):
            return try nativeMember(n, name, interp, line)
        case .function:
            break
        default:
            break
        }
        throw interp.fail("Value of type '\(base.typeName)' has no member '\(name)'", line)
    }

    static func nativeMember(_ n: KNative, _ name: String, _ interp: KInterpreter, _ line: Int) throws -> KV {
        switch n {
        case .uuid(let u):
            if name == "uuidString" || name == "description" { return .string(u.uuidString) }
            if name == "hashValue" { return .int(u.hashValue) }
        case .date(let d):
            switch name {
            case "timeIntervalSinceNow": return .double(d.timeIntervalSinceNow)
            case "timeIntervalSince1970": return .double(d.timeIntervalSince1970)
            case "timeIntervalSinceReferenceDate": return .double(d.timeIntervalSinceReferenceDate)
            case "description": return .string(d.description)
            default: break
            }
        case .url(let u):
            if name == "absoluteString" { return .string(u.absoluteString) }
            if name == "host" { return u.host.map { .string($0) } ?? .nilValue }
            if name == "lastPathComponent" { return .string(u.lastPathComponent) }
        case .color(let c):
            if name == "gradient" { return .view(.primitive("LinearGradient", [.array([.native(.color(c.opacity(0.8))), .native(.color(c))])], ["colors"], line: line)) }
            if name == "description" { return .string(c.description) }
        case .font(let f):
            switch name {
            case "bold": return .native(.font(f.bold()))
            case "italic": return .native(.font(f.italic()))
            case "monospaced": return .native(.font(f.monospaced()))
            case "monospacedDigit": return .native(.font(f.monospacedDigit()))
            case "smallCaps": return .native(.font(f.smallCaps()))
            default: break
            }
        case .implicit(let base, let args):
            // A chain on a symbolic value: `.white.opacity`, `.title2.bold`, `.number.precision`.
            if let resolved = implicit(base, args, expectedType: colorNames[base] != nil ? "Color" : (fontStyles[base] != nil ? "Font" : nil)) {
                if case .native(let r) = resolved, r != n { return try nativeMember(r, name, interp, line) }
            }
            return .native(.implicit(base + "." + name, args))
        case .format(let f):
            var g = f
            if name == "grouping" { g.grouping = false; return .native(.format(g)) }
            g.components.append(name)
            return .native(.format(g))
        case .size(let w, let h):
            if name == "width" { return .double(w) }
            if name == "height" { return .double(h) }
        case .rect(let x, let y, let w, let h):
            switch name {
            case "width": return .double(w)
            case "height": return .double(h)
            case "minX": return .double(x)
            case "minY": return .double(y)
            case "midX": return .double(x + w / 2)
            case "midY": return .double(y + h / 2)
            case "maxX": return .double(x + w)
            case "maxY": return .double(y + h)
            case "origin": return .native(.point(x, y))
            case "size": return .native(.size(w, h))
            default: break
            }
        case .point(let x, let y):
            if name == "x" { return .double(x) }
            if name == "y" { return .double(y) }
        case .angle(let d):
            if name == "degrees" { return .double(d) }
            if name == "radians" { return .double(d * .pi / 180) }
        case .object(let kind, let ref):
            if let v = networkMember(kind, ref, name) { return v }
            switch (kind, name) {
            case ("UIScreen", "bounds"): return .tuple([.double(0), .double(0), .double(402), .double(874)], ["x", "y", "width", "height"])
            case ("UIScreen", "main"): return .native(n)
            case ("DateFormatter", "dateFormat"): return .string((ref.value as! DateFormatter).dateFormat ?? "")
            case ("Locale", "identifier"): return .string(Locale.current.identifier)
            default: break
            }
        case .timer(let t):
            if name == "isValid" { return .bool(t.value.timer?.isValid ?? false) }
        case .indexSet(let s):
            if name == "first" { return s.first.map { .int($0) } ?? .nilValue }
            if name == "count" { return .int(s.count) }
        default: break
        }
        if name == "self" { return .native(n) }
        throw interp.fail("Value of type '\(n.kindName)' has no member '\(name)'", line)
    }

    static func setNativeMember(_ n: KNative, _ name: String, _ value: KV) -> Bool {
        guard case .object(let kind, let ref) = n else { return false }
        if setNetworkMember(kind, ref, name, value) { return true }
        switch (kind, name) {
        case ("DateFormatter", "dateStyle"):
            (ref.value as! DateFormatter).dateStyle = dateStyle(value); return true
        case ("DateFormatter", "timeStyle"):
            (ref.value as! DateFormatter).timeStyle = dateStyle(value); return true
        case ("DateFormatter", "dateFormat"):
            (ref.value as! DateFormatter).dateFormat = value.asString; return true
        case ("NumberFormatter", "numberStyle"):
            if case .native(.implicit(let s, _)) = value {
                let f = ref.value as! NumberFormatter
                f.numberStyle = s == "currency" ? .currency : (s == "percent" ? .percent : (s == "decimal" ? .decimal : .none))
            }
            return true
        case ("NumberFormatter", "maximumFractionDigits"):
            (ref.value as! NumberFormatter).maximumFractionDigits = value.asInt ?? 2; return true
        case ("NumberFormatter", "minimumFractionDigits"):
            (ref.value as! NumberFormatter).minimumFractionDigits = value.asInt ?? 0; return true
        case ("NumberFormatter", "currencyCode"):
            (ref.value as! NumberFormatter).currencyCode = value.asString; return true
        default:
            return true   // accept and ignore other formatter settings
        }
    }

    static func dateStyle(_ v: KV) -> DateFormatter.Style {
        guard case .native(.implicit(let s, _)) = v else { return .none }
        switch s {
        case "short": return .short
        case "medium": return .medium
        case "long": return .long
        case "full": return .full
        default: return .none
        }
    }

    // MARK: - Methods of built-in values

    /// Returns the result and, for mutating methods, the receiver's new value.
    static func callMethod(_ base: KV, _ name: String, _ args: [KV], _ labels: [String?], _ interp: KInterpreter, _ line: Int) throws -> (KV, KV?) {
        func arg(_ l: String) -> KV? { labels.firstIndex(of: l).map { args[$0] } }
        func fn(_ i: Int = 0) throws -> (KV) throws -> KV {
            guard i < args.count else { throw interp.fail("'\(name)' needs a closure", line) }
            return try applier(args[i], interp, line)
        }
        func fn2(_ i: Int = 0) throws -> (KV, KV) throws -> KV {
            guard i < args.count else { throw interp.fail("'\(name)' needs a closure", line) }
            let f = args[i]
            return { a, b in
                switch f {
                case .function(let fun): return try interp.call(fun, [a, b], [nil, nil])
                case .native(.keyPath(let comps)): return try interp.member(a, comps.first ?? "self", line: line)
                default: throw interp.fail("'\(name)' needs a closure", line)
                }
            }
        }

        // Optional.map / flatMap on a present value (Kiln keeps optionals
        // unwrapped): `year.map(String.init)`, `date.map { $0.formatted() }`.
        if name == "map" || name == "flatMap", args.count == 1 {
            switch base {
            case .int, .double, .bool, .structV, .enumV, .object, .native(.date), .native(.url), .native(.uuid), .native(.color):
                return (try fn()(base), nil)
            default: break
            }
        }

        switch base {
        case .array(var a):
            switch name {
            case "append":
                if let c = arg("contentsOf") { a.append(contentsOf: try interp.sequence(c)) } else if let x = args.first { a.append(x) }
                return (.void, .array(a))
            case "insert":
                let at = arg("at")?.asInt ?? 0
                if let c = arg("contentsOf") { a.insert(contentsOf: try interp.sequence(c), at: min(max(at, 0), a.count)) }
                else if let x = args.first { a.insert(x, at: min(max(at, 0), a.count)) }
                return (.void, .array(a))
            case "remove":
                if let offs = arg("atOffsets"), case .native(.indexSet(let set)) = offs {
                    for i in set.sorted(by: >) where i < a.count { a.remove(at: i) }
                    return (.void, .array(a))
                }
                guard let i = (arg("at") ?? args.first)?.asInt, i >= 0, i < a.count else { throw interp.fail("Index out of range in remove(at:)", line) }
                let removed = a.remove(at: i)
                return (removed, .array(a))
            case "removeFirst":
                guard !a.isEmpty else { throw interp.fail("Can't remove the first element from an empty array", line) }
                if let n = args.first?.asInt { a.removeFirst(min(n, a.count)); return (.void, .array(a)) }
                let x = a.removeFirst(); return (x, .array(a))
            case "removeLast":
                guard !a.isEmpty else { throw interp.fail("Can't remove the last element from an empty array", line) }
                if let n = args.first?.asInt { a.removeLast(min(n, a.count)); return (.void, .array(a)) }
                let x = a.removeLast(); return (x, .array(a))
            case "popLast":
                let x = a.popLast() ?? .nilValue; return (x, .array(a))
            case "removeAll":
                if !args.isEmpty { let f = try fn(); a = try a.filter { !interp.truthy(try f($0)) } } else { a.removeAll() }
                return (.void, .array(a))
            case "removeSubrange":
                if case .range(let lo, let hi, let closed)? = args.first, let l = lo.asInt, let h = hi.asInt {
                    a.removeSubrange(l..<min(closed ? h + 1 : h, a.count))
                }
                return (.void, .array(a))
            case "move":
                if case .native(.indexSet(let from))? = arg("fromOffsets"), let to = arg("toOffset")?.asInt {
                    a.move(fromOffsets: from, toOffset: to)
                }
                return (.void, .array(a))
            case "swapAt":
                if let i = args[0].asInt, let j = args[1].asInt, i < a.count, j < a.count { a.swapAt(i, j) }
                return (.void, .array(a))
            case "sort":
                a = try sortValues(a, args, labels, interp, line)
                return (.void, .array(a))
            case "reverse": a.reverse(); return (.void, .array(a))
            case "shuffle": a.shuffle(using: &interp.rng); return (.void, .array(a))
            case "toggle": break
            default: break
            }
            return (try arrayQuery(a, name, args, labels, interp, line, fn, fn2), nil)

        case .set(var s):
            switch name {
            case "insert":
                let (inserted, _) = s.insert(args[0])
                return (.tuple([.bool(inserted), args[0]], ["inserted", "memberAfterInsert"]), .set(s))
            case "remove":
                let r = s.remove(args[0]) ?? .nilValue
                return (r, .set(s))
            case "removeAll": s.removeAll(); return (.void, .set(s))
            case "formUnion": s.formUnion(try interp.sequence(args[0])); return (.void, .set(s))
            case "formIntersection": s.formIntersection(try interp.sequence(args[0])); return (.void, .set(s))
            case "subtract": s.subtract(try interp.sequence(args[0])); return (.void, .set(s))
            case "contains":
                if labels.first == "where" { let f = try fn(); return (.bool(try s.contains { interp.truthy(try f($0)) }), nil) }
                return (.bool(s.contains(args[0])), nil)
            case "union": return (.set(s.union(try interp.sequence(args[0]))), nil)
            case "intersection": return (.set(s.intersection(try interp.sequence(args[0]))), nil)
            case "subtracting": return (.set(s.subtracting(try interp.sequence(args[0]))), nil)
            case "symmetricDifference": return (.set(s.symmetricDifference(try interp.sequence(args[0]))), nil)
            case "isSubset": return (.bool(s.isSubset(of: try interp.sequence(args[0]))), nil)
            case "isSuperset": return (.bool(s.isSuperset(of: try interp.sequence(args[0]))), nil)
            case "isDisjoint": return (.bool(s.isDisjoint(with: try interp.sequence(args[0]))), nil)
            default:
                let sorted = Array(s)
                return (try arrayQuery(sorted, name, args, labels, interp, line, fn, fn2), nil)
            }

        case .dict(var d):
            switch name {
            case "removeValue":
                let k = arg("forKey") ?? args[0]
                let r = d.removeValue(forKey: k) ?? .nilValue
                return (r, .dict(d))
            case "updateValue":
                let k = arg("forKey") ?? args[1]
                let old = d.updateValue(args[0], forKey: k) ?? .nilValue
                return (old, .dict(d))
            case "removeAll": d.removeAll(); return (.void, .dict(d))
            case "merge":
                if case .dict(let other) = args[0] {
                    for (k, v) in other {
                        if let existing = d[k], args.count > 1 { d[k] = try fn2(1)(existing, v) } else { d[k] = v }
                    }
                }
                return (.void, .dict(d))
            case "mapValues":
                let f = try fn()
                var out: [KV: KV] = [:]
                for (k, v) in d { out[k] = try f(v) }
                return (.dict(out), nil)
            case "compactMapValues":
                let f = try fn()
                var out: [KV: KV] = [:]
                for (k, v) in d { let r = try f(v); if !r.isNil { out[k] = r } }
                return (.dict(out), nil)
            case "filter":
                let f = try fn()
                var out: [KV: KV] = [:]
                for (k, v) in d where interp.truthy(try f(.tuple([k, v], ["key", "value"]))) { out[k] = v }
                return (.dict(out), nil)
            case "index", "keys":
                break
            default:
                let pairs: [KV] = d.keys.sorted(by: { interp.describe($0) < interp.describe($1) }).map { .tuple([$0, d[$0]!], ["key", "value"]) }
                return (try arrayQuery(pairs, name, args, labels, interp, line, fn, fn2), nil)
            }

        case .string(var s):
            switch name {
            case "append":
                s += args.first.map { interp.describe($0) } ?? ""
                return (.void, .string(s))
            case "removeLast":
                guard !s.isEmpty else { throw interp.fail("Can't remove from an empty string", line) }
                let c = s.removeLast(); return (.string(String(c)), .string(s))
            case "removeFirst":
                guard !s.isEmpty else { throw interp.fail("Can't remove from an empty string", line) }
                let c = s.removeFirst(); return (.string(String(c)), .string(s))
            case "removeAll":
                if !args.isEmpty { let f = try fn(); s = String(try s.filter { !interp.truthy(try f(.string(String($0)))) }) } else { s = "" }
                return (.void, .string(s))
            case "insert":
                if let c = args.first, let at = arg("at")?.asInt {
                    let idx = s.index(s.startIndex, offsetBy: min(max(at, 0), s.count))
                    s.insert(contentsOf: interp.describe(c), at: idx)
                }
                return (.void, .string(s))
            case "uppercased": return (.string(s.uppercased()), nil)
            case "lowercased": return (.string(s.lowercased()), nil)
            case "capitalized": return (.string(s.capitalized), nil)
            case "hasPrefix": return (.bool(s.hasPrefix(args[0].asString ?? "")), nil)
            case "hasSuffix": return (.bool(s.hasSuffix(args[0].asString ?? "")), nil)
            case "contains":
                if labels.first == "where" { let f = try fn(); return (.bool(try s.contains { interp.truthy(try f(.string(String($0)))) }), nil) }
                return (.bool(s.contains(args[0].asString ?? "")), nil)
            case "localizedCaseInsensitiveContains", "localizedStandardContains":
                return (.bool(s.localizedCaseInsensitiveContains(args[0].asString ?? "")), nil)
            case "lowercasedContains": return (.bool(s.lowercased().contains(args[0].asString?.lowercased() ?? "")), nil)
            case "split":
                let sep = arg("separator")?.asString ?? args.first?.asString ?? " "
                let maxSplits = arg("maxSplits")?.asInt ?? Int.max
                let omit = arg("omittingEmptySubsequences").map { interp.truthy($0) } ?? true
                if let ch = sep.first, sep.count == 1 {
                    return (.array(s.split(separator: ch, maxSplits: maxSplits, omittingEmptySubsequences: omit).map { .string(String($0)) }), nil)
                }
                return (.array(s.components(separatedBy: sep).filter { !omit || !$0.isEmpty }.map { .string($0) }), nil)
            case "components":
                if let sep = arg("separatedBy")?.asString { return (.array(s.components(separatedBy: sep).map { .string($0) }), nil) }
                return (.array(s.components(separatedBy: .whitespaces).map { .string($0) }), nil)
            case "trimmingCharacters":
                let set: CharacterSet = {
                    if case .native(.implicit(let n, _))? = args.first {
                        switch n {
                        case "whitespaces": return .whitespaces
                        case "newlines": return .newlines
                        case "punctuationCharacters": return .punctuationCharacters
                        case "decimalDigits": return .decimalDigits
                        default: return .whitespacesAndNewlines
                        }
                    }
                    return .whitespacesAndNewlines
                }()
                return (.string(s.trimmingCharacters(in: set)), nil)
            case "replacingOccurrences":
                return (.string(s.replacingOccurrences(of: arg("of")?.asString ?? "", with: arg("with")?.asString ?? "")), nil)
            case "prefix":
                if let n = args.first?.asInt { return (.string(String(s.prefix(n))), nil) }
                if labels.first == "while" { let f = try fn(); return (.string(String(try s.prefix { interp.truthy(try f(.string(String($0)))) })), nil) }
            case "suffix":
                if let n = args.first?.asInt { return (.string(String(s.suffix(n))), nil) }
            case "dropFirst": return (.string(String(s.dropFirst(args.first?.asInt ?? 1))), nil)
            case "dropLast": return (.string(String(s.dropLast(args.first?.asInt ?? 1))), nil)
            case "reversed": return (.string(String(s.reversed())), nil)
            case "padding":
                let len = arg("toLength")?.asInt ?? s.count
                let pad = arg("withPad")?.asString ?? " "
                return (.string(s.padding(toLength: len, withPad: pad, startingAt: 0)), nil)
            case "isEmpty": return (.bool(s.isEmpty), nil)
            case "starts": return (.bool(s.hasPrefix(arg("with")?.asString ?? "")), nil)
            case "lowercasedFirst": break
            case "index", "firstIndex":
                if let c = args.first?.asString, let r = s.firstIndex(of: Character(c)) { return (.int(s.distance(from: s.startIndex, to: r)), nil) }
                return (.nilValue, nil)
            case "range":
                if let sub = arg("of")?.asString, let r = s.range(of: sub, options: .caseInsensitive) {
                    return (.range(.int(s.distance(from: s.startIndex, to: r.lowerBound)), .int(s.distance(from: s.startIndex, to: r.upperBound)), closed: false), nil)
                }
                return (.nilValue, nil)
            case "formatted": return (.string(s), nil)
            case "data": return (.native(.object("Data", KRef(Data(s.utf8) as NSData))), nil)
            default: break
            }
            let chars = s.map { KV.string(String($0)) }
            return (try arrayQuery(chars, name, args, labels, interp, line, fn, fn2), nil)

        case .int(let i):
            switch name {
            case "isMultiple": return (.bool(i.isMultiple(of: (arg("of") ?? args[0]).asInt ?? 1)), nil)
            case "formatted": return (.string(formatted(base, args.first ?? .nilValue, interp)), nil)
            case "advanced": return (.int(i + ((arg("by") ?? args[0]).asInt ?? 0)), nil)
            case "distance": return (.int(((arg("to") ?? args[0]).asInt ?? 0) - i), nil)
            case "quotientAndRemainder":
                let d = (arg("dividingBy") ?? args[0]).asInt ?? 1
                let (q, r) = i.quotientAndRemainder(dividingBy: d)
                return (.tuple([.int(q), .int(r)], ["quotient", "remainder"]), nil)
            case "clamped":
                if case .range(let lo, let hi, _)? = arg("to") { return (.int(min(max(i, lo.asInt ?? i), hi.asInt ?? i)), nil) }
            default: break
            }
            return (try doubleMethod(Double(i), name, args, labels, interp, line, isInt: true), nil)

        case .double(let d):
            return (try doubleMethod(d, name, args, labels, interp, line, isInt: false), nil)

        case .bool(let b):
            if name == "toggle" { return (.void, .bool(!b)) }

        case .range(let lo, let hi, let closed):
            switch name {
            case "contains":
                if labels.first == "where" { break }
                return (.bool(interp.rangeContains(base, args[0])), nil)
            case "clamped":
                return (base, nil)
            default:
                _ = (lo, hi, closed)
                let items = try interp.sequence(base)
                return (try arrayQuery(items, name, args, labels, interp, line, fn, fn2), nil)
            }

        case .native(let n):
            return (try nativeMethod(n, name, args, labels, interp, line), nil)

        case .nilValue:
            return (.nilValue, nil)

        case .tuple(let vals, _):
            if name == "map" { return (try arrayQuery(vals, name, args, labels, interp, line, fn, fn2), nil) }

        default:
            break
        }
        throw interp.fail("Value of type '\(base.typeName)' has no method '\(name)'", line)
    }

    /// Turn a closure argument (a function, a key path, an operator) into a callable.
    static func applier(_ f: KV, _ interp: KInterpreter, _ line: Int) throws -> (KV) throws -> KV {
        switch f {
        case .function(let fun): return { x in try interp.call(fun, [x], [nil]) }
        case .native(.keyPath(let comps)):
            return { x in
                var v = x
                for c in comps where c != "self" { v = try interp.member(v, c, line: line) }
                return v
            }
        case .type(.user(let t)):
            return { x in try interp.instantiate(t, args: [x], labels: [nil], line: line) }
        case .type(.builtin(let n)):
            return { x in try construct(n, [x], [nil], interp, line) }
        default:
            throw interp.fail("Expected a closure, found \(interp.describe(f))", line)
        }
    }

    static func sortValues(_ a: [KV], _ args: [KV], _ labels: [String?], _ interp: KInterpreter, _ line: Int) throws -> [KV] {
        if let f = args.first {
            var err: Error?
            let sorted = a.sorted { x, y in
                if err != nil { return false }
                do {
                    switch f {
                    case .function(let fun): return interp.truthy(try interp.call(fun, [x, y], [nil, nil]))
                    case .native(.keyPath(let comps)):
                        var vx = x, vy = y
                        for c in comps where c != "self" { vx = try interp.member(vx, c, line: line); vy = try interp.member(vy, c, line: line) }
                        return try interp.compare("<", vx, vy, line)
                    default: return false
                    }
                } catch { err = error; return false }
            }
            if let err { throw err }
            return sorted
        }
        var err: Error?
        let sorted = a.sorted { x, y in
            do { return try interp.compare("<", x, y, line) } catch { err = error; return false }
        }
        if let err { throw err }
        return sorted
    }

    static func arrayQuery(_ a: [KV], _ name: String, _ args: [KV], _ labels: [String?], _ interp: KInterpreter, _ line: Int,
                           _ fn: (Int) throws -> (KV) throws -> KV, _ fn2: (Int) throws -> (KV, KV) throws -> KV) throws -> KV {
        func arg(_ l: String) -> KV? { labels.firstIndex(of: l).map { args[$0] } }
        switch name {
        case "map": let f = try fn(0); return .array(try a.map(f))
        case "compactMap": let f = try fn(0); return .array(try a.map(f).filter { !$0.isNil })
        case "flatMap": let f = try fn(0); return .array(try a.flatMap { try interp.sequence(try f($0)) })
        case "filter": let f = try fn(0); return .array(try a.filter { interp.truthy(try f($0)) })
        case "forEach": let f = try fn(0); for x in a { _ = try f(x) }; return .void
        case "reduce":
            if labels.first == "into" {
                guard case .function(let fun) = args[1] else { throw interp.fail("reduce(into:) needs a closure", line) }
                let acc = KBox(args[0])
                for x in a {
                    _ = try interp.call(fun, [.binding(KBinding(get: { acc.value }, set: { acc.value = $0 })), x], [nil, nil])
                }
                return acc.value
            }
            let f = try fn2(1)
            var acc = args[0]
            for x in a { acc = try f(acc, x) }
            return acc
        case "sorted": return .array(try sortValues(a, args, labels, interp, line))
        case "reversed": return .array(a.reversed())
        case "shuffled": return .array(a.shuffled(using: &interp.rng))
        case "randomElement": return a.randomElement(using: &interp.rng) ?? .nilValue
        case "contains":
            if labels.first == "where" || (args.first.map { if case .function = $0 { return true }; return false } ?? false) {
                let f = try fn(0); return .bool(try a.contains { interp.truthy(try f($0)) })
            }
            return .bool(a.contains(args[0]))
        case "allSatisfy": let f = try fn(0); return .bool(try a.allSatisfy { interp.truthy(try f($0)) })
        case "first":
            let f = try fn(0); return try a.first { interp.truthy(try f($0)) } ?? .nilValue
        case "last":
            let f = try fn(0); return try a.last { interp.truthy(try f($0)) } ?? .nilValue
        case "firstIndex":
            if let of = arg("of") { return a.firstIndex(of: of).map { .int($0) } ?? .nilValue }
            let f = try fn(0); return try a.firstIndex { interp.truthy(try f($0)) }.map { .int($0) } ?? .nilValue
        case "lastIndex":
            if let of = arg("of") { return a.lastIndex(of: of).map { .int($0) } ?? .nilValue }
            let f = try fn(0); return try a.lastIndex { interp.truthy(try f($0)) }.map { .int($0) } ?? .nilValue
        case "count":
            if labels.first == "where" { let f = try fn(0); return .int(try a.filter { interp.truthy(try f($0)) }.count) }
            return .int(a.count)
        case "min", "max":
            if args.isEmpty {
                var best: KV? = nil
                for x in a {
                    if let b = best {
                        if try interp.compare(name == "min" ? "<" : ">", x, b, line) { best = x }
                    } else { best = x }
                }
                return best ?? .nilValue
            }
            let f = try fn2(0)
            var best: KV? = nil
            for x in a {
                guard let b = best else { best = x; continue }
                if name == "min" {
                    if interp.truthy(try f(x, b)) { best = x }
                } else if interp.truthy(try f(b, x)) {
                    best = x
                }
            }
            return best ?? .nilValue
        case "enumerated": return .array(a.enumerated().map { .tuple([.int($0.offset), $0.element], ["offset", "element"]) })
        case "prefix":
            if let n = args.first?.asInt { return .array(Array(a.prefix(n))) }
            let f = try fn(0); return .array(try Array(a.prefix { interp.truthy(try f($0)) }))
        case "suffix": return .array(Array(a.suffix(args.first?.asInt ?? 0)))
        case "dropFirst": return .array(Array(a.dropFirst(args.first?.asInt ?? 1)))
        case "dropLast": return .array(Array(a.dropLast(args.first?.asInt ?? 1)))
        case "joined":
            let sep = arg("separator")?.asString ?? ""
            if a.allSatisfy({ if case .array = $0 { return true }; return false }) { return .array(a.flatMap { $0.asArray ?? [] }) }
            return .string(a.map { interp.describe($0) }.joined(separator: sep))
        case "split":
            return .array([.array(a)])
        case "elementsEqual": return .bool(a == (try interp.sequence(args[0])))
        case "starts": return .bool(a.starts(with: try interp.sequence(arg("with") ?? args[0])))
        case "index":
            if let of = arg("of") { return a.firstIndex(of: of).map { .int($0) } ?? .nilValue }
        case "chunked":
            let n = max(1, arg("into")?.asInt ?? 1)
            return .array(stride(from: 0, to: a.count, by: n).map { .array(Array(a[$0..<min($0 + n, a.count)])) })
        case "sum":
            return a.reduce(KV.int(0)) { acc, x in (try? interp.arithmetic("+", acc, x, line)) ?? acc }
        case "uniqued":
            var seen = Set<KV>(); return .array(a.filter { seen.insert($0).inserted })
        case "isEmpty": return .bool(a.isEmpty)
        case "makeIterator": return .array(a)
        default: break
        }
        throw interp.fail("Value of type 'Array' has no method '\(name)'", line)
    }

    static func doubleMethod(_ d: Double, _ name: String, _ args: [KV], _ labels: [String?], _ interp: KInterpreter, _ line: Int, isInt: Bool) throws -> KV {
        switch name {
        case "rounded":
            if case .native(.implicit(let rule, _))? = args.first {
                switch rule {
                case "up": return .double(d.rounded(.up))
                case "down": return .double(d.rounded(.down))
                case "towardZero": return .double(d.rounded(.towardZero))
                case "awayFromZero": return .double(d.rounded(.awayFromZero))
                case "toNearestOrEven": return .double(d.rounded(.toNearestOrEven))
                default: return .double(d.rounded())
                }
            }
            return .double(d.rounded())
        case "squareRoot": return .double(d.squareRoot())
        case "truncatingRemainder":
            return .double(d.truncatingRemainder(dividingBy: (labels.firstIndex(of: "dividingBy").map { args[$0] } ?? args.first)?.asDouble ?? 1))
        case "remainder":
            return .double(d.remainder(dividingBy: args.first?.asDouble ?? 1))
        case "formatted":
            return .string(formatted(isInt ? .int(Int(d)) : .double(d), args.first ?? .nilValue, interp))
        case "isMultiple":
            return .bool(fmod(d, args.first?.asDouble ?? 1) == 0)
        case "clamped":
            if case .range(let lo, let hi, _)? = args.first { return .double(min(max(d, lo.asDouble ?? d), hi.asDouble ?? d)) }
        case "description": return .string(String(describing: d))
        default: break
        }
        throw interp.fail("Value of type '\(isInt ? "Int" : "Double")' has no method '\(name)'", line)
    }

    static func nativeMethod(_ n: KNative, _ name: String, _ args: [KV], _ labels: [String?], _ interp: KInterpreter, _ line: Int) throws -> KV {
        func arg(_ l: String) -> KV? { labels.firstIndex(of: l).map { args[$0] } }
        switch n {
        case .color(let c):
            if name == "opacity" { return .native(.color(c.opacity(args.first?.asDouble ?? 1))) }
            if name == "mix" { return .native(.color(c)) }
        case .implicit(let base, let a):
            if let resolved = implicit(base, a, expectedType: colorNames[base] != nil ? "Color" : (fontStyles[base] != nil ? "Font" : nil)),
               case .native(let r) = resolved, r != n {
                return try nativeMethod(r, name, args, labels, interp, line)
            }
            return .native(.implicit(base + "." + name, args))
        case .font(let f):
            switch name {
            case "bold": return .native(.font(f.bold()))
            case "italic": return .native(.font(f.italic()))
            case "weight":
                if case .native(.implicit(let w, _))? = args.first { return .native(.font(f.weight(weight(w)))) }
                return .native(.font(f))
            case "monospacedDigit": return .native(.font(f.monospacedDigit()))
            case "monospaced": return .native(.font(f.monospaced()))
            case "smallCaps": return .native(.font(f.smallCaps()))
            case "leading", "width": return .native(.font(f))
            default: break
            }
        case .date(let d):
            switch name {
            case "addingTimeInterval": return .native(.date(d.addingTimeInterval(args.first?.asDouble ?? 0)))
            case "timeIntervalSince":
                if case .native(.date(let o))? = args.first { return .double(d.timeIntervalSince(o)) }
            case "distance":
                if case .native(.date(let o))? = args.first { return .double(d.distance(to: o)) }
            case "formatted":
                if let ds = arg("date"), let ts = arg("time") {
                    return .string(d.formatted(date: dateFormatStyle(ds), time: timeFormatStyle(ts)))
                }
                if let style = args.first { return .string(formatted(.native(.date(d)), style, interp)) }
                return .string(d.formatted())
            case "compare":
                if case .native(.date(let o))? = args.first { return .native(.implicit(d < o ? "orderedAscending" : (d > o ? "orderedDescending" : "orderedSame"), [])) }
            default: break
            }
        case .publisher:
            if name == "autoconnect" || name == "receive" || name == "eraseToAnyPublisher" { return .native(n) }
        case .timer(let t):
            if name == "invalidate" { t.value.invalidate(); return .void }
            if name == "fire" { t.value.timer?.fire(); return .void }
        case .format(var f):
            switch name {
            case "precision":
                if case .native(.implicit(let p, let pa))? = args.first, p == "fractionLength" {
                    if let n = pa.first?.asInt { f.fraction = n...n }
                    else if case .range(let lo, let hi, _)? = pa.first { f.fraction = (lo.asInt ?? 0)...(hi.asInt ?? 2) }
                }
                return .native(.format(f))
            case "grouping":
                f.grouping = false
                return .native(.format(f))
            default:
                f.components.append(name)
                return .native(.format(f))
            }
        case .object(let kind, let ref):
            if let v = try networkMethod(kind, ref, name, args, labels, interp, line) { return v }
            switch (kind, name) {
            case ("DispatchQueue", "asyncAfter"):
                var delay = 0.0
                if case .native(.date(let when))? = arg("deadline") ?? args.first { delay = max(0, when.timeIntervalSinceNow) }
                else if let s = (arg("deadline") ?? args.first)?.asDouble { delay = s }
                if case .function(let f)? = args.last {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        MainActor.assumeIsolated {
                            do { _ = try interp.entry { try interp.call(f, [], []) } } catch { interp.report(error) }
                        }
                    }
                }
                return .void
            case ("DispatchQueue", "async"), ("DispatchQueue", "sync"):
                if case .function(let f)? = args.last {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            do { _ = try interp.entry { try interp.call(f, [], []) } } catch { interp.report(error) }
                        }
                    }
                }
                return .void
            case ("UserDefaults", "set"):
                let key = arg("forKey")?.asString ?? ""
                let v = args.first ?? .nilValue
                switch v {
                case .int(let i): UserDefaults.standard.set(i, forKey: "kiln." + key)
                case .double(let d): UserDefaults.standard.set(d, forKey: "kiln." + key)
                case .string(let s): UserDefaults.standard.set(s, forKey: "kiln." + key)
                case .bool(let b): UserDefaults.standard.set(b, forKey: "kiln." + key)
                default: UserDefaults.standard.set(interp.describe(v), forKey: "kiln." + key)
                }
                return .void
            case ("UserDefaults", "integer"): return .int(UserDefaults.standard.integer(forKey: "kiln." + (arg("forKey")?.asString ?? "")))
            case ("UserDefaults", "double"): return .double(UserDefaults.standard.double(forKey: "kiln." + (arg("forKey")?.asString ?? "")))
            case ("UserDefaults", "bool"): return .bool(UserDefaults.standard.bool(forKey: "kiln." + (arg("forKey")?.asString ?? "")))
            case ("UserDefaults", "string"): return UserDefaults.standard.string(forKey: "kiln." + (arg("forKey")?.asString ?? "")).map { .string($0) } ?? .nilValue
            case ("UserDefaults", "object"), ("UserDefaults", "data"), ("UserDefaults", "array"), ("UserDefaults", "stringArray"), ("UserDefaults", "dictionary"):
                return .nilValue
            case ("UserDefaults", "removeObject"):
                UserDefaults.standard.removeObject(forKey: "kiln." + (arg("forKey")?.asString ?? "")); return .void
            case ("Calendar", _):
                return try calendarMethod(name, args, labels, interp, line)
            case ("DateFormatter", "string"):
                if case .native(.date(let d))? = arg("from") ?? args.first { return .string((ref.value as! DateFormatter).string(from: d)) }
                return .string("")
            case ("DateFormatter", "date"):
                if let s = (arg("from") ?? args.first)?.asString, let d = (ref.value as! DateFormatter).date(from: s) { return .native(.date(d)) }
                return .nilValue
            case ("NumberFormatter", "string"):
                let f = ref.value as! NumberFormatter
                let v = (arg("from") ?? args.first)?.asDouble ?? 0
                return f.string(from: NSNumber(value: v)).map { .string($0) } ?? .nilValue
            case ("RelativeDateTimeFormatter", "localizedString"):
                if case .native(.date(let d))? = arg("for") ?? args.first {
                    return .string((ref.value as! RelativeDateTimeFormatter).localizedString(for: d, relativeTo: Date()))
                }
                return .string("")
            case ("Haptics", _), ("UIApplication", _), ("Task", _):
                return .void
            default:
                break
            }
        case .indexSet(let s):
            if name == "contains" { return .bool(s.contains(args.first?.asInt ?? -1)) }
            if name == "map" { let f = try applier(args[0], interp, line); return .array(try s.map { try f(.int($0)) }) }
        case .angle(let d):
            if name == "degrees" { return .double(d) }
        case .rect(let x, let y, let w, let h):
            if name == "insetBy" {
                let dx = arg("dx")?.asDouble ?? 0, dy = arg("dy")?.asDouble ?? 0
                return .native(.rect(x + dx, y + dy, w - 2 * dx, h - 2 * dy))
            }
            if name == "offsetBy" { return .native(.rect(x + (arg("dx")?.asDouble ?? 0), y + (arg("dy")?.asDouble ?? 0), w, h)) }
        case .path(let ref):
            func pt(_ v: KV?) -> CGPoint {
                if case .native(.point(let px, let py))? = v { return CGPoint(x: px, y: py) }
                return .zero
            }
            func rect(_ v: KV?) -> CGRect {
                if case .native(.rect(let rx, let ry, let rw, let rh))? = v { return CGRect(x: rx, y: ry, width: rw, height: rh) }
                return .zero
            }
            func ang(_ v: KV?) -> Angle {
                if case .native(.angle(let deg))? = v { return .degrees(deg) }
                return .degrees(v?.asDouble ?? 0)
            }
            switch name {
            case "move": ref.value.path.move(to: pt(arg("to") ?? args.first))
            case "addLine": ref.value.path.addLine(to: pt(arg("to") ?? args.first))
            case "addLines": ref.value.path.addLines((args.first?.asArray ?? []).map { pt($0) })
            case "addArc":
                if let center = arg("center") {
                    ref.value.path.addArc(center: pt(center), radius: arg("radius")?.cg ?? 10,
                                          startAngle: ang(arg("startAngle")), endAngle: ang(arg("endAngle")),
                                          clockwise: arg("clockwise").map { interp.truthy($0) } ?? false)
                }
            case "addRect": ref.value.path.addRect(rect(args.first))
            case "addEllipse": ref.value.path.addEllipse(in: rect(arg("in") ?? args.first))
            case "addRoundedRect":
                var r = 8.0
                if case .native(.size(let w, _))? = arg("cornerSize") { r = w }
                if let cr = arg("cornerRadius")?.asDouble { r = cr }
                ref.value.path.addRoundedRect(in: rect(arg("in") ?? args.first), cornerSize: CGSize(width: r, height: r))
            case "addQuadCurve": ref.value.path.addQuadCurve(to: pt(arg("to")), control: pt(arg("control")))
            case "addCurve": ref.value.path.addCurve(to: pt(arg("to")), control1: pt(arg("control1")), control2: pt(arg("control2")))
            case "closeSubpath": ref.value.path.closeSubpath()
            case "addPath":
                if case .native(.path(let other))? = args.first { ref.value.path.addPath(other.value.path) }
            default: break
            }
            return .void
        default:
            break
        }
        throw interp.fail("Value of type '\(n.kindName)' has no method '\(name)'", line)
    }

    static func calendarMethod(_ name: String, _ args: [KV], _ labels: [String?], _ interp: KInterpreter, _ line: Int) throws -> KV {
        func arg(_ l: String) -> KV? { labels.firstIndex(of: l).map { args[$0] } }
        let cal = Calendar.current
        func date(_ v: KV?) -> Date? { if case .native(.date(let d))? = v { return d }; return nil }
        func component(_ v: KV?) -> Calendar.Component? {
            guard case .native(.implicit(let n, _))? = v else { return nil }
            let map: [String: Calendar.Component] = ["year": .year, "month": .month, "day": .day, "hour": .hour, "minute": .minute,
                "second": .second, "weekday": .weekday, "weekOfYear": .weekOfYear, "weekOfMonth": .weekOfMonth]
            return map[n]
        }
        switch name {
        case "component":
            if let c = component(args.first), let d = date(arg("from")) { return .int(cal.component(c, from: d)) }
        case "isDateInToday": if let d = date(args.first) { return .bool(cal.isDateInToday(d)) }
        case "isDateInYesterday": if let d = date(args.first) { return .bool(cal.isDateInYesterday(d)) }
        case "isDateInTomorrow": if let d = date(args.first) { return .bool(cal.isDateInTomorrow(d)) }
        case "isDateInWeekend": if let d = date(args.first) { return .bool(cal.isDateInWeekend(d)) }
        case "isDate":
            if let a = date(args.first), let b = date(arg("inSameDayAs")) { return .bool(cal.isDate(a, inSameDayAs: b)) }
        case "startOfDay": if let d = date(arg("for") ?? args.first) { return .native(.date(cal.startOfDay(for: d))) }
        case "date":
            if let c = component(arg("byAdding")), let v = arg("value")?.asInt, let d = date(arg("to")) {
                return cal.date(byAdding: c, value: v, to: d).map { .native(.date($0)) } ?? .nilValue
            }
        case "dateComponents":
            if let from = date(arg("from")), let to = date(arg("to")) {
                let comps = cal.dateComponents([.day, .hour, .minute, .second], from: from, to: to)
                return .tuple([.int(comps.day ?? 0), .int(comps.hour ?? 0), .int(comps.minute ?? 0), .int(comps.second ?? 0)], ["day", "hour", "minute", "second"])
            }
        default: break
        }
        throw interp.fail("Calendar.\(name) isn't supported in Kiln", line)
    }

    static func dateFormatStyle(_ v: KV) -> Date.FormatStyle.DateStyle {
        guard case .native(.implicit(let s, _)) = v else { return .abbreviated }
        switch s {
        case "omitted": return .omitted
        case "numeric": return .numeric
        case "long": return .long
        case "complete": return .complete
        default: return .abbreviated
        }
    }

    static func timeFormatStyle(_ v: KV) -> Date.FormatStyle.TimeStyle {
        guard case .native(.implicit(let s, _)) = v else { return .shortened }
        switch s {
        case "omitted": return .omitted
        case "complete": return .complete
        case "standard": return .standard
        default: return .shortened
        }
    }

    // MARK: - Formatting

    /// `String(format:)` with Swift's argument types.
    static func format(_ fmt: String, _ args: [KV], _ interp: KInterpreter) -> String {
        var cargs: [CVarArg] = []
        var specs: [Character] = []
        var i = fmt.startIndex
        while i < fmt.endIndex {
            if fmt[i] == "%" {
                var j = fmt.index(after: i)
                while j < fmt.endIndex, !"dDiuUxXoOfFeEgGcsS@%".contains(fmt[j]) { j = fmt.index(after: j) }
                if j < fmt.endIndex, fmt[j] != "%" { specs.append(fmt[j]) }
                i = j < fmt.endIndex ? fmt.index(after: j) : j
            } else { i = fmt.index(after: i) }
        }
        for (k, a) in args.enumerated() {
            let spec: Character = k < specs.count ? specs[k] : "@"
            switch spec {
            case "d", "D", "i", "u", "U", "x", "X", "o", "O", "c":
                cargs.append(a.asInt ?? Int(a.asDouble ?? 0))
            case "f", "F", "e", "E", "g", "G":
                cargs.append(a.asDouble ?? 0)
            default:
                cargs.append(interp.describe(a))
            }
        }
        let normalized = fmt.replacingOccurrences(of: "%s", with: "%@").replacingOccurrences(of: "%S", with: "%@")
        return String(format: normalized, arguments: cargs)
    }

    /// `value.formatted(style)` / `Text(value, format:)` / `"\(value, format:)"`.
    static func formatted(_ v: KV, _ style: KV, _ interp: KInterpreter) -> String {
        if case .native(.date(let d)) = v {
            if case .native(.format(let f)) = style, f.kind == .dateTime, !f.components.isEmpty {
                var fs = Date.FormatStyle()
                for c in f.components {
                    switch c {
                    case "hour": fs = fs.hour()
                    case "minute": fs = fs.minute()
                    case "second": fs = fs.second()
                    case "day": fs = fs.day()
                    case "month": fs = fs.month()
                    case "year": fs = fs.year()
                    case "weekday": fs = fs.weekday()
                    default: break
                    }
                }
                return d.formatted(fs)
            }
            if case .native(.implicit(let s, _)) = style {
                switch s {
                case "relative": return d.formatted(.relative(presentation: .named))
                case "time": return d.formatted(date: .omitted, time: .shortened)
                case "date": return d.formatted(date: .abbreviated, time: .omitted)
                default: break
                }
            }
            return d.formatted()
        }
        guard let x = v.asDouble else { return interp.describe(v) }
        let isInt: Bool = { if case .int = v { return true }; return false }()
        guard case .native(.format(let f)) = style else {
            if case .native(.implicit(let n, let a)) = style, let resolved = implicit(n, a, expectedType: nil), case .native(.format) = resolved {
                return formatted(v, resolved, interp)
            }
            return isInt ? Int(x).formatted() : x.formatted()
        }
        switch f.kind {
        case .currency(let code):
            var s = FloatingPointFormatStyle<Double>.Currency(code: code)
            if let r = f.fraction { s = s.precision(.fractionLength(r)) }
            return x.formatted(s)
        case .percent:
            var s = FloatingPointFormatStyle<Double>.Percent()
            if let r = f.fraction { s = s.precision(.fractionLength(r)) }
            return (isInt ? x / 100 : x).formatted(s)
        default:
            if isInt && f.fraction == nil { return Int(x).formatted(.number.grouping(f.grouping ? .automatic : .never)) }
            var s = FloatingPointFormatStyle<Double>.number.grouping(f.grouping ? .automatic : .never)
            if let r = f.fraction { s = s.precision(.fractionLength(r)) }
            return x.formatted(s)
        }
    }
}

extension KEExpr {
    /// `\.dismiss` inside an attribute argument.
    var keyPathComponents: KEExpr? {
        if case .keyPath = self { return self }
        return nil
    }
}

extension Color {
    /// A UIKit semantic color by name, without importing UIKit on macOS.
    init(uiColorCompat name: String) {
        #if canImport(UIKit)
        let map: [String: UIColor] = [
            "systemBackground": .systemBackground, "secondarySystemBackground": .secondarySystemBackground,
            "tertiarySystemBackground": .tertiarySystemBackground, "systemGroupedBackground": .systemGroupedBackground,
            "secondarySystemGroupedBackground": .secondarySystemGroupedBackground, "systemGray2": .systemGray2,
            "systemGray3": .systemGray3, "systemGray4": .systemGray4, "systemGray5": .systemGray5, "systemGray6": .systemGray6,
            "tertiaryLabel": .tertiaryLabel, "separator": .separator, "systemFill": .systemFill,
            "secondarySystemFill": .secondarySystemFill, "tertiarySystemFill": .tertiarySystemFill,
        ]
        self = Color(uiColor: map[name] ?? .systemGray)
        #else
        self = .gray
        #endif
    }
}
