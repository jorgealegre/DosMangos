import ComposableArchitecture
import SharedModels
import TransactionForm
import TransactionsList
import SwiftUI

@Reducer
public struct App: Reducer {
    @ObservableState
    public struct State: Equatable {
        @Presents var destination: Destination.State?
        
        var appDelegate: AppDelegateReducer.State
        var migrationCompleted: Bool
        var transactionsList: TransactionsList.State

        public init(
            appDelegate: AppDelegateReducer.State = .init(),
            destination: Destination.State? = nil,
            migrationCompleted: Bool = false,
            transactionsList: TransactionsList.State = .init(date: .now)
        ) {
            self.appDelegate = appDelegate
            self.destination = destination
            self.migrationCompleted = migrationCompleted
            self.transactionsList = transactionsList
        }
    }

    public enum Action: Equatable, ViewAction {
        public enum View: Equatable {
            case addTransactionButtonTapped
        }

        case destination(PresentationAction<Destination.Action>)
        
        case appDelegate(AppDelegateReducer.Action)
        case migrationComplete
        case migrationFailed
        case transactionsList(TransactionsList.Action)
        case view(View)
    }

    @Reducer(state: .equatable, action: .equatable)
    public enum Destination {
        case transactionForm(TransactionForm)
    }

    public init() {}

    @Dependency(\.transactionsStore) private var transactionsStore
    
    public var body: some ReducerOf<Self> {
        Scope(state: \.appDelegate, action: \.appDelegate) {
            AppDelegateReducer()
        }

        Scope(state: \.transactionsList, action: \.transactionsList) {
            TransactionsList()
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

            case .view(.addTransactionButtonTapped):
                state.destination = .transactionForm(TransactionForm.State())
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}


@ViewAction(for: App.self)
public struct AppView: View {
    @Bindable public var store: StoreOf<App>

    public init(store: StoreOf<App>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
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
            }

            if !store.migrationCompleted {
                // TODO: better loading indicator
                Color.red
            }
        }
        .sheet(
            item: $store.scope(
                state: \.destination?.transactionForm,
                action: \.destination.transactionForm
            ),
            content: TransactionFormView.init
        )
    }

    @ViewBuilder
    private var addTransactionButton: some View {
        Button {
            send(.addTransactionButtonTapped)
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

#if DEBUG
struct AppView_Previews: PreviewProvider {
    static var previews: some View {
        AppView(
            store: Store(
                initialState: App.State(
                    migrationCompleted: true
                )
            ) {
                App()
            }
        )
        .tint(.purple)
    }
}
#endif
