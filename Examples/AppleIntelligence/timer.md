Here’s a SwiftUI Pomodoro focus timer with a circular progress ring, start/pause/reset controls, and a session counter:

```swift
import SwiftUI

struct PomodoroTimerView: View {
    @State private var timer: Timer?
    @State private var sessionDuration: TimeInterval = 25 * 60 // 25 minutes
    @State private var isPaused: Bool = false
    @State private var remainingTime: Int = Int(sessionDuration)
    @State private var sessionCount: Int = 0

    var body: some View {
        VStack(spacing: 20) {
            CircularProgressRing(progress: Double(remainingTime) / Double(sessionDuration))
                .frame(width: 200, height: 200)
                .foregroundColor(isPaused ? .gray : .green)

            HStack(spacing: 20) {
                Button(action: {
                    startTimer()
                }) {
                    Text(isPaused ? "Pause" : "Start")
                }
                .padding()
                .background(Color.blue)
                .cornerRadius(10)

                Button(action: {
                    pauseTimer()
                }) {
                    Text(isPaused ? "Resume" : "Pause")
                }
                .padding()
                .background(Color.green)
                .cornerRadius(10)

                Button(action: {
                    resetTimer()
                }) {
                    Text("Reset")
                }
                .padding()
                .background(Color.red)
                .cornerRadius(10)
            }

            Text("Session: \(sessionCount) sessions")
                .font(.headline)
                .padding()

            Text("Time left: \(String(format: "%02d:%02d", remainingTime / 60, remainingTime % 60))")
                .font(.largeTitle)
                .padding()
        }
        .padding()
    }

    private func startTimer() {
        guard !isPaused else { return }
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if isPaused { return }
            
            remainingTime -= 1
            
            if remainingTime <= 0 {
                sessionCount += 1
                
                if isPaused {
                    timer?.invalidate()
                    timer = nil
                    isPaused = false
                    
                    // Optionally, reset the timer for the next session
                    // sessionDuration = 25 * 60 // 25 minutes
                }
            }
        }
    }

    private func pauseTimer() {
        isPaused = true
        timer?.invalidate()
        timer = nil
    }

    private func resetTimer() {
        sessionCount = 0
        remainingTime = Int(sessionDuration)
        isPaused = false
        
        // Optionally, reset the timer for the next session
        // sessionDuration = 25 * 60 // 25 minutes
    }
}

struct CircularProgressRing: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        let width = min(rect.width, rect.height)
        let radius = (rect.width + rect.height) / 2 - 10
        let startAngle = atan2(radius, width / 2)
        let endAngle = atan2(radius, (width + width * progress) / 2)
        
        var path = Path()
        path.addArc(center: CGPoint(x: width / 2, y: height: rect.height / 2),
                    radius: radius,
                    startAngle: .degrees(startAngle),
                    endAngle: .degrees(endAngle),
                    clockwise: false)
        
        // Close the circle
        path.addLine(to: CGPoint(x: width / 2, y: height: rect.height / 2))
        path.addArc(center: CGPoint(x: width / 2, y: height: rect.height / 2),
                    radius: radius,
                    startAngle: .degrees(startAngle),
                    endAngle: .degrees(startAngle),
                    clockwise: true)
        
        return path
    }
}

struct PomodoroTimerView_Previews: PreviewProvider {
    static var previews: some View {
        PomodoroTimerView()
    }
}
```

### Explanation:

- **Circular Progress Ring**: A custom `Shape` that calculates the progress based on the `progress` parameter.
- **Timer Management**: Uses `@State` for the timer, session duration, pause state, and remaining time.
- **Controls**: Three buttons for start, pause, and reset, with state updates.
- **Session Counter**: Displays the number of completed sessions.

You can customize the duration and appearance further as needed.