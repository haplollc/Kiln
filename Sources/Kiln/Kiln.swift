//
//  Kiln.swift
//  Kiln — a Swift/SwiftUI interpreter you can embed in any iOS or macOS app.
//
//  Public API surface. The interpreter internals live in `SwiftRunner` and
//  friends; this file exposes a tight, drop-in namespace that's stable
//  across versions.
//

import SwiftUI

/// Gated debug logging for the interpreter. OFF by default — the parser/runtime
/// emit very chatty traces (including full AST descriptions) that, when always
/// printed, both spam the console and noticeably slow execution (the giant
/// strings get built even when nobody reads them). The `@autoclosure` means the
/// message isn't even constructed unless logging is enabled.
public enum KilnLog {
    nonisolated(unsafe) public static var enabled = false
    @inline(__always) static func d(_ message: @autoclosure () -> String) {
        if enabled { print(message()) }
    }
}

// MARK: - Top-level namespace

/// Kiln runs Swift / SwiftUI source code at runtime inside your app.
///
/// ```swift
/// import Kiln
///
/// let result = Kiln.run("""
/// import SwiftUI
/// struct ContentView: View {
///     var body: some View { Text("Hello, Kiln!") }
/// }
/// """)
///
/// if let view = result.view {
///     // render `view` anywhere AnyView is accepted
/// }
/// ```
public enum Kiln {
    /// Parse, evaluate, and render a Swift source string. Returns a
    /// `KilnResult` containing the rendered view (when the source produced
    /// one), any `print(...)` output, and any errors raised during parsing
    /// or evaluation.
    ///
    /// Safe to call from the main actor on any iOS 17+ / macOS 14+ device.
    /// No compilation step is involved — this is pure interpretation.
    @MainActor
    public static func run(_ code: String) -> KilnResult {
        let raw = SwiftRunner.shared.run(code)
        return KilnResult(
            view: raw.view,
            consoleOutput: raw.consoleOutput,
            errors: raw.errors
        )
    }

    /// Convenience flag: returns the latest known version of the Kiln
    /// public API. Bumped on breaking changes.
    public static let version: String = "0.1.0"

    // MARK: - Native bridges (host capabilities)

    /// Register a native Swift function the interpreted code can call by name —
    /// the way to expose real Apple-framework capabilities (HealthKit, haptics,
    /// device info, Calendar, …) to Kiln apps. The closure receives the call's
    /// evaluated arguments and returns a value.
    ///
    /// ```swift
    /// Kiln.register("Haptics.play") { _ in
    ///     UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    ///     return .null
    /// }
    /// // interpreted app: Haptics.play()
    /// ```
    ///
    /// Use a bare name (`steps`) for a global function, or `Type.method`
    /// (`Health.steps`) for a namespaced call.
    @MainActor
    public static func register(_ name: String, _ fn: @escaping ([KilnValue]) -> KilnValue) {
        SwiftRunnerState.nativeBridges[name] = { values in
            KilnValue.toInternal(fn(values.map(KilnValue.fromInternal)))
        }
    }

    /// Remove a previously registered bridge.
    @MainActor
    public static func unregister(_ name: String) {
        SwiftRunnerState.nativeBridges[name] = nil
    }
}

// MARK: - KilnValue (public bridge value)

/// The value type passed to/from native bridges registered via `Kiln.register`.
/// Mirrors the interpreter's internal JSON-shaped value model.
public enum KilnValue: Equatable, Sendable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case array([KilnValue])
    case object([String: KilnValue])
    case null

    /// Read a number regardless of stored numeric/bool/string form.
    public var doubleValue: Double? {
        switch self {
        case .number(let n): return n
        case .bool(let b): return b ? 1 : 0
        case .string(let s): return Double(s)
        default: return nil
        }
    }
    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }

    // Internal <-> public conversions (`Value` is module-internal).
    static func fromInternal(_ v: Value) -> KilnValue {
        switch v {
        case .number(let n): return .number(n)
        case .string(let s): return .string(s)
        case .boolean(let b): return .bool(b)
        case .array(let a): return .array(a.map(fromInternal))
        case .object(let o): return .object(o.mapValues(fromInternal))
        case .nil: return .null
        }
    }
    static func toInternal(_ v: KilnValue) -> Value {
        switch v {
        case .number(let n): return .number(n)
        case .string(let s): return .string(s)
        case .bool(let b): return .boolean(b)
        case .array(let a): return .array(a.map(toInternal))
        case .object(let o): return .object(o.mapValues(toInternal))
        case .null: return .nil
        }
    }
}

// MARK: - Result

/// The outcome of `Kiln.run(_:)`.
public struct KilnResult {
    /// The view produced by the source, if any. `nil` when the input was
    /// pure expression / declaration code (no `var body: some View`).
    public let view: AnyView?

    /// Anything the source emitted via `print(...)`.
    public let consoleOutput: String

    /// Lexer / parser / runtime errors. Empty on a successful run.
    public let errors: [String]

    /// `true` when `view` is non-nil — convenience for `if result.hasView { … }`.
    public var hasView: Bool { view != nil }

    public init(view: AnyView?, consoleOutput: String, errors: [String]) {
        self.view = view
        self.consoleOutput = consoleOutput
        self.errors = errors
    }
}

// MARK: - Drop-in SwiftUI view

/// `KilnView(code)` renders Swift source as a real SwiftUI view, inline.
///
/// ```swift
/// import Kiln
///
/// struct PreviewScreen: View {
///     @State var source: String = "Text(\"hi\")"
///     var body: some View {
///         VStack {
///             TextEditor(text: $source)
///             Divider()
///             KilnView(code: source)
///         }
///     }
/// }
/// ```
///
/// Re-runs the interpreter whenever `code` changes. Errors are shown
/// inline (override by passing a custom `errorContent`).
@MainActor
public struct KilnView<ErrorContent: View>: View {
    private let code: String
    private let errorContent: ([String]) -> ErrorContent

    @State private var result: KilnResult?

    /// Create a Kiln view with a default red error label.
    public init(code: String) where ErrorContent == _KilnDefaultErrorLabel {
        self.code = code
        self.errorContent = { _KilnDefaultErrorLabel(errors: $0) }
    }

    /// Create a Kiln view with a custom error renderer.
    public init(
        code: String,
        @ViewBuilder errorContent: @escaping ([String]) -> ErrorContent
    ) {
        self.code = code
        self.errorContent = errorContent
    }

    public var body: some View {
        Group {
            if let result = result {
                if let view = result.view {
                    view
                } else if !result.errors.isEmpty {
                    errorContent(result.errors)
                } else {
                    EmptyView()
                }
            } else {
                ProgressView()
            }
        }
        .task(id: code) {
            result = Kiln.run(code)
        }
    }
}

/// Default error renderer used by `KilnView(code:)`. Internal-ish — exposed
/// only so the public initializer can satisfy `ErrorContent: View`. Style
/// it via a custom `errorContent` closure if you want something else.
public struct _KilnDefaultErrorLabel: View {
    let errors: [String]
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(errors.enumerated()), id: \.offset) { _, msg in
                Text(msg)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
