import XCTest
@testable import Kiln

// Repro of the Button forms a real model emits (from a weather-app failure).
@MainActor
final class ButtonFormsRepro: XCTestCase {
    func report(_ name: String, _ body: String) {
        let src = "import SwiftUI\nstruct ContentView: View {\n  @State private var n = 0\n  var body: some View {\n\(body)\n  }\n  func act() { n = n + 1 }\n}"
        let v = Kiln.validate(src)
        XCTAssertTrue(v.hasView && v.renderedContent && v.errors.isEmpty,
                      "BTN[\(name)] failed: \(v.errors)")
    }

    func testButtonActionLabelClosure() {
        // Button(action: { … }) { label }
        report("action+trailingLabel", """
            Button(action: { act() }) {
                Text("Tap")
            }
        """)
    }

    func testButtonActionLabelLabeled() {
        // Button(action: { … }) label: { label }  — the failing form
        report("action+label:", """
            Button(action: { act() }) label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        """)
    }
}
