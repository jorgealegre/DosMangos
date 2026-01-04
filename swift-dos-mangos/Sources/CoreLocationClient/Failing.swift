import Combine
import CoreLocation
import XCTestDynamicOverlay

extension LocationManagerClient {
    /// A failing implementation of ``LocationManagerClient`` that immediately fails when any endpoint
    /// is accessed.
    ///
    /// This allows you to test that your features only use the location manager endpoints that you
    /// specify, and nothing else. This can be useful as a measurement of how complex a test is.
    ///
    /// To create a client for testing, start with `.failing` and override the endpoints you need:
    ///
    /// ```swift
    /// let client = withDependencies {
    ///   $0.locationManager.authorizationStatus = { .authorizedAlways }
    ///   $0.locationManager.delegate = { Empty<LocationManagerClient.Action, Never>().eraseToAnyPublisher() }
    ///   $0.locationManager.requestLocation = { }
    /// } operation: {
    ///   LocationManagerClient.failing
    /// }
    /// ```
    public static let failing = Self(
        accuracyAuthorization: unimplemented(
            "LocationManagerClient.accuracyAuthorization",
            placeholder: nil
        ),
        authorizationStatus: unimplemented(
            "LocationManagerClient.authorizationStatus",
            placeholder: .notDetermined
        ),
        delegate: unimplemented(
            "LocationManagerClient.delegate",
            placeholder: Empty<LocationManagerClient.Action, Never>().eraseToAnyPublisher()
        ),
        dismissHeadingCalibrationDisplay: unimplemented(
            "LocationManagerClient.dismissHeadingCalibrationDisplay"
        ),
        heading: unimplemented(
            "LocationManagerClient.heading",
            placeholder: nil
        ),
        headingAvailable: unimplemented(
            "LocationManagerClient.headingAvailable",
            placeholder: false
        ),
        isRangingAvailable: unimplemented(
            "LocationManagerClient.isRangingAvailable",
            placeholder: false
        ),
        location: unimplemented(
            "LocationManagerClient.location",
            placeholder: nil
        ),
        locationServicesEnabled: unimplemented(
            "LocationManagerClient.locationServicesEnabled",
            placeholder: false
        ),
        maximumRegionMonitoringDistance: unimplemented(
            "LocationManagerClient.maximumRegionMonitoringDistance",
            placeholder: CLLocationDistanceMax
        ),
        monitoredRegions: unimplemented(
            "LocationManagerClient.monitoredRegions",
            placeholder: []
        ),
        requestAlwaysAuthorization: unimplemented(
            "LocationManagerClient.requestAlwaysAuthorization"
        ),
        requestLocation: unimplemented(
            "LocationManagerClient.requestLocation"
        ),
        requestWhenInUseAuthorization: unimplemented(
            "LocationManagerClient.requestWhenInUseAuthorization"
        ),
        set: unimplemented(
            "LocationManagerClient.set"
        ),
        significantLocationChangeMonitoringAvailable: unimplemented(
            "LocationManagerClient.significantLocationChangeMonitoringAvailable",
            placeholder: false
        ),
        startMonitoringForRegion: unimplemented(
            "LocationManagerClient.startMonitoringForRegion"
        ),
        startMonitoringSignificantLocationChanges: unimplemented(
            "LocationManagerClient.startMonitoringSignificantLocationChanges"
        ),
        startMonitoringVisits: unimplemented(
            "LocationManagerClient.startMonitoringVisits"
        ),
        startUpdatingHeading: unimplemented(
            "LocationManagerClient.startUpdatingHeading"
        ),
        startUpdatingLocation: unimplemented(
            "LocationManagerClient.startUpdatingLocation"
        ),
        stopMonitoringForRegion: unimplemented(
            "LocationManagerClient.stopMonitoringForRegion"
        ),
        stopMonitoringSignificantLocationChanges: unimplemented(
            "LocationManagerClient.stopMonitoringSignificantLocationChanges"
        ),
        stopMonitoringVisits: unimplemented(
            "LocationManagerClient.stopMonitoringVisits"
        ),
        stopUpdatingHeading: unimplemented(
            "LocationManagerClient.stopUpdatingHeading"
        ),
        stopUpdatingLocation: unimplemented(
            "LocationManagerClient.stopUpdatingLocation"
        )
    )
}
