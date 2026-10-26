import SwiftUI

struct Habit: Identifiable {
    let id = UUID()
    var name: String
    var icon: String
    var streak: Int
    var doneToday: Bool = false
}

struct ContentView: View {
    @State private var habits: [Habit] = [
        Habit(name: "Drink water", icon: "drop.fill", streak: 4),
        Habit(name: "Read 20 pages", icon: "book.fill", streak: 12, doneToday: true),
        Habit(name: "Meditate", icon: "brain.head.profile", streak: 2),
        Habit(name: "Walk 8k steps", icon: "figure.walk", streak: 7)
    ]
    @State private var newHabit = ""

    private var completed: Int {
        habits.filter { $0.doneToday }.count
    }

    private var progress: Double {
        habits.isEmpty ? 0 : Double(completed) / Double(habits.count)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .stroke(Color.green.opacity(0.2), lineWidth: 10)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(Color.green, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut, value: progress)
                            Text("\(Int(progress * 100))%")
                                .font(.headline)
                        }
                        .frame(width: 72, height: 72)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Today")
                                .font(.title2.bold())
                            Text("\(completed) of \(habits.count) habits done")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Habits") {
                    ForEach($habits) { $habit in
                        HStack(spacing: 12) {
                            Image(systemName: habit.icon)
                                .foregroundStyle(.green)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(habit.name)
                                Text("🔥 \(habit.streak) day streak")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                habit.doneToday.toggle()
                                habit.streak += habit.doneToday ? 1 : -1
                            } label: {
                                Image(systemName: habit.doneToday ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(habit.doneToday ? .green : .gray)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Toggle \(habit.name)")
                        }
                    }
                    .onDelete { offsets in
                        habits.remove(atOffsets: offsets)
                    }
                }

                Section("New habit") {
                    HStack {
                        TextField("e.g. Stretch", text: $newHabit)
                        Button("Add") {
                            let name = newHabit.trimmingCharacters(in: .whitespaces)
                            habits.append(Habit(name: name, icon: "star.fill", streak: 0))
                            newHabit = ""
                        }
                        .disabled(newHabit.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Habits")
        }
    }
}
