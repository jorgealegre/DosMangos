import Combine
import CoreLocationClient
import Dependencies
import DependenciesTestSupport
import Foundation
import InlineSnapshotTesting
import SQLiteData
import SwiftUI
import Testing

@testable import DosMangos

@Suite(
    .dependency(\.continuousClock, ImmediateClock()),
    .dependency(\.date.now, Date(timeIntervalSince1970: 1_234_567_890)),
    .dependency(\.calendar, .current),
    .dependency(\.uuid, .incrementing),
    .dependencies {
        let delegate = PassthroughSubject<LocationManagerClient.Action, Never>()
        let sampleLocation = Location(
            coordinate: CLLocationCoordinate2D(
                latitude: -34.6037,
                longitude: -58.3816
            ),
            timestamp: Date(timeIntervalSince1970: 1_234_567_890)
        )
        $0.locationManager.locationServicesEnabled = { true }
        $0.locationManager.authorizationStatus = { .authorizedAlways }
        $0.locationManager.location = { sampleLocation }
        $0.locationManager.requestLocation = {
            Task {
                delegate.send(.didUpdateLocations([sampleLocation]))
            }
        }
        $0.locationManager.delegate = { delegate.eraseToAnyPublisher() }

        $0.geocodingClient.reverseGeocode = { _ in ("Córdoba", "AR") }


        try $0.bootstrapDatabase()

//        try $0.defaultDatabase.seedSampleData()
//        try await $0.defaultSyncEngine.sendChanges()
    },
    .snapshots(record: .failed)
)
@MainActor
struct BaseTestSuite {}
