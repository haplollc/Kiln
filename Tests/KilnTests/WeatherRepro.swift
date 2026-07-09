import XCTest
@testable import Kiln

// Repro of the weather app a real model wrote (after the Button-label fix), to
// see what else blocks a network app.
@MainActor
final class WeatherRepro: XCTestCase {

    func testModelWeather() {
        let src = """
        import SwiftUI
        struct ContentView: View {
            @State private var temperature = 0.0
            @State private var condition = "N/A"
            var body: some View {
                VStack(spacing: 20) {
                    Text("New York City Weather").font(.largeTitle)
                    HStack {
                        Text("\\(temperature)°F").font(.title)
                        Text(condition).font(.headline)
                    }
                    Button(action: { fetchWeather() }) label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .padding().background(Color.blue).foregroundColor(.white).cornerRadius(10)
                    }
                }
            }
            func fetchWeather() {
                let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=40&longitude=-74&current=temperature_2m")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoded = try JSONDecoder().decode(Forecast.self, from: data)
                temperature = decoded.current.temperature_2m
            }
        }
        struct Forecast: Codable { let current: Current }
        struct Current: Codable { let temperature_2m: Double }
        """
        let v = Kiln.validate(src)
        XCTAssertTrue(v.hasView && v.renderedContent, "model weather failed: \(v.errors)")
    }

    // The pattern we WANT to teach: fetch in .task, refresh via .task(id:).
    func testTaskWeather() {
        let src = """
        import SwiftUI
        struct ContentView: View {
            @State private var temp = 0.0
            @State private var reloads = 0
            var body: some View {
                VStack(spacing: 20) {
                    Text("Weather").font(.largeTitle)
                    Text("\\(temp)°").font(.system(size: 60))
                    Button("Refresh") { reloads = reloads + 1 }
                        .padding().background(Color.blue).foregroundColor(.white).cornerRadius(10)
                }
                .task(id: reloads) {
                    let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=40&longitude=-74&current=temperature_2m")!
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let decoded = try JSONDecoder().decode(Forecast.self, from: data)
                    temp = decoded.current.temperature_2m
                }
            }
        }
        struct Forecast: Codable { let current: Current }
        struct Current: Codable { let temperature_2m: Double }
        """
        let v = Kiln.validate(src)
        XCTAssertTrue(v.hasView && v.renderedContent, "task weather failed: \(v.errors)")
    }
}
