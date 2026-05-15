//
//  ViewNode.swift
//  SwiftRunner
//
//  Created by Claw on 2/21/26.
//

import Foundation

/// AST node representing a SwiftUI view or expression
public indirect enum ViewNode: Equatable {
    // MARK: - View Components
    
    /// Text view: Text("Hello")
    case text(String)
    
    /// Image view: Image(systemName: "star")
    case systemImage(String)
    
    /// Image asset: Image("photo")
    case assetImage(String)
    
    /// Button: Button("Title") { action }
    case button(label: ViewNode, action: ViewNode?)
    
    /// Stacks
    case vStack(spacing: Double?, alignment: Alignment?, children: [ViewNode])
    case hStack(spacing: Double?, alignment: Alignment?, children: [ViewNode])
    case zStack(alignment: Alignment?, children: [ViewNode])
    
    /// ScrollView
    case scrollView(axis: Axis?, showsIndicators: Bool?, content: ViewNode)
    
    /// Shapes
    case circle
    case rectangle
    case roundedRectangle(cornerRadius: Double)
    case capsule
    
    /// Spacer
    case spacer(minLength: Double?)
    
    /// Divider
    case divider
    
    /// ForEach: ForEach(0..<5) { i in ... }
    case forEach(range: ClosedRange<Int>, variable: String, body: ViewNode)

    /// ForEach over a collection: ForEach(items, id: \.self) { item in ... }
    case forEachCollection(collection: ViewNode, variable: String, body: ViewNode)

    /// TextField: TextField("Placeholder", text: $name)
    /// SecureField: SecureField("Password", text: $pw) — isSecure = true
    case textField(placeholder: String, variable: String, isSecure: Bool)

    /// Toggle: Toggle("Label", isOn: $flag)
    case toggle(label: String, variable: String)

    /// Slider: Slider(value: $val, in: 0...100)
    case slider(variable: String, range: ClosedRange<Double>?)

    /// AsyncImage: AsyncImage(url: URL(string: "..."))
    case asyncImage(url: String)
    /// AsyncImage with a dynamic URL expression evaluated at render time,
    /// e.g. `AsyncImage(url: URL(string: book.coverURL))`.
    case asyncImageDynamic(urlExpression: ViewNode)

    // MARK: - Modifiers

    /// View with modifiers applied
    case modified(view: ViewNode, modifiers: [ViewModifier])

    // MARK: - Expressions

    /// Variable reference
    case variable(String)

    /// Binding reference: $name
    case binding(String)

    /// Array literal: [value1, value2, ...]
    case arrayLiteral([ViewNode])

    /// Subscript access: array[index]
    case subscriptAccess(object: ViewNode, index: ViewNode)

    /// Method call on an expression: obj.method(args)
    case methodCall(object: ViewNode, method: String, arguments: [Argument])
    
    /// Literal values
    case literal(LiteralValue)
    
    /// Binary expression: a + b
    case binary(left: ViewNode, op: BinaryOperator, right: ViewNode)
    
    /// Function call: print("hello")
    case functionCall(name: String, arguments: [Argument])
    
    /// Property access: color.red
    case propertyAccess(object: ViewNode, property: String)
    
    /// Assignment: let x = 5
    case assignment(name: String, isVar: Bool, value: ViewNode)

    /// `@State`-style init-once assignment. Mirrors SwiftUI's @State semantics
    /// when a struct view is inlined at a callsite: the default value is
    /// committed to `state.variables` (the @Published store) the first time
    /// the inlined view is realized, and any later realization (a re-render,
    /// or popping back and re-pushing) is a no-op so user mutations via
    /// `.task` / actions aren't clobbered back to the default. Produced by
    /// the parser when storing struct bodies in `parsedStructs`, never
    /// emitted as a normal assignment.
    case stateInit(name: String, value: ViewNode)

    /// Frozen runtime value — captures a `Value` produced by eager evaluation
    /// at view-construction time so that later re-evaluation (when SwiftUI
    /// realizes a previously-baked subtree, e.g. a NavigationLink destination)
    /// returns the original value instead of re-reading a now-stale variable
    /// reference. Has no source-level form; produced only by the renderer.
    case valueLiteral(Value)

    /// Block of statements
    case block([ViewNode])
    
    /// Interpolated string: "Hello \(name)"
    case stringInterpolation([StringInterpolationPart])

    /// Compound assignment: count += 1, isOn.toggle(), etc.
    case compoundAssignment(variable: String, op: CompoundOp, value: ViewNode)

    /// Ternary expression: condition ? trueExpr : falseExpr
    case ternary(condition: ViewNode, trueExpr: ViewNode, falseExpr: ViewNode)

    /// Conditional view: if condition { views } else { views }
    case conditional(condition: ViewNode, thenBody: ViewNode, elseBody: ViewNode?)

    // MARK: - Plan 1: Parser foundation (Stage 1 — execution mostly stubbed)

    /// switch <scrutinee> { case <pattern>: <body> ... default: <body> }
    case switchStmt(scrutinee: ViewNode, cases: [SwitchCase], defaultBody: ViewNode?)

    /// do { <body> } catch [binding] { <body> } ...
    case doCatch(body: ViewNode, clauses: [CatchClause])

    /// throw <expr>
    case throwStmt(ViewNode)

    /// guard let <var> = <value> else { <elseBlock> }
    case guardLet(variable: String, value: ViewNode, elseBlock: ViewNode)

    /// guard <cond> else { <elseBlock> }
    case guardExpr(condition: ViewNode, elseBlock: ViewNode)

    /// defer { <body> }
    case deferBlock(ViewNode)

    /// enum <Name> { case A; case B; static func ...() }
    case enumDeclaration(name: String, cases: [EnumCase], members: [ViewNode])

    /// extension <Type> { ... }
    case extensionDeclaration(target: String, members: [ViewNode])

    /// func <name>(<params>) [async] [throws] [-> <Return>] { <body> }
    case functionDecl(
        name: String,
        parameters: [FunctionParameter],
        body: ViewNode,
        isAsync: Bool,
        isThrowing: Bool
    )

    /// `return [<expr>]` — exits the enclosing function call scope.
    case returnStmt(ViewNode?)

    /// `let (a, b, _) = expr` — evaluate expr; bind each non-nil name in `names`
    /// to the corresponding index of the resulting array value.
    case tupleBinding(names: [String?], value: ViewNode)

    /// Property / subscript chain assignment: `obj.prop = value`, `arr[0] = value`,
    /// `obj.a.b = value`. The target is a chain of `.propertyAccess` and
    /// `.subscriptAccess` nodes rooted at a `.variable(name)`.
    case propertyAssignment(target: ViewNode, op: CompoundOp, value: ViewNode)

    /// `{ doc in ... }` style closure — preserves the parameter name(s) so that
    /// callers like `arr.map { doc in body }` can bind the iteration variable
    /// before evaluating the body. Without this, `doc.title` inside the body
    /// would fail to resolve (only `$0`/`0` are auto-bound).
    case closure(parameters: [String], body: ViewNode)

    // MARK: - Plan 6/8: Additional view containers

    /// LazyVGrid(columns: [...], spacing: N) { content }
    case lazyVGrid(columns: [ViewNode], spacing: Double?, content: ViewNode)

    /// LazyHGrid(rows: [...], spacing: N) { content }
    case lazyHGrid(rows: [ViewNode], spacing: Double?, content: ViewNode)

    /// GridItem(.adaptive(minimum:), .fixed(N), or .flexible())
    case gridItem(style: GridItemStyle)

    /// GeometryReader { geo in <body> } — content receives a `geo` value with
    /// `.size.width` / `.size.height` at render time.
    case geometryReader(variable: String, body: ViewNode)

    /// LinearGradient(colors: [...], startPoint: ..., endPoint: ...)
    case linearGradient(colors: [ColorValue], startPoint: UnitPoint, endPoint: UnitPoint)

    /// AsyncImage(url: ...) { phase in switch phase { case .empty: ... } }
    /// Holds per-phase view branches. Success branch's `imageBinding` names the
    /// local binding (e.g. `image` in `.success(let image)`).
    case asyncImagePhased(
        urlExpression: ViewNode,
        emptyBranch: ViewNode?,
        successBranch: ViewNode?,
        failureBranch: ViewNode?,
        imageBinding: String?
    )

    // MARK: - Navigation
    //
    // SwiftUI's NavigationStack is replicated via a real `NavigationStack`
    // SwiftUI view. NavigationLink uses the destination form
    // (`NavigationLink(destination:) { label }` or
    // `NavigationLink("Title", destination: View)`); the value-based form
    // with `.navigationDestination(for:)` isn't covered yet because it
    // requires a typed registry the interpreter doesn't model.

    /// `NavigationStack { content }` — renders a real SwiftUI NavigationStack
    /// so child `NavigationLink`s and `.navigationTitle` work end-to-end.
    case navigationStack(children: [ViewNode])

    /// `NavigationLink(destination: <view>) { <label> }`
    /// or `NavigationLink("Title", destination: <view>)`.
    case navigationLink(label: ViewNode, destination: ViewNode)

    /// Empty node
    case empty
}

// MARK: - Plan 1 supporting types

/// A single `case <pattern>: <body>` inside a switch.
public struct SwitchCase: Equatable {
    public let pattern: SwitchPattern
    public let body: ViewNode
    public init(pattern: SwitchPattern, body: ViewNode) {
        self.pattern = pattern
        self.body = body
    }
}

/// What a switch case matches against.
public enum SwitchPattern: Equatable {
    /// `case .empty:` or `case .success(let image)` — matches enum member by name.
    /// `bindings` is the list of let-bindings (empty for `.empty`, `["image"]` for
    /// `.success(let image)`).
    case caseMember(name: String, bindings: [String])
    /// `case "foo":` or `case 1:` — literal equality against the scrutinee.
    case literal(LiteralValue)
    /// `case _:` wildcard.
    case wildcard
}

/// A single `catch [binding] { body }` clause on a `do`.
public struct CatchClause: Equatable {
    public let binding: String?
    public let body: ViewNode
    public init(binding: String?, body: ViewNode) {
        self.binding = binding
        self.body = body
    }
}

/// Plan 6: GridItem styling.
public enum GridItemStyle: Equatable {
    case adaptive(minimum: Double, maximum: Double?)
    case fixed(Double)
    case flexible
}

/// Plan 7: Material background values.
public enum MaterialValue: String, Equatable {
    case ultraThin = "ultraThinMaterial"
    case thin = "thinMaterial"
    case regular = "regularMaterial"
    case thick = "thickMaterial"
    case ultraThick = "ultraThickMaterial"
    case bar = "barMaterial"
}

/// Plan 7: Button style tokens.
public enum ButtonStyleValue: String, Equatable {
    case plain, bordered, borderless
    case borderedProminent
    case automatic
}

/// Plan 7: TextField style tokens.
public enum TextFieldStyleValue: String, Equatable {
    case plain, roundedBorder, automatic
}

/// Plan 7: ControlSize tokens.
public enum ControlSizeValue: String, Equatable {
    case mini, small, regular, large, extraLarge
}

/// Plan 6: UnitPoint for gradient endpoints.
public enum UnitPoint: String, Equatable {
    case top, bottom, leading, trailing
    case topLeading, topTrailing, bottomLeading, bottomTrailing
    case center
}

/// A single parameter in a function declaration.
public struct FunctionParameter: Equatable {
    /// External label (Swift's first-position name). `nil` means no external label
    /// beyond the internal one. `_` means callers use no label.
    public let externalLabel: String?
    /// Internal binding name the body uses.
    public let internalName: String
    /// Type annotation as a source string — not used at runtime yet.
    public let typeName: String?
    public init(externalLabel: String?, internalName: String, typeName: String?) {
        self.externalLabel = externalLabel
        self.internalName = internalName
        self.typeName = typeName
    }
}

/// A single `case` inside an `enum` declaration.
public struct EnumCase: Equatable {
    public let name: String
    public let associatedTypes: [String]
    public let rawValue: ViewNode?
    public init(name: String, associatedTypes: [String] = [], rawValue: ViewNode? = nil) {
        self.name = name
        self.associatedTypes = associatedTypes
        self.rawValue = rawValue
    }
}

// MARK: - Compound Assignment

public enum CompoundOp: String, Equatable {
    case assign = "="
    case plusAssign = "+="
    case minusAssign = "-="
    case mulAssign = "*="
    case divAssign = "/="
    case toggle = "toggle"
}

/// A part of a string interpolation — either literal text or an expression
public enum StringInterpolationPart: Equatable {
    case literal(String)
    case expression(ViewNode)
}

// MARK: - Supporting Types

public enum LiteralValue: Equatable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case color(ColorValue)
    case `nil`
}

public enum ColorValue: String, Equatable, CaseIterable {
    case red, orange, yellow, green, blue, purple, pink
    case white, black, gray, clear
    case primary, secondary
}

public enum Alignment: String, Equatable, CaseIterable {
    case leading, trailing, center
    case top, bottom
    case topLeading, topTrailing
    case bottomLeading, bottomTrailing
}

public enum Axis: String, Equatable {
    case horizontal, vertical
}

public enum BinaryOperator: String, Equatable {
    case plus = "+"
    case minus = "-"
    case multiply = "*"
    case divide = "/"
    case modulo = "%"
    case equal = "=="
    case notEqual = "!="
    case less = "<"
    case greater = ">"
    case lessEqual = "<="
    case greaterEqual = ">="
    case and = "&&"
    case or = "||"
}

public struct Argument: Equatable {
    public let label: String?
    public let value: ViewNode
    
    public init(label: String? = nil, value: ViewNode) {
        self.label = label
        self.value = value
    }
}

// MARK: - View Modifiers

public enum ViewModifier: Equatable {
    // Text modifiers
    case font(FontStyle)
    case fontWeight(FontWeight)
    case foregroundColor(ColorValue)
    case foregroundStyle(ColorValue)
    
    // Layout modifiers
    case padding(PaddingInsets)
    case frame(width: Double?, height: Double?, maxWidth: Double?, maxHeight: Double?, alignment: Alignment?)
    case background(ColorValue)
    /// `.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))`
    case materialBackground(material: MaterialValue, shape: ShapeType?)
    /// `.buttonStyle(.borderedProminent)` and friends
    case buttonStyle(ButtonStyleValue)
    /// `.textFieldStyle(.plain)` / `.roundedBorder`
    case textFieldStyle(TextFieldStyleValue)
    /// `.controlSize(.small)` etc.
    case controlSize(ControlSizeValue)
    /// `.refreshable { await … }` — runs the action when the user pulls to refresh.
    case refreshable(ViewNode)
    case cornerRadius(Double)
    case clipShape(ShapeType)
    
    // Appearance
    case opacity(Double)
    case shadow(radius: Double, x: Double, y: Double)
    case overlay(ViewNode)
    case border(ColorValue, width: Double)
    
    // Sizing
    case fixedSize(horizontal: Bool, vertical: Bool)
    case aspectRatio(Double?, contentMode: ContentMode)
    
    // Text appearance
    case bold
    case italic
    case strikethrough(ColorValue?)
    case underline(ColorValue?)
    case lineLimit(Int)
    case lineSpacing(Double)
    case truncationMode(TruncationModeValue)
    case multilineTextAlignment(TextAlignmentValue)
    case minimumScaleFactor(Double)
    case textCase(TextCaseValue)
    case kerning(Double)

    // Shape modifiers
    case fill(ColorValue)
    case stroke(ColorValue, lineWidth: Double)
    case clipped

    // Image
    case resizable
    case scaledToFit
    case scaledToFill
    case renderingMode(RenderingModeValue)

    // Position & Transform
    case offset(x: Double, y: Double)
    case zIndex(Double)
    case rotationEffect(Double)  // degrees
    case scaleEffect(Double)

    // Visual effects
    case blur(Double)
    case brightness(Double)
    case contrast(Double)
    case saturation(Double)
    case grayscale(Double)
    case colorMultiply(ColorValue)
    case colorInvert
    case compositingGroup
    case mask(ViewNode)

    /// Plan 5: `.modifier(Shimmer())` — resolve `{typeName}.body(content:)` at
    /// render time, substitute `content` with the receiver view, render the body.
    case userModifier(typeName: String)

    // Interaction
    case onTapGesture(ViewNode)
    case onLongPressGesture(ViewNode)
    case disabled(Bool)
    case hidden
    case allowsHitTesting(Bool)
    case contentShape

    // Color
    case tint(ColorValue)

    // Lifecycle
    case onAppear(ViewNode?)
    case onDisappear(ViewNode?)
    case onChange(variable: String?, action: ViewNode)
    /// `.task { await … }` — runs in SwiftUI's real `.task` async context so
    /// `await URLSession.shared.data(from:)` suspends the Task without blocking
    /// the main thread. Wired through `SwiftRunnerState.runAsync`.
    case taskAction(ViewNode)

    /// `.task(id: <expr>) { await … }` — same as `.taskAction` but cancels
    /// the previous task and starts a new one whenever `<expr>`'s evaluated
    /// value changes. The renderer reads the ID's description per-render so
    /// SwiftUI's identity tracking does the cancellation for free. This is
    /// the recommended pattern for live-search debouncing.
    case taskActionWithID(idExpression: ViewNode, action: ViewNode)

    /// `.onSubmit { … }` — fires when the user presses the keyboard's submit
    /// key on a focused TextField. The action runs through `runAsync` inside
    /// a fresh Task so submit-driven network re-fetches don't block main.
    case onSubmitAction(ViewNode)

    // Animation
    case animation(AnimationType)
    case transition(TransitionType)

    // Safe area
    case ignoresSafeArea

    // Layout
    case layoutPriority(Double)
    case position(x: Double, y: Double)

    // Shape advanced
    case strokeBorder(ColorValue, lineWidth: Double)
    case trim(from: Double, to: Double)

    /// Dynamic modifier whose argument depends on runtime state (e.g., ternary color).
    /// Resolved at render time by evaluating the argument expression.
    case dynamic(name: String, argument: ViewNode)

    /// Glass effect: .glassEffect(.regular.tint(.blue), in: RoundedRectangle(cornerRadius: 16))
    /// Falls back to .ultraThinMaterial on iOS < 26.
    case glassEffect(style: GlassStyle, tint: ColorValue?, shape: ShapeType?)

    // Keyboard / Input
    case keyboardType(KeyboardTypeValue)
    case textContentType(TextContentTypeValue)
    case submitLabel(SubmitLabelValue)
    case autocapitalization(AutocapitalizationValue)
    /// `.scrollDismissesKeyboard(.interactively)` etc. — wired to SwiftUI's
    /// real `.scrollDismissesKeyboard(_:)` modifier on a ScrollView.
    case scrollDismissesKeyboard(ScrollDismissMode)

    /// `.frame(width: <expr>, height: <expr>, maxWidth: <expr>, maxHeight: <expr>)`
    /// where one or more dimensions are runtime expressions (variable refs,
    /// computed values) rather than literal numbers. Resolved by evaluating
    /// each expression at render time. Falls back gracefully when an
    /// expression evaluates to `.nil` (that dimension is left unconstrained).
    case dynamicFrame(width: ViewNode?, height: ViewNode?, maxWidth: ViewNode?, maxHeight: ViewNode?)

    // MARK: - Modal presentation
    //
    // `.sheet(isPresented: $flag) { content }` and friends. The bool variable
    // backs SwiftUI's binding so toggling state.variables[varName] presents /
    // dismisses the modal exactly like real SwiftUI. The content is
    // re-rendered every time the modal appears so the latest state is shown.

    /// `.sheet(isPresented: $flag) { content }` — modal sheet.
    case sheet(isPresentedVar: String, content: ViewNode)
    /// `.fullScreenCover(isPresented: $flag) { content }`.
    case fullScreenCover(isPresentedVar: String, content: ViewNode)
    /// `.alert("Title", isPresented: $flag) { /* buttons */ } message: { Text(...) }`
    /// The simplest form: a title + isPresented bool. Buttons are rendered
    /// from the action body (typically `Button("OK") {}` calls).
    case alert(title: String, isPresentedVar: String, actions: ViewNode, message: ViewNode?)

    // Other
    case id(String)
    case tag(String)
    case navigationTitle(String)
}

public enum TruncationModeValue: String, Equatable {
    case head, tail, middle
}

public enum ScrollDismissMode: String, Equatable {
    case automatic, immediately, interactively, never
}

public enum TextCaseValue: String, Equatable {
    case uppercase, lowercase
}

public enum RenderingModeValue: String, Equatable {
    case original, template
}

public enum AnimationType: Equatable {
    case `default`
    case linear(duration: Double?)
    case easeIn(duration: Double?)
    case easeOut(duration: Double?)
    case easeInOut(duration: Double?)
    case spring(response: Double?, dampingFraction: Double?)
    case bouncy(duration: Double?)
    case smooth(duration: Double?)
    case snappy(duration: Double?)
    case none
}

public enum TransitionType: Equatable {
    case opacity
    case slide
    case scale
    case move(edge: EdgeValue)
    case identity
}

public enum EdgeValue: String, Equatable {
    case top, bottom, leading, trailing
}

public enum KeyboardTypeValue: String, Equatable {
    case `default`, asciiCapable, numbersAndPunctuation, URL, numberPad
    case phonePad, namePhonePad, emailAddress, decimalPad, twitter, webSearch, asciiCapableNumberPad
}

public enum TextContentTypeValue: String, Equatable {
    case name, namePrefix, givenName, middleName, familyName, nameSuffix, nickname
    case jobTitle, organizationName, location, fullStreetAddress, streetAddressLine1, streetAddressLine2
    case addressCity, addressState, addressCityAndState, sublocality, countryName, postalCode
    case telephoneNumber, emailAddress, URL, creditCardNumber, username, password, newPassword, oneTimeCode
}

public enum SubmitLabelValue: String, Equatable {
    case done, go, send, join, route, search, `return`, next, `continue`
}

public enum AutocapitalizationValue: String, Equatable {
    case none, words, sentences, allCharacters
}

public enum GlassStyle: String, Equatable {
    case regular, clear, identity
}

public enum TextAlignmentValue: String, Equatable {
    case leading, center, trailing
}

public enum FontStyle: Equatable {
    case largeTitle, title, title2, title3
    case headline, subheadline
    case body, callout, footnote, caption, caption2
    case system(size: Double, weight: FontWeight?, design: FontDesign?)
}

public enum FontWeight: String, Equatable, CaseIterable {
    case ultraLight, thin, light, regular, medium
    case semibold, bold, heavy, black
}

public enum FontDesign: String, Equatable {
    case `default`, serif, rounded, monospaced
}

public enum ShapeType: Equatable {
    case circle
    case rectangle
    case roundedRectangle(cornerRadius: Double)
    case capsule
}

public enum ContentMode: String, Equatable {
    case fit, fill
}

public struct PaddingInsets: Equatable {
    public let top: Double
    public let leading: Double
    public let bottom: Double
    public let trailing: Double
    
    public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
    
    public static func all(_ value: Double) -> PaddingInsets {
        PaddingInsets(top: value, leading: value, bottom: value, trailing: value)
    }
    
    public static func horizontal(_ value: Double) -> PaddingInsets {
        PaddingInsets(leading: value, trailing: value)
    }
    
    public static func vertical(_ value: Double) -> PaddingInsets {
        PaddingInsets(top: value, bottom: value)
    }
}
