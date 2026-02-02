import ComposableArchitecture
import ConcurrencyExtras
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@testable import DosMangos

extension BaseTestSuite {
    @MainActor
    @Suite(.dependencies)
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
            #expect(store.state.phase == .idle)

            // Open currency picker
            await store.send(\.view.changeCurrencyButtonTapped) {
                $0.destination = .currencyPicker(CurrencyPicker.State(selectedCurrencyCode: "USD"))
            }

            // Select EUR
            await store.send(\.destination.currencyPicker.delegate.currencySelected, "EUR") {
                $0.destination = nil
                $0.phase = .fetchingRates(targetCurrency: "EUR")
            }

            // No transactions to convert, so conversion happens automatically
            await store.receive(\.ratesFetched) {
                $0.phase = .converting(targetCurrency: "EUR")
            }

            await store.receive(\.conversionCompleted) {
                $0.phase = .idle
            }

            // Wait for database write effect to complete
            await store.finish()

            #expect(store.state.defaultCurrency == "EUR")
        }

        @Test("When all transactions are already in target currency, updates converted values")
        func allTransactionsInTargetCurrency_updatesConvertedValues() async throws {
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
                $0.phase = .fetchingRates(targetCurrency: "EUR")
            }

            // All transactions already in EUR, no rates needed - conversion happens automatically
            await store.receive(\.ratesFetched, timeout: .seconds(1)) {
                $0.phase = .converting(targetCurrency: "EUR")
            }

            await store.receive(\.conversionCompleted) {
                $0.phase = .completed(DefaultCurrencyPickerReducer.ConversionResult(
                    convertedCount: 1,
                    skippedCount: 0,
                    newCurrency: "EUR"
                ))
            }

            // Wait for database write effect to complete
            await store.finish()

            // Verify the transaction now has converted values set
            let transactions = try await database.read { db in
                try Transaction.fetchAll(db)
            }

            let eurTransaction = transactions.first!
            #expect(eurTransaction.convertedCurrencyCode == "EUR")
            #expect(eurTransaction.convertedValueMinorUnits == 500) // Same as original
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
                $0.phase = .fetchingRates(targetCurrency: "EUR")
            }

            // Rates fetched - both USD and ARS have rates
            await store.receive(\.ratesFetched) {
                $0.phase = .readyToConvert(
                    targetCurrency: "EUR",
                    summary: DefaultCurrencyPickerReducer.ConversionSummary(
                        convertibleCount: 2,
                        failedCount: 0,
                        sameCurrencyCount: 0,
                        rates: [
                            "2025-1-15-USD": 0.92,
                            "2025-1-15-ARS": 0.00092
                        ]
                    )
                )
            }

            // User taps convert
            await store.send(\.view.confirmConversionTapped) {
                $0.phase = .converting(targetCurrency: "EUR")
            }

            await store.receive(\.conversionCompleted) {
                $0.phase = .completed(DefaultCurrencyPickerReducer.ConversionResult(
                    convertedCount: 2,
                    skippedCount: 0,
                    newCurrency: "EUR"
                ))
            }

            // Wait for database write effect to complete
            await store.finish()

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
            await store.send(\.view.doneTapped) {
                $0.phase = .idle
            }
        }

        // MARK: - Rate Fetch Failures (Partial Success)

        @Test("When some rates fail, shows summary with failed count and allows conversion of successful ones")
        func partialRateFetchFailure_allowsPartialConversion() async throws {
            @Dependency(\.date.now) var now
            try await database.write { db in
                // Transaction that will get a rate
                try Transaction.insert {
                    Transaction.Draft(
                        description: "USD Transaction",
                        valueMinorUnits: 1000,
                        currencyCode: "USD",
                        type: .expense,
                        createdAtUTC: now,
                        localYear: 2025, localMonth: 1, localDay: 10
                    )
                }.execute(db)

                // Transaction that will fail to get a rate
                try Transaction.insert {
                    Transaction.Draft(
                        description: "GBP Transaction",
                        valueMinorUnits: 2000,
                        currencyCode: "GBP",
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
                $0.exchangeRate.getRate = { from, _, _ in
                    if from == "USD" { return 0.92 }
                    // GBP fails
                    throw ExchangeRateError.rateNotAvailable(from: from, to: "EUR", date: Date())
                }
            }

            await store.send(\.view.changeCurrencyButtonTapped) {
                $0.destination = .currencyPicker(CurrencyPicker.State(selectedCurrencyCode: "USD"))
            }

            await store.send(\.destination.currencyPicker.delegate.currencySelected, "EUR") {
                $0.destination = nil
                $0.phase = .fetchingRates(targetCurrency: "EUR")
            }

            // One rate succeeded, one failed
            await store.receive(\.ratesFetched) {
                $0.phase = .readyToConvert(
                    targetCurrency: "EUR",
                    summary: DefaultCurrencyPickerReducer.ConversionSummary(
                        convertibleCount: 1,
                        failedCount: 1,
                        sameCurrencyCount: 0,
                        rates: ["2025-1-10-USD": 0.92]
                    )
                )
            }

            // User still confirms conversion for the successful ones
            await store.send(\.view.confirmConversionTapped) {
                $0.phase = .converting(targetCurrency: "EUR")
            }

            await store.receive(\.conversionCompleted) {
                $0.phase = .completed(DefaultCurrencyPickerReducer.ConversionResult(
                    convertedCount: 1,
                    skippedCount: 1,
                    newCurrency: "EUR"
                ))
            }

            // Wait for database write effect to complete
            await store.finish()

            // Verify only USD transaction was converted
            let transactions = try await database.read { db in
                try Transaction.fetchAll(db)
            }

            let usdTransaction = transactions.first { $0.currencyCode == "USD" }!
            #expect(usdTransaction.convertedCurrencyCode == "EUR")
            #expect(usdTransaction.convertedValueMinorUnits == 920)

            let gbpTransaction = transactions.first { $0.currencyCode == "GBP" }!
            #expect(gbpTransaction.convertedCurrencyCode == nil) // Cleared for later retry
            #expect(gbpTransaction.convertedValueMinorUnits == nil)
        }

        // MARK: - Cancellation

        @Test("Cancellation resets state to idle")
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
                $0.phase = .fetchingRates(targetCurrency: "EUR")
            }

            await store.receive(\.ratesFetched, timeout: .seconds(1)) {
                $0.phase = .readyToConvert(
                    targetCurrency: "EUR",
                    summary: DefaultCurrencyPickerReducer.ConversionSummary(
                        convertibleCount: 1,
                        failedCount: 0,
                        sameCurrencyCount: 0,
                        rates: ["2025-1-10-USD": 0.92]
                    )
                )
            }

            // Cancel before converting
            await store.send(\.view.cancelTapped) {
                $0.phase = .idle
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
                // Phase stays idle, no fetching started
            }

            #expect(store.state.phase == .idle)
        }

        // MARK: - Multiple Dates

        @Test("Conversion with transactions on multiple dates uses correct rates")
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
                $0.phase = .fetchingRates(targetCurrency: "EUR")
            }

            await store.receive(\.ratesFetched) {
                $0.phase = .readyToConvert(
                    targetCurrency: "EUR",
                    summary: DefaultCurrencyPickerReducer.ConversionSummary(
                        convertibleCount: 3,
                        failedCount: 0,
                        sameCurrencyCount: 0,
                        rates: [
                            "2025-1-10-USD": 0.90,
                            "2025-1-15-USD": 0.91,
                            "2025-1-20-USD": 0.92
                        ]
                    )
                )
            }

            await store.send(\.view.confirmConversionTapped) {
                $0.phase = .converting(targetCurrency: "EUR")
            }

            await store.receive(\.conversionCompleted) {
                $0.phase = .completed(DefaultCurrencyPickerReducer.ConversionResult(
                    convertedCount: 3,
                    skippedCount: 0,
                    newCurrency: "EUR"
                ))
            }

            // Wait for database write effect to complete
            await store.finish()

            // Verify each transaction used the correct rate
            let transactions = try await database.read { db in
                try Transaction.fetchAll(db)
            }

            let jan10 = transactions.first { $0.description == "Jan 10" }!
            #expect(jan10.convertedValueMinorUnits == 900)  // 1000 * 0.90

            let jan15 = transactions.first { $0.description == "Jan 15" }!
            #expect(jan15.convertedValueMinorUnits == 1820) // 2000 * 0.91

            let jan20 = transactions.first { $0.description == "Jan 20" }!
            #expect(jan20.convertedValueMinorUnits == 2760) // 3000 * 0.92
        }

        // MARK: - Mixed Currencies

        @Test("Transactions already in target currency get their converted values set during conversion")
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
                $0.phase = .fetchingRates(targetCurrency: "EUR")
            }

            // 1 USD transaction needs rate, 1 EUR transaction is same-currency
            await store.receive(\.ratesFetched) {
                $0.phase = .readyToConvert(
                    targetCurrency: "EUR",
                    summary: DefaultCurrencyPickerReducer.ConversionSummary(
                        convertibleCount: 1,
                        failedCount: 0,
                        sameCurrencyCount: 1,
                        rates: ["2025-1-15-USD": 0.92]
                    )
                )
            }

            await store.send(\.view.confirmConversionTapped) {
                $0.phase = .converting(targetCurrency: "EUR")
            }

            // Both transactions get updated (count = 2)
            await store.receive(\.conversionCompleted) {
                $0.phase = .completed(DefaultCurrencyPickerReducer.ConversionResult(
                    convertedCount: 2,
                    skippedCount: 0,
                    newCurrency: "EUR"
                ))
            }

            // Wait for database write effect to complete
            await store.finish()

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
