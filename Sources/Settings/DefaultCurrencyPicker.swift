import ComposableArchitecture
import Currency
import IssueReporting
import Sharing
import SQLiteData
import SwiftUI

@Reducer
struct DefaultCurrencyPickerReducer: Reducer {

    /// Information about transactions that need conversion
    struct ConversionInfo: Equatable {
        /// Unique local dates (year, month, day) of transactions that need conversion
        let dates: [DateComponents]
        /// Total number of transactions that need conversion
        let transactionCount: Int

        var needsConversion: Bool { transactionCount > 0 }
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
        }
        case destination(PresentationAction<Destination.Action>)
        case view(View)
        case conversionInfoLoaded(ConversionInfo)
        case currencyChangedDirectly
    }

    @Dependency(\.defaultDatabase) private var database
    @Dependency(\.dismiss) private var dismiss

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
                } else {
                    // No transactions need conversion, update directly
                    if let pending = state.pendingCurrency {
                        state.$defaultCurrency.withLock { $0 = pending }
                        state.pendingCurrency = nil
                    }
                    return .send(.currencyChangedDirectly)
                }
                return .none

            case .currencyChangedDirectly:
                // Currency was changed without needing conversion
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
                    state.isLoadingConversionInfo = false
                    return .none
                }
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }

    private func fetchConversionInfo(targetCurrency: String) -> Effect<Action> {
        return .run { send in
            let info = try await database.read { db -> ConversionInfo in
                // Find all transactions where currencyCode != target currency
                // Group by unique dates
                let rows = try Transaction
                    .where { $0.currencyCode.neq(targetCurrency) }
                    .group { ($0.localYear, $0.localMonth, $0.localDay) }
                    .order { ($0.localYear.desc(), $0.localMonth.desc(), $0.localDay.desc()) }
                    .select { ($0.localYear, $0.localMonth, $0.localDay, $0.id.count()) }
                    .fetchAll(db)

                let dates = rows.map { row in
                    DateComponents(year: row.0, month: row.1, day: row.2)
                }

                let totalCount = rows.reduce(0) { $0 + $1.3 }

                return ConversionInfo(dates: dates, transactionCount: totalCount)
            }

            await send(.conversionInfoLoaded(info))
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
                transactionDatesSection(info: info, targetCurrency: currency)
            }

            Section {
                Button("Cancel", role: .destructive) {
                    send(.cancelChangeTapped)
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
            ForEach(info.dates, id: \.self) { dateComponents in
                HStack {
                    Text(formattedDate(from: dateComponents))

                    Spacer()

                    Image(systemName: "circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Transactions to Convert (\(info.transactionCount))")
        } footer: {
            Text("Exchange rates will be fetched for each date to convert transactions to \(targetCurrency.code).")
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
