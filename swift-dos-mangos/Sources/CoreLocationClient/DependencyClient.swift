import Combine
import CoreLocation
import Dependencies

extension LocationManagerClient: DependencyKey {
    public static let liveValue: Self = .live
    
    public static let testValue: Self = .failing

    public static let previewValue = {
        return LocationManagerClient(
            accuracyAuthorization: { .fullAccuracy },
            authorizationStatus: { .authorizedWhenInUse },
            delegate: { .init(Empty().eraseToAnyPublisher()) },
            dismissHeadingCalibrationDisplay: { },
            heading: { .none },
            headingAvailable: { false },
            isRangingAvailable: { false },
            location: {
                Location(
                    coordinate: CLLocationCoordinate2D(
                        latitude: -34.6037,
                        longitude: -58.3816
                    )
                )
            },
            locationServicesEnabled: { true },
            maximumRegionMonitoringDistance: { 0 },
            monitoredRegions: { [] },
            requestAlwaysAuthorization: { },
            requestLocation: { },
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
