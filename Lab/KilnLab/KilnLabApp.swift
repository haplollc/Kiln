//
//  KilnLabApp.swift
//  Kiln Lab: shows one example app either compiled natively or interpreted by
//  Kiln, so the two can be compared screen by screen.
//
//  Launch arguments:
//    -example <Name>   an Examples/Apps file (HabitTracker, …), an
//                      Examples/AppleIntelligence reply (habit.md, …), or an
//                      absolute path to any .swift / .md file on the Mac
//    -mode native|kiln
//

import SwiftUI
import Kiln

@main
struct KilnLabApp: App {
    var body: some Scene {
        WindowGroup {
            LabRoot()
        }
    }
}

/// The seeded generator native examples draw from (gen_native.py rewrites
/// their random calls); Kiln gets the same seed through Kiln.randomSeed.
enum LabRandom {
    nonisolated(unsafe) static var generator = KilnRandom(seed: seed)
    static var seed: UInt64? {
        UserDefaults.standard.object(forKey: "seed") == nil ? nil : UInt64(UserDefaults.standard.integer(forKey: "seed"))
    }
}

struct LabRoot: View {
    private let example = UserDefaults.standard.string(forKey: "example") ?? "HabitTracker"
    private let mode = UserDefaults.standard.string(forKey: "mode") ?? "kiln"

    var body: some View {
        if example == "Probe" {
            if mode == "kiln" { KilnScreen(source: LabProbeSource.code) } else { LabProbe() }
        } else if mode == "native" {
            NativeIndex.view(named: example)
        } else {
            KilnScreen(source: LabSources.source(named: example))
        }
    }
}

/// Kiln's output, full screen, the way an app runs.
struct KilnScreen: View {
    let source: String
    @State private var result: KilnResult?

    var body: some View {
        Group {
            if let result {
                if let view = result.view {
                    view
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Kiln error").font(.headline).foregroundStyle(.red)
                            ForEach(Array(result.errors.enumerated()), id: \.offset) { _, error in
                                Text(error).font(.footnote.monospaced())
                            }
                        }
                        .padding()
                    }
                }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if result == nil {
                Kiln.randomSeed = LabRandom.seed
                result = Kiln.run(source)
            }
        }
    }
}

enum LabSources {
    static func source(named name: String) -> String {
        // A path on the Mac (the simulator can read it): run any file.
        if name.hasPrefix("/") {
            let text = (try? String(contentsOfFile: name, encoding: .utf8)) ?? ""
            return name.hasSuffix(".md") ? Kiln.swiftSource(fromMarkdown: text) : text
        }
        if name.hasSuffix(".md") {
            guard let url = Bundle.main.url(forResource: (name as NSString).deletingPathExtension, withExtension: "md", subdirectory: "AppleIntelligence"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
            return Kiln.swiftSource(fromMarkdown: text)
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "swift", subdirectory: "Apps"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    /// The code block a person would tap Run on: the longest Swift block.
    static func largestSwiftBlock(in markdown: String) -> String {
        var blocks: [String] = []
        var current: [String]?
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if current == nil, trimmed.hasPrefix("```swift") { current = []; continue }
            if current != nil, trimmed.hasPrefix("```") { blocks.append(current!.joined(separator: "\n")); current = nil; continue }
            current?.append(line)
        }
        return blocks.max(by: { $0.count < $1.count }) ?? ""
    }
}
