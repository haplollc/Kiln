//
//  KilnMapView.swift
//  Kiln
//
//  Backs the interpreted `Map(...)` view with a real MapKit map. Kept in its own
//  file (like the chart/game views) so ViewBuilder only has to construct it. The
//  interpreter re-renders the host whenever @State changes, so we mirror the
//  incoming center/markers into the camera position on change to stay live.
//

import SwiftUI
import MapKit

/// One map annotation parsed from an interpreted value object.
public struct KilnMapMarker: Identifiable, Equatable {
    public let id = UUID()
    public let latitude: Double
    public let longitude: Double
    public let title: String
    public let tint: Color

    public static func == (lhs: KilnMapMarker, rhs: KilnMapMarker) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude &&
        lhs.title == rhs.title
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension DynamicViewBuilder {
    /// Normalizes interpreted values into map markers. Accepts an array of objects
    /// with `lat`/`latitude` + `lng`/`lon`/`longitude` (numbers), plus optional
    /// `title`/`name`/`label` and `color`/`tint` (a Kiln color name or hex).
    static func mapMarkers(from values: [Value]) -> [KilnMapMarker] {
        values.compactMap { item -> KilnMapMarker? in
            guard case .object(let d) = item else { return nil }
            let latV = d["lat"] ?? d["latitude"] ?? d["y"]
            let lngV = d["lng"] ?? d["lon"] ?? d["long"] ?? d["longitude"] ?? d["x"]
            guard case .number(let lat)? = latV, case .number(let lng)? = lngV else { return nil }
            let title: String
            if case .string(let s)? = (d["title"] ?? d["name"] ?? d["label"]) { title = s } else { title = "" }
            let tintVal = d["color"] ?? d["tint"]
            // Reuse the game-canvas color resolver (names + hex); default to red.
            let tint: Color = tintVal == nil ? .red : KilnGameCanvas.color(tintVal)
            return KilnMapMarker(latitude: lat, longitude: lng, title: title, tint: tint)
        }
    }
}

/// Renders an interpreted `Map(...)` with the modern (iOS 17+) SwiftUI Map API.
/// The camera follows the interpreted center/markers: when @State drives a new
/// center (or the marker set changes its span), `.onChange` re-seats the region.
@MainActor
struct KilnMapView: View {
    let centerLat: Double?
    let centerLng: Double?
    let span: Double?
    let markers: [KilnMapMarker]
    let showsUser: Bool

    @State private var position: MapCameraPosition

    init(centerLat: Double?, centerLng: Double?, span: Double?,
         markers: [KilnMapMarker], showsUser: Bool) {
        self.centerLat = centerLat
        self.centerLng = centerLng
        self.span = span
        self.markers = markers
        self.showsUser = showsUser
        _position = State(initialValue: .region(
            Self.region(centerLat: centerLat, centerLng: centerLng, span: span, markers: markers)))
    }

    var body: some View {
        Map(position: $position) {
            if showsUser { UserAnnotation() }
            ForEach(markers) { m in
                Marker(m.title.isEmpty ? " " : m.title, coordinate: m.coordinate)
                    .tint(m.tint)
            }
        }
        .frame(minHeight: 220)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // Re-seat the camera when the interpreted inputs change (state-driven
        // recenter / new markers). Keyed on a cheap string so we don't need
        // CLLocationCoordinate2D to be Equatable.
        .onChange(of: regionKey) {
            position = .region(Self.region(
                centerLat: centerLat, centerLng: centerLng, span: span, markers: markers))
        }
    }

    private var regionKey: String {
        let c = "\(centerLat ?? .nan),\(centerLng ?? .nan),\(span ?? .nan)"
        let m = markers.map { "\($0.latitude),\($0.longitude)" }.joined(separator: "|")
        return c + ";" + m
    }

    /// Builds a region from an explicit center, else fits the markers, else falls
    /// back to a world-ish view so an empty `Map()` still renders something.
    static func region(centerLat: Double?, centerLng: Double?, span: Double?,
                       markers: [KilnMapMarker]) -> MKCoordinateRegion {
        let delta = span ?? 0.05
        if let lat = centerLat, let lng = centerLng {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                span: MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta))
        }
        if !markers.isEmpty {
            let lats = markers.map(\.latitude), lngs = markers.map(\.longitude)
            let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
            let minLng = lngs.min() ?? 0, maxLng = lngs.max() ?? 0
            let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                                longitude: (minLng + maxLng) / 2)
            // Pad the fit so pins aren't flush against the edges; floor the span
            // so a single marker still gets a sensible zoom.
            let latSpan = max((maxLat - minLat) * 1.4, 0.02)
            let lngSpan = max((maxLng - minLng) * 1.4, 0.02)
            return MKCoordinateRegion(center: center,
                span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lngSpan))
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
            span: MKCoordinateSpan(latitudeDelta: span ?? 0.2, longitudeDelta: span ?? 0.2))
    }
}
