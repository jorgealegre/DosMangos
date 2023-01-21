import AddTransactionFeature
import ComposableArchitecture
import IdentifiedCollections
import TransactionsStore
import SharedModels
import SwiftUI

extension Date {
    func get(_ components: Calendar.Component..., calendar: Calendar = Calendar.current) -> DateComponents {
        return calendar.dateComponents(Set(components), from: self)
    }

    func get(_ component: Calendar.Component, calendar: Calendar = Calendar.current) -> Int {
        return calendar.component(component, from: self)
    }
}

public struct TransactionsFeature: ReducerProtocol {
    public struct State: Equatable {
        public var addTransaction: AddTransaction.State?
        public var date: Date
        public var transactions: IdentifiedArrayOf<SharedModels.Transaction>

        var transactionsByDay: [Int: [SharedModels.Transaction]] {
            Dictionary(grouping: transactions) { transaction in
                // extract the day from the transaction
                transaction.date.get(.day)
            }
        }

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
            transactions: IdentifiedArrayOf<SharedModels.Transaction> = []
        ) {
            self.addTransaction = addTransaction
            self.date = date
            self.transactions = transactions
        }
    }

    public enum Action: Equatable {
        case addTransaction(AddTransaction.Action)
        case deleteTransactions([UUID])
        case newTransactionButtonTapped
        case onAppear
        case setAddTransactionSheetPresented(Bool)
        case transactionsLoaded(TaskResult<IdentifiedArrayOf<SharedModels.Transaction>>)
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
                return .fireAndForget {
                    do {
                        try await transactionsStore.saveTransaction(transaction)
                    } catch {
                        print(error)
                        // TODO: should try to recover
                    }
                }

            case .addTransaction:
                return .none

            case let .deleteTransactions(ids):
                ids.forEach { state.transactions.remove(id: $0) }
                return .fireAndForget {
                    do {
                        try await transactionsStore.deleteTransactions(ids)
                    } catch {
                        print(error)
                        // TODO: should try to recover
                    }
                }

            case .newTransactionButtonTapped:
                state.addTransaction = .init()
                return .none

            case .onAppear:
                return .run { [date = state.date] send in
                    await send(
                        .transactionsLoaded(
                            TaskResult { try await transactionsStore.fetchTransactions(date) }
                        )
                    )
                }

            case let .setAddTransactionSheetPresented(presented):
                if !presented {
                    state.addTransaction = nil
                }
                return .none

            case let .transactionsLoaded(.failure(error)):
                print(error)
                return .none

            case let .transactionsLoaded(.success(transactions)):
                state.transactions = transactions
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
        let currentDate: Date
        let isAddingTransaction: Bool
        let monthlySummary: MonthlySummary
        let transactionsByDay: [Int: [SharedModels.Transaction]]
        let days: [Int]

        init(state: TransactionsFeature.State) {
            self.addTransaction = state.addTransaction
            self.isAddingTransaction = state.addTransaction != nil
            self.currentDate = state.date
            self.monthlySummary = state.monthlySummary
            self.transactionsByDay = state.transactionsByDay
            self.days = Array(state.transactionsByDay.keys.sorted().reversed())
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
                        ForEach(viewStore.days, id: \.self) { day in
                            Section {
                                let transactions = viewStore.transactionsByDay[day] ?? []
                                ForEach(transactions, content: TransactionView.init)
                                    .onDelete { indices in
                                        let ids = indices.map { transactions[$0].id }
                                        viewStore.send(.deleteTransactions(ids))
                                    }
                            } header: {
                                HStack {
                                    Text("\(viewStore.transactionsByDay[day]!.first!.date.formatted(Date.FormatStyle().month().day()))")
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
            .navigationTitle(viewStore.currentDate.formatted(Date.FormatStyle().month(.wide).year()))
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
                    transactions: [.mock()]
                ),
                reducer: TransactionsFeature()
            )
        )
    }
}
