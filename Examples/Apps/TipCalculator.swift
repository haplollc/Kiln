import SwiftUI

struct ContentView: View {
    @State private var bill = 86.50
    @State private var tipPercent = 18
    @State private var people = 2

    private let tipOptions = [10, 15, 18, 20, 25]

    private var tip: Double {
        bill * Double(tipPercent) / 100
    }

    private var total: Double {
        bill + tip
    }

    private var perPerson: Double {
        total / Double(people)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bill") {
                    TextField("Amount", value: $bill, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                }

                Section("Tip") {
                    Picker("Tip", selection: $tipPercent) {
                        ForEach(tipOptions, id: \.self) { option in
                            Text("\(option)%")
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Split") {
                    Stepper("\(people) \(people == 1 ? "person" : "people")", value: $people, in: 1...12)
                }

                Section("Summary") {
                    HStack {
                        Text("Tip")
                        Spacer()
                        Text(tip, format: .currency(code: "USD"))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Total")
                        Spacer()
                        Text(total, format: .currency(code: "USD"))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Each pays")
                            .font(.headline)
                        Spacer()
                        Text(perPerson, format: .currency(code: "USD"))
                            .font(.title2.bold())
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Split the Bill")
        }
    }
}
