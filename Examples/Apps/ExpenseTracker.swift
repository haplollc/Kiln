import SwiftUI
import Charts

enum Category: String, CaseIterable, Identifiable {
    case food = "Food"
    case transport = "Transport"
    case fun = "Fun"
    case bills = "Bills"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .transport: return "car.fill"
        case .fun: return "gamecontroller.fill"
        case .bills: return "doc.text.fill"
        }
    }

    var color: Color {
        switch self {
        case .food: return .orange
        case .transport: return .blue
        case .fun: return .purple
        case .bills: return .red
        }
    }
}

struct Expense: Identifiable {
    let id = UUID()
    var title: String
    var amount: Double
    var category: Category
}

struct ContentView: View {
    @State private var expenses: [Expense] = [
        Expense(title: "Groceries", amount: 64.20, category: .food),
        Expense(title: "Metro card", amount: 30, category: .transport),
        Expense(title: "Concert", amount: 85, category: .fun),
        Expense(title: "Internet", amount: 55, category: .bills),
        Expense(title: "Tacos", amount: 18.50, category: .food)
    ]
    @State private var showingAdd = false

    private var total: Double {
        expenses.reduce(0) { $0 + $1.amount }
    }

    private func total(for category: Category) -> Double {
        expenses.filter { $0.category == category }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Spent this month")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(total, format: .currency(code: "USD"))
                            .font(.largeTitle.bold())
                        Chart(Category.allCases) { category in
                            BarMark(
                                x: .value("Category", category.rawValue),
                                y: .value("Amount", total(for: category))
                            )
                            .foregroundStyle(category.color)
                        }
                        .frame(height: 140)
                    }
                    .padding(.vertical, 6)
                }

                ForEach(Category.allCases) { category in
                    let items = expenses.filter { $0.category == category }
                    if !items.isEmpty {
                        Section(category.rawValue) {
                            ForEach(items) { expense in
                                HStack {
                                    Image(systemName: category.icon)
                                        .foregroundStyle(category.color)
                                        .frame(width: 28)
                                    Text(expense.title)
                                    Spacer()
                                    Text(expense.amount, format: .currency(code: "USD"))
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Expenses")
            .toolbar {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add expense")
            }
            .sheet(isPresented: $showingAdd) {
                AddExpenseView { expense in
                    expenses.append(expense)
                }
            }
        }
    }
}

struct AddExpenseView: View {
    var onSave: (Expense) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var amount = 0.0
    @State private var category: Category = .food

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Amount", value: $amount, format: .number)
                    .keyboardType(.decimalPad)
                Picker("Category", selection: $category) {
                    ForEach(Category.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
            }
            .navigationTitle("New Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(Expense(title: title, amount: amount, category: category))
                        dismiss()
                    }
                    .disabled(title.isEmpty || amount <= 0)
                }
            }
        }
    }
}
