@preconcurrency import CoreLocation
import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct GeocodingClient {
    var reverseGeocode: @Sendable (CLLocationCoordinate2D) async throws -> (city: String?, countryCode: String?)
}

extension GeocodingClient: DependencyKey {
    static let liveValue: Self = {
        let geocoder = CLGeocoder()
        return Self(
            reverseGeocode: { coordinate in
                let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                let placemark = placemarks.first
                return (city: placemark?.locality, countryCode: placemark?.isoCountryCode)
            }
        )
    }()
}

extension GeocodingClient: TestDependencyKey {
    static let testValue = Self()

    static let previewValue = Self(
        reverseGeocode: { _ in
            try await Task.sleep(for: .seconds(0.5))
            return (city: "Córdoba", countryCode: "AR")
        }
    )
}

extension DependencyValues {
    var geocodingClient: GeocodingClient {
        get { self[GeocodingClient.self] }
        set { self[GeocodingClient.self] = newValue }
    }
}

