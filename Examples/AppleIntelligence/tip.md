Here is a tip calculator in SwiftUI with a bill amount, tip percentage options, and splitting between people:

```swift 5.10
import SwiftUI

struct TipCalculatorView: View {
  @State private var billAmount: Double = 0.0
  @State private var tipPercentage: Double = 15.0
  @State private var numberOfPeople: Int = 1
  @State private var totalTip: Double = 0.0
  @State private var totalAmount: Double = 0.0

  var body: some View {
    VStack(spacing: 20) {
      Text("Tip Calculator")
        .font(.largeTitle)
        .padding()

      Text("Bill Amount ($)")
        .font(.headline)
        .padding()
        .frame(width: 150)

      TextField("Enter bill amount", value: $billAmount, formatter: NumberFormatter())
        .keyboardType(.decimalPad)
        .padding()

      Text("Tip Percentage (%)")
        .font(.headline)
        .padding()
        .frame(width: 150)

      Picker("Tip Percentage", selection: $tipPercentage) {
        ForEach(0...20, id: \.self) { percentage in
          Text("\(percentage)%")
        }
      }
      .pickerStyle(SegmentedPickerStyle())
      .padding()

      Text("Number of People")
        .font(.headline)
        .padding()
        .frame(width: 150)

      Stepper("1", value: $numberOfPeople, increment: 1)
        .padding()

      Text("Total Tip ($)")
        .font(.headline)
        .padding()
        .frame(width: 150)

      Text(String(format: "%.2f", totalTip))
        .padding()

      Text("Total Amount ($)")
        .font(.headline)
        .padding()
        .frame(width: 150)

      Text(String(format: "%.2f", totalAmount))
        .padding()

      Button(action: calculate) {
        Text("Calculate")
          .foregroundColor(.white)
          .padding()
          .background(Color.blue)
          .cornerRadius(10)
      }
      .padding()
    }
    .padding()
  }

  func calculate() {
    totalTip = billAmount * (tipPercentage / 100)
    totalAmount = billAmount + totalTip
  }
}

struct TipCalculatorView_Previews: PreviewProvider {
  static var previews: some View {
    TipCalculatorView()
  }
}
```