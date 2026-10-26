//
//  LabProbe.swift
//  Native SwiftUI behaviour Kiln has to match, checked on a simulator
//  (`-example Probe`; `-mode kiln` runs LabProbeSource through Kiln):
//  - H: Text("\(1400)") shows "1,400" and Text("\(3.5)") "3.500000"
//    (LocalizedStringKey interpolation); verbatim: and Strings do not.
//  - A–F: Sections and Stepper labels survive AnyView wrapping, so lost
//    headers in Kiln were Kiln's own bug.
//  - G: emoji inside a rotation3DEffect card show after an animated flip.
//

import SwiftUI

struct LabProbe: View {
    @State private var n = 2
    @State private var up = [false, false, false]

    var body: some View {
        NavigationStack {
            Form {
                Section("H interpolation") {
                    Text("int \(1400)")
                    Text("double \(3.5)")
                    Text("cgfloat \(CGFloat(2.25))")
                    Text("float \(Float(1.5))")
                    Text("neg \(-12345)")
                    Text("str \("a" + "b")")
                    Text(verbatim: "verbatim \(1400)")
                    Text("int \(1400)" as String)
                    Text("spec \(3.14159, specifier: "%.2f")")
                    Text("bool \(String(true))")
                }
                AnyView(Section("A anyview section") { AnyView(Stepper(value: $n, in: 1...12) { AnyView(Text("A \(n) people")) }) })
                ForEach([1], id: \.self) { _ in
                    AnyView(Section("B foreach anyview") { Stepper(value: $n, in: 1...12) { Text("B \(n) people") } })
                }
                AnyView(ForEach([1], id: \.self) { _ in
                    AnyView(Section("C anyview foreach anyview") { Text("C row") })
                })
                ForEach([1], id: \.self) { _ in
                    Section { AnyView(Text("D row")) } header: { AnyView(Text("D concrete section")) }
                }
                AnyView(ForEach([1], id: \.self) { _ in
                    Section { AnyView(Stepper(value: $n, in: 1...12) { AnyView(Text("E \(n) people")) }) } header: { AnyView(Text("E anyview foreach concrete")) }
                })
                Section("F plain") { Stepper("F \(n) people", value: $n, in: 1...12) }
                Section("G card flip: plain, withAnimation, both") {
                    HStack {
                        ForEach(0..<3, id: \.self) { i in
                            ZStack {
                                RoundedRectangle(cornerRadius: 12).fill(up[i] ? Color.white : Color.indigo).shadow(radius: 2)
                                if up[i] { Text("🐸").font(.system(size: 40)) } else { Image(systemName: "star.fill") }
                            }
                            .frame(height: 90)
                            .rotation3DEffect(.degrees(up[i] ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                        }
                    }
                }
            }
            .task {
                try? await Task.sleep(for: .seconds(1))
                up[0] = true
                withAnimation(.easeInOut(duration: 0.3)) { up[1] = true }
                withAnimation(.easeInOut(duration: 0.3)) { up[2] = true }
            }
            .navigationTitle("Probe")
        }
    }
}

/// The same questions asked of Kiln (`-example Probe -mode kiln`).
enum LabProbeSource {
    static let code = """
    import SwiftUI

    struct ContentView: View {
        @State private var n = 2
        var body: some View {
            NavigationStack {
                Form {
                    Section("A section title") { Text("A row") }
                    Section { Text("B row") } header: { Text("B header") }
                    Section(header: Text("C header")) { Text("C row") }
                    Section("D stepper") { Stepper("D \\(n) people", value: $n, in: 1...12) }
                    Stepper(value: $n, in: 1...12) { Text("E \\(n) people") }
                    Toggle("F toggle", isOn: .constant(true))
                    LabeledContent("G labeled", value: "value")
                }
                .navigationTitle("Probe")
            }
        }
    }
    """
}
