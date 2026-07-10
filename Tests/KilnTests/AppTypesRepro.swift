import XCTest
@testable import Kiln

// Pre-validate the structures a model would write for the remaining batch app
// types, so Kiln gaps are found without burning thermally-limited device time.
@MainActor
final class AppTypesRepro: XCTestCase {
    override func setUp() {
        super.setUp()
        // Mirror Bond's bridges so Storage-backed apps validate as they would live.
        Kiln.register("Storage.has") { _ in .bool(false) }
        Kiln.register("Storage.load") { _ in .null }
        Kiln.register("Storage.save") { _ in .null }
    }
    func v(_ name: String, _ src: String) {
        let r = Kiln.validate(src)
        XCTAssertTrue(r.hasView && r.renderedContent && r.errors.isEmpty && r.warnings.isEmpty,
                      "APPTYPE[\(name)] failed — errors=\(r.errors) warnings=\(r.warnings)")
    }

    // Calculator: grid of buttons, a display, an operation func with switch.
    func testCalculator() {
        v("calculator", """
        import SwiftUI
        struct ContentView: View {
            @State private var display = "0"
            @State private var rows = [["7","8","9","/"],["4","5","6","*"],["1","2","3","-"],["0","C","=","+"]]
            var body: some View {
                VStack(spacing: 10) {
                    Spacer()
                    Text(display).font(.system(size: 60)).foregroundColor(.white)
                    ForEach(rows, id: \\.self) { row in
                        HStack(spacing: 10) {
                            ForEach(row, id: \\.self) { key in
                                Button(key) { press(key) }
                                    .font(.title).frame(width: 80, height: 70)
                                    .background(Color.gray).foregroundColor(.white).cornerRadius(12)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
            }
            func press(_ key: String) {
                if key == "C" { display = "0" }
                else if key == "=" { display = display }
                else if display == "0" { display = key }
                else { display = display + key }
            }
        }
        """)
    }

    // Tip calculator: TextField + Slider + computed totals.
    func testTip() {
        v("tip", """
        import SwiftUI
        struct ContentView: View {
            @State private var bill = ""
            @State private var pct = 18.0
            var body: some View {
                VStack(spacing: 20) {
                    Text("Tip Calculator").font(.largeTitle).bold()
                    TextField("Bill amount", text: $bill).padding().background(Color.gray).cornerRadius(8)
                    Text("Tip: \\(Int(pct))%")
                    Slider(value: $pct, in: 0...30)
                    let amount = (Double(bill) ?? 0)
                    let tip = amount * pct / 100
                    Text("Tip: $\\(tip)").font(.title2)
                    Text("Total: $\\(amount + tip)").font(.title)
                }.padding()
            }
        }
        """)
    }

    // Flashcards: tap to flip, next, counter.
    func testFlashcards() {
        v("flashcards", """
        import SwiftUI
        struct ContentView: View {
            @State private var cards = [["es": "hola", "en": "hello"], ["es": "gato", "en": "cat"], ["es": "perro", "en": "dog"]]
            @State private var index = 0
            @State private var flipped = false
            var body: some View {
                VStack(spacing: 30) {
                    Text("Card \\(index + 1) of \\(cards.count)").font(.headline)
                    Text(flipped ? cards[index]["en"] ?? "" : cards[index]["es"] ?? "")
                        .font(.system(size: 44)).bold()
                        .frame(width: 300, height: 200)
                        .background(Color.blue).foregroundColor(.white).cornerRadius(16)
                        .onTapGesture { flipped = !flipped }
                    Button("Next") { index = (index + 1) % cards.count; flipped = false }
                        .padding().background(Color.gray).foregroundColor(.white).cornerRadius(10)
                }
            }
        }
        """)
    }

    // Expense tracker: add name+amount, list, running total, persisted.
    func testExpenses() {
        v("expenses", """
        import SwiftUI
        struct ContentView: View {
            @State private var items = []
            @State private var name = ""
            @State private var amount = ""
            var body: some View {
                VStack(spacing: 12) {
                    Text("Expenses").font(.largeTitle).bold()
                    HStack {
                        TextField("Name", text: $name).padding(8).background(Color.gray).cornerRadius(8)
                        TextField("Amount", text: $amount).padding(8).background(Color.gray).cornerRadius(8)
                        Button("Add") {
                            if name != "" {
                                items.append(["name": name, "amount": amount])
                                name = ""; amount = ""
                                Storage.save("items", items)
                            }
                        }.padding(8).background(Color.blue).foregroundColor(.white).cornerRadius(8)
                    }
                    ScrollView {
                        ForEach(items, id: \\.self) { item in
                            HStack { Text(item["name"] ?? ""); Spacer(); Text("$" + (item["amount"] ?? "")) }
                                .padding().background(Color.gray).cornerRadius(8)
                        }
                    }
                    Spacer()
                }.padding().onAppear { if Storage.has("items") { items = Storage.load("items") } }
            }
        }
        """)
    }

    // Trivia quiz: questions, answer feedback, final score + restart.
    func testQuiz() {
        v("quiz", """
        import SwiftUI
        struct ContentView: View {
            @State private var questions = [
                ["q": "Capital of France?", "a": "Paris", "b": "London", "c": "Rome", "ans": "Paris"],
                ["q": "2 + 2?", "a": "3", "b": "4", "c": "5", "ans": "4"]
            ]
            @State private var index = 0
            @State private var score = 0
            @State private var feedback = ""
            @State private var done = false
            var body: some View {
                VStack(spacing: 20) {
                    if done {
                        Text("Score: \\(score) / \\(questions.count)").font(.largeTitle)
                        Button("Restart") { index = 0; score = 0; done = false; feedback = "" }
                            .padding().background(Color.blue).foregroundColor(.white).cornerRadius(10)
                    } else {
                        Text(questions[index]["q"] ?? "").font(.title2)
                        ForEach(["a", "b", "c"], id: \\.self) { key in
                            Button(questions[index][key] ?? "") { answer(questions[index][key] ?? "") }
                                .padding().frame(maxWidth: .infinity)
                                .background(Color.gray).foregroundColor(.white).cornerRadius(10)
                        }
                        Text(feedback).font(.headline)
                    }
                }.padding()
            }
            func answer(_ choice: String) {
                if choice == questions[index]["ans"] { score = score + 1; feedback = "Correct!" }
                else { feedback = "Wrong!" }
                if index + 1 >= questions.count { done = true } else { index = index + 1 }
            }
        }
        """)
    }
}
