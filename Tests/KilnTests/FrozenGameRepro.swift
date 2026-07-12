import XCTest
@testable import Kiln

// A GameCanvas app with an .onTick loop that never changes what it draws is
// broken (frozen screen) even though it renders — the Tetris failure class:
// a moving entity starts empty/nil and is never spawned. The probe must FAIL it,
// while a genuinely animating game (snake) must still PASS.
@MainActor
final class FrozenGameRepro: XCTestCase {

    // onTick runs but the drawn shapes never change (pieces array never filled).
    func testFrozenGameFails() {
        let r = Kiln.validate("""
        import SwiftUI
        struct ContentView: View {
            @State private var pieces = [[Double]]()
            @State private var t = 0
            var body: some View {
                GameCanvas(cells())
                    .onTick(0.2) { t = t + 1 }
            }
            func cells() -> [[String: Double]] {
                var shapes = [["type": "rect", "x": 0.0, "y": 0.0, "w": 200.0, "h": 300.0, "color": "#000000"]]
                for p in pieces {
                    shapes.append(["type": "rect", "x": p[0], "y": p[1], "w": 20.0, "h": 20.0, "color": "red"])
                }
                return shapes
            }
        }
        """)
        XCTAssertFalse(r.errors.isEmpty, "a frozen onTick game should FAIL, got errors=\(r.errors)")
        XCTAssertTrue(r.errors.contains { $0.lowercased().contains("frozen") || $0.lowercased().contains("nothing on the gamecanvas") },
                      "should explain the frozen loop — errors=\(r.errors)")
    }

    // A real snake: onTick advances the snake, so the shapes change → PASS.
    func testAnimatingGamePasses() {
        let r = Kiln.validate("""
        import SwiftUI
        struct ContentView: View {
            @State private var snake = [[5.0, 8.0], [4.0, 8.0], [3.0, 8.0]]
            @State private var dx = 1.0
            var body: some View {
                GameCanvas(cells())
                    .onTick(0.2) { step() }
            }
            func step() {
                let head = snake[0]
                snake = [[head[0] + dx, head[1]]] + snake.dropLast()
            }
            func cells() -> [[String: Double]] {
                var shapes = [["type": "rect", "x": 0.0, "y": 0.0, "w": 360.0, "h": 500.0, "color": "#000000"]]
                for seg in snake {
                    shapes.append(["type": "rect", "x": seg[0] * 18.0, "y": seg[1] * 18.0, "w": 16.0, "h": 16.0, "color": "lime"])
                }
                return shapes
            }
        }
        """)
        XCTAssertTrue(r.errors.isEmpty, "an animating snake should PASS, got errors=\(r.errors)")
    }
}
