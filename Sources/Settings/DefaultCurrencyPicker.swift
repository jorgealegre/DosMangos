import ComposableArchitecture
import Currency
import IssueReporting
import Sharing
import SQLiteData
import SwiftUI

@Reducer
struct DefaultCurrencyPickerReducer: Reducer {

    /// A unique (date, currency) pair that needs an exchange rate
    struct ConversionPair: Equatable, Hashable {
        let date: DateComponents
        let fromCurrency: String
        /// Number of transactions with this pair
        let transactionCount: Int

        var dateValue: Date? {
            guard let year = date.year, let month = date.month, let day = date.day else {
                return nil
            }
            return Date.localDate(year: year, month: month, day: day)
        }
    }

    /// Information about transactions that need conversion
    struct ConversionInfo: Equatable {
        /// Unique (date, currency) pairs that need exchange rates
        let pairs: [ConversionPair]
        /// Total number of transactions that need conversion
        let transactionCount: Int

        var needsConversion: Bool { transactionCount > 0 }
    }

    /// Result of fetching a rate for a pair
    enum RateFetchResult: Equatable {
        case loading
        case success(Double)
        case failure(String)
    }

    /// State of the conversion process
    enum ConversionState: Equatable {
        case idle
        case converting
        case success(convertedCount: Int)
        case failure(String)
    }

    @Reducer
    enum Destination {
        case currencyPicker(CurrencyPicker)
    }

    @ObservableState
    struct State: Equatable {
        @Shared(.defaultCurrency) var defaultCurrency: String

        /// The currency the user wants to switch to (nil if no change pending)
        var pendingCurrency: String?

        /// Loading state for conversion info
        var isLoadingConversionInfo = false

        /// Information about what needs to be converted (nil until loaded)
        var conversionInfo: ConversionInfo?

        /// Fetched exchange rates keyed by ConversionPair
        var fetchedRates: [ConversionPair: RateFetchResult] = [:]

        /// Whether all rates have been fetched successfully
        var allRatesFetched: Bool {
            guard let info = conversionInfo else { return false }
            return info.pairs.allSatisfy { pair in
                if case .success = fetchedRates[pair] {
                    return true
                }
                return false
            }
        }

        /// Whether any rate fetch failed
        var hasRateFetchError: Bool {
            fetchedRates.values.contains { result in
                if case .failure = result { return true }
                return false
            }
        }

        /// State of the conversion process
        var conversionState: ConversionState = .idle

        @Presents var destination: Destination.State?

        /// The currency to display (pending takes precedence for showing what will be converted to)
        var displayCurrency: String {
            pendingCurrency ?? defaultCurrency
        }

        /// Whether a currency change is pending
        var hasPendingChange: Bool {
            pendingCurrency != nil && pendingCurrency != defaultCurrency
        }

        init() {}
    }

    enum Action: ViewAction {
        enum View {
            case changeCurrencyButtonTapped
            case cancelChangeTapped
            case retryFailedRatesTapped
            case convertButtonTapped
            case doneButtonTapped
        }
        case destination(PresentationAction<Destination.Action>)
        case view(View)
        case conversionInfoLoaded(ConversionInfo)
        case currencyChangedDirectly
        case rateFetched(ConversionPair, Result<Double, Error>)
        case conversionCompleted(Result<Int, Error>)
    }

    @Dependency(\.defaultDatabase) private var database
    @Dependency(\.dismiss) private var dismiss
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
                        state.pendingCurrency = currencyCode
                        state.isLoadingConversionInfo = true
                        state.conversionInfo = nil
                        return fetchConversionInfo(targetCurrency: currencyCode)
                    }
                    return .none
                }

            case .destination:
                return .none

            case let .conversionInfoLoaded(info):
                state.isLoadingConversionInfo = false
                if info.needsConversion {
                    state.conversionInfo = info
                    // Initialize all pairs as loading
                    for pair in info.pairs {
                        state.fetchedRates[pair] = .loading
                    }
                    // Start fetching rates in parallel
                    guard let targetCurrency = state.pendingCurrency else { return .none }
                    return fetchRates(pairs: info.pairs, targetCurrency: targetCurrency)
                } else {
                    // No transactions need conversion, update directly
                    if let pending = state.pendingCurrency {
                        state.$defaultCurrency.withLock { $0 = pending }
                        state.pendingCurrency = nil
                    }
                    return .send(.currencyChangedDirectly)
                }

            case .currencyChangedDirectly:
                // Currency was changed without needing conversion
                return .none

            case let .rateFetched(pair, result):
                switch result {
                case let .success(rate):
                    state.fetchedRates[pair] = .success(rate)
                case let .failure(error):
                    state.fetchedRates[pair] = .failure(error.localizedDescription)
                }
                return .none

            case let .conversionCompleted(result):
                switch result {
                case let .success(count):
                    state.conversionState = .success(convertedCount: count)
                    // Update the default currency
                    if let pending = state.pendingCurrency {
                        state.$defaultCurrency.withLock { $0 = pending }
                    }
                case let .failure(error):
                    state.conversionState = .failure(error.localizedDescription)
                }
                return .none

            case let .view(view):
                switch view {
                case .changeCurrencyButtonTapped:
                    state.destination = .currencyPicker(CurrencyPicker.State(
                        selectedCurrencyCode: state.displayCurrency
                    ))
                    return .none

                case .cancelChangeTapped:
                    state.pendingCurrency = nil
                    state.conversionInfo = nil
                    state.fetchedRates = [:]
                    state.conversionState = .idle
                    state.isLoadingConversionInfo = false
                    return .none

                case .retryFailedRatesTapped:
                    guard let info = state.conversionInfo,
                          let targetCurrency = state.pendingCurrency else { return .none }
                    // Find pairs that failed
                    let failedPairs = info.pairs.filter { pair in
                        if case .failure = state.fetchedRates[pair] { return true }
                        return false
                    }
                    // Reset them to loading and retry
                    for pair in failedPairs {
                        state.fetchedRates[pair] = .loading
                    }
                    return fetchRates(pairs: failedPairs, targetCurrency: targetCurrency)

                case .convertButtonTapped:
                    guard let targetCurrency = state.pendingCurrency else { return .none }
                    state.conversionState = .converting
                    // Build a lookup dictionary from (year, month, day, currency) -> rate
                    var rateLookup: [String: Double] = [:]
                    for (pair, result) in state.fetchedRates {
                        if case let .success(rate) = result,
                           let year = pair.date.year,
                           let month = pair.date.month,
                           let day = pair.date.day {
                            let key = "\(year)-\(month)-\(day)-\(pair.fromCurrency)"
                            rateLookup[key] = rate
                        }
                    }
                    return convertTransactions(targetCurrency: targetCurrency, rateLookup: rateLookup)

                case .doneButtonTapped:
                    // Reset state and stay on screen with new currency
                    state.pendingCurrency = nil
                    state.conversionInfo = nil
                    state.fetchedRates = [:]
                    state.conversionState = .idle
                    return .none
                }
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }

    private func fetchConversionInfo(targetCurrency: String) -> Effect<Action> {
        return .run { send in
            let info = try await database.read { db -> ConversionInfo in
                // Find all unique (date, currency) pairs where currencyCode != target currency
                let rows = try Transaction
                    .where { $0.currencyCode.neq(targetCurrency) }
                    .group { ($0.localYear, $0.localMonth, $0.localDay, $0.currencyCode) }
                    .order { ($0.localYear.desc(), $0.localMonth.desc(), $0.localDay.desc(), $0.currencyCode) }
                    .select { ($0.localYear, $0.localMonth, $0.localDay, $0.currencyCode, $0.id.count()) }
                    .fetchAll(db)

                let pairs = rows.map { row in
                    ConversionPair(
                        date: DateComponents(year: row.0, month: row.1, day: row.2),
                        fromCurrency: row.3,
                        transactionCount: row.4
                    )
                }

                let totalCount = rows.reduce(0) { $0 + $1.4 }

                return ConversionInfo(pairs: pairs, transactionCount: totalCount)
            }

            await send(.conversionInfoLoaded(info))
        }
    }

    private func fetchRates(pairs: [ConversionPair], targetCurrency: String) -> Effect<Action> {
        return .run { send in
            await withTaskGroup(of: (ConversionPair, Result<Double, Error>).self) { group in
                for pair in pairs {
                    group.addTask {
                        guard let date = pair.dateValue else {
                            return (pair, .failure(ExchangeRateError.rateNotAvailable(
                                from: pair.fromCurrency,
                                to: targetCurrency,
                                date: Date()
                            )))
                        }

                        do {
                            let rate = try await exchangeRate.getRate(
                                pair.fromCurrency,
                                targetCurrency,
                                date
                            )
                            return (pair, .success(rate))
                        } catch {
                            return (pair, .failure(error))
                        }
                    }
                }

                for await (pair, result) in group {
                    await send(.rateFetched(pair, result))
                }
            }
        }
    }

    private func convertTransactions(
        targetCurrency: String,
        rateLookup: [String: Double]
    ) -> Effect<Action> {
        return .run { send in
            do {
                let convertedCount = try await database.write { db -> Int in
                    // Fetch all transactions that need conversion
                    let transactions = try Transaction
                        .where { $0.currencyCode.neq(targetCurrency) }
                        .fetchAll(db)

                    var count = 0
                    for transaction in transactions {
                        let key = "\(transaction.localYear)-\(transaction.localMonth)-\(transaction.localDay)-\(transaction.currencyCode)"

                        guard let rate = rateLookup[key] else {
                            // Skip transactions without a rate (shouldn't happen if UI is correct)
                            continue
                        }

                        let convertedValue = Int(Double(transaction.valueMinorUnits) * rate)

                        try Transaction
                            .where { $0.id.eq(transaction.id) }
                            .update {
                                $0.convertedValueMinorUnits = convertedValue
                                $0.convertedCurrencyCode = targetCurrency
                            }
                            .execute(db)

                        count += 1
                    }

                    // Also update transactions that are already in the target currency
                    // (set converted = original)
                    let sameTransactions = try Transaction
                        .where { $0.currencyCode.eq(targetCurrency) }
                        .fetchAll(db)

                    for transaction in sameTransactions {
                        try Transaction
                            .where { $0.id.eq(transaction.id) }
                            .update {
                                $0.convertedValueMinorUnits = transaction.valueMinorUnits
                                $0.convertedCurrencyCode = targetCurrency
                            }
                            .execute(db)
                    }

                    return count + sameTransactions.count
                }

                await send(.conversionCompleted(.success(convertedCount)))
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

            if store.hasPendingChange {
                pendingChangeSection
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
        } footer: {
            Text("All transactions are converted to this currency for totals and reports.")
        }
    }

    @ViewBuilder
    private var pendingChangeSection: some View {
        if let pendingCode = store.pendingCurrency,
           let currency = CurrencyRegistry.all[pendingCode] {

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("Change to \(currency.name) (\(currency.code))")
                            .font(.headline)
                    } icon: {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Pending Change")
            }

            if store.isLoadingConversionInfo {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading transactions...")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let info = store.conversionInfo {
                switch store.conversionState {
                case .idle:
                    transactionDatesSection(info: info, targetCurrency: currency)

                    if store.allRatesFetched {
                        Section {
                            Button {
                                send(.convertButtonTapped)
                            } label: {
                                Text("Convert \(info.transactionCount) Transactions")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                        }
                    }

                case .converting:
                    Section {
                        HStack {
                            ProgressView()
                            Text("Converting transactions...")
                                .foregroundStyle(.secondary)
                        }
                    }

                case let .success(convertedCount):
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.green)

                            Text("Conversion Complete")
                                .font(.headline)

                            Text("\(convertedCount) transactions converted to \(currency.code)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }

                    Section {
                        Button {
                            send(.doneButtonTapped)
                        } label: {
                            Text("Done")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }

                case let .failure(errorMessage):
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.red)

                            Text("Conversion Failed")
                                .font(.headline)

                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                }
            }

            // Only show cancel when not in success state
            if case .success = store.conversionState {
                // Don't show cancel
            } else {
                Section {
                    Button("Cancel", role: .destructive) {
                        send(.cancelChangeTapped)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func transactionDatesSection(
        info: DefaultCurrencyPickerReducer.ConversionInfo,
        targetCurrency: Currency
    ) -> some View {
        Section {
            ForEach(info.pairs, id: \.self) { pair in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formattedDate(from: pair.date))
                        Text("\(pair.fromCurrency) → \(targetCurrency.code)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    rateView(for: pair)
                }
            }
        } header: {
            Text("Exchange Rates (\(info.pairs.count))")
        } footer: {
            if store.hasRateFetchError {
                Button {
                    send(.retryFailedRatesTapped)
                } label: {
                    Label("Retry Failed", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
            } else {
                Text("\(info.transactionCount) transactions will be converted to \(targetCurrency.code).")
            }
        }
    }

    @ViewBuilder
    private func rateView(for pair: DefaultCurrencyPickerReducer.ConversionPair) -> some View {
        switch store.fetchedRates[pair] {
        case .loading, .none:
            ProgressView()
                .scaleEffect(0.8)
        case let .success(rate):
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(formatRate(rate))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failure:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func formattedDate(from components: DateComponents) -> String {
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let date = Date.localDate(year: year, month: month, day: day) else {
            return "Unknown date"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func formatRate(_ rate: Double) -> String {
        if rate >= 1 {
            return String(format: "%.2f", rate)
        } else {
            return String(format: "%.6f", rate)
        }
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
