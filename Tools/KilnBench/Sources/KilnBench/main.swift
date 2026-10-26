import Foundation
import Kiln

/// The Swift source to run from a file: a .swift file as is, or a model reply
/// (.md) merged the way Haplo AI runs it (Kiln.swiftSource(fromMarkdown:)).
@MainActor func source(of path: String) -> String {
    let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    return path.hasSuffix(".md") ? Kiln.swiftSource(fromMarkdown: text) : text
}

@MainActor func main() {
    var rows: [[String: Any]] = []
    // KILN_ENGINE=legacy compares against the original interpreter.
    if ProcessInfo.processInfo.environment["KILN_ENGINE"] == "legacy" { Kiln.engine = .legacy }
    for path in CommandLine.arguments.dropFirst() {
        let code = source(of: path)
        let started = Date()
        let v = Kiln.validate(code)
        rows.append([
            "file": (path as NSString).lastPathComponent,
            "valid": v.isValid,
            "hasView": v.hasView,
            "rendered": v.renderedContent,
            "errors": v.errors.map { String($0.prefix(240)) },
            "warnings": v.warnings.prefix(6).map { String($0.prefix(200)) },
            "ms": Int(Date().timeIntervalSince(started) * 1000)
        ])
    }
    // One marked line per input: Kiln's own debug prints share stdout.
    for row in rows {
        let data = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        print("@@KILNBENCH@@" + String(data: data, encoding: .utf8)!)
    }
}
MainActor.assumeIsolated { main() }
