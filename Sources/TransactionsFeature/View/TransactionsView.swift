import AddTransactionFeature
import ComposableArchitecture
import TransactionsStore
import SharedModels
import SwiftUI

public struct TransactionsFeature: ReducerProtocol {
    public struct State: Equatable {
        public var addTransaction: AddTransaction.State?
        public var date: Date
        public var transactions: [SharedModels.Transaction]

        var monthlySummary: MonthlySummary {
            let expenses = transactions.map(\.value).map(Double.init).reduce(0.0, +)
            let income = 0.0
            let worth = income - expenses

            return MonthlySummary(
                income: income,
                expenses: expenses,
                worth: worth
            )
        }

        public init(
            addTransaction: AddTransaction.State? = nil,
            date: Date,
            transactions: [SharedModels.Transaction] = []
        ) {
            self.addTransaction = addTransaction
            self.date = date
            self.transactions = transactions
        }
    }

    public enum Action: Equatable {
        case addTransaction(AddTransaction.Action)
        case deleteTransactions(IndexSet)
        case newTransactionButtonTapped
        case onAppear
        case setAddTransactionSheetPresented(Bool)
    }

    @Dependency(\.transactionsStore) private var transactionsStore

    public init() {}

    public var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
            case .addTransaction(.saveButtonTapped):
                defer { state.addTransaction = nil }
                guard let transaction = state.addTransaction?.transaction else { return .none }
                state.transactions.insert(transaction, at: 0)
                return .none

            case .addTransaction:
                return .none

            case let .deleteTransactions(indices):
                state.transactions.remove(atOffsets: indices)
                return .none

            case .newTransactionButtonTapped:
                state.addTransaction = .init()
                return .none

            case .onAppear:
                return .run { send in
                    //          await send(
                    //            .transactionsLoaded(
                    //              TaskResult { try await fileClient.loadTransactions() }
                    //            )
                    //          )
                }

            case let .setAddTransactionSheetPresented(presented):
                if !presented {
                    state.addTransaction = nil
                }
                return .none
            }
        }
        .ifLet(\.addTransaction, action: /Action.addTransaction) {
            AddTransaction()
        }
        ._printChanges()
    }
}

public struct TransactionsView: View {

    private struct ViewState: Equatable {
        let addTransaction: AddTransaction.State?
        let currentDate: String
        let dates: [Date]
        let isAddingTransaction: Bool
        let monthlySummary: MonthlySummary
        let transactions: [Date: [SharedModels.Transaction]]

        init(state: TransactionsFeature.State) {
            self.addTransaction = state.addTransaction
            self.isAddingTransaction = state.addTransaction != nil
            self.currentDate = state.date.formatted(Date.FormatStyle().month(.wide))
            self.monthlySummary = state.monthlySummary
            let sortedTransactions = state.transactions.sorted(by: { $0.date < $1.date })
            self.transactions = Dictionary(grouping: sortedTransactions, by: \.date)
            self.dates = transactions.keys.sorted(by: { $0 < $1 })
        }
    }

    private let store: StoreOf<TransactionsFeature>
    @ObservedObject private var viewStore: ViewStore<ViewState, TransactionsFeature.Action>

    public init(store: StoreOf<TransactionsFeature>) {
        self.store = store
        self.viewStore = .init(store.scope(state: ViewState.init))
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    Divider()
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("In")
                            Spacer()
                            Text("$\(viewStore.monthlySummary.income.formatted())")
                                .monospacedDigit()
                                .bold()
                        }
                        HStack {
                            Text("Out")
                            Spacer()
                            Text("$\(viewStore.monthlySummary.expenses.formatted())")
                                .monospacedDigit()
                                .bold()
                        }
                        HStack {
                            Text("Worth")
                            Spacer()
                            Text("$\(abs(viewStore.monthlySummary.worth).formatted())")
                                .monospacedDigit()
                                .bold()
                                .foregroundColor(viewStore.monthlySummary.worth < 0 ? .red : .green)
                        }
                        HStack {
                            Text("Monthly Balance")
                            Spacer()
                            Text("$\(abs(viewStore.monthlySummary.worth).formatted())")
                                .monospacedDigit()
                                .bold()
                                .foregroundColor(viewStore.monthlySummary.worth < 0 ? .red : .green)
                        }
                    }
                    .padding(8)

                    Divider()

                    List {
                        ForEach(viewStore.dates, id: \.self) { (date: Date) in
                            Section {
                                ForEach(viewStore.transactions[date] ?? [], content: TransactionView.init)
                                    .onDelete { indices in
                                        viewStore.send(.deleteTransactions(indices))
                                    }
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            } header: {
                                HStack {
                                    Text("\(date.formatted(date: .long, time: .omitted))")
                                    Spacer()
                                    HStack {
                                        Text("$\(viewStore.monthlySummary.worth.formatted())")
                                            .monospacedDigit()
                                            .bold()
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }

                Button {
                    viewStore.send(.newTransactionButtonTapped)
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
            .onAppear { viewStore.send(.onAppear) }
            .navigationTitle(viewStore.currentDate)
            .sheet(
                isPresented: viewStore.binding(
                    get: \.isAddingTransaction,
                    send: TransactionsFeature.Action.setAddTransactionSheetPresented
                )
            ) {
                IfLetStore(
                    store.scope(
                        state: \.addTransaction,
                        action: TransactionsFeature.Action.addTransaction
                    )
                ) {
                    AddTransactionView(store: $0)
                }
            }
        }
    }
}

struct TransactionView: View {
    let transaction: SharedModels.Transaction

    var body: some View {
        HStack {
            VStack {
                HStack {
                    Text("\(transaction.description)")
                        .font(.title)
                    Spacer()
                }
            }
            Spacer()

            Text("$\(transaction.value)")
                .monospacedDigit()
                .bold()
        }
    }
}

struct TransactionsView_Previews: PreviewProvider {
    static var previews: some View {
        TransactionsView(
            store: .init(
                initialState: .init(
                    date: .now,
                    transactions: [.mock]
                ),
                reducer: TransactionsFeature()
            )
        )
    }
}
