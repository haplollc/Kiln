//
//  SwiftParserTests.swift
//  SwiftRunnerTests
//
//  Created by Claw on 2/21/26.
//

import XCTest
@testable import Kiln

final class SwiftParserTests: XCTestCase {
    
    private let parser = SwiftParser()
    
    private func parse(_ code: String) throws -> ViewNode {
        let lexer = SwiftLexer(source: code)
        let tokens = try lexer.tokenize()
        return try parser.parse(tokens)
    }
    
    // MARK: - Text Views
    
    func testParseText() throws {
        let node = try parse("Text(\"Hello World\")")
        XCTAssertEqual(node, .text("Hello World"))
    }
    
    func testParseTextWithModifier() throws {
        let node = try parse("Text(\"Hello\").font(.title)")
        
        if case .modified(let view, let modifiers) = node {
            XCTAssertEqual(view, .text("Hello"))
            XCTAssertEqual(modifiers.count, 1)
            XCTAssertEqual(modifiers[0], .font(.title))
        } else {
            XCTFail("Expected modified view")
        }
    }
    
    func testParseTextWithMultipleModifiers() throws {
        let node = try parse("Text(\"Hi\").font(.title).foregroundColor(.blue)")
        
        if case .modified(let view, let modifiers) = node {
            XCTAssertEqual(view, .text("Hi"))
            XCTAssertEqual(modifiers.count, 2)
            XCTAssertEqual(modifiers[0], .font(.title))
            XCTAssertEqual(modifiers[1], .foregroundColor(.blue))
        } else {
            XCTFail("Expected modified view")
        }
    }
    
    // MARK: - Images
    
    func testParseSystemImage() throws {
        let node = try parse("Image(systemName: \"star.fill\")")
        XCTAssertEqual(node, .systemImage("star.fill"))
    }
    
    func testParseAssetImage() throws {
        let node = try parse("Image(\"photo\")")
        XCTAssertEqual(node, .assetImage("photo"))
    }
    
    // MARK: - Stacks
    
    func testParseVStack() throws {
        let code = """
        VStack {
            Text("Hello")
            Text("World")
        }
        """
        let node = try parse(code)
        
        if case .vStack(let spacing, let alignment, let children) = node {
            XCTAssertNil(spacing)
            XCTAssertNil(alignment)
            XCTAssertEqual(children.count, 2)
            XCTAssertEqual(children[0], .text("Hello"))
            XCTAssertEqual(children[1], .text("World"))
        } else {
            XCTFail("Expected VStack, got \(node)")
        }
    }
    
    func testParseVStackWithSpacing() throws {
        let code = """
        VStack(spacing: 20) {
            Text("A")
        }
        """
        let node = try parse(code)
        
        if case .vStack(let spacing, _, _) = node {
            XCTAssertEqual(spacing, 20)
        } else {
            XCTFail("Expected VStack")
        }
    }
    
    func testParseHStack() throws {
        let code = """
        HStack {
            Text("Left")
            Text("Right")
        }
        """
        let node = try parse(code)
        
        if case .hStack(_, _, let children) = node {
            XCTAssertEqual(children.count, 2)
        } else {
            XCTFail("Expected HStack")
        }
    }
    
    func testParseZStack() throws {
        let code = """
        ZStack {
            Circle()
            Text("Center")
        }
        """
        let node = try parse(code)
        
        if case .zStack(_, let children) = node {
            XCTAssertEqual(children.count, 2)
            XCTAssertEqual(children[0], .circle)
        } else {
            XCTFail("Expected ZStack")
        }
    }
    
    // MARK: - Shapes
    
    func testParseCircle() throws {
        let node = try parse("Circle()")
        XCTAssertEqual(node, .circle)
    }
    
    func testParseRectangle() throws {
        let node = try parse("Rectangle()")
        XCTAssertEqual(node, .rectangle)
    }
    
    func testParseRoundedRectangle() throws {
        let node = try parse("RoundedRectangle(cornerRadius: 10)")
        XCTAssertEqual(node, .roundedRectangle(cornerRadius: 10))
    }
    
    func testParseCapsule() throws {
        let node = try parse("Capsule()")
        XCTAssertEqual(node, .capsule)
    }
    
    // MARK: - Modifiers
    
    func testParsePaddingModifier() throws {
        let node = try parse("Text(\"Hi\").padding()")
        
        if case .modified(_, let modifiers) = node {
            XCTAssertEqual(modifiers[0], .padding(.all(16)))
        } else {
            XCTFail("Expected modified view")
        }
    }
    
    func testParsePaddingWithValue() throws {
        let node = try parse("Text(\"Hi\").padding(20)")
        
        if case .modified(_, let modifiers) = node {
            XCTAssertEqual(modifiers[0], .padding(.all(20)))
        } else {
            XCTFail("Expected modified view")
        }
    }
    
    func testParseFrameModifier() throws {
        let node = try parse("Text(\"Hi\").frame(width: 100, height: 50)")
        
        if case .modified(_, let modifiers) = node {
            XCTAssertEqual(modifiers[0], .frame(width: 100, height: 50, maxWidth: nil, maxHeight: nil, alignment: nil))
        } else {
            XCTFail("Expected modified view")
        }
    }
    
    func testParseBackgroundModifier() throws {
        let node = try parse("Text(\"Hi\").background(.blue)")
        
        if case .modified(_, let modifiers) = node {
            XCTAssertEqual(modifiers[0], .background(.blue))
        } else {
            XCTFail("Expected modified view")
        }
    }
    
    func testParseCornerRadiusModifier() throws {
        let node = try parse("Text(\"Hi\").cornerRadius(8)")
        
        if case .modified(_, let modifiers) = node {
            XCTAssertEqual(modifiers[0], .cornerRadius(8))
        } else {
            XCTFail("Expected modified view")
        }
    }
    
    // MARK: - Expressions
    
    func testParseMathExpression() throws {
        let node = try parse("1 + 2")
        
        if case .binary(let left, let op, let right) = node {
            XCTAssertEqual(left, .literal(.number(1)))
            XCTAssertEqual(op, .plus)
            XCTAssertEqual(right, .literal(.number(2)))
        } else {
            XCTFail("Expected binary expression")
        }
    }
    
    func testParseVariableDeclaration() throws {
        let node = try parse("let x = 5")
        
        if case .assignment(let name, let isVar, let value) = node {
            XCTAssertEqual(name, "x")
            XCTAssertFalse(isVar)
            XCTAssertEqual(value, .literal(.number(5)))
        } else {
            XCTFail("Expected assignment")
        }
    }
    
    func testParsePrintStatement() throws {
        let node = try parse("print(\"Hello\")")
        
        if case .functionCall(let name, let args) = node {
            XCTAssertEqual(name, "print")
            XCTAssertEqual(args.count, 1)
        } else {
            XCTFail("Expected function call")
        }
    }
    
    // MARK: - Complex Views
    
    func testParseNestedStacks() throws {
        let code = """
        VStack {
            HStack {
                Text("A")
                Text("B")
            }
            Text("C")
        }
        """
        let node = try parse(code)
        
        if case .vStack(_, _, let children) = node {
            XCTAssertEqual(children.count, 2)
            if case .hStack(_, _, let hChildren) = children[0] {
                XCTAssertEqual(hChildren.count, 2)
            } else {
                XCTFail("Expected HStack as first child")
            }
        } else {
            XCTFail("Expected VStack")
        }
    }
    
    func testParseComplexView() throws {
        let code = """
        VStack(spacing: 20) {
            Text("Title").font(.largeTitle)
            Circle().frame(width: 100, height: 100).foregroundColor(.blue)
        }
        """
        let node = try parse(code)
        
        if case .vStack(let spacing, _, let children) = node {
            XCTAssertEqual(spacing, 20)
            // Filter out empty nodes
            let nonEmptyChildren = children.filter { 
                if case .empty = $0 { return false }
                return true
            }
            XCTAssertEqual(nonEmptyChildren.count, 2)
            
            // First child should be modified Text
            if case .modified(let text, let textMods) = nonEmptyChildren[0] {
                XCTAssertEqual(text, .text("Title"))
                XCTAssertEqual(textMods.count, 1)
            } else {
                XCTFail("Expected modified Text, got \(nonEmptyChildren[0])")
            }
            
            // Second child should be modified Circle
            if case .modified(let circle, let circleMods) = nonEmptyChildren[1] {
                XCTAssertEqual(circle, .circle)
                XCTAssertEqual(circleMods.count, 2)
            } else {
                XCTFail("Expected modified Circle, got \(nonEmptyChildren[1])")
            }
        } else {
            XCTFail("Expected VStack")
        }
    }

    // MARK: - Import & Struct Tests

    func testParseImportStatement() throws {
        let code = """
        import SwiftUI

        Text("Hello")
        """
        let result = try parse(code)
        // import is skipped, Text is parsed
        XCTAssertEqual(result, .text("Hello"))
    }

    func testParseStructWithBody() throws {
        let code = """
        import SwiftUI

        struct ContentView: View {
            var body: some View {
                Text("Hello, World!")
                    .padding()
            }
        }
        """
        let result = try parse(code)
        // Should extract the body: Text with padding modifier
        if case .modified(let view, let mods) = result {
            XCTAssertEqual(view, .text("Hello, World!"))
            XCTAssertEqual(mods.count, 1)
            if case .padding = mods[0] {} else {
                XCTFail("Expected padding modifier, got \(mods[0])")
            }
        } else {
            XCTFail("Expected modified text, got \(result)")
        }
    }

    func testParseStructWithPreviewProvider() throws {
        let code = """
        import SwiftUI

        struct ContentView: View {
            var body: some View {
                Text("Hello, World!")
                    .padding()
            }
        }

        struct ContentView_Previews: PreviewProvider {
            static var previews: some View {
                Text("Preview")
            }
        }
        """
        let result = try parse(code)
        // Should extract body from the first struct
        if case .block(let stmts) = result {
            // First struct body + second struct body
            let nonEmpty = stmts.filter { $0 != .empty }
            XCTAssertGreaterThanOrEqual(nonEmpty.count, 1)
            // First should be the modified Text("Hello, World!")
            if case .modified(let view, _) = nonEmpty[0] {
                XCTAssertEqual(view, .text("Hello, World!"))
            } else {
                XCTFail("Expected modified text from first struct, got \(nonEmpty[0])")
            }
        } else if case .modified(let view, _) = result {
            // If only one view extracted
            XCTAssertEqual(view, .text("Hello, World!"))
        } else {
            XCTFail("Expected block or modified text, got \(result)")
        }
    }

    // MARK: - End-to-End Runner Tests

    @MainActor
    func testRunProducesViewForStructCode() throws {
        let code = """
        import SwiftUI

        struct ContentView: View {
            var body: some View {
                Text("Hello, World!")
                    .padding()
            }
        }
        """
        let result = SwiftRunner.shared.run(code)
        XCTAssertTrue(result.hasView, "Expected hasView=true, got false. Errors: \(result.errors)")
        XCTAssertTrue(result.errors.isEmpty, "Expected no errors, got: \(result.errors)")
    }

    @MainActor
    func testRunProducesViewForBarebonesCode() throws {
        let code = """
        VStack {
            Text("Hello")
            Text("World")
        }
        """
        let result = SwiftRunner.shared.run(code)
        XCTAssertTrue(result.hasView, "Expected hasView=true. Errors: \(result.errors)")
    }

    @MainActor
    func testRunProducesViewForStructWithStateAndModifiers() throws {
        let code = """
        import SwiftUI

        struct ContentView: View {
            @State var count = 0

            var body: some View {
                VStack(spacing: 20) {
                    Text("Count")
                        .font(.title)
                        .foregroundColor(.blue)
                    Circle()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.red)
                }
                .padding()
            }
        }
        """
        let result = SwiftRunner.shared.run(code)
        XCTAssertTrue(result.hasView, "Expected hasView=true. Errors: \(result.errors)")
        XCTAssertTrue(result.errors.isEmpty, "Expected no errors, got: \(result.errors)")
    }

    @MainActor
    func testRunProducesViewForSimpleText() throws {
        let code = "Text(\"Hello\")"
        let result = SwiftRunner.shared.run(code)
        XCTAssertTrue(result.hasView, "Expected hasView=true. Errors: \(result.errors)")
    }

    // MARK: - Attribute Handling Tests

    func testLexerHandlesAtAttributes() throws {
        let code = """
        @State var count = 0
        """
        let lexer = SwiftLexer(source: code)
        let tokens = try lexer.tokenize()
        // @State should be skipped, we should get: var, count, =, 0, EOF
        let nonNewline = tokens.filter { if case .newline = $0.type { return false }; return true }
        XCTAssertTrue(nonNewline.contains(where: { $0.type == .keyword(.var) }), "Should contain 'var' token")
    }

    func testParseStructWithAtAttributes() throws {
        let code = """
        struct ContentView: View {
            @State var count = 0

            var body: some View {
                Text("Hello")
            }
        }
        """
        let node = try parse(code)
        // Struct with @State produces a block: [assignment("count"), text("Hello")]
        if case .block(let stmts) = node {
            XCTAssertTrue(stmts.contains(where: { if case .text("Hello") = $0 { return true }; return false }))
        } else {
            XCTFail("Expected block from struct with @State, got \(node)")
        }
    }

    @MainActor
    func testRunProducesViewWithPreviewProvider() throws {
        let code = """
        import SwiftUI

        struct ContentView: View {
            var body: some View {
                Text("Hello, World!")
                    .padding()
            }
        }

        struct ContentView_Previews: PreviewProvider {
            static var previews: some View {
                ContentView()
            }
        }
        """
        let result = SwiftRunner.shared.run(code)
        XCTAssertTrue(result.hasView, "Expected hasView=true. Errors: \(result.errors)")
        XCTAssertTrue(result.errors.isEmpty, "Expected no errors, got: \(result.errors)")
    }
}
