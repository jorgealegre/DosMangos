import Dependencies
import DependenciesMacros
import Foundation
import MapKit

@DependencyClient
struct LocalSearchClient {
    struct Result: Equatable, Identifiable, Sendable {
        let id: UUID
        var title: String
        var subtitle: String?
        var latitude: Double
        var longitude: Double
    }

    var search: @Sendable (_ query: String, _ region: MKCoordinateRegion?) async throws -> [Result]
}

extension LocalSearchClient: TestDependencyKey {
    static let testValue = Self()
}

extension LocalSearchClient: DependencyKey {
    static let liveValue: Self = Self(
        search: { query, region in
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            if let region { request.region = region }

            let response = try await MKLocalSearch(request: request).start()

            return response.mapItems.prefix(10).map { item in
                let coordinate = item.placemark.coordinate
                return Result(
                    id: UUID(),
                    title: item.name ?? "",
                    subtitle: item.placemark.title,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
        }
    )

    static let previewValue: Self = Self(
        search: { query, _ in
            try await Task.sleep(for: .seconds(2))
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !q.isEmpty else { return [] }

            let all: [Result] = [
                .init(
                    id: UUID(0),
                    title: "Coffee Shop",
                    subtitle: "Main St",
                    latitude: 37.776_5,
                    longitude: -122.417_2
                ),
                .init(
                    id: UUID(1),
                    title: "Grocery Store",
                    subtitle: "Market St",
                    latitude: 37.781_0,
                    longitude: -122.411_0
                ),
                .init(
                    id: UUID(2),
                    title: "Office",
                    subtitle: "Downtown",
                    latitude: 37.790_0,
                    longitude: -122.401_0
                ),
                .init(
                    id: UUID(3),
                    title: "Home",
                    subtitle: "Mission",
                    latitude: 37.759_9,
                    longitude: -122.414_8
                ),
            ]

            return all
                .filter { result in
                    result.title.lowercased().contains(q)
                    || (result.subtitle?.lowercased().contains(q) ?? false)
                }
        }
    )
}

extension DependencyValues {
    var localSearch: LocalSearchClient {
        get { self[LocalSearchClient.self] }
        set { self[LocalSearchClient.self] = newValue }
    }
}
