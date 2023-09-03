import ComposableArchitecture
import SharedModels
import TransactionsFeature
import SwiftUI

public struct AppReducer: Reducer {
    public struct State: Equatable {
        var migrationCompleted: Bool
        var transactions: TransactionsFeature.State

        public init(
            migrationCompleted: Bool = false,
            transactions: TransactionsFeature.State = .init(date: .now)
        ) {
            self.migrationCompleted = migrationCompleted
            self.transactions = transactions
        }
    }

    public enum Action: Equatable {
        case migrationComplete
        case migrationFailed
        case appDelegate(AppDelegateReducer.Action)
        case transactions(TransactionsFeature.Action)
    }

    public init() {}

    @Dependency(\.transactionsStore) private var transactionsStore
    
    public var body: some ReducerOf<Self> {
        Scope(state: \.transactions, action: /Action.transactions) {
            TransactionsFeature()
        }

        Reduce { state, action in
            switch action {
            case .appDelegate(.didFinishLaunching):
                return .run { send in
                    do {
                        try await self.transactionsStore.migrate()
                        await send(.migrationComplete)
                    } catch {
                        print(error.localizedDescription)
                        await send(.migrationFailed)
                    }
                }

            case .appDelegate:
                return .none

            case .migrationComplete:
                state.migrationCompleted = true
                return .none

            case .migrationFailed:
                state.migrationCompleted = true
                return .none

            case .transactions:
                return .none
            }
        }
    }
}

public struct AppView: View {
    let store: StoreOf<AppReducer>
    @ObservedObject var viewStore: ViewStore<ViewState, AppReducer.Action>

    struct ViewState: Equatable {
        var migrationCompleted: Bool

        init(state: AppReducer.State) {
            self.migrationCompleted = state.migrationCompleted
        }
    }

    public init(store: StoreOf<AppReducer>) {
        self.store = store
        self.viewStore = ViewStore(store, observe: ViewState.init)
    }

    public var body: some View {
        if viewStore.migrationCompleted {
            TabView {
                TransactionsView(
                    store: store.scope(
                        state: \.transactions,
                        action: AppReducer.Action.transactions
                    )
                )
                .tabItem {
                    Label("Transactions", systemImage: "list.bullet.rectangle.portrait")
                }
            }
            .onAppear {
                let tabBarAppearance = UITabBarAppearance()
                tabBarAppearance.configureWithDefaultBackground()
                UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
            }
        } else {
            Color.black
        }
    }
}

#if DEBUG
struct AppView_Previews: PreviewProvider {
    static var previews: some View {
        AppView(
            store: Store(initialState: AppReducer.State()) {
                AppReducer()
            }
        )
        .tint(.purple)
    }
}
#endif
