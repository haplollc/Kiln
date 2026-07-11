import XCTest
@testable import Kiln

// The interpreted `Map(...)` view — should parse and render (previously a hard
// "Maps aren't available" error). Covers explicit center+markers, markers-only
// auto-fit, the user-location dot, and state-driven recentering.
@MainActor
final class MapRepro: XCTestCase {
    func v(_ name: String, _ src: String) {
        let r = Kiln.validate(src)
        XCTAssertTrue(r.hasView && r.renderedContent && r.errors.isEmpty,
                      "MAP[\(name)] failed — errors=\(r.errors) warnings=\(r.warnings)")
    }

    // Explicit center + span + a couple of titled, colored markers.
    func testCenteredWithMarkers() {
        v("centered", """
        import SwiftUI
        struct ContentView: View {
            @State private var pins = [
                ["lat": 37.3349, "lng": -122.0090, "title": "Apple Park", "color": "blue"],
                ["lat": 37.3317, "lng": -122.0301, "title": "Infinite Loop", "color": "red"]
            ]
            var body: some View {
                VStack {
                    Text("Nearby").font(.title).bold()
                    Map(latitude: 37.3349, longitude: -122.0090, span: 0.05, markers: pins)
                }
                .padding()
            }
        }
        """)
    }

    // Markers-only: the map should auto-fit around them (no explicit center).
    func testMarkersAutoFit() {
        v("autofit", """
        import SwiftUI
        struct ContentView: View {
            var body: some View {
                Map(markers: [
                    ["lat": 40.7128, "lng": -74.0060, "title": "NYC"],
                    ["lat": 34.0522, "lng": -118.2437, "title": "LA"]
                ])
            }
        }
        """)
    }

    // User-location dot + a recenter button driving @State (live camera follow).
    func testUserLocationAndRecenter() {
        v("user", """
        import SwiftUI
        struct ContentView: View {
            @State private var lat = 37.7749
            @State private var lng = -122.4194
            var body: some View {
                VStack {
                    Map(latitude: lat, longitude: lng, span: 0.02, showsUserLocation: true)
                    Button("Jump to LA") {
                        lat = 34.0522
                        lng = -118.2437
                    }
                }
            }
        }
        """)
    }
}
