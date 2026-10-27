//
//  LabScenarios.swift
//  Kiln Lab UI tests: the same scripted session, run against each example
//  compiled natively and interpreted by Kiln. Every step saves a screenshot and
//  the labels on screen, named "<example>|<mode>|<step>", for Lab/report.py to
//  pair up. A missing control is noted, never fatal, so a broken Kiln render
//  still yields a full report.
//

import XCTest

class LabCase: XCTestCase {
    var app: XCUIApplication!
    var example = ""
    var mode = ""
    private var notes: [String] = []

    override func setUp() {
        continueAfterFailure = true
    }

    override func tearDown() {
        if !notes.isEmpty {
            let a = XCTAttachment(string: notes.joined(separator: "\n"))
            a.name = "\(example)|\(mode)|notes"
            a.lifetime = .keepAlways
            add(a)
        }
        app?.terminate()
    }

    func launch(_ example: String, _ mode: String) {
        self.example = example
        self.mode = mode
        app = XCUIApplication()
        // A fixed seed: shuffles and random picks come out the same natively and in Kiln.
        app.launchArguments = ["-example", example, "-mode", mode, "-seed", "7"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)
        Thread.sleep(forTimeInterval: 1.5)
    }

    func note(_ s: String) { notes.append(s) }

    /// Screenshot plus every label on screen.
    func snap(_ step: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "\(example)|\(mode)|\(step)"
        shot.lifetime = .keepAlways
        add(shot)
        var labels: [String] = []
        for query in [app.staticTexts, app.buttons, app.textFields, app.switches, app.steppers, app.segmentedControls.buttons] {
            for e in query.allElementsBoundByIndex where e.exists {
                let label = e.label.trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty { labels.append(label) }
                if let v = e.value as? String, !v.isEmpty, query === app.textFields { labels.append("field: " + v) }
            }
        }
        let t = XCTAttachment(string: labels.joined(separator: "\n"))
        t.name = "\(example)|\(mode)|\(step)|texts"
        t.lifetime = .keepAlways
        add(t)
    }

    func element(_ label: String) -> XCUIElement? {
        for q in [app.buttons, app.staticTexts, app.images, app.cells, app.otherElements] {
            let e = q[label]
            if e.exists { return e }
        }
        let any = app.descendants(matching: .any)[label]
        return any.exists ? any : nil
    }

    @discardableResult
    func tap(_ label: String, wait: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(wait)
        repeat {
            if let e = element(label), e.isHittable { e.tap(); return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        note("missing: \(label)")
        return false
    }

    @discardableResult
    func type(_ text: String, into placeholder: String) -> Bool {
        let field = app.textFields[placeholder]
        guard field.waitForExistence(timeout: 3) else { note("missing field: \(placeholder)"); return false }
        field.tap()
        if let current = field.value as? String, !current.isEmpty, current != placeholder {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
        return true
    }
}

final class AppScenarios: LabCase {
    // MARK: Habit tracker

    func habit(_ mode: String) {
        launch("HabitTracker", mode)
        snap("1 start")
        tap("Toggle Drink water")
        snap("2 checked off a habit")
        if type("Stretch", into: "e.g. Stretch") { tap("Add") }
        snap("3 added a habit")
        let row = app.cells.containing(.staticText, identifier: "Meditate").firstMatch
        if row.exists {
            row.swipeLeft()
            tap("Delete")
        } else { note("missing row: Meditate") }
        snap("4 deleted a habit")
    }
    func testHabitTrackerNative() { habit("native") }
    func testHabitTrackerKiln() { habit("kiln") }

    // MARK: Tip calculator

    func tip(_ mode: String) {
        launch("TipCalculator", mode)
        snap("1 start")
        tap("20%")
        snap("2 picked 20 percent")
        let stepper = app.steppers.firstMatch
        if stepper.exists { stepper.buttons["Increment"].tap() } else { note("missing stepper") }
        snap("3 added a person")
    }
    func testTipCalculatorNative() { tip("native") }
    func testTipCalculatorKiln() { tip("kiln") }

    // MARK: Focus timer

    func timer(_ mode: String) {
        launch("FocusTimer", mode)
        snap("1 start")
        tap("Start")
        Thread.sleep(forTimeInterval: 3.2)
        tap("Pause")
        snap("2 ran 3 seconds")
        tap("Break")
        snap("3 break mode")
    }
    func testFocusTimerNative() { timer("native") }
    func testFocusTimerKiln() { timer("kiln") }

    // MARK: Memory match

    func memory(_ mode: String) {
        launch("MemoryMatch", mode)
        snap("1 start")
        tap("Card 0")
        tap("Card 1")
        snap("2 flipped two cards")
        Thread.sleep(forTimeInterval: 1.4)
        snap("3 after the pause")
        tap("New Game")
        snap("4 new game")
    }
    func testMemoryMatchNative() { memory("native") }
    func testMemoryMatchKiln() { memory("kiln") }

    // MARK: Expense tracker

    func expense(_ mode: String) {
        launch("ExpenseTracker", mode)
        snap("1 start")
        tap("Add expense")
        snap("2 add sheet")
        type("Coffee", into: "Title")
        type("4.5", into: "Amount")
        snap("3 filled in")
        tap("Save")
        snap("4 saved")
    }
    func testExpenseTrackerNative() { expense("native") }
    func testExpenseTrackerKiln() { expense("kiln") }

    // MARK: Reading list

    func reading(_ mode: String) {
        launch("ReadingList", mode)
        snap("1 start")
        tap("Cosmos")
        snap("2 book detail")
        let finished = app.switches["Finished"]
        if finished.waitForExistence(timeout: 3) {
            finished.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        } else { note("missing switch: Finished") }
        let stepper = app.steppers.firstMatch
        if stepper.exists {
            stepper.buttons["Increment"].tap()
            stepper.buttons["Increment"].tap()
        } else { note("missing stepper") }
        snap("3 finished and rated")
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() } else { note("missing back button") }
        snap("4 back in the list")
        tap("Stats")
        snap("5 stats")
        tap("Library")
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            search.tap()
            search.typeText("weir")
        } else { note("missing search field") }
        snap("6 searched")
    }
    func testReadingListNative() { reading("native") }
    func testReadingListKiln() { reading("kiln") }

    // MARK: Chess

    func chess(_ mode: String) {
        launch("Chess", mode)
        snap("1 start")
        tap("e2")
        snap("2 legal moves")
        // Scholar's mate: 1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7#
        for square in ["e4", "e7", "e5", "f1", "c4", "b8", "c6", "d1", "h5", "g8", "f6"] {
            tap(square)
            Thread.sleep(forTimeInterval: 0.4)
        }
        snap("3 queen out")
        tap("h5")
        tap("f7")
        Thread.sleep(forTimeInterval: 0.8)
        snap("4 checkmate")
    }
    func testChessNative() { chess("native") }
    func testChessKiln() { chess("kiln") }
}

/// Apple Intelligence's own replies, as Haplo AI receives them. There is no
/// native version (most don't compile), so these record what Kiln shows.
final class ModelReplies: LabCase {
    func reply(_ file: String) {
        launch(file, "kiln")
        snap("1 start")
    }
    func testHabitReply() { reply("habit.md") }
    func testTipReply() { reply("tip.md") }
    func testTimerReply() { reply("timer.md") }
    func testMemoryReply() { reply("memory.md") }
    func testExpenseReply() { reply("expense.md") }
}
