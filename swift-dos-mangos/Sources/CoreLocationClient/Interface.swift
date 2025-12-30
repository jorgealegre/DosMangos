import Combine
import CoreLocation
import Dependencies

/// A wrapper around Core Location's `CLLocationManager` that exposes its functionality through
/// async/await and Combine publishers, making it easy to use as a dependency.
///
/// To use it as a standalone dependency, access it via the `@Dependency` property wrapper:
///
/// ```swift
/// import CoreLocationClient
/// import Dependencies
///
/// @Dependency(\.locationManager) var locationManager
/// ```
///
/// Then subscribe to delegate actions using the async sequence:
///
/// ```swift
/// for await action in await locationManager.delegate() {
///   switch action {
///   case .didUpdateLocations(let locations):
///     // Handle location updates
///   case .didChangeAuthorization(let status):
///     // Handle authorization changes
///   default:
///     break
///   }
/// }
/// ```
///
/// **Thread Safety**: While this client can be called from any context, the underlying
/// `CLLocationManager` requires main thread access. The live implementation handles this
/// internally by ensuring the manager is created and used on the main thread. Most methods
/// are synchronous fire-and-forget operations that internally dispatch to the main thread.
///
public struct LocationManagerClient: Sendable {
    /// Actions that correspond to `CLLocationManagerDelegate` methods.
    ///
    /// See `CLLocationManagerDelegate` for more information.
    public enum Action: Equatable, Sendable {
        case didChangeAuthorization(CLAuthorizationStatus)
        
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        case didDetermineState(CLRegionState, region: Region)
        
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        case didEnterRegion(Region)
        
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        case didExitRegion(Region)
        
        @available(macOS, unavailable)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        case didFailRanging(beaconConstraint: CLBeaconIdentityConstraint, error: Error)
        
        case didFailWithError(Error)
        
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        case didFinishDeferredUpdatesWithError(Error?)
        
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        case didPauseLocationUpdates
        
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        case didResumeLocationUpdates
        
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        case didStartMonitoring(region: Region)
        
        @available(macOS, unavailable)
        @available(tvOS, unavailable)
        case didUpdateHeading(newHeading: Heading)
        
        case didUpdateLocations([Location])
        
        @available(macCatalyst, deprecated: 13)
        @available(tvOS, unavailable)
        case didUpdateTo(newLocation: Location, oldLocation: Location)
        
        @available(macOS, unavailable)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        case didVisit(Visit)
        
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        case monitoringDidFail(region: Region?, error: Error)
        
        @available(macOS, unavailable)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        case didRangeBeacons([Beacon], satisfyingConstraint: CLBeaconIdentityConstraint)
    }
    
    public struct Error: Swift.Error, Equatable {
        public let error: NSError
        
        public init(_ error: Swift.Error) {
            self.error = error as NSError
        }
    }
    
    public var accuracyAuthorization: @Sendable () async -> AccuracyAuthorization?
    
    public var authorizationStatus: @Sendable () async -> CLAuthorizationStatus
    
    public var delegate: @Sendable () async -> AsyncPublisher<AnyPublisher<Action, Never>>
    
    public var dismissHeadingCalibrationDisplay: @Sendable () async -> Void
    
    public var heading: @Sendable () async -> Heading?
    
    public var headingAvailable: @Sendable () async -> Bool
    
    public var isRangingAvailable: @Sendable () async -> Bool
    
    public var location: @Sendable () async -> Location?
    
    public var locationServicesEnabled: @Sendable () async -> Bool
    
    public var maximumRegionMonitoringDistance: @Sendable () async -> CLLocationDistance
    
    public var monitoredRegions: @Sendable () async -> Set<Region>
    
    public var requestAlwaysAuthorization: @Sendable () async -> Void
    
    public var requestLocation: @Sendable () async -> Void
    
    public var requestWhenInUseAuthorization: @Sendable () async -> Void
    
    public var set: @Sendable (Properties) async -> Void
    
    public var significantLocationChangeMonitoringAvailable: @Sendable () async -> Bool
    
    public var startMonitoringForRegion: @Sendable (Region) async -> Void
    
    public var startMonitoringSignificantLocationChanges: @Sendable () async -> Void
    
    public var startMonitoringVisits: @Sendable () async -> Void
    
    public var startUpdatingHeading: @Sendable () async -> Void
    
    public var startUpdatingLocation: @Sendable () async -> Void
    
    public var stopMonitoringForRegion: @Sendable (Region) async -> Void
    
    public var stopMonitoringSignificantLocationChanges: @Sendable () async -> Void
    
    public var stopMonitoringVisits: @Sendable () async -> Void
    
    public var stopUpdatingHeading: @Sendable () async -> Void
    
    public var stopUpdatingLocation: @Sendable () async -> Void
    
    /// Updates the given properties of a uniquely identified `CLLocationManager`.
    public func set(
        activityType: CLActivityType? = nil,
        allowsBackgroundLocationUpdates: Bool? = nil,
        desiredAccuracy: CLLocationAccuracy? = nil,
        distanceFilter: CLLocationDistance? = nil,
        headingFilter: CLLocationDegrees? = nil,
        headingOrientation: CLDeviceOrientation? = nil,
        pausesLocationUpdatesAutomatically: Bool? = nil,
        showsBackgroundLocationIndicator: Bool? = nil
    ) async {
#if os(macOS) || os(tvOS) || os(watchOS)
        return
#else
        await self.set(
            Properties(
                activityType: activityType,
                allowsBackgroundLocationUpdates: allowsBackgroundLocationUpdates,
                desiredAccuracy: desiredAccuracy,
                distanceFilter: distanceFilter,
                headingFilter: headingFilter,
                headingOrientation: headingOrientation,
                pausesLocationUpdatesAutomatically: pausesLocationUpdatesAutomatically,
                showsBackgroundLocationIndicator: showsBackgroundLocationIndicator
            )
        )
#endif
    }
}

extension LocationManagerClient {
    public struct Properties: Equatable, Sendable {
        var activityType: CLActivityType? = nil
        
        var allowsBackgroundLocationUpdates: Bool? = nil
        
        var desiredAccuracy: CLLocationAccuracy? = nil
        
        var distanceFilter: CLLocationDistance? = nil
        
        var headingFilter: CLLocationDegrees? = nil
        
        var headingOrientation: CLDeviceOrientation? = nil
        
        var pausesLocationUpdatesAutomatically: Bool? = nil
        
        var showsBackgroundLocationIndicator: Bool? = nil
        
        public static func == (lhs: Self, rhs: Self) -> Bool {
            var isEqual = true
#if os(iOS) || targetEnvironment(macCatalyst) || os(watchOS)
            isEqual =
            isEqual
            && lhs.activityType == rhs.activityType
            && lhs.allowsBackgroundLocationUpdates == rhs.allowsBackgroundLocationUpdates
#endif
            isEqual =
            isEqual
            && lhs.desiredAccuracy == rhs.desiredAccuracy
            && lhs.distanceFilter == rhs.distanceFilter
#if os(iOS) || targetEnvironment(macCatalyst) || os(watchOS)
            isEqual =
            isEqual
            && lhs.headingFilter == rhs.headingFilter
            && lhs.headingOrientation == rhs.headingOrientation
#endif
#if os(iOS) || targetEnvironment(macCatalyst)
            isEqual =
            isEqual
            && lhs.pausesLocationUpdatesAutomatically == rhs.pausesLocationUpdatesAutomatically
            && lhs.showsBackgroundLocationIndicator == rhs.showsBackgroundLocationIndicator
#endif
            return isEqual
        }
        
        @available(macOS, unavailable)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        public init(
            activityType: CLActivityType? = nil,
            allowsBackgroundLocationUpdates: Bool? = nil,
            desiredAccuracy: CLLocationAccuracy? = nil,
            distanceFilter: CLLocationDistance? = nil,
            headingFilter: CLLocationDegrees? = nil,
            headingOrientation: CLDeviceOrientation? = nil,
            pausesLocationUpdatesAutomatically: Bool? = nil,
            showsBackgroundLocationIndicator: Bool? = nil
        ) {
            self.activityType = activityType
            self.allowsBackgroundLocationUpdates = allowsBackgroundLocationUpdates
            self.desiredAccuracy = desiredAccuracy
            self.distanceFilter = distanceFilter
            self.headingFilter = headingFilter
            self.headingOrientation = headingOrientation
            self.pausesLocationUpdatesAutomatically = pausesLocationUpdatesAutomatically
            self.showsBackgroundLocationIndicator = showsBackgroundLocationIndicator
        }
        
        @available(iOS, unavailable)
        @available(macCatalyst, unavailable)
        @available(watchOS, unavailable)
        public init(
            desiredAccuracy: CLLocationAccuracy? = nil,
            distanceFilter: CLLocationDistance? = nil
        ) {
            self.desiredAccuracy = desiredAccuracy
            self.distanceFilter = distanceFilter
        }
        
        @available(iOS, unavailable)
        @available(macCatalyst, unavailable)
        @available(macOS, unavailable)
        @available(tvOS, unavailable)
        public init(
            activityType: CLActivityType? = nil,
            allowsBackgroundLocationUpdates: Bool? = nil,
            desiredAccuracy: CLLocationAccuracy? = nil,
            distanceFilter: CLLocationDistance? = nil,
            headingFilter: CLLocationDegrees? = nil,
            headingOrientation: CLDeviceOrientation? = nil
        ) {
            self.activityType = activityType
            self.allowsBackgroundLocationUpdates = allowsBackgroundLocationUpdates
            self.desiredAccuracy = desiredAccuracy
            self.distanceFilter = distanceFilter
            self.headingFilter = headingFilter
            self.headingOrientation = headingOrientation
        }
    }
}
