Creating a habit tracker app in SwiftUI with habits, daily checks, and streak tracking is a great project. Here’s a basic outline and code to get you started:

### 1. Project Setup
- **Create a new SwiftUI project** in Xcode.
- Name it `HabitTracker`.
- Add a `Habit` struct to define habits.

```swift
import Foundation

struct Habit: Identifiable {
    let id = UUID()
    let title: String
    var isCompleted: Bool = false
}
```

### 2. Main View
Create a main view to manage habits, track completion, and display streaks.

```swift
import SwiftUI

@MainActor
class HabitTracker: ObservableObject {
    @Published var habits: [Habit] = [
        Habit(title: "Drink water"),
        Habit(title: "Meditate"),
        Habit(title: "Read")
    ]
    
    @Published var streak: Int = 0
    
    func completeHabit(at index: Int) {
        guard index < habits.count else { return }
        
        if habits[index].isCompleted {
            return
        }
        
        habits[index].isCompleted = true
        
        if streak == 0 || habits[index].isCompleted {
            streak += 1
        } else {
            streak += 1
            if !habits[index].isCompleted {
                streak -= 1
            }
        }
    }
}

struct HabitTrackerView: View {
    @ObservedObject var tracker = HabitTracker()
    
    var body: some View {
        NavigationView {
            VStack {
                List(tracker.habits, id: \ .id) { habit in
                    HStack {
                        Text(habit.title)
                        Spacer()
                        Button(habit.isCompleted ? "Reset" : "Check Off") {
                            if habit.isCompleted {
                                tracker.completeHabit(at: $0.index)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                Text("Streak: \(tracker.streak) days")
                    .padding()
                
                NavigationLink(destination: Text("Add Habit")) {
                    Text("Add New Habit")
                }
            }
            .navigationTitle("Habit Tracker")
        }
    }
}

struct HabitTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        HabitTrackerView()
    }
}
```

### 3. Adding a New Habit
Add a button to add a new habit:

```swift
NavigationLink(destination: Text("Add Habit")) {
    Text("Add New Habit")
}
```

### 4. Customization
- **Streaks**: Adjust logic to handle streaks correctly.
- **UI**: Style buttons and lists for better UX.
- **Persistence**: Save habits and streaks using `UserDefaults` or `CoreData`.

### 5. Running the App
- Open your `.xcodeproj` in Xcode.
- Run the app on a simulator or device.
- Add habits, check them off, and see streaks.

### 6. Enhancements
- **Delete Habits**: Add functionality to remove habits.
- **Statistics**: Display daily completions and overall progress.
- **Themes**: Use SwiftUI’s `ColorScheme` to apply themes.

### Notes
- **Concurrency**: Use `@MainActor` for UI updates.
- **Data Persistence**: Implement saving/loading from `UserDefaults` or `CoreData` for persistence.
- **Error Handling**: Handle edge cases (e.g., invalid indices).

This is a foundational example. You can expand it with more features and polish the UI. Let me know if you need further assistance!