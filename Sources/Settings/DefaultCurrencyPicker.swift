import ComposableArchitecture
import Currency
import Sharing
import SQLiteData
import SwiftUI

@Reducer
struct DefaultCurrencyPickerReducer: Reducer {

    /// Summary of what can be converted after fetching rates
    struct ConversionSummary: Equatable {
        /// Number of transactions that can be converted (have exchange rates)
        let convertibleCount: Int
        /// Number of transactions without available exchange rates
        let failedCount: Int
        /// Number of transactions already in the target currency
        let sameCurrencyCount: Int
        /// Exchange rates keyed by "year-month-day-currency"
        let rates: [String: Double]

        var totalCount: Int { convertibleCount + failedCount + sameCurrencyCount }
        var willConvertCount: Int { convertibleCount + sameCurrencyCount }
    }

    /// Result after performing conversion
    struct ConversionResult: Equatable {
        let convertedCount: Int
        let skippedCount: Int
        let newCurrency: String
    }

    /// The current phase of the currency change flow
    enum Phase: Equatable {
        case idle
        case fetchingRates(targetCurrency: String)
        case readyToConvert(targetCurrency: String, summary: ConversionSummary)
        case converting(targetCurrency: String)
        case completed(ConversionResult)
        case failed(String)
    }

    @Reducer
    enum Destination {
        case currencyPicker(CurrencyPicker)
    }

    @ObservableState
    struct State: Equatable {
        @Shared(.defaultCurrency) var defaultCurrency: String
        var phase: Phase = .idle
        @Presents var destination: Destination.State?

        init() {}
    }

    enum Action: ViewAction {
        @CasePathable
        enum View {
            case changeCurrencyButtonTapped
            case cancelTapped
            case confirmConversionTapped
            case doneTapped
        }
        case destination(PresentationAction<Destination.Action>)
        case view(View)
        case ratesFetched(targetCurrency: String, Result<ConversionSummary, Error>)
        case conversionCompleted(Result<ConversionResult, Error>)
    }

    private enum CancelID { case fetchRates }

    @Dependency(\.defaultDatabase) private var database
    @Dependency(\.exchangeRate) private var exchangeRate

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .destination(.dismiss):
                return .none

            case let .destination(.presented(.currencyPicker(.delegate(delegateAction)))):
                switch delegateAction {
                case let .currencySelected(currencyCode):
                    state.destination = nil
                    if currencyCode != state.defaultCurrency {
                        state.phase = .fetchingRates(targetCurrency: currencyCode)
                        return fetchRatesAndPrepare(targetCurrency: currencyCode)
                    }
                    return .none
                }

            case .destination:
                return .none

            case let .ratesFetched(targetCurrency, result):
                switch result {
                case let .success(summary):
                    // If conversion is straightforward (no rates needed), proceed automatically
                    let isSimpleConversion = summary.convertibleCount == 0 && summary.failedCount == 0
                    if isSimpleConversion {
                        state.phase = .converting(targetCurrency: targetCurrency)
                        return performConversion(targetCurrency: targetCurrency, rates: summary.rates)
                    }
                    state.phase = .readyToConvert(targetCurrency: targetCurrency, summary: summary)
                case let .failure(error):
                    state.phase = .failed(error.localizedDescription)
                }
                return .none

            case let .conversionCompleted(result):
                switch result {
                case let .success(conversionResult):
                    state.$defaultCurrency.withLock { $0 = conversionResult.newCurrency }
                    if conversionResult.convertedCount == 0 {
                        state.phase = .idle
                    } else {
                        state.phase = .completed(conversionResult)
                    }
                case let .failure(error):
                    state.phase = .failed(error.localizedDescription)
                }
                return .none

            case let .view(view):
                switch view {
                case .changeCurrencyButtonTapped:
                    state.destination = .currencyPicker(CurrencyPicker.State(
                        selectedCurrencyCode: state.defaultCurrency
                    ))
                    return .none

                case .cancelTapped:
                    state.phase = .idle
                    return .cancel(id: CancelID.fetchRates)

                case .confirmConversionTapped:
                    guard case let .readyToConvert(targetCurrency, summary) = state.phase else {
                        return .none
                    }
                    state.phase = .converting(targetCurrency: targetCurrency)
                    return performConversion(targetCurrency: targetCurrency, rates: summary.rates)

                case .doneTapped:
                    state.phase = .idle
                    return .none
                }
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }

    // MARK: - Effects

    /// Fetches all exchange rates needed for conversion and returns a summary
    private func fetchRatesAndPrepare(targetCurrency: String) -> Effect<Action> {
        .run { send in
            do {
                // 1. Get unique (date, currency) pairs needing rates
                let pairs = try await database.read { db in
                    try Transaction
                        .where { $0.currencyCode.neq(targetCurrency) }
                        .group { ($0.localYear, $0.localMonth, $0.localDay, $0.currencyCode) }
                        .select { ($0.localYear, $0.localMonth, $0.localDay, $0.currencyCode, $0.id.count()) }
                        .fetchAll(db)
                }

                // 2. Fetch rates in parallel, continuing on failures
                var rates: [String: Double] = [:]
                var convertibleCount = 0
                var failedCount = 0

                await withTaskGroup(of: (String, Int, Double?).self) { group in
                    for pair in pairs {
                        let (year, month, day, currency, count) = pair
                        group.addTask {
                            let key = "\(year)-\(month)-\(day)-\(currency)"
                            guard let date = Date.localDate(year: year, month: month, day: day) else {
                                return (key, count, nil)
                            }
                            do {
                                let rate = try await exchangeRate.getRate(currency, targetCurrency, date)
                                return (key, count, rate)
                            } catch {
                                return (key, count, nil)
                            }
                        }
                    }

                    for await (key, count, rate) in group {
                        if let rate {
                            rates[key] = rate
                            convertibleCount += count
                        } else {
                            failedCount += count
                        }
                    }
                }

                // 3. Count same-currency transactions
                let sameCurrencyCount = try await database.read { db in
                    try Transaction
                        .where { $0.currencyCode.eq(targetCurrency) }
                        .select { $0.id.count() }
                        .fetchOne(db) ?? 0
                }

                let summary = ConversionSummary(
                    convertibleCount: convertibleCount,
                    failedCount: failedCount,
                    sameCurrencyCount: sameCurrencyCount,
                    rates: rates
                )

                await send(.ratesFetched(targetCurrency: targetCurrency, .success(summary)))
            } catch {
                await send(.ratesFetched(targetCurrency: targetCurrency, .failure(error)))
            }
        }
        .cancellable(id: CancelID.fetchRates)
    }

    /// Performs the actual conversion using bulk updates
    private func performConversion(targetCurrency: String, rates: [String: Double]) -> Effect<Action> {
        .run { send in
            do {
                let result = try await database.write { db -> ConversionResult in
                    // 1. Bulk update same-currency transactions (converted = original)
                    // Single SQL statement instead of fetching + looping
                    try #sql("""
                    UPDATE \(Transaction.self)
                    SET \(quote: Transaction.columns.convertedValueMinorUnits.name) = \(quote: Transaction.columns.valueMinorUnits.name),
                        \(quote: Transaction.columns.convertedCurrencyCode.name) = \(bind: targetCurrency)
                    WHERE \(Transaction.columns.currencyCode) = \(bind: targetCurrency)
                    """).execute(db)

                    let sameCurrencyCount = try Transaction
                        .where { $0.currencyCode.eq(targetCurrency) }
                        .select { $0.id.count() }
                        .fetchOne(db) ?? 0

                    // 2. Clear converted values for all different-currency transactions first
                    // This handles transactions without rates in a single bulk operation
                    try #sql("""
                    UPDATE \(Transaction.self)
                    SET \(quote: Transaction.columns.convertedValueMinorUnits.name) = NULL,
                        \(quote: Transaction.columns.convertedCurrencyCode.name) = NULL
                    WHERE \(Transaction.columns.currencyCode) != \(bind: targetCurrency)
                    """).execute(db)

                    // 3. Update transactions that have rates, grouped by (year, month, day, currency)
                    // Each rate key maps to one bulk update instead of N individual updates
                    var convertedWithRateCount = 0
                    for (key, rate) in rates {
                        // Parse key format: "year-month-day-currency"
                        let parts = key.split(separator: "-")
                        guard parts.count == 4,
                              let year = Int(parts[0]),
                              let month = Int(parts[1]),
                              let day = Int(parts[2]) else {
                            continue
                        }
                        let currency = String(parts[3])

                        // Bulk update all transactions matching this (date, currency) combination
                        try #sql("""
                        UPDATE \(Transaction.self)
                        SET \(quote: Transaction.columns.convertedValueMinorUnits.name) = CAST(\(quote: Transaction.columns.valueMinorUnits.name) * \(bind: rate) AS INTEGER),
                            \(quote: Transaction.columns.convertedCurrencyCode.name) = \(bind: targetCurrency)
                        WHERE \(Transaction.columns.localYear) = \(bind: year)
                          AND \(Transaction.columns.localMonth) = \(bind: month)
                          AND \(Transaction.columns.localDay) = \(bind: day)
                          AND \(Transaction.columns.currencyCode) = \(bind: currency)
                        """).execute(db)

                        // Count how many transactions were updated for this key
                        let count = try Transaction
                            .where {
                                $0.localYear.eq(year) &&
                                $0.localMonth.eq(month) &&
                                $0.localDay.eq(day) &&
                                $0.currencyCode.eq(currency)
                            }
                            .select { $0.id.count() }
                            .fetchOne(db) ?? 0
                        convertedWithRateCount += count
                    }

                    // Count transactions that remain without conversion (nil converted values)
                    let skippedCount = try Transaction
                        .where { $0.convertedValueMinorUnits.is(nil) }
                        .select { $0.id.count() }
                        .fetchOne(db) ?? 0

                    return ConversionResult(
                        convertedCount: sameCurrencyCount + convertedWithRateCount,
                        skippedCount: skippedCount,
                        newCurrency: targetCurrency
                    )
                }

                await send(.conversionCompleted(.success(result)))
            } catch {
                await send(.conversionCompleted(.failure(error)))
            }
        }
    }
}

extension DefaultCurrencyPickerReducer.Destination.State: Equatable {}

@ViewAction(for: DefaultCurrencyPickerReducer.self)
struct DefaultCurrencyPickerView: View {
    @Bindable var store: StoreOf<DefaultCurrencyPickerReducer>

    var body: some View {
        List {
            currentCurrencySection

            switch store.phase {
            case .idle:
                EmptyView()

            case let .fetchingRates(targetCurrency):
                fetchingRatesSection(targetCurrency: targetCurrency)

            case let .readyToConvert(targetCurrency, summary):
                readyToConvertSection(targetCurrency: targetCurrency, summary: summary)

            case let .converting(targetCurrency):
                convertingSection(targetCurrency: targetCurrency)

            case let .completed(result):
                completedSection(result: result)

            case let .failed(message):
                failedSection(message: message)
            }
        }
        .navigationTitle("Default Currency")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(
            item: $store.scope(
                state: \.destination?.currencyPicker,
                action: \.destination.currencyPicker
            )
        ) { store in
            NavigationStack {
                CurrencyPickerView(store: store)
            }
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var currentCurrencySection: some View {
        Section {
            Button {
                send(.changeCurrencyButtonTapped)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Currency")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let currency = CurrencyRegistry.all[store.defaultCurrency] {
                            Text(currency.name)
                                .font(.headline)
                            Text(currency.code)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(store.defaultCurrency)
                                .font(.headline)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.phase != .idle && !isCompleted(store.phase))
        } footer: {
            Text("All transactions are converted to this currency for totals and reports.")
        }
    }

    @ViewBuilder
    private func fetchingRatesSection(targetCurrency: String) -> some View {
        if let currency = CurrencyRegistry.all[targetCurrency] {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preparing to change to \(currency.name)")
                            .font(.subheadline)
                        Text("Fetching exchange rates...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            cancelSection
        }
    }

    @ViewBuilder
    private func readyToConvertSection(
        targetCurrency: String,
        summary: DefaultCurrencyPickerReducer.ConversionSummary
    ) -> some View {
        if let currency = CurrencyRegistry.all[targetCurrency] {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        Text("Change to \(currency.name) (\(currency.code))")
                            .font(.headline)
                    } icon: {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(.blue)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        if summary.willConvertCount > 0 {
                            Label {
                                Text("\(summary.willConvertCount) transactions ready to convert")
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            .font(.subheadline)
                        }

                        if summary.failedCount > 0 {
                            Label {
                                Text("\(summary.failedCount) transactions without exchange rates")
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                            .font(.subheadline)

                            Text("These will remain in their original currency until rates are available.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 28)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Pending Change")
            }

            if summary.willConvertCount > 0 {
                Section {
                    Button {
                        send(.confirmConversionTapped)
                    } label: {
                        Text("Convert \(summary.willConvertCount) Transactions")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }

            cancelSection
        }
    }

    @ViewBuilder
    private func convertingSection(targetCurrency: String) -> some View {
        if let currency = CurrencyRegistry.all[targetCurrency] {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Converting to \(currency.name)")
                            .font(.subheadline)
                        Text("Please wait...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func completedSection(result: DefaultCurrencyPickerReducer.ConversionResult) -> some View {
        if let currency = CurrencyRegistry.all[result.newCurrency] {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)

                    Text("Conversion Complete")
                        .font(.headline)

                    Text("\(result.convertedCount) transactions converted to \(currency.code)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if result.skippedCount > 0 {
                        Text("\(result.skippedCount) transactions skipped (no exchange rate)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }

            Section {
                Button {
                    send(.doneTapped)
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
    }

    @ViewBuilder
    private func failedSection(message: String) -> some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)

                Text("Conversion Failed")
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }

        cancelSection
    }

    @ViewBuilder
    private var cancelSection: some View {
        Section {
            Button("Cancel", role: .destructive) {
                send(.cancelTapped)
            }
        }
    }

    // MARK: - Helpers

    private func isCompleted(_ phase: DefaultCurrencyPickerReducer.Phase) -> Bool {
        if case .completed = phase { return true }
        return false
    }
}

#Preview {
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
        try seedSampleData()
    }
    NavigationStack {
        DefaultCurrencyPickerView(
            store: Store(initialState: DefaultCurrencyPickerReducer.State()) {
                DefaultCurrencyPickerReducer()
                    ._printChanges()
            }
        )
    }
}
