import Combine
import ComposableArchitecture
import CoreLocationClient
import Dependencies
import DependenciesTestSupport
import Foundation
import InlineSnapshotTesting
import Testing
import SnapshotTestingCustomDump
import SQLiteData

@testable import DosMangos

extension BaseTestSuite {
    @MainActor
    struct DosMangosTests {
        @Dependency(\.defaultDatabase) var database

        @Test()
        func happyPath() async throws {
            let store = TestStore(initialState: AppReducer.State()) {
                AppReducer()
            } withDependencies: {
                $0.exchangeRate.prefetchRatesForToday = { }
                $0.groupClient.ensureParticipantID = { }
            }

            await store.send(\.appDelegate.didFinishLaunching)
            await store.send(\.appDelegate.sceneDelegate.willEnterForeground)
            await store.send(\.view.task)

            #expect(store.state.transactionsList.data.rows.isEmpty)

            var transaction = Transaction.Draft(currencyCode: "USD")
            await store.send(\.view.newTransactionButtonTapped) {
                $0.destination = .transactionForm(TransactionFormReducer.State(transaction: transaction))
            }
            await store.send(\.destination.transactionForm.view.task)

            transaction.wholeUnits = 123
            transaction.description = "Rent"
            await store.send(\.destination.transactionForm.binding.transaction, transaction) {
                $0.destination.modify(\.transactionForm) {
                    $0.transaction.valueMinorUnits = 12300
                    $0.transaction.description = "Rent"
                }
            }

            await store.send(\.destination.transactionForm.view.saveButtonTapped)
            await store.receive(\.destination.dismiss) {
                $0.destination = nil
            }

            try await store.state.transactionsList.$data.load()
            assertInlineSnapshot(of: store.state.transactionsList.data, as: .customDump) {
                """
                TransactionsList.DataRequest.Value(
                  rows: [
                    [0]: TransactionsListRow(
                      transaction: Transaction(
                        id: UUID(00000000-0000-0000-0000-000000000001),
                        description: "Rent",
                        valueMinorUnits: 12300,
                        currencyCode: "USD",
                        convertedValueMinorUnits: 12300,
                        convertedCurrencyCode: "USD",
                        type: .expense,
                        createdAtUTC: Date(2009-02-13T23:31:30.000Z),
                        localYear: 2009,
                        localMonth: 2,
                        localDay: 13,
                        recurringTransactionID: nil,
                        groupTransactionSplitID: nil
                      ),
                      categoryDisplayName: nil,
                      tags: [],
                      location: TransactionLocation(
                        transactionID: UUID(00000000-0000-0000-0000-000000000001),
                        latitude: -34.6037,
                        longitude: -58.3816,
                        city: "Córdoba",
                        countryCode: "AR"
                      )
                    )
                  ],
                  dueRows: [],
                  rowsByDay: [
                    13: [
                      [0]: TransactionsListRow(
                        transaction: Transaction(
                          id: UUID(00000000-0000-0000-0000-000000000001),
                          description: "Rent",
                          valueMinorUnits: 12300,
                          currencyCode: "USD",
                          convertedValueMinorUnits: 12300,
                          convertedCurrencyCode: "USD",
                          type: .expense,
                          createdAtUTC: Date(2009-02-13T23:31:30.000Z),
                          localYear: 2009,
                          localMonth: 2,
                          localDay: 13,
                          recurringTransactionID: nil,
                          groupTransactionSplitID: nil
                        ),
                        categoryDisplayName: nil,
                        tags: [],
                        location: TransactionLocation(
                          transactionID: UUID(00000000-0000-0000-0000-000000000001),
                          latitude: -34.6037,
                          longitude: -58.3816,
                          city: "Córdoba",
                          countryCode: "AR"
                        )
                      )
                    ]
                  ],
                  balanceByDay: [
                    13: Money(
                      value: -12300,
                      currencyCode: "USD"
                    )
                  ],
                  days: [
                    [0]: 13
                  ],
                  incomeTotal: 0,
                  expenseTotal: 12300,
                  currencyCode: "USD",
                  topCategories: []
                )
                """
            }

            await store.finish()
        }
    }
}
