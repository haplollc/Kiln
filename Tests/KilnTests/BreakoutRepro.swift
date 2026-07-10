import XCTest
@testable import Kiln

// From a real 7B breakout that looped on "blank screen" with zero clues: the
// model wrote `var shapes = ["type": …]` (a DICTIONARY — forgot the outer
// brackets) then `shapes.append(brick)`, which silently no-opped.
@MainActor
final class BreakoutRepro: XCTestCase {

    // The dict-instead-of-array mistake must produce a NAMED error mentioning
    // the double-bracket fix, not a silent blank screen.
    func testAppendOnDictionaryIsNamed() {
        let src = """
        import SwiftUI
        struct ContentView: View {
            @State private var bricks = [["type": "rect", "x": 60.0, "y": 100.0, "w": 80.0, "h": 20.0, "color": "red"]]
            var body: some View {
                GameCanvas(cells())
            }
            func cells() -> [[String: Double]] {
                var shapes = ["type": "rect", "x": 0.0, "y": 0.0, "w": 393.0, "h": 414.0, "color": "#0B1021"]
                for brick in bricks {
                    shapes.append(brick)
                }
                return shapes
            }
        }
        """
        let v = Kiln.validate(src)
        XCTAssertFalse(v.isValid, "dict-shapes app should not validate")
        let all = (v.errors + v.warnings).joined(separator: " ")
        XCTAssertTrue(all.contains("DICTIONARY") || all.contains("dictionary"),
                      "expected a dictionary-append fix-it, got errors=\(v.errors) warnings=\(v.warnings)")
    }

    // for (i, x) in arr.enumerated() must actually iterate (used for brick hits).
    func testEnumeratedLoop() {
        let src = """
        import SwiftUI
        struct ContentView: View {
            @State private var total = 0
            @State private var nums = [10, 20, 30]
            var body: some View {
                Text("Total \\(total)")
                    .onAppear {
                        var sum = 0
                        for (i, n) in nums.enumerated() {
                            sum = sum + n + i
                        }
                        total = sum
                    }
            }
        }
        """
        let v = Kiln.validate(src)
        XCTAssertTrue(v.errors.isEmpty && v.warnings.isEmpty,
                      "enumerated loop should run clean: \(v.errors) \(v.warnings)")
    }

    // The CORRECT breakout shape (array of dicts + loops + collision) validates.
    func testCorrectBreakoutValidates() {
        let src = """
        import SwiftUI
        struct ContentView: View {
            @State private var paddleX = 160.0
            @State private var ball = [180.0, 250.0]
            @State private var vel = [4.0, -3.0]
            @State private var bricks = [[60.0, 100.0], [150.0, 100.0], [240.0, 100.0]]
            @State private var score = 0
            @State private var over = false
            var body: some View {
                GameCanvas(cells())
                    .onTick(0.02) { step() }
                    .onSwipe { dir in
                        if dir == "left" && paddleX > 0 { paddleX = paddleX - 30 }
                        if dir == "right" && paddleX < 313 { paddleX = paddleX + 30 }
                    }
                    .onTapGesture { if over { reset() } }
            }
            func step() {
                if over { return }
                ball[0] = ball[0] + vel[0]
                ball[1] = ball[1] + vel[1]
                if ball[0] < 8 || ball[0] > 385 { vel[0] = 0 - vel[0] }
                if ball[1] < 8 { vel[1] = 0 - vel[1] }
                if ball[1] > 700 && ball[0] > paddleX && ball[0] < paddleX + 80 { vel[1] = 0 - vel[1] }
                if ball[1] > 800 { over = true }
                var kept = []
                for b in bricks {
                    if ball[0] > b[0] && ball[0] < b[0] + 80 && ball[1] > b[1] && ball[1] < b[1] + 20 {
                        score = score + 1
                        vel[1] = 0 - vel[1]
                    } else {
                        kept.append(b)
                    }
                }
                bricks = kept
            }
            func reset() {
                ball = [180.0, 250.0]; vel = [4.0, -3.0]
                bricks = [[60.0, 100.0], [150.0, 100.0], [240.0, 100.0]]
                score = 0; over = false
            }
            func cells() -> [[String: Double]] {
                var shapes = [["type": "rect", "x": 0.0, "y": 0.0, "w": 393.0, "h": 820.0, "color": "#101020"]]
                for b in bricks {
                    shapes.append(["type": "rect", "x": b[0], "y": b[1], "w": 78.0, "h": 18.0, "color": "orange"])
                }
                shapes.append(["type": "rect", "x": paddleX, "y": 700.0, "w": 80.0, "h": 16.0, "color": "white"])
                shapes.append(["type": "circle", "x": ball[0], "y": ball[1], "r": 8.0, "color": "lime"])
                shapes.append(["type": "text", "x": 12.0, "y": 24.0, "text": "Score: " + String(score), "size": 20.0, "color": "white"])
                return shapes
            }
        }
        """
        let v = Kiln.validate(src)
        XCTAssertTrue(v.isValid, "correct breakout should validate: \(v.errors) \(v.warnings)")
    }
}
