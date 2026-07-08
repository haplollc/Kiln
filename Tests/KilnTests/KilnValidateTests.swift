//
//  KilnValidateTests.swift
//  KilnTests
//
//  Tests for the `Kiln.validate` probe — the deep native-app validation that
//  eagerly renders + exercises generated apps instead of trusting the vacuous
//  "parsed and produced a view wrapper" check.
//

import XCTest
@testable import Kiln

@MainActor
final class KilnValidateTests: XCTestCase {

    // A complete, working app validates clean.
    func testGoodTodoAppIsValid() {
        let src = """
        import SwiftUI
        struct ContentView: View {
            @State private var items = ["Buy groceries", "Walk the dog"]
            @State private var newItem = ""
            var body: some View {
                VStack {
                    Text("To-Do").font(.largeTitle)
                    ForEach(items, id: \\.self) { item in
                        Text(item)
                    }
                    Button("Add") { items.append("task") }
                }
            }
        }
        """
        let v = Kiln.validate(src)
        XCTAssertTrue(v.hasView)
        XCTAssertTrue(v.renderedContent, "expected visible content")
        XCTAssertTrue(v.errors.isEmpty, "unexpected errors: \(v.errors)")
        XCTAssertTrue(v.isValid)
    }

    // A game that draws via GameCanvas + advances on tick validates clean, and
    // firing onTick many times must not hang (bounded fuel).
    func testGameCanvasWithTickIsValid() {
        let src = """
        import SwiftUI
        struct ContentView: View {
            @State private var x = 100.0
            @State private var vx = 5.0
            var body: some View {
                GameCanvas([["type": "circle", "x": x, "y": 200.0, "r": 20.0, "color": "lime"]])
                    .onTick(0.1) {
                        x = x + vx
                        if x > 300.0 { vx = -5.0 }
                        if x < 20.0 { vx = 5.0 }
                    }
            }
        }
        """
        let v = Kiln.validate(src)
        XCTAssertTrue(v.renderedContent)
        XCTAssertTrue(v.errors.isEmpty, "unexpected errors: \(v.errors)")
    }

    // A body that returns nothing visible is caught as a blank screen — the exact
    // failure the old errors+hasView check missed.
    func testBlankBodyIsCaught() {
        let src = """
        import SwiftUI
        struct ContentView: View {
            var body: some View {
                VStack {
                    EmptyView()
                }
            }
        }
        """
        let v = Kiln.validate(src)
        XCTAssertFalse(v.renderedContent, "a body with no visible content must not read as rendered")
        XCTAssertFalse(v.isValid)
    }

    // A GameCanvas whose shape helper is broken (calls an undefined function)
    // renders a blank canvas AND reports the runtime error — old check passed it.
    func testBrokenHelperReportsError() {
        let src = """
        import SwiftUI
        struct ContentView: View {
            var body: some View {
                GameCanvas(cells())
            }
            func cells() -> [[String: Double]] {
                var shapes = [["type": "rect", "x": 0.0, "y": 0.0, "w": 50.0, "h": 50.0, "color": "red"]]
                shapes.append(makeMissingShape())
                return shapes
            }
        }
        """
        let v = Kiln.validate(src)
        XCTAssertTrue(!v.errors.isEmpty || !v.warnings.isEmpty,
                      "expected the undefined makeMissingShape() to be reported; errors=\(v.errors) warnings=\(v.warnings)")
    }

    // An infinite recursion must terminate via the call-depth / fuel guard, not
    // hang the test, and must be reported.
    func testInfiniteRecursionIsBounded() {
        let src = """
        import SwiftUI
        struct ContentView: View {
            var body: some View {
                Text(spin())
            }
            func spin() -> String {
                return spin()
            }
        }
        """
        let v = Kiln.validate(src, fuel: 100_000)
        XCTAssertFalse(v.errors.isEmpty, "runaway recursion should be reported")
    }

    // A huge for-range in an onTick handler must be capped, not freeze.
    func testHugeRangeIsCapped() {
        let src = """
        import SwiftUI
        struct ContentView: View {
            @State private var total = 0
            var body: some View {
                Text("Sum \\(total)")
                    .onTick(0.1) {
                        for i in 0..<100000000 {
                            total = total + 1
                        }
                    }
            }
        }
        """
        let v = Kiln.validate(src, fuel: 500_000)
        XCTAssertFalse(v.errors.isEmpty, "an unbounded loop should be reported as runaway")
    }

    // Parse-level failure still reports (no view produced).
    func testNoContentViewReported() {
        let src = "import SwiftUI\nlet x = 5"
        let v = Kiln.validate(src)
        XCTAssertFalse(v.hasView)
        XCTAssertFalse(v.errors.isEmpty)
    }
}
