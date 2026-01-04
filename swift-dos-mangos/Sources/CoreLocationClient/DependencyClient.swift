@preconcurrency import Combine
import CoreLocation
import Dependencies

extension LocationManagerClient: DependencyKey {
    public static let liveValue: Self = .live

    public static let testValue: Self = .failing

    public static let previewValue = {
        let delegate = PassthroughSubject<LocationManagerClient.Action, Never>()
        let sampleLocation = Location(
            coordinate: CLLocationCoordinate2D(
                latitude: -34.6037,
                longitude: -58.3816
            )
        )

        return LocationManagerClient(
            accuracyAuthorization: { .fullAccuracy },
            authorizationStatus: { .authorizedWhenInUse },
            delegate: { delegate.eraseToAnyPublisher() },
            dismissHeadingCalibrationDisplay: { },
            heading: { .none },
            headingAvailable: { false },
            isRangingAvailable: { false },
            location: {
                sampleLocation
            },
            locationServicesEnabled: { true },
            maximumRegionMonitoringDistance: { 0 },
            monitoredRegions: { [] },
            requestAlwaysAuthorization: { },
            requestLocation: {
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    delegate.send(.didUpdateLocations([sampleLocation]))
                }
            },
            requestWhenInUseAuthorization: { },
            set: { _ in },
            significantLocationChangeMonitoringAvailable: { false },
            startMonitoringForRegion: { _ in },
            startMonitoringSignificantLocationChanges: { },
            startMonitoringVisits: { },
            startUpdatingHeading: { },
            startUpdatingLocation: { },
            stopMonitoringForRegion: { _ in },
            stopMonitoringSignificantLocationChanges: { },
            stopMonitoringVisits: { },
            stopUpdatingHeading: { },
            stopUpdatingLocation: { }
        )
    }()
}

extension DependencyValues {
    public var locationManager: LocationManagerClient {
        get { self[LocationManagerClient.self] }
        set { self[LocationManagerClient.self] = newValue }
    }
}
