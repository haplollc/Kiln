Here's a basic expense tracker in SwiftUI with categories, a list of expenses, a total, and a form to add new expenses:

```swift
import SwiftUI

// Expense model
struct Expense: Identifiable, Hashable {
    let id = UUID()
    let category: String
    let amount: Double
    let date: Date
}

// Expense model extension
extension Expense {
    static func == (lhs: Expense, rhs: Expense) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// Expense tracker view
struct ExpenseTrackerView: View {
    @State private var expenses: [Expense] = []
    @State private var newExpense: Expense = Expense(category: "", amount: 0.0, date: Date())
    @State private var totalSpent: Double = 0.0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Form to add new expense
                Form {
                    Section(header: Text("New Expense")) {
                        TextField("Category", text: $newExpense.category)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Stepper(value: $newExpense.amount) {
                            Text("\(newExpense.amount, specifier: "%.2f")")
                        }
                        .stepValue(0.1)
                        
                        DatePicker("Date", selection: $newExpense.date, displayedComponents: .date)
                    }
                }
                .padding()
                
                // List of expenses
                List(expenses, id: \.id) { expense in
                    HStack(alignment: .top) {
                        Text(expense.category)
                        Spacer()
                        Text(String(format: "$%.2f", expense.amount))
                        Text(DateFormatter.localizedString(from: expense.date, dateStyle: .short, timeStyle: .none))
                    }
                }
                .listStyle(PlainListStyle())
                
                // Total spent
                Text("Total Spent: \(String(format: "$%.2f", totalSpent))")
                    .font(.headline)
                    .padding()
            }
            .navigationTitle("Expense Tracker")
            .toolbar {
                Button("Add Expense") {
                    // Add new expense
                    if let category = newExpense.category.trimmingCharacters(in: .whitespacesAndNewlines),
                       let amount = Double(newExpense.amount) {
                        expenses.append(newExpense)
                        totalSpent += amount
                        newExpense = Expense(category: "", amount: 0.0, date: Date())
                    }
                }
            }
        }
    }
}

// Preview provider
struct ExpenseTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        ExpenseTrackerView()
    }
}
```

### Key Components:

1. **Expense Model**: Represents an expense with a unique ID, category, amount, and date.
2. **ExpenseTrackerView**:
   - Uses `@State` to manage the list of expenses, new expense data, and total spent.
   - Contains a form to add new expenses.
   - Displays a list of expenses with category, amount, and date.
   - Shows the total amount spent.
   - Uses a `Stepper` for amount input and a `DatePicker` for the date.
3. **Navigation and Toolbar**: Includes a navigation bar and a toolbar button to add new expenses.

### Usage:

- Run the app and add expenses by filling out the form.
- See the list of expenses and total spent in real time.

This is a basic example. You can enhance it by adding features like editing, deleting, sorting, and persisting data.