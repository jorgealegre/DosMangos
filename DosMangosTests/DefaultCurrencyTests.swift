import ComposableArchitecture
import ConcurrencyExtras
import Dependencies
import DependenciesTestSupport
import Foundation
import InlineSnapshotTesting
import SnapshotTestingCustomDump
import SQLiteData
import Testing

@testable import DosMangos

extension BaseTestSuite {
    @MainActor
    struct DefaultCurrencyTests {
        @Dependency(\.defaultDatabase) var database

        // MARK: - No Transactions to Convert

        @Test("When no transactions exist, currency changes directly")
        func noTransactions_changesDirectly() async throws {
            let store = TestStore(
                initialState: DefaultCurrencyPickerReducer.State()
            ) {
                DefaultCurrencyPickerReducer()
            }

            // Verify initial state
            #expect(store.state.defaultCurrency == "USD")

            // Open currency picker
            await store.send(\.view.changeCurrencyButtonTapped) {
                $0.destination = .currencyPicker(CurrencyPicker.State(selectedCurrencyCode: "USD"))
            }

            // Select EUR
            await store.send(\.destination.currencyPicker.delegate.currencySelected, "EUR") {
                $0.destination = nil
                $0.pendingCurrency = "EUR"
                $0.isLoadingConversionInfo = true
            }

            // No transactions, so conversion info shows empty
            await store.receive(\.conversionInfoLoaded) {
                $0.isLoadingConversionInfo = false
                $0.pendingCurrency = nil
                $0.$defaultCurrency.withLock { $0 = "EUR" }
            }

            // Currency changed without needing conversion
            await store.receive(\.currencyChangedDirectly)

            #expect(store.state.defaultCurrency == "EUR")
        }

        @Test("When all transactions are already in target currency, changes directly")
        func allTransactionsInTargetCurrency_changesDirectly() async throws {
            // Create transactions in EUR
            @Dependency(\.date.now) var now
            try await database.write { db in
                try Transaction.insert {
                    Transaction.Draft(
                        description: "Coffee",
                        valueMinorUnits: 500,
                        currencyCode: "EUR",
                        type: .expense,
                        createdAtUTC: now,
                        localYear: 2025, localMonth: 1, localDay: 15
                    )
                }.execute(db)
            }

            let store = TestStore(
                initialState: DefaultCurrencyPickerReducer.State()
            ) {
                DefaultCurrencyPickerReducer()
            }

            await store.send(\.view.changeCurrencyButtonTapped) {
                $0.destination = .currencyPicker(CurrencyPicker.State(selectedCurrencyCode: "USD"))
            }

            // Select EUR (same as the transaction currency)
            await store.send(\.destination.currencyPicker.delegate.currencySelected, "EUR") {
                $0.destination = nil
                $0.pendingCurrency = "EUR"
                $0.isLoadingConversionInfo = true
            }

            await store.receive(\.conversionInfoLoaded) {
                $0.isLoadingConversionInfo = false
                $0.pendingCurrency = nil
                $0.$defaultCurrency.withLock { $0 = "EUR" }
            }

            await store.receive(\.currencyChangedDirectly)
        }

        // MARK: - Conversion Flow

        @Test("Full conversion flow with rate fetching and conversion")
        func fullConversionFlow() async throws {
            // Create transactions in different currencies
            @Dependency(\.date.now) var now
            try await database.write { db in
                try Transaction.insert {
                    Transaction.Draft(
                        description: "Rent",
                        valueMinorUnits: 100000, // $1000
                        currencyCode: "USD",
                        type: .expense,
                        createdAtUTC: now,
                        localYear: 2025, localMonth: 1, localDay: 15
                    )
                }.execute(db)

                try Transaction.insert {
                    Transaction.Draft(
                        description: "Coffee in Buenos Aires",
                        valueMinorUnits: 500000, // 5000 ARS
                        currencyCode: "ARS",
                        type: .expense,
                        createdAtUTC: now,
                        localYear: 2025, localMonth: 1, localDay: 15
                    )
                }.execute(db)
            }

            let store = TestStore(
                initialState: DefaultCurrencyPickerReducer.State()
            ) {
                DefaultCurrencyPickerReducer()
            } withDependencies: {
                $0.exchangeRate.getRate = { from, to, _ in
                    // USD -> EUR = 0.92
                    // ARS -> EUR = 0.00092 (1 ARS = 0.00092 EUR)
                    if from == "USD" && to == "EUR" { return 0.92 }
                    if from == "ARS" && to == "EUR" { return 0.00092 }
                    return 1.0
                }
            }

            await store.send(\.view.changeCurrencyButtonTapped) {
                $0.destination = .currencyPicker(CurrencyPicker.State(selectedCurrencyCode: "USD"))
            }

            await store.send(\.destination.currencyPicker.delegate.currencySelected, "EUR") {
                $0.destination = nil
                $0.pendingCurrency = "EUR"
                $0.isLoadingConversionInfo = true
            }

            // Should receive conversion info with 2 pairs (USD and ARS on same date)
            await store.receive(\.conversionInfoLoaded) {
                $0.isLoadingConversionInfo = false
                $0.conversionInfo = DefaultCurrencyPickerReducer.ConversionInfo(
                    pairs: [
                        DefaultCurrencyPickerReducer.ConversionPair(
                            date: DateComponents(year: 2025, month: 1, day: 15),
                            fromCurrency: "ARS",
                            transactionCount: 1
                        ),
                        DefaultCurrencyPickerReducer.ConversionPair(
                            date: DateComponents(year: 2025, month: 1, day: 15),
                            fromCurrency: "USD",
                            transactionCount: 1
                        ),
                    ],
                    transactionCount: 2
                )
                // Rates initialized as loading
                for pair in $0.conversionInfo!.pairs {
                    $0.fetchedRates[pair] = .loading
                }
            }

            // Receive rate fetches (order may vary due to parallel execution)
            // Skip checking exact order, just verify final state
            await store.skipReceivedActions()

            #expect(store.state.allRatesFetched == true)

            // Verify both rates were fetched correctly
            let arsPair = DefaultCurrencyPickerReducer.ConversionPair(
                date: DateComponents(year: 2025, month: 1, day: 15),
                fromCurrency: "ARS",
                transactionCount: 1
            )
            let usdPair = DefaultCurrencyPickerReducer.ConversionPair(
                date: DateComponents(year: 2025, month: 1, day: 15),
                fromCurrency: "USD",
                transactionCount: 1
            )
            #expect(store.state.fetchedRates[arsPair] == .success(0.00092))
            #expect(store.state.fetchedRates[usdPair] == .success(0.92))

            // User taps convert
            await store.send(\.view.convertButtonTapped) {
                $0.conversionState = .converting
            }

            await store.receive(\.conversionCompleted) {
                $0.conversionState = .success(convertedCount: 2)
                $0.$defaultCurrency.withLock { $0 = "EUR" }
            }

            // Verify transactions were converted
            let transactions = try await database.read { db in
                try Transaction.fetchAll(db)
            }

            let usdTransaction = transactions.first { $0.currencyCode == "USD" }!
            #expect(usdTransaction.convertedCurrencyCode == "EUR")
            #expect(usdTransaction.convertedValueMinorUnits == 92000) // 1000 * 0.92 = 920 EUR = 92000 cents

            let arsTransaction = transactions.first { $0.currencyCode == "ARS" }!
            #expect(arsTransaction.convertedCurrencyCode == "EUR")
            #expect(arsTransaction.convertedValueMinorUnits == 460) // 5000 * 0.00092 = 4.6 EUR = 460 cents

            // User taps done
            await store.send(\.view.doneButtonTapped) {
                $0.pendingCurrency = nil
                $0.conversionInfo = nil
                $0.fetchedRates = [:]
                $0.conversionState = .idle
            }
        }

        // MARK: - Rate Fetch Failures

        @Test("Rate fetch failure shows error and allows retry")
        func rateFetchFailure_allowsRetry() async throws {
            @Dependency(\.date.now) var now
            try await database.write { db in
                try Transaction.insert {
                    Transaction.Draft(
                        description: "Test",
                        valueMinorUnits: 1000,
                        currencyCode: "USD",
                        type: .expense,
                        createdAtUTC: now,
                        localYear: 2025, localMonth: 1, localDay: 10
                    )
                }.execute(db)
            }

            let callCount = LockIsolated(0)
            let store = TestStore(
                initialState: DefaultCurrencyPickerReducer.State()
            ) {
                DefaultCurrencyPickerReducer()
            } withDependencies: {
                $0.exchangeRate.getRate = { _, _, _ in
                    let count = callCount.withValue { value in
                        value += 1
                        return value
                    }
                    if count == 1 {
                        throw ExchangeRateError.rateNotAvailable(from: "USD", to: "EUR", date: Date())
                    }
                    return 0.92
                }
            }

            await store.send(\.view.changeCurrencyButtonTapped) {
                $0.destination = .currencyPicker(CurrencyPicker.State(selectedCurrencyCode: "USD"))
            }

            await store.send(\.destination.currencyPicker.delegate.currencySelected, "EUR") {
                $0.destination = nil
                $0.pendingCurrency = "EUR"
                $0.isLoadingConversionInfo = true
            }

            let pair = DefaultCurrencyPickerReducer.ConversionPair(
                date: DateComponents(year: 2025, month: 1, day: 10),
                fromCurrency: "USD",
                transactionCount: 1
            )

            await store.receive(\.conversionInfoLoaded) {
                $0.isLoadingConversionInfo = false
                $0.conversionInfo = DefaultCurrencyPickerReducer.ConversionInfo(
                    pairs: [pair],
                    transactionCount: 1
                )
                $0.fetchedRates[pair] = .loading
            }

            // First fetch fails - skip the exact state check due to date formatting in error message
            await store.skipReceivedActions()

            #expect(store.state.hasRateFetchError == true)
            #expect(store.state.allRatesFetched == false)
            // Verify it is indeed a failure
            if case .failure = store.state.fetchedRates[pair] {
                // Good - it's a failure as expected
            } else {
                Issue.record("Expected failure state but got: \(String(describing: store.state.fetchedRates[pair]))")
            }

            // Retry
            await store.send(\.view.retryFailedRatesTapped) {
                $0.fetchedRates[pair] = .loading
            }

            // Second fetch succeeds
            await store.receive(\.rateFetched) {
                $0.fetchedRates[pair] = .success(0.92)
            }

            #expect(store.state.hasRateFetchError == false)
            #expect(store.state.allRatesFetched == true)
        }

        // MARK: - Cancellation

        @Test("Cancellation resets all state")
        func cancellation_resetsState() async throws {
            @Dependency(\.date.now) var now
            try await database.write { db in
                try Transaction.insert {
                    Transaction.Draft(
                        description: "Test",
                        valueMinorUnits: 1000,
                        currencyCode: "USD",
                        type: .expense,
                        createdAtUTC: now,
                        localYear: 2025, localMonth: 1, localDay: 10
                    )
                }.execute(db)
            }

            let store = TestStore(
                initialState: DefaultCurrencyPickerReducer.State()
            ) {
                DefaultCurrencyPickerReducer()
            } withDependencies: {
                $0.exchangeRate.getRate = { _, _, _ in 0.92 }
            }

            await store.send(\.view.changeCurrencyButtonTapped) {
                $0.destination = .currencyPicker(CurrencyPicker.State(selectedCurrencyCode: "USD"))
            }

            await store.send(\.destination.currencyPicker.delegate.currencySelected, "EUR") {
                $0.destination = nil
                $0.pendingCurrency = "EUR"
                $0.isLoadingConversionInfo = true
            }

            let pair = DefaultCurrencyPickerReducer.ConversionPair(
                date: DateComponents(year: 2025, month: 1, day: 10),
                fromCurrency: "USD",
                transactionCount: 1
            )

            await store.receive(\.conversionInfoLoaded) {
                $0.isLoadingConversionInfo = false
                $0.conversionInfo = DefaultCurrencyPickerReducer.ConversionInfo(
                    pairs: [pair],
                    transactionCount: 1
                )
                $0.fetchedRates[pair] = .loading
            }

            await store.receive(\.rateFetched) {
                $0.fetchedRates[pair] = .success(0.92)
            }

            // Cancel before converting
            await store.send(\.view.cancelChangeTapped) {
                $0.pendingCurrency = nil
                $0.conversionInfo = nil
                $0.fetchedRates = [:]
                $0.conversionState = .idle
                $0.isLoadingConversionInfo = false
            }

            // Currency should still be USD
            #expect(store.state.defaultCurrency == "USD")
        }

        // MARK: - Selecting Same Currency

        @Test("Selecting same currency does nothing")
        func selectingSameCurrency_doesNothing() async throws {
            let store = TestStore(
                initialState: DefaultCurrencyPickerReducer.State()
            ) {
                DefaultCurrencyPickerReducer()
            }

            await store.send(\.view.changeCurrencyButtonTapped) {
                $0.destination = .currencyPicker(CurrencyPicker.State(selectedCurrencyCode: "USD"))
            }

            // Select USD (same as current)
            await store.send(\.destination.currencyPicker.delegate.currencySelected, "USD") {
                $0.destination = nil
                // No pending currency set, no loading started
            }

            #expect(store.state.pendingCurrency == nil)
            #expect(store.state.isLoadingConversionInfo == false)
        }

        // MARK: - Multiple Dates

        @Test("Conversion with transactions on multiple dates")
        func conversionWithMultipleDates() async throws {
            @Dependency(\.date.now) var now
            try await database.write { db in
                try Transaction.insert {
                    Transaction.Draft(
                        description: "Jan 10",
                        valueMinorUnits: 1000,
                        currencyCode: "USD",
                        type: .expense,
                        createdAtUTC: now,
                        localYear: 2025, localMonth: 1, localDay: 10
                    )
                }.execute(db)

                try Transaction.insert {
                    Transaction.Draft(
                        description: "Jan 15",
                        valueMinorUnits: 2000,
                        currencyCode: "USD",
                        type: .expense,
                        createdAtUTC: now,
                        localYear: 2025, localMonth: 1, localDay: 15
                    )
                }.execute(db)

                try Transaction.insert {
                    Transaction.Draft(
                        description: "Jan 20",
                        valueMinorUnits: 3000,
                        currencyCode: "USD",
                        type: .expense,
                        createdAtUTC: now,
                        localYear: 2025, localMonth: 1, localDay: 20
                    )
                }.execute(db)
            }

            let store = TestStore(
                initialState: DefaultCurrencyPickerReducer.State()
            ) {
                DefaultCurrencyPickerReducer()
            } withDependencies: {
                $0.exchangeRate.getRate = { _, _, date in
                    // Different rates for different dates
                    let calendar = Calendar.current
                    let day = calendar.component(.day, from: date)
                    switch day {
                    case 10: return 0.90
                    case 15: return 0.91
                    case 20: return 0.92
                    default: return 1.0
                    }
                }
            }

            await store.send(\.view.changeCurrencyButtonTapped) {
                $0.destination = .currencyPicker(CurrencyPicker.State(selectedCurrencyCode: "USD"))
            }

            await store.send(\.destination.currencyPicker.delegate.currencySelected, "EUR") {
                $0.destination = nil
                $0.pendingCurrency = "EUR"
                $0.isLoadingConversionInfo = true
            }

            await store.receive(\.conversionInfoLoaded) {
                $0.isLoadingConversionInfo = false
                // 3 pairs for 3 different dates
                $0.conversionInfo = DefaultCurrencyPickerReducer.ConversionInfo(
                    pairs: [
                        DefaultCurrencyPickerReducer.ConversionPair(
                            date: DateComponents(year: 2025, month: 1, day: 20),
                            fromCurrency: "USD",
                            transactionCount: 1
                        ),
                        DefaultCurrencyPickerReducer.ConversionPair(
                            date: DateComponents(year: 2025, month: 1, day: 15),
                            fromCurrency: "USD",
                            transactionCount: 1
                        ),
                        DefaultCurrencyPickerReducer.ConversionPair(
                            date: DateComponents(year: 2025, month: 1, day: 10),
                            fromCurrency: "USD",
                            transactionCount: 1
                        ),
                    ],
                    transactionCount: 3
                )
                for pair in $0.conversionInfo!.pairs {
                    $0.fetchedRates[pair] = .loading
                }
            }

            // Receive all rate fetches (exhaustivity off for ordering)
            await store.skipReceivedActions()

            await store.finish()

            #expect(store.state.allRatesFetched == true)
            #expect(store.state.conversionInfo?.pairs.count == 3)
        }

        // MARK: - Transactions Already in Target Currency Get Updated

        @Test("Transactions already in target currency get their converted values set")
        func transactionsInTargetCurrency_getConvertedValuesSet() async throws {
            // Mix of currencies - one in target, one not
            @Dependency(\.date.now) var now
            try await database.write { db in
                // Transaction in EUR (the target)
                try Transaction.insert {
                    Transaction.Draft(
                        description: "Already in EUR",
                        valueMinorUnits: 5000,
                        currencyCode: "EUR",
                        type: .expense,
                        createdAtUTC: now,
                        localYear: 2025, localMonth: 1, localDay: 15
                    )
                }.execute(db)

                // Transaction in USD (needs conversion)
                try Transaction.insert {
                    Transaction.Draft(
                        description: "In USD",
                        valueMinorUnits: 10000,
                        currencyCode: "USD",
                        type: .expense,
                        createdAtUTC: now,
                        localYear: 2025, localMonth: 1, localDay: 15
                    )
                }.execute(db)
            }

            let store = TestStore(
                initialState: DefaultCurrencyPickerReducer.State()
            ) {
                DefaultCurrencyPickerReducer()
            } withDependencies: {
                $0.exchangeRate.getRate = { _, _, _ in 0.92 }
            }

            await store.send(\.view.changeCurrencyButtonTapped) {
                $0.destination = .currencyPicker(CurrencyPicker.State(selectedCurrencyCode: "USD"))
            }

            await store.send(\.destination.currencyPicker.delegate.currencySelected, "EUR") {
                $0.destination = nil
                $0.pendingCurrency = "EUR"
                $0.isLoadingConversionInfo = true
            }

            // Only USD transaction needs rate fetch
            let pair = DefaultCurrencyPickerReducer.ConversionPair(
                date: DateComponents(year: 2025, month: 1, day: 15),
                fromCurrency: "USD",
                transactionCount: 1
            )

            await store.receive(\.conversionInfoLoaded) {
                $0.isLoadingConversionInfo = false
                $0.conversionInfo = DefaultCurrencyPickerReducer.ConversionInfo(
                    pairs: [pair],
                    transactionCount: 1
                )
                $0.fetchedRates[pair] = .loading
            }

            await store.receive(\.rateFetched) {
                $0.fetchedRates[pair] = .success(0.92)
            }

            await store.send(\.view.convertButtonTapped) {
                $0.conversionState = .converting
            }

            // Both transactions get updated (count = 2)
            await store.receive(\.conversionCompleted) {
                $0.conversionState = .success(convertedCount: 2)
                $0.$defaultCurrency.withLock { $0 = "EUR" }
            }

            // Verify EUR transaction has converted values set (same as original)
            let transactions = try await database.read { db in
                try Transaction.fetchAll(db)
            }

            let eurTransaction = transactions.first { $0.currencyCode == "EUR" }!
            #expect(eurTransaction.convertedCurrencyCode == "EUR")
            #expect(eurTransaction.convertedValueMinorUnits == 5000) // Same as original

            let usdTransaction = transactions.first { $0.currencyCode == "USD" }!
            #expect(usdTransaction.convertedCurrencyCode == "EUR")
            #expect(usdTransaction.convertedValueMinorUnits == 9200) // 10000 * 0.92
        }
    }
}
