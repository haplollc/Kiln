//
//  SwiftRunnerInteractiveTests.swift
//  SwiftRunnerTests
//
//  Tests for interactive state, dynamic modifiers, view syntax variants,
//  animations, lifecycle modifiers, AsyncImage, bindings, and more.
//

import XCTest
@testable import Kiln

final class SwiftRunnerInteractiveTests: XCTestCase {

    private let parser = SwiftParser()

    private func parse(_ code: String) throws -> ViewNode {
        let lexer = SwiftLexer(source: code)
        let tokens = try lexer.tokenize()
        return try parser.parse(tokens)
    }

    private func tokenize(_ code: String) throws -> [Token] {
        let lexer = SwiftLexer(source: code)
        return try lexer.tokenize()
    }

    // MARK: - Lexer: Smart Quotes

    func testSmartQuotesNormalized() throws {
        // Curly quotes should be normalized to straight quotes
        let code = "\u{201C}Hello\u{201D}"
        let tokens = try tokenize(code)
        guard case .string(let s) = tokens[0].type else {
            return XCTFail("Expected string token")
        }
        XCTAssertEqual(s, "Hello")
    }

    // MARK: - Lexer: Compound Assignment Tokens

    func testPlusEqualsToken() throws {
        let tokens = try tokenize("x += 1")
        XCTAssertEqual(tokens[1].type, .plusEquals)
    }

    func testMinusEqualsToken() throws {
        let tokens = try tokenize("x -= 1")
        XCTAssertEqual(tokens[1].type, .minusEquals)
    }

    func testStarEqualsToken() throws {
        let tokens = try tokenize("x *= 2")
        XCTAssertEqual(tokens[1].type, .starEquals)
    }

    func testSlashEqualsToken() throws {
        let tokens = try tokenize("x /= 2")
        XCTAssertEqual(tokens[1].type, .slashEquals)
    }

    // MARK: - Lexer: Range Operators

    func testHalfOpenRangeToken() throws {
        let tokens = try tokenize("0..<5")
        XCTAssertEqual(tokens[0].type, .number(0))
        XCTAssertEqual(tokens[1].type, .halfOpenRange)
        XCTAssertEqual(tokens[2].type, .number(5))
    }

    func testClosedRangeToken() throws {
        let tokens = try tokenize("1...10")
        XCTAssertEqual(tokens[0].type, .number(1))
        XCTAssertEqual(tokens[1].type, .closedRange)
        XCTAssertEqual(tokens[2].type, .number(10))
    }

    // MARK: - Lexer: Question Mark

    func testQuestionMarkToken() throws {
        let tokens = try tokenize("a ? b : c")
        XCTAssertEqual(tokens[1].type, .questionMark)
        XCTAssertEqual(tokens[3].type, .colon)
    }

    // MARK: - Lexer: Binding

    func testBindingToken() throws {
        let tokens = try tokenize("$name")
        guard case .bindingIdentifier(let name) = tokens[0].type else {
            return XCTFail("Expected bindingIdentifier")
        }
        XCTAssertEqual(name, "name")
    }

    // MARK: - Lexer: Attributes

    func testAtStateEmittedAsAttributeToken() throws {
        // Attributes are now surfaced as .attribute(name) tokens so the parser
        // can choose how to handle them. Downstream parsing still treats @State
        // as a transparent marker by consuming the attribute token wherever it
        // precedes a var/let declaration.
        let tokens = try tokenize("@State var x = 0")
        XCTAssertEqual(tokens[0].type, .attribute("State"))
        XCTAssertEqual(tokens[1].type, .keyword(.var))
    }

    // MARK: - Lexer: Semicolons

    func testSemicolonToken() throws {
        let tokens = try tokenize("a; b")
        XCTAssertEqual(tokens[1].type, .semicolon)
    }

    // MARK: - Parser: Compound Assignments

    func testCompoundAssignmentPlusEquals() throws {
        let node = try parse("count += 1")
        if case .compoundAssignment(let v, let op, let val) = node {
            XCTAssertEqual(v, "count")
            XCTAssertEqual(op, .plusAssign)
            XCTAssertEqual(val, .literal(.number(1)))
        } else {
            XCTFail("Expected compoundAssignment, got \(node)")
        }
    }

    func testCompoundAssignmentMinusEquals() throws {
        let node = try parse("count -= 1")
        if case .compoundAssignment(let v, let op, _) = node {
            XCTAssertEqual(v, "count")
            XCTAssertEqual(op, .minusAssign)
        } else {
            XCTFail("Expected compoundAssignment")
        }
    }

    func testSimpleAssignment() throws {
        let node = try parse("name = \"hello\"")
        if case .compoundAssignment(let v, let op, let val) = node {
            XCTAssertEqual(v, "name")
            XCTAssertEqual(op, .assign)
            XCTAssertEqual(val, .literal(.string("hello")))
        } else {
            XCTFail("Expected compoundAssignment with .assign")
        }
    }

    // MARK: - Parser: Toggle

    func testToggleOnVariable() throws {
        let node = try parse("isOn.toggle()")
        if case .compoundAssignment(let v, let op, _) = node {
            XCTAssertEqual(v, "isOn")
            XCTAssertEqual(op, .toggle)
        } else {
            XCTFail("Expected compoundAssignment with .toggle, got \(node)")
        }
    }

    // MARK: - Parser: Append

    func testAppendOnVariable() throws {
        let node = try parse("text.append(\"hi\")")
        if case .compoundAssignment(let v, let op, let val) = node {
            XCTAssertEqual(v, "text")
            XCTAssertEqual(op, .plusAssign)
            XCTAssertEqual(val, .literal(.string("hi")))
        } else {
            XCTFail("Expected compoundAssignment with .plusAssign")
        }
    }

    // MARK: - Parser: Ternary Expressions

    func testTernaryExpression() throws {
        let node = try parse("isOn ? 1 : 0")
        if case .ternary(let cond, let t, let f) = node {
            XCTAssertEqual(cond, .variable("isOn"))
            XCTAssertEqual(t, .literal(.number(1)))
            XCTAssertEqual(f, .literal(.number(0)))
        } else {
            XCTFail("Expected ternary")
        }
    }

    func testTernaryWithStrings() throws {
        let node = try parse("flag ? \"yes\" : \"no\"")
        if case .ternary(_, let t, let f) = node {
            XCTAssertEqual(t, .literal(.string("yes")))
            XCTAssertEqual(f, .literal(.string("no")))
        } else {
            XCTFail("Expected ternary")
        }
    }

    // MARK: - Parser: If/Else Conditional

    func testIfElse() throws {
        let node = try parse("if isOn { Text(\"ON\") } else { Text(\"OFF\") }")
        if case .conditional(let cond, let then, let elseBody) = node {
            XCTAssertEqual(cond, .variable("isOn"))
            XCTAssertEqual(then, .text("ON"))
            XCTAssertEqual(elseBody, .text("OFF"))
        } else {
            XCTFail("Expected conditional, got \(node)")
        }
    }

    func testIfWithoutElse() throws {
        let node = try parse("if isOn { Text(\"ON\") }")
        if case .conditional(_, _, let elseBody) = node {
            XCTAssertNil(elseBody)
        } else {
            XCTFail("Expected conditional")
        }
    }

    // MARK: - Parser: Text with Variable

    func testTextWithVariable() throws {
        let node = try parse("Text(myVar)")
        if case .stringInterpolation(let parts) = node {
            XCTAssertEqual(parts.count, 1)
            if case .expression(let expr) = parts[0] {
                XCTAssertEqual(expr, .variable("myVar"))
            }
        } else {
            XCTFail("Expected stringInterpolation, got \(node)")
        }
    }

    func testTextWithTernary() throws {
        let node = try parse("Text(flag ? \"A\" : \"B\")")
        if case .stringInterpolation(let parts) = node {
            XCTAssertEqual(parts.count, 1)
            if case .expression(let expr) = parts[0] {
                if case .ternary = expr { /* ok */ }
                else { XCTFail("Expected ternary expression") }
            }
        } else {
            XCTFail("Expected stringInterpolation")
        }
    }

    // MARK: - Parser: Button Syntax Variants

    func testButtonTitleAction() throws {
        let node = try parse("Button(\"Tap\") { count += 1 }")
        if case .button(let label, let action) = node {
            XCTAssertEqual(label, .text("Tap"))
            XCTAssertNotNil(action)
        } else {
            XCTFail("Expected button")
        }
    }

    func testButtonActionLabel() throws {
        let node = try parse("Button(action: { count += 1 }) { Text(\"Tap\") }")
        if case .button(let label, let action) = node {
            // action: closure is the action, trailing closure is the label
            XCTAssertNotNil(action)
            if case .compoundAssignment = action! { /* ok */ }
            else { XCTFail("Expected compoundAssignment action") }
            XCTAssertEqual(label, .text("Tap"))
        } else {
            XCTFail("Expected button")
        }
    }

    func testButtonMultipleTrailingClosures() throws {
        let node = try parse("Button { count += 1 } label: { Text(\"Tap\") }")
        if case .button(let label, let action) = node {
            XCTAssertNotNil(action)
            XCTAssertEqual(label, .text("Tap"))
        } else {
            XCTFail("Expected button, got \(node)")
        }
    }

    // MARK: - Parser: TextField

    func testTextField() throws {
        let node = try parse("TextField(\"Name\", text: $name)")
        if case .textField(let placeholder, let variable, _) = node {
            XCTAssertEqual(placeholder, "Name")
            XCTAssertEqual(variable, "name")
        } else {
            XCTFail("Expected textField, got \(node)")
        }
    }

    // MARK: - Parser: Toggle View

    func testToggleView() throws {
        let node = try parse("Toggle(\"Enable\", isOn: $flag)")
        if case .toggle(let label, let variable) = node {
            XCTAssertEqual(label, "Enable")
            XCTAssertEqual(variable, "flag")
        } else {
            XCTFail("Expected toggle, got \(node)")
        }
    }

    // MARK: - Parser: Slider

    func testSlider() throws {
        let node = try parse("Slider(value: $progress)")
        if case .slider(let variable, _) = node {
            XCTAssertEqual(variable, "progress")
        } else {
            XCTFail("Expected slider, got \(node)")
        }
    }

    // MARK: - Parser: AsyncImage

    func testAsyncImage() throws {
        let node = try parse("AsyncImage(url: URL(string: \"https://example.com/img.jpg\"))")
        if case .asyncImage(let url) = node {
            XCTAssertEqual(url, "https://example.com/img.jpg")
        } else {
            XCTFail("Expected asyncImage, got \(node)")
        }
    }

    // MARK: - Parser: ForEach with Range

    func testForEachHalfOpenRange() throws {
        let node = try parse("ForEach(0..<5) { i in Text(\"hi\") }")
        if case .forEach(let range, _, let body) = node {
            XCTAssertEqual(range, 0...4)
            XCTAssertEqual(body, .text("hi"))
        } else {
            XCTFail("Expected forEach, got \(node)")
        }
    }

    func testForEachClosedRange() throws {
        let node = try parse("ForEach(1...3) { i in Text(\"hi\") }")
        if case .forEach(let range, _, _) = node {
            XCTAssertEqual(range, 1...3)
        } else {
            XCTFail("Expected forEach")
        }
    }

    // MARK: - Parser: Color.xxx Recognition

    func testColorDotBlue() throws {
        let node = try parse("Text(\"hi\").foregroundColor(Color.blue)")
        if case .modified(_, let mods) = node {
            XCTAssertEqual(mods.first, .foregroundColor(.blue))
        } else {
            XCTFail("Expected modified")
        }
    }

    // MARK: - Parser: Modifiers

    func testBoldModifier() throws {
        let node = try parse("Text(\"hi\").bold()")
        if case .modified(_, let mods) = node {
            XCTAssertTrue(mods.contains(.bold))
        } else {
            XCTFail("Expected modified")
        }
    }

    func testBoldNoParen() throws {
        let node = try parse("Text(\"hi\").bold")
        if case .modified(_, let mods) = node {
            XCTAssertTrue(mods.contains(.bold))
        } else {
            XCTFail("Expected modified")
        }
    }

    func testItalicModifier() throws {
        let node = try parse("Text(\"hi\").italic()")
        if case .modified(_, let mods) = node {
            XCTAssertTrue(mods.contains(.italic))
        } else {
            XCTFail("Expected modified")
        }
    }

    func testStrikethroughModifier() throws {
        let node = try parse("Text(\"hi\").strikethrough()")
        if case .modified(_, let mods) = node {
            XCTAssertTrue(mods.contains(.strikethrough(nil)))
        } else {
            XCTFail("Expected modified")
        }
    }

    func testUnderlineModifier() throws {
        let node = try parse("Text(\"hi\").underline()")
        if case .modified(_, let mods) = node {
            XCTAssertTrue(mods.contains(.underline(nil)))
        } else {
            XCTFail("Expected modified")
        }
    }

    func testLineLimitModifier() throws {
        let node = try parse("Text(\"hi\").lineLimit(2)")
        if case .modified(_, let mods) = node {
            XCTAssertTrue(mods.contains(.lineLimit(2)))
        } else {
            XCTFail("Expected modified")
        }
    }

    func testFrameMaxWidth() throws {
        let node = try parse("Text(\"hi\").frame(maxWidth: .infinity)")
        if case .modified(_, let mods) = node {
            if case .frame(_, _, let maxW, _, _) = mods.first {
                XCTAssertEqual(maxW, .infinity)
            } else {
                XCTFail("Expected frame modifier")
            }
        } else {
            XCTFail("Expected modified")
        }
    }

    func testPaddingHorizontal() throws {
        let node = try parse("Text(\"hi\").padding(.horizontal, 16)")
        if case .modified(_, let mods) = node {
            if case .padding(let insets) = mods.first {
                XCTAssertEqual(insets.leading, 16)
                XCTAssertEqual(insets.trailing, 16)
                XCTAssertEqual(insets.top, 0)
            } else {
                XCTFail("Expected padding modifier")
            }
        } else {
            XCTFail("Expected modified")
        }
    }

    func testFillModifier() throws {
        let node = try parse("Circle().fill(.blue)")
        if case .modified(let view, let mods) = node {
            XCTAssertEqual(view, .circle)
            XCTAssertTrue(mods.contains(.fill(.blue)))
        } else {
            XCTFail("Expected modified")
        }
    }

    func testStrokeModifier() throws {
        let node = try parse("Circle().stroke(.red, lineWidth: 2)")
        if case .modified(let view, let mods) = node {
            XCTAssertEqual(view, .circle)
            XCTAssertTrue(mods.contains(.stroke(.red, lineWidth: 2)))
        } else {
            XCTFail("Expected modified")
        }
    }

    func testOffsetModifier() throws {
        let node = try parse("Text(\"hi\").offset(x: 10, y: 20)")
        if case .modified(_, let mods) = node {
            XCTAssertTrue(mods.contains(.offset(x: 10, y: 20)))
        } else {
            XCTFail("Expected modified")
        }
    }

    func testRotationEffectModifier() throws {
        let node = try parse("Text(\"hi\").rotationEffect(45)")
        if case .modified(_, let mods) = node {
            XCTAssertTrue(mods.contains(.rotationEffect(45)))
        } else {
            XCTFail("Expected modified")
        }
    }

    func testScaleEffectModifier() throws {
        let node = try parse("Text(\"hi\").scaleEffect(1.5)")
        if case .modified(_, let mods) = node {
            XCTAssertTrue(mods.contains(.scaleEffect(1.5)))
        } else {
            XCTFail("Expected modified")
        }
    }

    func testBlurModifier() throws {
        let node = try parse("Text(\"hi\").blur(radius: 5)")
        if case .modified(_, let mods) = node {
            XCTAssertTrue(mods.contains(.blur(5)))
        } else {
            XCTFail("Expected modified")
        }
    }

    func testNavigationTitleModifier() throws {
        let node = try parse("Text(\"hi\").navigationTitle(\"Home\")")
        if case .modified(_, let mods) = node {
            XCTAssertTrue(mods.contains(.navigationTitle("Home")))
        } else {
            XCTFail("Expected modified")
        }
    }

    func testIgnoresSafeArea() throws {
        let node = try parse("Text(\"hi\").ignoresSafeArea()")
        if case .modified(_, let mods) = node {
            XCTAssertTrue(mods.contains(.ignoresSafeArea))
        } else {
            XCTFail("Expected modified")
        }
    }

    func testAnimationModifier() throws {
        let node = try parse("Text(\"hi\").animation(.easeInOut)")
        if case .modified(_, let mods) = node {
            if case .animation(let anim) = mods.first {
                if case .easeInOut(nil) = anim { /* ok */ }
                else { XCTFail("Expected easeInOut animation") }
            } else {
                XCTFail("Expected animation modifier")
            }
        } else {
            XCTFail("Expected modified")
        }
    }

    func testTransitionModifier() throws {
        let node = try parse("Text(\"hi\").transition(.slide)")
        if case .modified(_, let mods) = node {
            XCTAssertTrue(mods.contains(.transition(.slide)))
        } else {
            XCTFail("Expected modified")
        }
    }

    func testFontSystemSize() throws {
        let node = try parse("Text(\"hi\").font(.system(size: 24, weight: .bold))")
        if case .modified(_, let mods) = node {
            if case .font(let style) = mods.first {
                if case .system(let size, let weight, _) = style {
                    XCTAssertEqual(size, 24)
                    XCTAssertEqual(weight, .bold)
                } else {
                    XCTFail("Expected .system font style")
                }
            }
        } else {
            XCTFail("Expected modified")
        }
    }

    func testFontWeightModifier() throws {
        let node = try parse("Text(\"hi\").fontWeight(.semibold)")
        if case .modified(_, let mods) = node {
            XCTAssertTrue(mods.contains(.fontWeight(.semibold)))
        } else {
            XCTFail("Expected modified")
        }
    }

    // MARK: - Parser: Dynamic Modifiers (Ternary in Color Args)

    func testDynamicForegroundColor() throws {
        let node = try parse("Text(\"hi\").foregroundColor(flag ? .blue : .red)")
        if case .modified(_, let mods) = node {
            if case .dynamic(let name, _) = mods.first {
                XCTAssertEqual(name, "foregroundColor")
            } else {
                XCTFail("Expected dynamic modifier, got \(mods)")
            }
        } else {
            XCTFail("Expected modified")
        }
    }

    func testDynamicBackground() throws {
        let node = try parse("Text(\"hi\").background(flag ? .blue : .red)")
        if case .modified(_, let mods) = node {
            if case .dynamic(let name, _) = mods.first {
                XCTAssertEqual(name, "background")
            } else {
                XCTFail("Expected dynamic modifier")
            }
        } else {
            XCTFail("Expected modified")
        }
    }

    // MARK: - Parser: GlassEffect

    func testGlassEffectBasic() throws {
        let node = try parse("Text(\"hi\").glassEffect()")
        if case .modified(_, let mods) = node {
            if case .glassEffect(let style, _, _) = mods.first {
                XCTAssertEqual(style, .regular)
            } else {
                XCTFail("Expected glassEffect modifier")
            }
        } else {
            XCTFail("Expected modified")
        }
    }

    func testGlassEffectWithStyle() throws {
        let node = try parse("Text(\"hi\").glassEffect(.clear)")
        if case .modified(_, let mods) = node {
            if case .glassEffect(let style, _, _) = mods.first {
                XCTAssertEqual(style, .clear)
            } else {
                XCTFail("Expected glassEffect modifier")
            }
        } else {
            XCTFail("Expected modified")
        }
    }

    // MARK: - Parser: Struct Extraction

    func testStructBodyExtraction() throws {
        let code = """
        struct MyView: View {
            @State private var count = 0
            var body: some View {
                Text("Hello")
            }
        }
        """
        let node = try parse(code)
        // Should produce a block with assignment + text
        if case .block(let stmts) = node {
            XCTAssertTrue(stmts.contains(where: { if case .assignment = $0 { return true }; return false }))
            XCTAssertTrue(stmts.contains(where: { if case .text = $0 { return true }; return false }))
        } else if case .text = node {
            // Only body extracted without state
        } else {
            XCTFail("Expected block or text from struct, got \(node)")
        }
    }

    // MARK: - State: Execute

    @MainActor
    func testStateExecutePlusAssign() {
        let state = SwiftRunnerState(["count": .number(0)])
        state.execute(.compoundAssignment(variable: "count", op: .plusAssign, value: .literal(.number(1))))
        XCTAssertEqual(state.variables["count"], .number(1))
    }

    @MainActor
    func testStateExecuteMinusAssign() {
        let state = SwiftRunnerState(["count": .number(5)])
        state.execute(.compoundAssignment(variable: "count", op: .minusAssign, value: .literal(.number(2))))
        XCTAssertEqual(state.variables["count"], .number(3))
    }

    @MainActor
    func testStateExecuteToggle() {
        let state = SwiftRunnerState(["flag": .boolean(true)])
        state.execute(.compoundAssignment(variable: "flag", op: .toggle, value: .empty))
        XCTAssertEqual(state.variables["flag"], .boolean(false))
        state.execute(.compoundAssignment(variable: "flag", op: .toggle, value: .empty))
        XCTAssertEqual(state.variables["flag"], .boolean(true))
    }

    @MainActor
    func testStateExecuteAssign() {
        let state = SwiftRunnerState(["name": .string("old")])
        state.execute(.compoundAssignment(variable: "name", op: .assign, value: .literal(.string("new"))))
        XCTAssertEqual(state.variables["name"], .string("new"))
    }

    @MainActor
    func testStateExecuteBlock() {
        let state = SwiftRunnerState(["a": .number(0), "b": .number(0)])
        state.execute(.block([
            .compoundAssignment(variable: "a", op: .plusAssign, value: .literal(.number(1))),
            .compoundAssignment(variable: "b", op: .plusAssign, value: .literal(.number(2)))
        ]))
        XCTAssertEqual(state.variables["a"], .number(1))
        XCTAssertEqual(state.variables["b"], .number(2))
    }

    @MainActor
    func testStateStringAppend() {
        let state = SwiftRunnerState(["text": .string("Hello")])
        state.execute(.compoundAssignment(variable: "text", op: .plusAssign, value: .literal(.string(" World"))))
        XCTAssertEqual(state.variables["text"], .string("Hello World"))
    }

    // MARK: - State: Evaluate

    @MainActor
    func testStateEvaluateVariable() {
        let state = SwiftRunnerState(["x": .number(42)])
        XCTAssertEqual(state.evaluate(.variable("x")), .number(42))
    }

    @MainActor
    func testStateEvaluateTernary() {
        let state = SwiftRunnerState(["flag": .boolean(true)])
        let result = state.evaluate(.ternary(
            condition: .variable("flag"),
            trueExpr: .literal(.string("yes")),
            falseExpr: .literal(.string("no"))
        ))
        XCTAssertEqual(result, .string("yes"))
    }

    @MainActor
    func testStateEvaluateTernaryFalse() {
        let state = SwiftRunnerState(["flag": .boolean(false)])
        let result = state.evaluate(.ternary(
            condition: .variable("flag"),
            trueExpr: .literal(.number(1)),
            falseExpr: .literal(.number(0))
        ))
        XCTAssertEqual(result, .number(0))
    }

    @MainActor
    func testStateEvaluateBinary() {
        let state = SwiftRunnerState(["x": .number(3)])
        let result = state.evaluate(.binary(
            left: .variable("x"),
            op: .multiply,
            right: .literal(.number(2))
        ))
        XCTAssertEqual(result, .number(6))
    }

    @MainActor
    func testStateEvaluateMin() {
        let state = SwiftRunnerState([:])
        let result = state.evaluate(.functionCall(name: "min", arguments: [
            Argument(value: .literal(.number(5))),
            Argument(value: .literal(.number(3)))
        ]))
        XCTAssertEqual(result, .number(3))
    }

    @MainActor
    func testStateEvaluateMax() {
        let state = SwiftRunnerState([:])
        let result = state.evaluate(.functionCall(name: "max", arguments: [
            Argument(value: .literal(.number(5))),
            Argument(value: .literal(.number(3)))
        ]))
        XCTAssertEqual(result, .number(5))
    }

    @MainActor
    func testStateResolveInterpolation() {
        let state = SwiftRunnerState(["name": .string("World")])
        let result = state.resolveInterpolation([
            .literal("Hello "),
            .expression(.variable("name")),
            .literal("!")
        ])
        XCTAssertEqual(result, "Hello World!")
    }

    @MainActor
    func testStateEvaluateColorProperty() {
        let state = SwiftRunnerState([:])
        let result = state.evaluate(.propertyAccess(object: .variable("Color"), property: "blue"))
        XCTAssertEqual(result, .string("blue"))
    }

    // MARK: - Integration: Full Counter View

    func testFullCounterCodeParses() throws {
        let code = """
        struct CounterView: View {
            @State private var count = 0
            var body: some View {
                VStack {
                    Text("Count: \\(count)")
                    Button("Add") { count += 1 }
                }
            }
        }
        """
        let node = try parse(code)
        // Should not throw and should produce a view-like AST
        XCTAssertNotEqual(node, .empty)
    }

    func testFullToggleCodeParses() throws {
        let code = """
        struct ToggleView: View {
            @State private var isOn = false
            var body: some View {
                VStack {
                    Text(isOn ? "ON" : "OFF")
                    Button("Toggle") { isOn.toggle() }
                }
            }
        }
        """
        let node = try parse(code)
        XCTAssertNotEqual(node, .empty)
    }

    func testImportAndPreviewHandled() throws {
        let code = """
        import SwiftUI
        struct V: View {
            var body: some View { Text("Hi") }
        }
        #Preview { V() }
        """
        // Should not throw
        let node = try parse(code)
        XCTAssertNotEqual(node, .empty)
    }
}
