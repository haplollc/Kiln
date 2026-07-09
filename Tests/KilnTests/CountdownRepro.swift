import XCTest
@testable import Kiln
// Pomodoro / countdown timer: @State seconds + onTick + start/pause + sessions.
@MainActor
final class CountdownRepro: XCTestCase {
    func testPomodoro() {
        let src = """
        import SwiftUI
        struct ContentView: View {
            @State private var secondsLeft = 1500
            @State private var running = false
            @State private var sessions = 0
            var body: some View {
                VStack(spacing: 24) {
                    Text("Pomodoro").font(.largeTitle).bold()
                    Text(String(secondsLeft / 60) + ":" + String(secondsLeft % 60)).font(.system(size: 64))
                    HStack(spacing: 20) {
                        Button("Start") { running = true }
                            .padding().background(Color.green).foregroundColor(.white).cornerRadius(10)
                        Button("Pause") { running = false }
                            .padding().background(Color.orange).foregroundColor(.white).cornerRadius(10)
                    }
                    Text("Completed: " + String(sessions)).font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTick(1.0) {
                    if running && secondsLeft > 0 { secondsLeft = secondsLeft - 1 }
                    if secondsLeft == 0 { running = false; sessions = sessions + 1; secondsLeft = 1500 }
                }
            }
        }
        """
        let v = Kiln.validate(src)
        XCTAssertTrue(v.hasView && v.renderedContent && v.errors.isEmpty, "pomodoro failed: \(v.errors)")
    }
}
