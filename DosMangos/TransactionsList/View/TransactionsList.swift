import ComposableArchitecture
import Currency
import IdentifiedCollections
import SwiftUI

extension Date {
    var startOfMonth: Date {
        @Dependency(\.calendar) var calendar
        let day = calendar.date(from: Calendar.current.dateComponents([.year, .month], from: calendar.startOfDay(for: self)))!
        return day
    }

    var endOfMonth: Date {
        @Dependency(\.calendar) var calendar
        return calendar.date(byAdding: DateComponents(month: 1, second: -1), to: self.startOfMonth)!
    }
}

@Reducer
public struct TransactionsList: Reducer {
    @ObservableState
    public struct State: Equatable {
        public var date: Date

        @FetchAll
        public var transactions: [Transaction]

        var transactionsByDay: [Int: [Transaction]] {
            Dictionary(grouping: transactions) { transaction in
                // extract the day from the transaction
                transaction.createdAt.get(.day)
            }
        }

//        var summary: Summary {
//            // TODO: could be simplified
//            let expenses = transactions
//                .filter({ $0.transactionType == .expense })
//                .map(\.value)
//                .reduce(0, +)
//
//            let income = transactions
//                .filter({ $0.transactionType == .income })
//                .map(\.value)
//                .reduce(0, +)
//
//            let monthlyBalance = income + expenses
//
//            return Summary(
//                monthlyIncome: income,
//                monthlyExpenses: expenses,
//                monthlyBalance: monthlyBalance,
//                worth: monthlyBalance
//            )
//        }

        var balanceByDay: [Int: USD] {
            var balanceByDay: [Int: USD] = [:]
            for (day, transactions) in transactionsByDay {
                balanceByDay[day] = transactions
                    .map { $0.value }
                    .reduce(USD(integerLiteral: 0)) { total, value in
                        total.adding(value)
                    }
            }
            return balanceByDay
        }
        var days: [Int] {
            Array(transactionsByDay.keys.sorted().reversed())
        }

        var transactionsQuery: some Statement<Transaction> & Sendable {
            Transaction
                .where { $0.createdAt.between(#bind(date.startOfMonth), and: #bind(date.endOfMonth)) }
                .select { $0 }
        }

        public init(
            date: Date
        ) {
            self.date = date
            self._transactions = FetchAll(transactionsQuery, animation: .default)
        }
    }

    public enum Action: ViewAction {
        public enum View {
            case nextMonthButtonTapped
            case onAppear
            case previousMonthButtonTapped
            case deleteTransactions([UUID])
        }

        case loadTransactions
        case view(View)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .loadTransactions:
                let fetchAll = state.$transactions
                let query = state.transactionsQuery
                return .run { _ in
                    print("fetchAll")
                    try await fetchAll.load(query, animation: .default)
                }

            case let .view(.deleteTransactions(ids)):
//                ids.forEach { state.transactions.remove(id: $0) }
                return .run { _ in
                    do {
//                        try await transactionsStore.deleteTransactions(ids)
                    } catch {
                        print(error)
                        // TODO: should try to recover
                    }
                }

            case .view(.nextMonthButtonTapped):
                state.date = Calendar.current.date(byAdding: .month, value: 1, to: state.date)!
                return .send(.loadTransactions, animation: .default)

            case .view(.onAppear):
                return .none

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
//                ValueView(value: store.summary.monthlyIncome)
            }
            HStack {
                Text("Out")
                Spacer()
//                ValueView(value: store.summary.monthlyExpenses)
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
                    ValueView(value: store.balanceByDay[day]!)
                }
            }
        }
    }
}

struct TransactionsView_Previews: PreviewProvider {
    static var previews: some View {
        withDependencies {
            $0.defaultDatabase = try! appDatabase()
        } operation: {
            TransactionsListView(
                store: Store(initialState: TransactionsList.State(date: .now)) {
                    TransactionsList()
                }
            )
        }
        .tint(.purple)
    }
}
