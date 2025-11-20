import ComposableArchitecture
import SwiftUI

@Reducer
public struct App: Reducer {
    @ObservableState
    public struct State: Equatable {
        @Presents var destination: Destination.State?
        
        var appDelegate: AppDelegateReducer.State
        var transactionsList: TransactionsList.State

        public init(
            appDelegate: AppDelegateReducer.State = .init(),
            destination: Destination.State? = nil,
            transactionsList: TransactionsList.State = .init(date: .now)
        ) {
            self.appDelegate = appDelegate
            self.destination = destination
            self.transactionsList = transactionsList
        }
    }

    public enum Action: ViewAction {
        public enum View {
            case newTransactionButtonTapped
            case discardButtonTapped
        }

        case destination(PresentationAction<Destination.Action>)
        
        case appDelegate(AppDelegateReducer.Action)
        case transactionsList(TransactionsList.Action)
        case view(View)
    }

    @Reducer
    public enum Destination {
        case transactionForm(TransactionForm)
    }

    public init() {}

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
                return .none

            case .appDelegate:
                return .none

            case .destination:
                return .none

            case .transactionsList:
                return .none

            case let .view(view):
                switch view {
//                case .addTransactionButtonTapped:
//                    defer { state.destination = nil }
//                    guard let transaction = state.destination?.transactionForm?.transaction
//                    else { return .none }
//
//                    return saveTransaction(state: &state, transaction)

                case .discardButtonTapped:
                    state.destination = nil
                    return .none

                case .newTransactionButtonTapped:
                    state.destination = .transactionForm(TransactionForm.State())
                    return .none
                }
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}
extension App.Destination.State: Equatable {}

@ViewAction(for: App.self)
public struct AppView: View {
    @Bindable public var store: StoreOf<App>

    public init(store: StoreOf<App>) {
        self.store = store
    }

    public var body: some View {
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
        .sheet(
            item: $store.scope(state: \.destination?.transactionForm, action: \.destination.transactionForm)
        ) { store in
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
//                        ToolbarItem(placement: .confirmationAction) {
//                            Button("Add") {
////                                send(.addTransactionButtonTapped)
//                            }
//                        }
                    }
            }
        }
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

struct AppPreview: PreviewProvider {
    static var previews: some View {
        let _ = try! prepareDependencies {
            $0.defaultDatabase = try appDatabase()
        }
        AppView(store: Store(initialState: App.State()) {
            App()
        })
        .tint(.purple)
    }
}
