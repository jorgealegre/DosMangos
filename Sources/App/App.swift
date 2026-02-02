import ComposableArchitecture
import CoreLocationClient
import Sharing
import SQLiteData
import SwiftUI

@Reducer
struct AppReducer: Reducer {

    @Reducer
    enum Destination {
        case transactionForm(TransactionFormReducer)
        case debugMenu
    }

    @ObservableState
    struct State: Equatable {
        @Presents var destination: Destination.State?

        // Just by declaring this property here, a load will start
        @SharedReader(.currentLocation) var currentLocation: GeocodedLocation?

        @FetchOne
        var userSettings: UserSettings?

        var appDelegate = AppDelegateReducer.State()
        var transactionsList: TransactionsList.State
        var recurringTransactionsList = RecurringTransactionsList.State()
        var transactionsMap = TransactionsMap.State()
        var settings = SettingsReducer.State()

        init() {
            @Dependency(\.date.now) var now
            self.transactionsList = TransactionsList.State(date: now)
        }
    }

    enum Action: ViewAction {
        @CasePathable
        enum View {
            case newTransactionButtonTapped
            case discardButtonTapped
            case task
            case shakeDetected
        }

        case appDelegate(AppDelegateReducer.Action)
        case transactionsList(TransactionsList.Action)
        case transactionsMap(TransactionsMap.Action)
        case settings(SettingsReducer.Action)
        case recurringTransactionsList(RecurringTransactionsList.Action)

        case destination(PresentationAction<Destination.Action>)
        case view(View)
    }

    @Dependency(\.locationManager) private var locationManager
    @Dependency(\.defaultDatabase) private var database
    @Dependency(\.exchangeRate) private var exchangeRate

    var body: some ReducerOf<Self> {
        Scope(state: \.appDelegate, action: \.appDelegate) {
            AppDelegateReducer()
        }

        Scope(state: \.transactionsList, action: \.transactionsList) {
            TransactionsList()
        }

        Scope(state: \.transactionsMap, action: \.transactionsMap) {
            TransactionsMap()
        }

        Scope(state: \.settings, action: \.settings) {
            SettingsReducer()
        }

        Scope(state: \.recurringTransactionsList, action: \.recurringTransactionsList) {
            RecurringTransactionsList()
        }

        Reduce { state, action in
            switch action {
            case .appDelegate(.didFinishLaunching):
                return .none

            case .appDelegate:
                return .none

            case .destination:
                return .none

            case .transactionsList:
                return .none

            case .transactionsMap:
                return .none

            case .settings:
                return .none

            case .recurringTransactionsList:
                return .none

            case let .view(view):
                switch view {
                case .discardButtonTapped:
                    state.destination = nil
                    return .none

                case .newTransactionButtonTapped:
                    guard let defaultCurrency = state.userSettings?.defaultCurrency else { return .none }

                    state.destination = .transactionForm(
                        TransactionFormReducer.State(
                            transaction: Transaction.Draft(currencyCode: defaultCurrency)
                        )
                    )
                    return .none

                case .task:
                    return .merge(
                        requestLocationPermissionIfNeeded(),
                        convertPendingTransactions()
                    )

                case .shakeDetected:
                    #if DEBUG || TESTFLIGHT
                    state.destination = .debugMenu
                    #endif
                    return .none
                }
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }

    // MARK: - Private Effects

    private func requestLocationPermissionIfNeeded() -> Effect<Action> {
        .run { _ in
            guard await locationManager.locationServicesEnabled() else { return }
            let status = await locationManager.authorizationStatus()
            if status == .notDetermined {
                await locationManager.requestWhenInUseAuthorization()
            }
        }
    }

    @Selection
    struct PendingRate: Hashable {
        let currency: String
        let year: Int
        let month: Int
        let day: Int
    }

    private func convertPendingTransactions() -> Effect<Action> {
        .run { _ in
            await withErrorReporting {
                // 1. Get default currency
                guard let defaultCurrency = try await database.read({ db in
                    try UserSettings.fetchOne(db)?.defaultCurrency
                }) else { return }

                // 2. Get unique (currency, year, month, day) combinations for pending transactions
                let pendingRates: [PendingRate] = try await database.read { db in
                    try Transaction
                        .where { $0.convertedValueMinorUnits.is(nil) }
                        .where { $0.currencyCode.neq(defaultCurrency) }
                        .distinct()
                        .select {
                            PendingRate.Columns(
                                currency: $0.currencyCode,
                                year: $0.localYear,
                                month: $0.localMonth,
                                day: $0.localDay
                            )
                        }
                        .fetchAll(db)
                }
                guard !pendingRates.isEmpty else { return }

                // 3. Fetch rates in parallel (one per unique currency+date)
                let rates: [(PendingRate, Double)] = await withTaskGroup(of: (PendingRate, Double)?.self) { group in
                    for pending in pendingRates {
                        group.addTask {
                            let date = Date.localDate(
                                year: pending.year,
                                month: pending.month,
                                day: pending.day
                            )!
                            guard let rate = try? await self.exchangeRate.getRate(
                                from: pending.currency,
                                to: defaultCurrency,
                                date: date
                            ) else { return nil }
                            return (pending, rate)
                        }
                    }

                    var result: [(PendingRate, Double)] = []
                    for await item in group {
                        if let item { result.append(item) }
                    }
                    return result
                }

                guard !rates.isEmpty else { return }

                // 4. Bulk update each (currency, date) group in a single transaction
                try await database.write { db in
                    for (pending, rate) in rates {
                        try Transaction
                            .where {
                                $0.convertedValueMinorUnits.is(nil) &&
                                $0.currencyCode.eq(pending.currency) &&
                                $0.localYear.eq(pending.year) &&
                                $0.localMonth.eq(pending.month) &&
                                $0.localDay.eq(pending.day)
                            }
                            .update {
                                $0.convertedValueMinorUnits = #sql("CAST(\($0.valueMinorUnits) * \(bind: rate) AS INTEGER)")
                                $0.convertedCurrencyCode = defaultCurrency
                            }
                            .execute(db)
                    }
                }
            }
        }
    }
}

extension AppReducer.Destination.State: Equatable {}

@ViewAction(for: AppReducer.self)
struct AppView: View {
    @Bindable var store: StoreOf<AppReducer>

    var body: some View {
        TabView {
            ZStack(alignment: .bottom) {
                TransactionsListView(
                    store: store.scope(
                        state: \.transactionsList,
                        action: \.transactionsList
                    )
                )

                addTransactionButton
            }
            .tabItem {
                Label("Transactions", systemImage: "list.bullet.rectangle.portrait")
            }

            RecurringTransactionsListView(
                store: store.scope(
                    state: \.recurringTransactionsList,
                    action: \.recurringTransactionsList
                )
            )
                .tabItem {
                    Label("Recurring", systemImage: "repeat.circle")
                }

            TransactionsMapView(
                store: store.scope(
                    state: \.transactionsMap,
                    action: \.transactionsMap
                )
            )
            .tabItem {
                Label("Map", systemImage: "map.fill")
            }

            SettingsView(
                store: store.scope(
                    state: \.settings,
                    action: \.settings
                )
            )
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .task { await send(.task).finish() }
        .sheet(item: $store.scope(
            state: \.destination?.transactionForm,
            action: \.destination.transactionForm
        )) { store in
            NavigationStack {
                TransactionFormView(store: store)
                    .navigationTitle("New transaction")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Discard") {
                                send(.discardButtonTapped)
                            }
                        }
                    }
            }
        }
        #if DEBUG || TESTFLIGHT
        .sheet(item: $store.scope(
            state: \.destination?.debugMenu,
            action: \.destination.debugMenu
        )) { _ in
            DebugMenuView()
        }
        .onShake {
            send(.shakeDetected)
        }
        #endif
    }

    @ViewBuilder
    private var addTransactionButton: some View {
        Button {
            send(.newTransactionButtonTapped)
        } label: {
            ZStack {
                Circle()
                    .fill(.purple)

                Image(systemName: "plus")
                    .font(.largeTitle)
                    .foregroundColor(.white)
            }
            .frame(width: 60, height: 60)
        }
        .padding()
    }
}

//struct AppPreview: PreviewProvider {
//    static var previews: some View {
//        let _ = try! prepareDependencies {
//            $0.defaultDatabase = try appDatabase()
//        }
//        AppView(store: Store(initialState: App.State()) {
//            App()
//        })
//        .tint(.purple)
//    }
//}

#Preview {
    let locale = Locale(identifier: "en_US")
//    let locale = Locale(identifier: "es_AR")
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
        try seedSampleData()
        $0.locale = locale
    }
    AppView(
        store: Store(initialState: AppReducer.State()) {
            AppReducer()
                ._printChanges()
        }
    )
//    .tint(.purple)
    .environment(\.locale, locale)
}
