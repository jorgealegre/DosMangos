import ComposableArchitecture
import SharedModels
import TransactionsFeature
import SwiftUI

public struct AppReducer: ReducerProtocol {
    public struct State: Equatable {
        var transactions: TransactionsFeature.State

        public init(
            transactions: TransactionsFeature.State = .init(date: .now)
        ) {
            self.transactions = transactions
        }
    }

    public enum Action: Equatable {
        case appDelegate(AppDelegateReducer.Action)
        case transactions(TransactionsFeature.Action)
    }

    public init() {}

    public var body: some ReducerProtocol<State, Action> {
        Scope(state: \.transactions, action: /Action.transactions) {
            TransactionsFeature()
        }

        Reduce { state, action in
            switch action {
            case .appDelegate(.didFinishLaunching):
                state.transactions.transactions = [.mock]
                return .none

            case .appDelegate:
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

        init(state: AppReducer.State) {
        }
    }

    public init(store: StoreOf<AppReducer>) {
        self.store = store
        self.viewStore = ViewStore(self.store.scope(state: ViewState.init))
    }

    public var body: some View {
        TabView {
            TransactionsView(
                store: store.scope(
                    state: \.transactions,
                    action: AppReducer.Action.transactions
                )
            )
            .tabItem {
                VStack {
                    Label {
                        Text("Transactions")
                    } icon: {
                        Image(systemName: "list.bullet.rectangle.portrait")
                    }
                }
            }
        }
    }
}

#if DEBUG
struct AppView_Previews: PreviewProvider {
    static var previews: some View {
        AppView(
            store: .init(
                initialState: .init(),
                reducer: AppReducer()
            )
        )
        .tint(.purple)
    }
}
#endif
