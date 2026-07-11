import XCTest
@testable import Kiln

// Candidate dashboard + live-data patterns to teach the model. Iterate until
// they validate, then move the winners into Bond's cookbook + prompt.
@MainActor
final class DashboardRepro: XCTestCase {
    func v(_ name: String, _ src: String) {
        let r = Kiln.validate(src)
        XCTAssertTrue(r.hasView && r.renderedContent && r.errors.isEmpty && r.warnings.isEmpty,
                      "DASH[\(name)] failed — errors=\(r.errors) warnings=\(r.warnings)")
    }

    // A polished stat-grid dashboard: header, LazyVGrid of stat cards (dynamic
    // per-card color via ternary), a BarChart, and a Capsule progress bar.
    func testStatDashboard() {
        v("stat", """
        import SwiftUI
        struct ContentView: View {
            @State private var stats = [
                ["title": "Steps", "value": "7,420", "icon": "figure.walk", "color": "green"],
                ["title": "Calories", "value": "540", "icon": "flame.fill", "color": "orange"],
                ["title": "Water", "value": "5 cups", "icon": "drop.fill", "color": "blue"],
                ["title": "Heart", "value": "72 bpm", "icon": "heart.fill", "color": "pink"]
            ]
            @State private var weekly = [6200.0, 8100.0, 7400.0, 9200.0, 5300.0, 10400.0, 7420.0]
            @State private var goal = 0.74
            var body: some View {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Today").font(.largeTitle).bold()
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                            ForEach(stats, id: \\.self) { s in
                                VStack(alignment: .leading, spacing: 8) {
                                    Image(systemName: s["icon"] ?? "circle")
                                    Text(s["value"] ?? "").font(.title2).bold()
                                    Text(s["title"] ?? "").font(.caption).foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.gray.opacity(0.12))
                                .cornerRadius(16)
                            }
                        }
                        Text("Goal").font(.headline)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.gray.opacity(0.2)).frame(height: 16)
                            Capsule().fill(Color.green).frame(width: 300 * goal, height: 16)
                        }
                        Text("This week").font(.headline)
                        BarChart(weekly).frame(height: 180)
                            .padding().background(Color.gray.opacity(0.1)).cornerRadius(16)
                    }
                    .padding()
                }
            }
        }
        """)
    }

    // Live data: fetch a public JSON API on appear AND poll it every 30s by
    // bumping a tick that .task(id:) watches — the "constantly fetch" pattern.
    func testLiveDataDashboard() {
        v("live", """
        import SwiftUI
        struct ContentView: View {
            @State private var temp = 0.0
            @State private var wind = 0.0
            @State private var updated = "—"
            @State private var tick = 0
            var body: some View {
                VStack(spacing: 24) {
                    Text("Live Weather").font(.largeTitle).bold()
                    HStack(spacing: 30) {
                        VStack { Text("\\(temp)°").font(.system(size: 44)).bold(); Text("Temp").font(.caption) }
                        VStack { Text("\\(wind)").font(.system(size: 44)).bold(); Text("Wind").font(.caption) }
                    }
                    Text("Updated: " + updated).font(.caption).foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTick(30.0) { tick = tick + 1 }
                .task(id: tick) {
                    let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=40.71&longitude=-74.01&current=temperature_2m,wind_speed_10m")!
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let decoded = try JSONDecoder().decode(Forecast.self, from: data)
                    temp = decoded.current.temperature_2m
                    wind = decoded.current.wind_speed_10m
                    updated = "just now"
                }
            }
        }
        struct Forecast: Codable { let current: Current }
        struct Current: Codable {
            let temperature_2m: Double
            let wind_speed_10m: Double
        }
        """)
    }
}
