import AddTransactionFeature
import ComposableArchitecture
import IdentifiedCollections
import TransactionsStore
import SharedModels
import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .displayP3,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 08) & 0xff) / 255,
            blue: Double((hex >> 00) & 0xff) / 255,
            opacity: alpha
        )
    }
}

extension Color {
    static var income: Color {
        .init(hex: 0x9BD770)
    }

    static var expense: Color {
        .init(hex: 0xFE8176)
    }
}

extension Date {
    func get(_ components: Calendar.Component...) -> DateComponents {
        @Dependency(\.calendar) var calendar
        return calendar.dateComponents(Set(components), from: self)
    }

    func get(_ component: Calendar.Component) -> Int {
        @Dependency(\.calendar) var calendar
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
                transaction.createdAt.get(.day)
            }
        }

        var summary: Summary {
            // TODO: could be simplified
            let expenses = transactions
                .filter({ $0.transactionType == .expense })
                .map(\.value)
                .reduce(0, +)

            let income = transactions
                .filter({ $0.transactionType == .income })
                .map(\.value)
                .reduce(0, +)

            let monthlyBalance = income + expenses

            return Summary(
                monthlyIncome: income,
                monthlyExpenses: expenses,
                monthlyBalance: monthlyBalance,
                worth: monthlyBalance
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

struct ValueView: View {
    let value: Int

    var body: some View {
        Text("$\(value.formatted())")
            .monospacedDigit()
            .bold()
            .foregroundColor(value < 0 ? .expense : .income)

    }
}

public struct TransactionsView: View {

    private struct ViewState: Equatable {
        let addTransaction: AddTransaction.State?
        let currentDate: Date
        let isAddingTransaction: Bool
        let summary: Summary
        let transactionsByDay: [Int: [SharedModels.Transaction]]
        let balanceByDay: [Int: Int]
        let days: [Int]

        init(state: TransactionsFeature.State) {
            self.addTransaction = state.addTransaction
            self.isAddingTransaction = state.addTransaction != nil
            self.currentDate = state.date
            self.summary = state.summary
            self.transactionsByDay = state.transactionsByDay
            self.days = Array(state.transactionsByDay.keys.sorted().reversed())
            var balanceByDay: [Int: Int] = [:]
            for (day, transactions) in state.transactionsByDay {
                balanceByDay[day] = transactions.map { $0.value }.reduce(0, +)
            }
            self.balanceByDay = balanceByDay
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
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("In")
                            Spacer()
                            ValueView(value: viewStore.summary.monthlyIncome)
                        }
                        HStack {
                            Text("Out")
                            Spacer()
                            ValueView(value: viewStore.summary.monthlyExpenses)
                        }
                        HStack {
                            Text("Monthly Balance")
                            Spacer()
                            ValueView(value: viewStore.summary.monthlyBalance)
                        }
                        HStack {
                            Text("Worth")
                            Spacer()
                            ValueView(value: viewStore.summary.worth)
                        }
                    }
                    .padding(8)

                    Divider()

                    List {
                        ForEach(viewStore.days, id: \.self) { day in
                            Section {
                                let transactions = viewStore.transactionsByDay[day] ?? []
                                ForEach(transactions) { transaction in
                                    VStack(spacing: 0) {
                                        TransactionView(transaction: transaction)
                                        Divider()
                                    }
                                }
                                .onDelete { indices in
                                    let ids = indices.map { transactions[$0].id }
                                    viewStore.send(.deleteTransactions(ids))
                                }
                            } header: {
                                HStack {
                                    Text("\(viewStore.transactionsByDay[day]!.first!.createdAt.formatted(Date.FormatStyle().year().month().day()))")
                                    Spacer()
                                    HStack {
                                        Text("$\(viewStore.balanceByDay[day]!.formatted())")
                                            .monospacedDigit()
                                            .bold()
                                    }
                                }
                            } footer: {
                                if day == viewStore.days.last {
                                    Spacer(minLength: 80)
                                }
                            }
                        }
                        .headerProminence(Prominence.standard)
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                }

                addTransactionButton
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

    @ViewBuilder
    private var addTransactionButton: some View {
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
