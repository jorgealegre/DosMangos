@preconcurrency import Combine
@preconcurrency import CoreLocation

@MainActor
private final class LiveLocationManager {
  let manager: CLLocationManager
  let delegateSubject: PassthroughSubject<LocationManagerClient.Action, Never>
  let locationDelegate: LocationManagerDelegate

  init() {
    self.manager = CLLocationManager()
    self.delegateSubject = PassthroughSubject<LocationManagerClient.Action, Never>()
    self.locationDelegate = LocationManagerDelegate(delegateSubject)
    self.manager.delegate = locationDelegate
  }

  var delegateStream: AsyncPublisher<AnyPublisher<LocationManagerClient.Action, Never>> {
    delegateSubject
      .share()
      .eraseToAnyPublisher()
      .values
  }

  func accuracyAuthorization() -> AccuracyAuthorization? {
    #if os(iOS) || os(macOS) || os(watchOS) || targetEnvironment(macCatalyst)
      AccuracyAuthorization(manager.accuracyAuthorization)
    #else
      nil
    #endif
  }

  func authorizationStatus() -> CLAuthorizationStatus {
    manager.authorizationStatus
  }

  func dismissHeadingCalibrationDisplay() {
    #if os(iOS) || os(macOS) || os(watchOS) || targetEnvironment(macCatalyst)
      manager.dismissHeadingCalibrationDisplay()
    #endif
  }

  func heading() -> Heading? {
    #if os(iOS) || os(watchOS) || targetEnvironment(macCatalyst)
      manager.heading.map(Heading.init(rawValue:))
    #else
      nil
    #endif
  }

  func headingAvailable() -> Bool {
    CLLocationManager.headingAvailable()
  }

  func isRangingAvailable() -> Bool {
    CLLocationManager.isRangingAvailable()
  }

  func location() -> Location? {
    manager.location.map(Location.init(rawValue:))
  }

  func locationServicesEnabled() async -> Bool {
    await Task.detached { CLLocationManager.locationServicesEnabled() }.value
  }

  func maximumRegionMonitoringDistance() -> CLLocationDistance {
    #if os(iOS) || os(macOS) || targetEnvironment(macCatalyst)
      manager.maximumRegionMonitoringDistance
    #else
      CLLocationDistanceMax
    #endif
  }

  func monitoredRegions() -> Set<Region> {
    #if os(iOS) || os(macOS) || targetEnvironment(macCatalyst)
      Set(manager.monitoredRegions.map(Region.init(rawValue:)))
    #else
      []
    #endif
  }

  func requestAlwaysAuthorization() {
    #if os(iOS) || os(macOS) || os(watchOS) || targetEnvironment(macCatalyst)
      manager.requestAlwaysAuthorization()
    #endif
  }

  func requestLocation() {
    manager.requestLocation()
  }

  func requestWhenInUseAuthorization() {
    #if os(iOS) || os(macOS) || os(watchOS) || targetEnvironment(macCatalyst)
      manager.requestWhenInUseAuthorization()
    #endif
  }

  func set(properties: LocationManagerClient.Properties) {
    #if os(iOS) || os(watchOS) || targetEnvironment(macCatalyst)
      if let activityType = properties.activityType {
        manager.activityType = activityType
      }
      if let allowsBackgroundLocationUpdates = properties.allowsBackgroundLocationUpdates {
        manager.allowsBackgroundLocationUpdates = allowsBackgroundLocationUpdates
      }
    #endif
    #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS) || targetEnvironment(macCatalyst)
      if let desiredAccuracy = properties.desiredAccuracy {
        manager.desiredAccuracy = desiredAccuracy
      }
      if let distanceFilter = properties.distanceFilter {
        manager.distanceFilter = distanceFilter
      }
    #endif
    #if os(iOS) || os(watchOS) || targetEnvironment(macCatalyst)
      if let headingFilter = properties.headingFilter {
        manager.headingFilter = headingFilter
      }
      if let headingOrientation = properties.headingOrientation {
        manager.headingOrientation = headingOrientation
      }
    #endif
    #if os(iOS) || targetEnvironment(macCatalyst)
      if let pausesLocationUpdatesAutomatically = properties.pausesLocationUpdatesAutomatically {
        manager.pausesLocationUpdatesAutomatically = pausesLocationUpdatesAutomatically
      }
      if let showsBackgroundLocationIndicator = properties.showsBackgroundLocationIndicator {
        manager.showsBackgroundLocationIndicator = showsBackgroundLocationIndicator
      }
    #endif
  }

  func significantLocationChangeMonitoringAvailable() -> Bool {
    CLLocationManager.significantLocationChangeMonitoringAvailable()
  }

  func startMonitoringForRegion(_ region: Region) {
    #if os(iOS) || os(macOS) || targetEnvironment(macCatalyst)
      manager.startMonitoring(for: region.rawValue!)
    #endif
  }

  func startMonitoringSignificantLocationChanges() {
    #if os(iOS) || targetEnvironment(macCatalyst)
      manager.startMonitoringSignificantLocationChanges()
    #endif
  }

  func startMonitoringVisits() {
    #if os(iOS) || targetEnvironment(macCatalyst)
      manager.startMonitoringVisits()
    #endif
  }

  func startUpdatingHeading() {
    #if os(iOS) || os(macOS) || os(watchOS) || targetEnvironment(macCatalyst)
      manager.startUpdatingHeading()
    #endif
  }

  func startUpdatingLocation() {
    #if os(iOS) || os(macOS) || os(watchOS) || targetEnvironment(macCatalyst)
      manager.startUpdatingLocation()
    #endif
  }

  func stopMonitoringForRegion(_ region: Region) {
    #if os(iOS) || os(macOS) || targetEnvironment(macCatalyst)
      manager.stopMonitoring(for: region.rawValue!)
    #endif
  }

  func stopMonitoringSignificantLocationChanges() {
    #if os(iOS) || targetEnvironment(macCatalyst)
      manager.stopMonitoringSignificantLocationChanges()
    #endif
  }

  func stopMonitoringVisits() {
    #if os(iOS) || targetEnvironment(macCatalyst)
      manager.stopMonitoringVisits()
    #endif
  }

  func stopUpdatingHeading() {
    #if os(iOS) || os(watchOS) || targetEnvironment(macCatalyst)
      manager.stopUpdatingHeading()
    #endif
  }

  func stopUpdatingLocation() {
    #if os(iOS) || os(macOS) || os(watchOS) || targetEnvironment(macCatalyst)
      manager.stopUpdatingLocation()
    #endif
  }
}

extension LocationManagerClient {
  /// The live implementation of the `LocationManagerClient`. This implementation creates a real
  /// `CLLocationManager` instance and directly interacts with the system's Core Location services.
  public static let live: Self = {
    MainActor.shared.preconditionIsolated()
    let liveManager = LiveLocationManager()

    return Self(
      accuracyAuthorization: {
        await liveManager.accuracyAuthorization()
      },
      authorizationStatus: {
        await liveManager.authorizationStatus()
      },
      delegate: {
        await liveManager.delegateStream
      },
      dismissHeadingCalibrationDisplay: {
        await liveManager.dismissHeadingCalibrationDisplay()
      },
      heading: {
        await liveManager.heading()
      },
      headingAvailable: {
        await liveManager.headingAvailable()
      },
      isRangingAvailable: {
        await liveManager.isRangingAvailable()
      },
      location: {
        await liveManager.location()
      },
      locationServicesEnabled: {
        await liveManager.locationServicesEnabled()
      },
      maximumRegionMonitoringDistance: {
        await liveManager.maximumRegionMonitoringDistance()
      },
      monitoredRegions: {
        await liveManager.monitoredRegions()
      },
      requestAlwaysAuthorization: {
        await liveManager.requestAlwaysAuthorization()
      },
      requestLocation: {
        await liveManager.requestLocation()
      },
      requestWhenInUseAuthorization: {
        await liveManager.requestWhenInUseAuthorization()
      },
      set: { properties in
        await liveManager.set(properties: properties)
      },
      significantLocationChangeMonitoringAvailable: {
        await liveManager.significantLocationChangeMonitoringAvailable()
      },
      startMonitoringForRegion: { region in
        await liveManager.startMonitoringForRegion(region)
      },
      startMonitoringSignificantLocationChanges: {
        await liveManager.startMonitoringSignificantLocationChanges()
      },
      startMonitoringVisits: {
        await liveManager.startMonitoringVisits()
      },
      startUpdatingHeading: {
        await liveManager.startUpdatingHeading()
      },
      startUpdatingLocation: {
        await liveManager.startUpdatingLocation()
      },
      stopMonitoringForRegion: { region in
        await liveManager.stopMonitoringForRegion(region)
      },
      stopMonitoringSignificantLocationChanges: {
        await liveManager.stopMonitoringSignificantLocationChanges()
      },
      stopMonitoringVisits: {
        await liveManager.stopMonitoringVisits()
      },
      stopUpdatingHeading: {
        await liveManager.stopUpdatingHeading()
      },
      stopUpdatingLocation: {
        await liveManager.stopUpdatingLocation()
      }
    )
  }()
}


/// The delegate class that receives `CLLocationManager` callbacks and forwards them to the subject.
/// Note: This cannot be @MainActor because CLLocationManagerDelegate protocol is not actor-isolated.
/// However, CLLocationManager ensures delegate methods are called on the thread where it was created (main thread).
private final class LocationManagerDelegate: NSObject, CLLocationManagerDelegate {
  let subject: PassthroughSubject<LocationManagerClient.Action, Never>

  init(_ subject: PassthroughSubject<LocationManagerClient.Action, Never>) {
    self.subject = subject
  }

  func locationManager(
    _ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus
  ) {
    self.subject.send(.didChangeAuthorization(status))
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    self.subject.send(.didFailWithError(LocationManagerClient.Error(error)))
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    self.subject.send(.didUpdateLocations(locations.map(Location.init(rawValue:))))
  }

  #if os(macOS)
    func locationManager(
      _ manager: CLLocationManager, didUpdateTo newLocation: CLLocation,
      from oldLocation: CLLocation
    ) {
      self.subject.send(
        .didUpdateTo(
          newLocation: Location(rawValue: newLocation),
          oldLocation: Location(rawValue: oldLocation)
        )
      )
    }
  #endif

  #if os(iOS) || os(macOS) || targetEnvironment(macCatalyst)
    func locationManager(
      _ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?
    ) {
      self.subject.send(
        .didFinishDeferredUpdatesWithError(error.map(LocationManagerClient.Error.init))
      )
    }
  #endif

  #if os(iOS) || targetEnvironment(macCatalyst)
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
      self.subject.send(.didPauseLocationUpdates)
    }
  #endif

  #if os(iOS) || targetEnvironment(macCatalyst)
    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
      self.subject.send(.didResumeLocationUpdates)
    }
  #endif

  #if os(iOS) || os(watchOS) || targetEnvironment(macCatalyst)
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
      self.subject.send(.didUpdateHeading(newHeading: Heading(rawValue: newHeading)))
    }
  #endif

  #if os(iOS) || os(macOS) || targetEnvironment(macCatalyst)
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
      self.subject.send(.didEnterRegion(Region(rawValue: region)))
    }
  #endif

  #if os(iOS) || os(macOS) || targetEnvironment(macCatalyst)
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
      self.subject.send(.didExitRegion(Region(rawValue: region)))
    }
  #endif

  #if os(iOS) || os(macOS) || targetEnvironment(macCatalyst)
    func locationManager(
      _ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion
    ) {
      self.subject.send(.didDetermineState(state, region: Region(rawValue: region)))
    }
  #endif

  #if os(iOS) || os(macOS) || targetEnvironment(macCatalyst)
    func locationManager(
      _ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error
    ) {
      self.subject.send(
        .monitoringDidFail(
          region: region.map(Region.init(rawValue:)), error: LocationManagerClient.Error(error)))
    }
  #endif

  #if os(iOS) || os(macOS) || targetEnvironment(macCatalyst)
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
      self.subject.send(.didStartMonitoring(region: Region(rawValue: region)))
    }
  #endif

  #if os(iOS) || targetEnvironment(macCatalyst)
    func locationManager(
      _ manager: CLLocationManager, didRange beacons: [CLBeacon],
      satisfying beaconConstraint: CLBeaconIdentityConstraint
    ) {
      self.subject.send(
        .didRangeBeacons(
          beacons.map(Beacon.init(rawValue:)), satisfyingConstraint: beaconConstraint
        )
      )
    }
  #endif

  #if os(iOS) || targetEnvironment(macCatalyst)
    func locationManager(
      _ manager: CLLocationManager, didFailRangingFor beaconConstraint: CLBeaconIdentityConstraint,
      error: Error
    ) {
      self.subject.send(
        .didFailRanging(beaconConstraint: beaconConstraint, error: LocationManagerClient.Error(error))
      )
    }
  #endif

  #if os(iOS) || targetEnvironment(macCatalyst)
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
      self.subject.send(.didVisit(Visit(visit: visit)))
    }
  #endif
}
