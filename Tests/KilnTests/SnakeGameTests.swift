import XCTest
@testable import Kiln

// Regression tests for the constructs a real Qwen-generated snake game used that
// used to fail Kiln (from a Bond export that burned 30 build-loop iterations):
// custom init(), repeat-while, let-constants with computed initializers.
@MainActor
final class SnakeGameTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Mirror Bond's native bridges so Screen.width()/height() resolve (Bond
        // registers these via KilnBridges; the standalone test must too).
        Kiln.register("Screen.width") { _ in .number(393) }
        Kiln.register("Screen.height") { _ in .number(852) }
    }

    func assertValid(_ name: String, _ src: String) {
        let v = Kiln.validate(src)
        XCTAssertTrue(v.hasView, "\(name): no view — errors=\(v.errors)")
        XCTAssertTrue(v.renderedContent, "\(name): rendered nothing")
        XCTAssertTrue(v.errors.isEmpty, "\(name): errors=\(v.errors)")
        XCTAssertTrue(v.warnings.isEmpty, "\(name): warnings=\(v.warnings)")
    }

    func report(_ name: String, _ src: String) { assertValid(name, src) }

    // Minimal: custom init() in the struct.
    func testInit() {
        report("init", """
        import SwiftUI
        struct ContentView: View {
            @State private var n = 0
            init() { n = 5 }
            var body: some View { Text("n \\(n)") }
        }
        """)
    }

    // Minimal: repeat-while loop.
    func testRepeatWhile() {
        report("repeat-while", """
        import SwiftUI
        struct ContentView: View {
            @State private var x = 0
            func setup() {
                var i = 0
                repeat { i += 1 } while i < 3
                x = i
            }
            var body: some View { Text("x \\(x)").onAppear { setup() } }
        }
        """)
    }

    // Minimal: optional tuple @State + optional chaining.
    func testOptionalTuple() {
        report("optional-tuple", """
        import SwiftUI
        struct ContentView: View {
            @State private var food: (x: Double, y: Double)? = nil
            var body: some View {
                GameCanvas([["type": "rect", "x": food?.x ?? 0, "y": food?.y ?? 0, "w": 20.0, "h": 20.0, "color": "red"]])
            }
        }
        """)
    }

    // Minimal: PreviewProvider extra struct.
    func testPreviewProvider() {
        report("preview", """
        import SwiftUI
        struct ContentView: View {
            var body: some View { Text("hi") }
        }
        struct ContentView_Previews: PreviewProvider {
            static var previews: some View { ContentView() }
        }
        """)
    }

    // The full exported snake (cleaned of the stray leading/trailing "").
    func testFullSnake() {
        let src = """
        import SwiftUI

        struct ContentView: View {
            @State private var snake = [(x: 100.0, y: 200.0)]
            @State private var direction = "Right"
            @State private var food: (x: Double, y: Double)?
            @State private var score = 0
            @State private var gameOver = false

            let cellSize = 20.0
            let gridWidth = Int(Screen.width() / cellSize)
            let gridHeight = Int(Screen.height() / cellSize)

            init() {
                placeFood()
            }

            func moveSnake() {
                guard !gameOver else { return }
                var newHead = snake[0]
                switch direction {
                case "Up": newHead.y -= cellSize
                case "Down": newHead.y += cellSize
                case "Left": newHead.x -= cellSize
                case "Right": newHead.x += cellSize
                default: break
                }
                if !isCollision(newHead) {
                    snake.insert(newHead, at: 0)
                    if let food = food, newHead == food {
                        score += 1
                        placeFood()
                    } else {
                        snake.removeLast()
                    }
                } else {
                    gameOver = true
                }
            }

            func isCollision(_ head: (x: Double, y: Double)) -> Bool {
                if head.x < 0 || head.x >= Screen.width() || head.y < 0 || head.y >= Screen.height() {
                    return true
                }
                for segment in snake.dropFirst(1) {
                    if segment == head { return true }
                }
                return false
            }

            func placeFood() {
                var foodPosition: (x: Double, y: Double)
                repeat {
                    foodPosition = (Double.random(in: 0..<gridWidth) * cellSize, Double.random(in: 0..<gridHeight) * cellSize)
                } while snake.contains(where: { $0.x == foodPosition.x && $0.y == foodPosition.y })
                food = foodPosition
            }

            func onSwipe(_ dir: String) {
                switch direction {
                case "Up": if dir != "Down" { direction = dir }
                case "Down": if dir != "Up" { direction = dir }
                case "Left": if dir != "Right" { direction = dir }
                case "Right": if dir != "Left" { direction = dir }
                default: break
                }
            }

            var body: some View {
                GameCanvas([
                    ["type": "text", "x": 5, "y": 20, "text": "Score: \\(score)", "size": 18.0, "color": "black"],
                    ["type": "rect", "x": food?.x ?? 0, "y": food?.y ?? 0, "w": cellSize, "h": cellSize, "color": "red"]
                ] + snake.map { ["type": "rect", "x": $0.x, "y": $0.y, "w": cellSize, "h": cellSize, "color": "green"] })
                .onTick(0.18) { moveSnake() }
                .onSwipe(onSwipe)
            }
        }
        """
        report("full-snake", src)
    }
}
