import Combine
import ComposableArchitecture
import CoreLocationClient
import Dependencies
import DependenciesTestSupport
import Foundation
import InlineSnapshotTesting
import Testing
import SQLiteData

@testable import DosMangos

extension BaseTestSuite {
    @MainActor
    struct DosMangosTests {
        @Dependency(\.defaultDatabase) var database

        @Test()
        func example() async throws {
            let store = TestStore(initialState: AppReducer.State()) {
                AppReducer()
            } withDependencies: {
                $0.exchangeRate.prefetchRatesForToday = { }
            }

            await store.send(.appDelegate(.didFinishLaunching))
            await store.send(.appDelegate(.sceneDelegate(.willEnterForeground)))
            await store.send(.view(.task))

            await store.send(.transactionsList(.view(.onAppear)))

//            _ = await store.state.transactionsList.$rows.publisher.values.first(where: { _ in true })
//            try await store.state.transactionsList.$rows.load(store.state.transactionsList.rowsQuery)

            assertInlineSnapshot(of: store.state.transactionsList.rows, as: .dump) {
                """
                - 0 elements

                """
            }

            await store.finish()
        }
    }
}
