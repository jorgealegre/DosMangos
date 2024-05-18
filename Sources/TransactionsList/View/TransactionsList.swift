import ComposableArchitecture
import IdentifiedCollections
import TransactionsStore
import SharedModels
import SwiftUI

@Reducer
public struct TransactionsList: Reducer {
    @ObservableState
    public struct State: Equatable {
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

        var balanceByDay: [Int: Int] {
            var balanceByDay: [Int: Int] = [:]
            for (day, transactions) in transactionsByDay {
                balanceByDay[day] = transactions.map { $0.value }.reduce(0, +)
            }
            return balanceByDay
        }
        var days: [Int] {
            Array(transactionsByDay.keys.sorted().reversed())
        }

        public init(
            date: Date,
            transactions: IdentifiedArrayOf<SharedModels.Transaction> = []
        ) {
            self.date = date
            self.transactions = transactions
        }
    }

    public enum Action: Equatable, ViewAction {
        public enum View: Equatable {
            case nextMonthButtonTapped
            case onAppear
            case previousMonthButtonTapped
            case deleteTransactions([UUID])
        }

        case loadTransactions
        case transactionsLoaded(TaskResult<IdentifiedArrayOf<SharedModels.Transaction>>)
        case view(View)
    }

    @Dependency(\.transactionsStore) private var transactionsStore

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .loadTransactions:
                state.transactions = []
                return .run { [date = state.date] send in
                    await send(
                        .transactionsLoaded(
                            TaskResult { try await transactionsStore.fetchTransactions(date) }
                        ),
                        animation: .default
                    )
                }

            case let .transactionsLoaded(.failure(error)):
                print(error)
                return .none

            case let .transactionsLoaded(.success(transactions)):
                state.transactions = transactions
                return .none

            case let .view(.deleteTransactions(ids)):
                ids.forEach { state.transactions.remove(id: $0) }
                return .run { _ in
                    do {
                        try await transactionsStore.deleteTransactions(ids)
                    } catch {
                        print(error)
                        // TODO: should try to recover
                    }
                }

            case .view(.nextMonthButtonTapped):
                state.date = Calendar.current.date(byAdding: .month, value: 1, to: state.date)!
                return .send(.loadTransactions, animation: .default)

            case .view(.onAppear):
                return .send(.loadTransactions)

            case .view(.previousMonthButtonTapped):
                state.date = Calendar.current.date(byAdding: .month, value: -1, to: state.date)!
                return .send(.loadTransactions, animation: .default)

            }
        }
        ._printChanges()
    }
}

@ViewAction(for: TransactionsList.self)
public struct TransactionsListView: View {

    public let store: StoreOf<TransactionsList>

    public init(store: StoreOf<TransactionsList>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                summary

                ForEach(store.days, id: \.self) { day in
                    let transactions = store.transactionsByDay[day] ?? []
                    Section {
                        ForEach(transactions) { transaction in
                            TransactionView(transaction: transaction)
                        }
                        .onDelete(perform: { indexSet in
                            let ids = indexSet.map { transactions[$0].id }
                            send(.deleteTransactions(ids), animation: .default)
                        })
                    } header: {
                        sectionHeaderView(day: day)
                    } footer: {
                        if day == store.days.last {
                            Spacer(minLength: 80)
                        }
                    }
                }
            }
            .onAppear { send(.onAppear) }
            .navigationTitle(store.date.formatted(Date.FormatStyle().month(.wide)))
            .listStyle(.insetGrouped)
            .listSectionSeparator(.hidden)
            .listRowSeparator(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        send(.previousMonthButtonTapped, animation: .default)
                    } label: {
                        Image(systemName: "chevron.backward")
                            .renderingMode(.template)
                            .foregroundColor(.accentColor)
                            .padding(8)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        send(.nextMonthButtonTapped, animation: .default)
                    } label: {
                        Image(systemName: "chevron.forward")
                            .renderingMode(.template)
                            .foregroundColor(.accentColor)
                            .padding(8)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("In")
                Spacer()
                ValueView(value: store.summary.monthlyIncome)
            }
            HStack {
                Text("Out")
                Spacer()
                ValueView(value: store.summary.monthlyExpenses)
            }

        }
    }

    @ViewBuilder
    private func sectionHeaderView(day: Int) -> some View {
        if
            store.transactionsByDay.keys.contains(day),
            let createdAt = store.transactionsByDay[day]?.first?.createdAt
        {
            VStack(spacing: 0) {
                HStack {
                    Text("\(createdAt.formatted(Date.FormatStyle().year().month().day()))")
                        .font(.caption.bold())
                    Spacer()
                    HStack {
                        Text("$\(store.balanceByDay[day]!.formatted())")
                            .monospacedDigit()
                            .font(.caption.bold())
                    }
                }
            }
        }
    }
}

struct TransactionsView_Previews: PreviewProvider {

    static var previews: some View {
        TransactionsListView(
            store: Store(
                initialState: TransactionsList.State(
                    date: .now
                )
            ) {
                TransactionsList()
            } withDependencies: {
                $0.transactionsStore.fetchTransactions = { date in
                    [
                        .mock(),
                        .mock(),
                        .mock(),
                        .mock(),
                        .init(
                            absoluteValue: 50,
                            createdAt: Date.now.addingTimeInterval(
                                -60*60*24*2
                            ),
                            description: "Coffee beans",
                            transactionType: .expense
                        )
                    ]
                }
            }
        )
        .tabItem {
            Label.init("Transactions", systemImage: "list.bullet.rectangle.portrait")
        }
        .tint(.purple)
    }
}
