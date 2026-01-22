import Combine
import CoreLocationClient
import Dependencies
import OSLog
import Sharing

private let logger = Logger(subsystem: "dev.alegre.DosMangos", category: "LocationSharedKey")

struct GeocodedLocation: Equatable, Sendable {
    let location: Location
    let city: String?
    let countryCode: String?

    var countryDisplayName: String? {
        guard let countryCode = countryCode else { return nil }
        @Dependency(\.locale) var locale
        return locale.localizedString(forRegionCode: countryCode)
    }
}

final class LocationSharedKey: SharedReaderKey {
    typealias Value = GeocodedLocation?

    let id: String = "currentLocation"

    private actor LoadState {
        @Dependency(\.locationManager) var locationManager
        @Dependency(\.geocodingClient) var geocodingClient

        var loadTask: Task<GeocodedLocation?, Error>?

        func load() async throws -> GeocodedLocation? {
            if let task = loadTask {
                logger.debug("Loading location from existing running task")
                let value = try await task.value
                loadTask = nil
                return value
            }

            logger.debug("Starting new location load")
            let task = Task<GeocodedLocation?, Error> {
                logger.debug("Checking location services")
                let servicesEnabled = await locationManager.locationServicesEnabled()
                guard servicesEnabled else {
                    logger.warning("Location services not enabled")
                    return nil
                }

                let authorizationStatus = await locationManager.authorizationStatus()
                guard authorizationStatus == .authorizedWhenInUse ||
                      authorizationStatus == .authorizedAlways else {
                    logger.warning("Location authorization not granted")
                    return nil
                }

                func geocodeLocation(_ location: Location) async throws -> GeocodedLocation {
                    let coordinate = location.coordinate
                    let geocoded = try await geocodingClient.reverseGeocode(coordinate)
                    return GeocodedLocation(
                        location: location,
                        city: geocoded.city,
                        countryCode: geocoded.countryCode
                    )
                }

                // Create an AsyncStream that subscribes BEFORE we request the location.
                // This prevents a race condition where the location update could be
                // delivered before we start iterating.
                let delegatePublisher = await locationManager.delegate()
                let (stream, continuation) = AsyncStream<LocationManagerClient.Action>.makeStream()
                let cancellable = delegatePublisher.sink { action in
                    continuation.yield(action)
                }
                defer {
                    cancellable.cancel()
                    continuation.finish()
                }

                logger.debug("Requesting location update")
                await locationManager.requestLocation()

                for await action in stream {
                    switch action {
                    case .didUpdateLocations(let locations):
                        guard let location = locations.last else {
                            logger.warning("No location in locations array")
                            continue
                        }
                        logger.debug("Location received")
                        return try await geocodeLocation(location)
                    case .didFailWithError(let error):
                        logger.warning("Location error received")
                        throw error
                    default:
                        continue
                    }
                }

                logger.warning("Delegate stream ended without location")
                return nil
            }

            loadTask = task
            do {
                let value = try await task.value
                loadTask = nil
                if value != nil {
                    logger.info("Location load completed successfully")
                } else {
                    logger.debug("Location load completed with nil value")
                }
                return value
            } catch {
                loadTask = nil
                logger.error("Location load failed")
                throw error
            }
        }
    }

    private let loadState = LoadState()

    func load(
        context: LoadContext<GeocodedLocation?>,
        continuation: LoadContinuation<GeocodedLocation?>
    ) {
        logger.debug("Loading current location")
        Task {
            do {
                let value = try await loadState.load()
                continuation.resume(returning: value)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func subscribe(
        context: LoadContext<GeocodedLocation?>,
        subscriber: SharedSubscriber<GeocodedLocation?>
    ) -> SharedSubscription {
        return SharedSubscription {

        }
    }
}

extension SharedReaderKey where Self == LocationSharedKey {
    static var currentLocation: Self {
        LocationSharedKey()
    }
}

