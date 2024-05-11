import ComposableArchitecture
import SharedModels
import TransactionForm
import TransactionsList
import SwiftUI

public struct App: Reducer {
    public struct State: Equatable {
        @PresentationState var destination: Destination.State?
        var migrationCompleted: Bool
        var transactionsList: TransactionsList.State

        public init(
            destination: Destination.State? = nil,
            migrationCompleted: Bool = false,
            transactionsList: TransactionsList.State = .init(date: .now)
        ) {
            self.destination = destination
            self.migrationCompleted = migrationCompleted
            self.transactionsList = transactionsList
        }
    }

    public enum Action: Equatable {
        case addTransactionButtonTapped
        case destination(PresentationAction<Destination.Action>)
        case migrationComplete
        case migrationFailed
        case appDelegate(AppDelegateReducer.Action)
        case transactionsList(TransactionsList.Action)
    }

    public struct Destination: Reducer {
        public enum State: Equatable {
            case transactionForm(TransactionForm.State)
        }
        public enum Action: Equatable {
            case transactionForm(TransactionForm.Action)
        }

        public var body: some ReducerOf<Self> {
            Scope(state: /State.transactionForm, action: /Action.transactionForm) {
                TransactionForm()
            }
        }
    }

    public init() {}

    @Dependency(\.transactionsStore) private var transactionsStore
    
    public var body: some ReducerOf<Self> {
        Scope(state: \.transactionsList, action: /Action.transactionsList) {
            TransactionsList()
        }

        Reduce { state, action in
            switch action {
            case .addTransactionButtonTapped:
                state.destination = .transactionForm(TransactionForm.State())
                return .none

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

            case .destination:
                return .none

            case .migrationComplete:
                state.migrationCompleted = true
                return .none

            case .migrationFailed:
                state.migrationCompleted = true
                return .none

            case .transactionsList:
                return .none
            }
        }
        .ifLet(\.$destination, action: /Action.destination) {
            Destination()
        }
    }
}

public struct AppView: View {
    let store: StoreOf<App>
    @ObservedObject var viewStore: ViewStore<ViewState, App.Action>

    struct ViewState: Equatable {
        var migrationCompleted: Bool

        init(state: App.State) {
            self.migrationCompleted = state.migrationCompleted
        }
    }

    public init(store: StoreOf<App>) {
        self.store = store
        self.viewStore = ViewStore(store, observe: ViewState.init)
    }

    public var body: some View {
        ZStack {
            TabView {
                ZStack(alignment: .bottom) {
                    TransactionsListView(
                        store: store.scope(
                            state: \.transactionsList,
                            action: App.Action.transactionsList
                        )
                    )

                    addTransactionButton
                }
                .tabItem {
                    Label("Transactions", systemImage: "list.bullet.rectangle.portrait")
                }
            }

            if !viewStore.migrationCompleted {
                // TODO: better loading indicator
                Color.red
            }
        }
        .sheet(
            store: store.scope(state: \.$destination, action: { .destination($0) }),
            state: /App.Destination.State.transactionForm,
            action: App.Destination.Action.transactionForm,
            content: TransactionFormView.init
        )
    }

    @ViewBuilder
    private var addTransactionButton: some View {
        Button {
            viewStore.send(.addTransactionButtonTapped)
        } label: {
            ZStack {
                Circle()
                    .fill(.purple.gradient)

                Image(systemName: "plus.square")
                    .font(.largeTitle)
                    .foregroundColor(.white)
            }
            .frame(width: 60, height: 60)
        }
        .padding()
    }
}

#if DEBUG
struct AppView_Previews: PreviewProvider {
    static var previews: some View {
        AppView(
            store: Store(initialState: App.State(migrationCompleted: true)) {
                App()
            }
        )
        .tint(.purple)
    }
}
#endif
