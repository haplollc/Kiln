import SwiftUI

enum TimerMode: String, CaseIterable {
    case focus = "Focus"
    case shortBreak = "Break"

    var minutes: Int {
        switch self {
        case .focus: return 25
        case .shortBreak: return 5
        }
    }

    var color: Color {
        self == .focus ? .red : .green
    }
}

struct ContentView: View {
    @State private var mode: TimerMode = .focus
    @State private var remaining = 25 * 60
    @State private var isRunning = false
    @State private var sessions = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var total: Int { mode.minutes * 60 }
    private var progress: Double { 1 - Double(remaining) / Double(total) }
    private var timeText: String { String(format: "%02d:%02d", remaining / 60, remaining % 60) }

    var body: some View {
        VStack(spacing: 32) {
            Picker("Mode", selection: $mode) {
                ForEach(TimerMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) {
                reset()
            }

            ZStack {
                Circle()
                    .stroke(mode.color.opacity(0.15), lineWidth: 18)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(mode.color, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                VStack(spacing: 6) {
                    Text(timeText)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(mode.rawValue.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 260, height: 260)

            HStack(spacing: 16) {
                Button(isRunning ? "Pause" : "Start") {
                    isRunning.toggle()
                }
                .buttonStyle(.borderedProminent)
                .tint(mode.color)

                Button("Reset", action: reset)
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(0..<4) { index in
                        Circle()
                            .fill(index < sessions % 4 ? mode.color : Color.gray.opacity(0.3))
                            .frame(width: 12, height: 12)
                    }
                }
                Text("\(sessions) sessions completed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .onReceive(timer) { _ in
            guard isRunning else { return }
            if remaining > 0 {
                remaining -= 1
            } else {
                isRunning = false
                if mode == .focus {
                    sessions += 1
                }
                mode = mode == .focus ? .shortBreak : .focus
                remaining = mode.minutes * 60
            }
        }
    }

    private func reset() {
        isRunning = false
        remaining = mode.minutes * 60
    }
}
