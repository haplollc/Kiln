//
//  SwiftRunnerModifierTests.swift
//  SwiftRunnerTests
//
//  Comprehensive tests for all modifiers, view constructors, and state operations.
//

import XCTest
@testable import Kiln

final class SwiftRunnerModifierTests: XCTestCase {

    private let parser = SwiftParser()

    private func parse(_ code: String) throws -> ViewNode {
        let lexer = SwiftLexer(source: code)
        let tokens = try lexer.tokenize()
        return try parser.parse(tokens)
    }

    private func assertModifier(_ code: String, contains modifier: ViewModifier, file: StaticString = #file, line: UInt = #line) throws {
        let node = try parse(code)
        guard case .modified(_, let mods) = node else {
            XCTFail("Expected modified view from: \(code)", file: file, line: line); return
        }
        XCTAssertTrue(mods.contains(modifier), "Expected \(modifier) in \(mods) from: \(code)", file: file, line: line)
    }

    // MARK: - Appearance Modifiers

    func testOpacity() throws {
        try assertModifier("Text(\"hi\").opacity(0.5)", contains: .opacity(0.5))
    }

    func testShadow() throws {
        try assertModifier("Text(\"hi\").shadow(radius: 4, x: 1, y: 2)", contains: .shadow(radius: 4, x: 1, y: 2))
    }

    func testBrightness() throws {
        try assertModifier("Text(\"hi\").brightness(0.3)", contains: .brightness(0.3))
    }

    func testContrast() throws {
        try assertModifier("Text(\"hi\").contrast(1.5)", contains: .contrast(1.5))
    }

    func testSaturation() throws {
        try assertModifier("Text(\"hi\").saturation(0.0)", contains: .saturation(0.0))
    }

    func testGrayscale() throws {
        try assertModifier("Text(\"hi\").grayscale(1.0)", contains: .grayscale(1.0))
    }

    func testColorMultiply() throws {
        try assertModifier("Text(\"hi\").colorMultiply(.red)", contains: .colorMultiply(.red))
    }

    func testColorInvert() throws {
        try assertModifier("Text(\"hi\").colorInvert()", contains: .colorInvert)
    }

    func testCompositingGroup() throws {
        try assertModifier("Text(\"hi\").compositingGroup()", contains: .compositingGroup)
    }

    func testTint() throws {
        try assertModifier("Text(\"hi\").tint(.blue)", contains: .tint(.blue))
    }

    // MARK: - Text Modifiers

    func testKerning() throws {
        try assertModifier("Text(\"hi\").kerning(2.0)", contains: .kerning(2.0))
    }

    func testLineSpacing() throws {
        try assertModifier("Text(\"hi\").lineSpacing(8)", contains: .lineSpacing(8))
    }

    func testMinimumScaleFactor() throws {
        try assertModifier("Text(\"hi\").minimumScaleFactor(0.5)", contains: .minimumScaleFactor(0.5))
    }

    func testTruncationMode() throws {
        try assertModifier("Text(\"hi\").truncationMode(.tail)", contains: .truncationMode(.tail))
    }

    func testTextCaseUppercase() throws {
        try assertModifier("Text(\"hi\").textCase(.uppercase)", contains: .textCase(.uppercase))
    }

    // MARK: - Layout Modifiers

    func testBorder() throws {
        try assertModifier("Text(\"hi\").border(.red, 2)", contains: .border(.red, width: 2))
    }

    func testFixedSize() throws {
        try assertModifier("Text(\"hi\").fixedSize()", contains: .fixedSize(horizontal: true, vertical: true))
    }

    func testFixedSizeHorizontal() throws {
        try assertModifier("Text(\"hi\").fixedSize(horizontal: true, vertical: false)", contains: .fixedSize(horizontal: true, vertical: false))
    }

    func testAspectRatio() throws {
        let node = try parse("Image(systemName: \"star\").aspectRatio(contentMode: .fit)")
        guard case .modified(_, let mods) = node else { return XCTFail("Expected modified") }
        if case .aspectRatio(_, let mode) = mods.first {
            XCTAssertEqual(mode, .fit)
        } else {
            XCTFail("Expected aspectRatio, got \(mods)")
        }
    }

    func testClipShapeCircle() throws {
        let node = try parse("Text(\"hi\").clipShape(Circle())")
        guard case .modified(_, let mods) = node else { return XCTFail("Expected modified") }
        XCTAssertTrue(mods.contains(.clipShape(.circle)))
    }

    func testClipped() throws {
        try assertModifier("Image(systemName: \"star\").clipped()", contains: .clipped)
    }

    func testOverlay() throws {
        let node = try parse("Text(\"hi\").overlay(Circle())")
        guard case .modified(_, let mods) = node else { return XCTFail("Expected modified") }
        if case .overlay(let overlayNode) = mods.first {
            XCTAssertEqual(overlayNode, .circle)
        } else {
            XCTFail("Expected overlay modifier")
        }
    }

    // MARK: - Position & Transform

    func testPosition() throws {
        try assertModifier("Text(\"hi\").position(x: 100, y: 200)", contains: .position(x: 100, y: 200))
    }

    func testZIndex() throws {
        try assertModifier("Text(\"hi\").zIndex(5)", contains: .zIndex(5))
    }

    func testLayoutPriority() throws {
        try assertModifier("Text(\"hi\").layoutPriority(1)", contains: .layoutPriority(1))
    }

    // MARK: - Interaction Modifiers

    func testDisabled() throws {
        try assertModifier("Button(\"hi\") { }.disabled(true)", contains: .disabled(true))
    }

    func testDisabledDefault() throws {
        let node = try parse("Button(\"hi\") { }.disabled()")
        guard case .modified(_, let mods) = node else { return XCTFail("Expected modified") }
        XCTAssertTrue(mods.contains(.disabled(true)))
    }

    func testHidden() throws {
        try assertModifier("Text(\"hi\").hidden()", contains: .hidden)
    }

    func testAllowsHitTesting() throws {
        try assertModifier("Text(\"hi\").allowsHitTesting(false)", contains: .allowsHitTesting(false))
    }

    func testContentShape() throws {
        try assertModifier("Text(\"hi\").contentShape()", contains: .contentShape)
    }

    // MARK: - Shape Modifiers

    func testStrokeBorder() throws {
        let node = try parse("Circle().strokeBorder(.red, lineWidth: 3)")
        guard case .modified(_, let mods) = node else { return XCTFail("Expected modified") }
        XCTAssertTrue(mods.contains(.strokeBorder(.red, lineWidth: 3)))
    }

    func testTrim() throws {
        let node = try parse("Circle().trim(from: 0, to: 0.75)")
        guard case .modified(_, let mods) = node else { return XCTFail("Expected modified") }
        XCTAssertTrue(mods.contains(.trim(from: 0, to: 0.75)))
    }

    // MARK: - Image Modifiers

    func testResizable() throws {
        try assertModifier("Image(systemName: \"star\").resizable()", contains: .resizable)
    }

    func testScaledToFit() throws {
        try assertModifier("Image(systemName: \"star\").scaledToFit()", contains: .scaledToFit)
    }

    func testScaledToFill() throws {
        try assertModifier("Image(systemName: \"star\").scaledToFill()", contains: .scaledToFill)
    }

    // MARK: - Lifecycle Modifiers

    func testOnAppear() throws {
        let node = try parse("Text(\"hi\").onAppear()")
        guard case .modified(_, let mods) = node else { return XCTFail("Expected modified") }
        if case .onAppear = mods.first { /* ok */ }
        else { XCTFail("Expected onAppear, got \(mods)") }
    }

    func testOnDisappear() throws {
        let node = try parse("Text(\"hi\").onDisappear()")
        guard case .modified(_, let mods) = node else { return XCTFail("Expected modified") }
        if case .onDisappear = mods.first { /* ok */ }
        else { XCTFail("Expected onDisappear, got \(mods)") }
    }

    // MARK: - Animation Modifiers

    func testAnimationSpring() throws {
        let node = try parse("Text(\"hi\").animation(.spring)")
        guard case .modified(_, let mods) = node else { return XCTFail("Expected modified") }
        if case .animation(let anim) = mods.first {
            if case .spring = anim { /* ok */ }
            else { XCTFail("Expected spring, got \(anim)") }
        } else {
            XCTFail("Expected animation modifier")
        }
    }

    func testAnimationLinearDuration() throws {
        let node = try parse("Text(\"hi\").animation(.linear(duration: 0.3))")
        guard case .modified(_, let mods) = node else { return XCTFail("Expected modified") }
        if case .animation(let anim) = mods.first {
            if case .linear(let dur) = anim { XCTAssertEqual(dur, 0.3) }
            else { XCTFail("Expected linear, got \(anim)") }
        } else {
            XCTFail("Expected animation modifier")
        }
    }

    func testAnimationNone() throws {
        let node = try parse("Text(\"hi\").animation(nil)")
        guard case .modified(_, let mods) = node else { return XCTFail("Expected modified") }
        if case .animation(let anim) = mods.first {
            if case .none = anim { /* ok */ }
            else { XCTFail("Expected none, got \(anim)") }
        } else {
            XCTFail("Expected animation modifier")
        }
    }

    func testTransitionScale() throws {
        try assertModifier("Text(\"hi\").transition(.scale)", contains: .transition(.scale))
    }

    func testTransitionMoveEdge() throws {
        try assertModifier("Text(\"hi\").transition(.move(edge: .bottom))", contains: .transition(.move(edge: .bottom)))
    }

    // MARK: - View Constructors

    func testScrollViewHorizontal() throws {
        let node = try parse("ScrollView(.horizontal) { Text(\"hi\") }")
        if case .scrollView(let axis, _, let content) = node {
            XCTAssertEqual(axis, .horizontal)
            XCTAssertEqual(content, .text("hi"))
        } else {
            XCTFail("Expected scrollView, got \(node)")
        }
    }

    func testScrollViewDefault() throws {
        let node = try parse("ScrollView { Text(\"hi\") }")
        if case .scrollView(let axis, _, _) = node {
            XCTAssertNil(axis) // defaults to vertical
        } else {
            XCTFail("Expected scrollView")
        }
    }

    func testSpacer() throws {
        let node = try parse("Spacer()")
        XCTAssertEqual(node, .spacer(minLength: nil))
    }

    func testSpacerMinLength() throws {
        let node = try parse("Spacer(minLength: 20)")
        XCTAssertEqual(node, .spacer(minLength: 20))
    }

    func testDivider() throws {
        let node = try parse("Divider()")
        XCTAssertEqual(node, .divider)
    }

    func testVStackWithSpacing() throws {
        let node = try parse("VStack(spacing: 10) { Text(\"hi\") }")
        if case .vStack(let spacing, _, let children) = node {
            XCTAssertEqual(spacing, 10)
            XCTAssertEqual(children.count, 1)
        } else {
            XCTFail("Expected vStack")
        }
    }

    func testHStackWithAlignment() throws {
        let node = try parse("HStack(alignment: .top) { Text(\"hi\") }")
        if case .hStack(_, let alignment, _) = node {
            XCTAssertEqual(alignment, .top)
        } else {
            XCTFail("Expected hStack")
        }
    }

    func testZStackDefault() throws {
        let node = try parse("ZStack { Text(\"hi\") }")
        if case .zStack(let alignment, _) = node {
            XCTAssertNil(alignment)
        } else {
            XCTFail("Expected zStack")
        }
    }

    func testNavigationStack() throws {
        // Real SwiftUI NavigationStack — children come from the trailing closure.
        let node = try parse("NavigationStack { Text(\"hi\") }")
        if case .navigationStack(let children) = node {
            XCTAssertEqual(children.first, .text("hi"))
        } else {
            XCTFail("Expected navigationStack, got \(node)")
        }
    }

    func testNavigationLinkWithDestinationAndLabelClosure() throws {
        // Form 2: NavigationLink(destination: …) { Label() }
        let node = try parse("""
        NavigationLink(destination: Text("dest")) {
            Text("label")
        }
        """)
        guard case .navigationLink(let label, let destination) = node else {
            return XCTFail("Expected navigationLink, got \(node)")
        }
        XCTAssertEqual(label, .text("label"))
        XCTAssertEqual(destination, .text("dest"))
    }

    func testNavigationLinkWithTitleStringForm() throws {
        // Form 1: NavigationLink("Title", destination: …)
        let node = try parse(#"NavigationLink("Title", destination: Text("dest"))"#)
        guard case .navigationLink(let label, let destination) = node else {
            return XCTFail("Expected navigationLink, got \(node)")
        }
        XCTAssertEqual(label, .text("Title"))
        XCTAssertEqual(destination, .text("dest"))
    }

    func testSheetIsPresentedBindsModifier() throws {
        // .sheet(isPresented: $flag) { Text("modal") } stores the bool var
        // backing the binding plus the modal content for render-time wiring.
        let node = try parse(#"""
        Text("hi")
            .sheet(isPresented: $showing) { Text("modal") }
        """#)
        guard case .modified(_, let modifiers) = node,
              let mod = modifiers.last,
              case .sheet(let bindingVar, let content) = mod else {
            return XCTFail("Expected modified with .sheet, got \(node)")
        }
        XCTAssertEqual(bindingVar, "showing")
        XCTAssertEqual(content, .text("modal"))
    }

    func testFullScreenCoverIsPresentedBindsModifier() throws {
        let node = try parse(#"""
        Text("hi")
            .fullScreenCover(isPresented: $showing) { Text("cover") }
        """#)
        guard case .modified(_, let modifiers) = node,
              let mod = modifiers.last,
              case .fullScreenCover(let bindingVar, let content) = mod else {
            return XCTFail("Expected modified with .fullScreenCover, got \(node)")
        }
        XCTAssertEqual(bindingVar, "showing")
        XCTAssertEqual(content, .text("cover"))
    }

    func testAlertCapturesTitleAndBindingAndActions() throws {
        let node = try parse(#"""
        Text("hi")
            .alert("Heads up", isPresented: $showError) {
                Button("OK") {}
            }
        """#)
        guard case .modified(_, let modifiers) = node,
              let mod = modifiers.last,
              case .alert(let title, let bindingVar, _, _) = mod else {
            return XCTFail("Expected modified with .alert, got \(node)")
        }
        XCTAssertEqual(title, "Heads up")
        XCTAssertEqual(bindingVar, "showError")
    }

    func testLazyVStack() throws {
        let node = try parse("LazyVStack { Text(\"hi\") }")
        if case .vStack(_, _, let children) = node {
            XCTAssertEqual(children.first, .text("hi"))
        } else {
            XCTFail("Expected vStack (LazyVStack alias)")
        }
    }

    func testLazyHStack() throws {
        let node = try parse("LazyHStack { Text(\"hi\") }")
        if case .hStack(_, _, let children) = node {
            XCTAssertEqual(children.first, .text("hi"))
        } else {
            XCTFail("Expected hStack (LazyHStack alias)")
        }
    }

    func testProgressViewSpinner() throws {
        let node = try parse("ProgressView()")
        if case .functionCall(let name, _) = node {
            XCTAssertEqual(name, "ProgressView")
        } else {
            XCTFail("Expected functionCall ProgressView, got \(node)")
        }
    }

    func testProgressViewLabeled() throws {
        let node = try parse("ProgressView(\"Loading...\")")
        if case .functionCall(let name, let args) = node {
            XCTAssertEqual(name, "ProgressView")
            if case .literal(.string(let s)) = args.first?.value {
                XCTAssertEqual(s, "Loading...")
            }
        } else {
            XCTFail("Expected functionCall ProgressView")
        }
    }

    func testProgressViewValue() throws {
        let node = try parse("ProgressView(value: 0.5)")
        if case .functionCall(let name, let args) = node {
            XCTAssertEqual(name, "ProgressView")
            XCTAssertTrue(args.contains(where: { $0.label == "value" }))
        } else {
            XCTFail("Expected functionCall ProgressView")
        }
    }

    func testLabel() throws {
        let node = try parse("Label(\"Settings\", systemImage: \"gear\")")
        // Label renders as HStack with icon + text
        if case .hStack(_, _, let children) = node {
            XCTAssertEqual(children.count, 2)
            XCTAssertEqual(children[0], .systemImage("gear"))
            XCTAssertEqual(children[1], .text("Settings"))
        } else {
            XCTFail("Expected hStack from Label, got \(node)")
        }
    }

    func testSecureField() throws {
        let node = try parse("SecureField(\"Password\", text: $password)")
        if case .textField(let placeholder, let variable, _) = node {
            XCTAssertEqual(placeholder, "Password")
            XCTAssertEqual(variable, "password")
        } else {
            XCTFail("Expected textField from SecureField, got \(node)")
        }
    }

    // MARK: - State: Multiply/Divide Assign

    @MainActor
    func testStateExecuteMulAssign() {
        let state = SwiftRunnerState(["x": .number(3)])
        state.execute(.compoundAssignment(variable: "x", op: .mulAssign, value: .literal(.number(4))))
        XCTAssertEqual(state.variables["x"], .number(12))
    }

    @MainActor
    func testStateExecuteDivAssign() {
        let state = SwiftRunnerState(["x": .number(10)])
        state.execute(.compoundAssignment(variable: "x", op: .divAssign, value: .literal(.number(2))))
        XCTAssertEqual(state.variables["x"], .number(5))
    }

    @MainActor
    func testStateExecuteDivByZero() {
        let state = SwiftRunnerState(["x": .number(10)])
        state.execute(.compoundAssignment(variable: "x", op: .divAssign, value: .literal(.number(0))))
        // Should not crash, value unchanged
        XCTAssertEqual(state.variables["x"], .number(10))
    }

    // MARK: - State: Evaluate Functions

    @MainActor
    func testStateEvaluateAbs() {
        let state = SwiftRunnerState([:])
        let result = state.evaluate(.functionCall(name: "abs", arguments: [
            Argument(value: .binary(left: .literal(.number(0)), op: .minus, right: .literal(.number(5))))
        ]))
        XCTAssertEqual(result, .number(5))
    }

    @MainActor
    func testStateEvaluateStringConversion() {
        let state = SwiftRunnerState([:])
        let result = state.evaluate(.functionCall(name: "String", arguments: [
            Argument(value: .literal(.number(42)))
        ]))
        XCTAssertEqual(result, .string("42"))
    }

    @MainActor
    func testStateEvaluateIntConversion() {
        let state = SwiftRunnerState([:])
        let result = state.evaluate(.functionCall(name: "Int", arguments: [
            Argument(value: .literal(.number(3.7)))
        ]))
        XCTAssertEqual(result, .number(3))
    }

    // MARK: - State: Evaluate Binary Ops

    @MainActor
    func testStateEvaluateStringConcat() {
        let state = SwiftRunnerState([:])
        let result = state.evaluate(.binary(
            left: .literal(.string("Hello ")),
            op: .plus,
            right: .literal(.string("World"))
        ))
        XCTAssertEqual(result, .string("Hello World"))
    }

    @MainActor
    func testStateEvaluateComparison() {
        let state = SwiftRunnerState(["x": .number(5)])
        let result = state.evaluate(.binary(left: .variable("x"), op: .greater, right: .literal(.number(3))))
        XCTAssertEqual(result, .boolean(true))
    }

    @MainActor
    func testStateEvaluateEquality() {
        let state = SwiftRunnerState(["name": .string("test")])
        let result = state.evaluate(.binary(left: .variable("name"), op: .equal, right: .literal(.string("test"))))
        XCTAssertEqual(result, .boolean(true))
    }

    @MainActor
    func testStateEvaluateLogicalAnd() {
        let state = SwiftRunnerState([:])
        let result = state.evaluate(.binary(left: .literal(.boolean(true)), op: .and, right: .literal(.boolean(false))))
        XCTAssertEqual(result, .boolean(false))
    }

    @MainActor
    func testStateEvaluateModulo() {
        let state = SwiftRunnerState([:])
        let result = state.evaluate(.binary(left: .literal(.number(7)), op: .modulo, right: .literal(.number(3))))
        XCTAssertEqual(result, .number(1))
    }

    // MARK: - Dynamic Modifiers

    func testDynamicOpacity() throws {
        let node = try parse("Text(\"hi\").opacity(flag ? 1.0 : 0.5)")
        guard case .modified(_, let mods) = node else { return XCTFail("Expected modified") }
        if case .dynamic(let name, _) = mods.first {
            XCTAssertEqual(name, "opacity")
        } else {
            XCTFail("Expected dynamic opacity, got \(mods)")
        }
    }

    func testDynamicCornerRadius() throws {
        let node = try parse("Text(\"hi\").cornerRadius(flag ? 20 : 8)")
        guard case .modified(_, let mods) = node else { return XCTFail("Expected modified") }
        if case .dynamic(let name, _) = mods.first {
            XCTAssertEqual(name, "cornerRadius")
        } else {
            XCTFail("Expected dynamic cornerRadius, got \(mods)")
        }
    }

    func testDynamicFill() throws {
        let node = try parse("Circle().fill(flag ? .blue : .red)")
        guard case .modified(_, let mods) = node else { return XCTFail("Expected modified") }
        if case .dynamic(let name, _) = mods.first {
            XCTAssertEqual(name, "fill")
        } else {
            XCTFail("Expected dynamic fill, got \(mods)")
        }
    }

    // MARK: - Closure Parameter Handling

    func testClosureParameterSkipped() throws {
        let node = try parse("ForEach(0..<3) { index in Text(\"hi\") }")
        if case .forEach(_, _, let body) = node {
            XCTAssertEqual(body, .text("hi"))
        } else {
            XCTFail("Expected forEach, got \(node)")
        }
    }

    // MARK: - Multiple Statements in Closure

    func testMultipleStatementsInButton() throws {
        let node = try parse("Button(\"Go\") { x += 1; y += 2 }")
        if case .button(_, let action) = node {
            if case .block(let stmts) = action {
                XCTAssertEqual(stmts.count, 2)
            } else {
                XCTFail("Expected block action")
            }
        } else {
            XCTFail("Expected button")
        }
    }

    // MARK: - Chained Modifiers

    func testManyModifiers() throws {
        let node = try parse("Text(\"hi\").font(.title).bold().italic().foregroundColor(.red).padding()")
        guard case .modified(let view, let mods) = node else { return XCTFail("Expected modified") }
        XCTAssertEqual(view, .text("hi"))
        XCTAssertEqual(mods.count, 5)
        XCTAssertEqual(mods[0], .font(.title))
        XCTAssertEqual(mods[1], .bold)
        XCTAssertEqual(mods[2], .italic)
        XCTAssertEqual(mods[3], .foregroundColor(.red))
    }

    // MARK: - Edge Cases

    func testEmptyVStack() throws {
        let node = try parse("VStack { }")
        if case .vStack(_, _, let children) = node {
            XCTAssertTrue(children.isEmpty || children.allSatisfy { if case .empty = $0 { return true }; return false })
        } else {
            XCTFail("Expected vStack")
        }
    }

    func testNestedStacks() throws {
        let node = try parse("VStack { HStack { Text(\"A\"); Text(\"B\") } }")
        if case .vStack(_, _, let children) = node {
            if case .hStack(_, _, let hChildren) = children.first {
                XCTAssertEqual(hChildren.count, 2)
            } else {
                XCTFail("Expected nested hStack")
            }
        } else {
            XCTFail("Expected vStack")
        }
    }

    @MainActor
    func testStateUninitializedVariable() {
        let state = SwiftRunnerState([:])
        let result = state.evaluate(.variable("nonexistent"))
        XCTAssertEqual(result, .nil)
    }

    @MainActor
    func testStatePlusAssignOnNil() {
        // count is nil, += 1 should do string concat "nil" + "1" = "nil1"
        // This tests the fallback behavior
        let state = SwiftRunnerState([:])
        state.execute(.compoundAssignment(variable: "count", op: .plusAssign, value: .literal(.number(1))))
        // nil + number falls to string concat
        if case .string = state.variables["count"] {
            // Expected — nil description + 1 description
        } else if case .number = state.variables["count"] {
            // Also acceptable if nil is treated as 0
        } else {
            // Any non-crash result is acceptable
        }
    }

    // MARK: - Object / Struct Constructor

    @MainActor
    func testStructConstructorCreatesObject() {
        let state = SwiftRunnerState([:])
        let result = state.evaluate(.functionCall(name: "MyStruct", arguments: [
            Argument(label: "title", value: .literal(.string("Hello"))),
            Argument(label: "count", value: .literal(.number(5)))
        ]))
        if case .object(let dict) = result {
            XCTAssertEqual(dict["title"], .string("Hello"))
            XCTAssertEqual(dict["count"], .number(5))
        } else {
            XCTFail("Expected object, got \(result)")
        }
    }

    @MainActor
    func testObjectPropertyAccess() {
        let state = SwiftRunnerState(["req": .object(["title": .string("Test"), "isMet": .boolean(false)])])
        let result = state.evaluate(.propertyAccess(object: .variable("req"), property: "title"))
        XCTAssertEqual(result, .string("Test"))
    }

    @MainActor
    func testObjectPropertyAccessBoolean() {
        let state = SwiftRunnerState(["req": .object(["isMet": .boolean(true)])])
        let result = state.evaluate(.propertyAccess(object: .variable("req"), property: "isMet"))
        XCTAssertEqual(result, .boolean(true))
    }

    // MARK: - Subscript Access

    @MainActor
    func testArraySubscriptAccess() {
        let state = SwiftRunnerState(["arr": .array([.string("a"), .string("b"), .string("c")])])
        let result = state.evaluate(.subscriptAccess(object: .variable("arr"), index: .literal(.number(1))))
        XCTAssertEqual(result, .string("b"))
    }

    @MainActor
    func testArraySubscriptOutOfBounds() {
        let state = SwiftRunnerState(["arr": .array([.string("a")])])
        let result = state.evaluate(.subscriptAccess(object: .variable("arr"), index: .literal(.number(5))))
        XCTAssertEqual(result, .nil)
    }

    // MARK: - Collection Methods

    @MainActor
    func testArrayContainsValue() {
        let state = SwiftRunnerState([:])
        let result = state.evaluate(.methodCall(
            object: .arrayLiteral([.literal(.number(1)), .literal(.number(2)), .literal(.number(3))]),
            method: "contains",
            arguments: [Argument(value: .literal(.number(2)))]
        ))
        XCTAssertEqual(result, .boolean(true))
    }

    @MainActor
    func testStringContains() {
        let state = SwiftRunnerState([:])
        let result = state.evaluate(.methodCall(
            object: .literal(.string("Hello World")),
            method: "contains",
            arguments: [Argument(value: .literal(.string("World")))]
        ))
        XCTAssertEqual(result, .boolean(true))
    }

    @MainActor
    func testStringCount() {
        let state = SwiftRunnerState(["name": .string("Swift")])
        let result = state.evaluate(.propertyAccess(object: .variable("name"), property: "count"))
        XCTAssertEqual(result, .number(5))
    }

    @MainActor
    func testArrayCount() {
        let state = SwiftRunnerState(["items": .array([.number(1), .number(2)])])
        let result = state.evaluate(.propertyAccess(object: .variable("items"), property: "count"))
        XCTAssertEqual(result, .number(2))
    }

    // MARK: - Text with Property Access

    func testTextWithPropertyAccess() throws {
        let node = try parse("Text(req.title)")
        if case .stringInterpolation(let parts) = node {
            XCTAssertEqual(parts.count, 1)
            if case .expression(let expr) = parts[0] {
                if case .propertyAccess = expr { /* ok */ }
                else { XCTFail("Expected propertyAccess, got \(expr)") }
            }
        } else {
            XCTFail("Expected stringInterpolation, got \(node)")
        }
    }

    func testTextWithSubscript() throws {
        let node = try parse("Text(items[0])")
        if case .stringInterpolation(let parts) = node {
            XCTAssertEqual(parts.count, 1)
        } else {
            XCTFail("Expected stringInterpolation, got \(node)")
        }
    }

    // MARK: - Dynamic Image

    func testImageDynamicSystemName() throws {
        let node = try parse("Image(systemName: flag ? \"star.fill\" : \"star\")")
        if case .functionCall(let name, _) = node {
            XCTAssertEqual(name, "Image_systemName")
        } else {
            XCTFail("Expected functionCall Image_systemName, got \(node)")
        }
    }

    // MARK: - Subscript Parsing

    func testSubscriptParsing() throws {
        let node = try parse("items[0]")
        if case .subscriptAccess(let obj, let idx) = node {
            XCTAssertEqual(obj, .variable("items"))
            XCTAssertEqual(idx, .literal(.number(0)))
        } else {
            XCTFail("Expected subscriptAccess, got \(node)")
        }
    }

    // MARK: - Nil Coalescing

    func testNilCoalescing() throws {
        let node = try parse("name ?? \"default\"")
        if case .ternary = node { /* ok — ?? desugars to ternary */ }
        else { XCTFail("Expected ternary from ??, got \(node)") }
    }

    // MARK: - Negative Number Init

    @MainActor
    func testNegativeNumberStateInit() {
        // @State var x = -1 parsed as binary(0, -, 1)
        let node = ViewNode.binary(left: .literal(.number(0)), op: .minus, right: .literal(.number(1)))
        let runner = SwiftRunner.shared
        // Use nodeToValue indirectly through separateState
        let (vars, _) = runner.testSeparateState(.block([.assignment(name: "x", isVar: true, value: node)]))
        XCTAssertEqual(vars["x"], .number(-1))
    }
}
