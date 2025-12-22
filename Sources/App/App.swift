import ComposableArchitecture
import CoreLocationClient
import SwiftUI

@Reducer
struct AppReducer: Reducer {
    @ObservableState
    struct State: Equatable {
        @Presents var destination: Destination.State?

        var appDelegate: AppDelegateReducer.State
        var transactionsList: TransactionsList.State

        init(
            appDelegate: AppDelegateReducer.State = AppDelegateReducer.State(),
            destination: Destination.State? = nil,
            transactionsList: TransactionsList.State = TransactionsList.State(date: .now)
        ) {
            self.appDelegate = appDelegate
            self.destination = destination
            self.transactionsList = transactionsList
        }
    }

    enum Action: ViewAction {
        enum View {
            case newTransactionButtonTapped
            case discardButtonTapped
            case task
            case shakeDetected
        }

        case appDelegate(AppDelegateReducer.Action)
        case transactionsList(TransactionsList.Action)

        case location(LocationManagerClient.Action)
        case destination(PresentationAction<Destination.Action>)
        case view(View)
    }

    @Reducer
    enum Destination {
        case transactionForm(TransactionFormReducer)
        case debugMenu
    }

    @Dependency(\.locationManager) private var locationManager

    var body: some ReducerOf<Self> {
        Scope(state: \.appDelegate, action: \.appDelegate) {
            AppDelegateReducer()
        }

        Scope(state: \.transactionsList, action: \.transactionsList) {
            TransactionsList()
        }

        Reduce { state, action in
            switch action {
            case .appDelegate(.didFinishLaunching):
                return .none

            case .appDelegate:
                return .none

            case let .location(locationAction):
                switch locationAction {
                default:
                    return .none
                }

            case .destination:
                return .none

            case .transactionsList:
                return .none

            case let .view(view):
                switch view {
                case .discardButtonTapped:
                    state.destination = nil
                    return .none

                case .newTransactionButtonTapped:
                    state.destination = .transactionForm(
                        TransactionFormReducer.State(
                            transaction: Transaction.Draft()
                        )
                    )
                    return .none

                case .task:
                    return .merge(
                        .run { send in
                            for await locationAction in await locationManager.delegate() {
                                await send(.location(locationAction))
                            }
                        },
                        .run { _ in
                            guard locationManager.locationServicesEnabled() else { return }
                            let authorizationStatus = await locationManager.authorizationStatus()
                            switch authorizationStatus {
                            case .notDetermined:
                                // TODO: we might prefer always location permissions
                                await locationManager.requestWhenInUseAuthorization()
                            case .denied:
                                // TODO: let the user know
                                return
                            case .restricted:
                                // TODO: figure this out
                                return
                            case .authorizedWhenInUse, .authorizedAlways:
                                return
                            @unknown default:
                                return
                            }
                        }
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

            Color.red
                .tabItem {
                    Label("Recurring", systemImage: "repeat.circle")
                }

            Color.red
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
        }
        .task { await send(.task).finish() }
        .sheet(item: $store.scope(
            state: \.destination?.transactionForm,
            action: \.destination.transactionForm
        )) { store in
            NavigationStack {
                TransactionFormView(store: store)
                    .navigationTitle("New Transaction")
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
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try appDatabase()
        $0.locale = Locale(identifier: "es_AR")
    }
    AppView(store: Store(initialState: AppReducer.State()) {
        AppReducer()
            ._printChanges()
    })
    .tint(.purple)
    .environment(\.locale, Locale(identifier: "es_AR"))
}
