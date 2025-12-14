import ComposableArchitecture
import Currency
import IdentifiedCollections
import SwiftUI

@Reducer
struct TransactionsList: Reducer {
    @ObservableState
    struct State: Equatable {
        var date: Date

        @FetchAll(Transaction.none) // this query is dynamic
        var transactions: [Transaction]

        var transactionsByDay: [Int: [Transaction]] {
            var byDay = Dictionary(grouping: transactions) { transaction in
                transaction.localDay
            }
            for (day, dayTransactions) in byDay {
                byDay[day] = dayTransactions.sorted { $0.createdAtUTC > $1.createdAtUTC }
            }
            return byDay
        }

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
            @Dependency(\.calendar) var calendar
            let components = calendar.dateComponents([.year, .month], from: date)
            let year = components.year!
            let month = components.month!
            return Transaction
                .where { $0.localYear.eq(year) && $0.localMonth.eq((month)) }
                .select { $0 }
        }

        init(
            date: Date
        ) {
            self.date = date
            self._transactions = FetchAll(transactionsQuery, animation: .default)
        }
    }

    enum Action: ViewAction {
        enum View {
            case nextMonthButtonTapped
            case onAppear
            case previousMonthButtonTapped
            case deleteTransactions([UUID])
        }

        case loadTransactions
        case view(View)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .loadTransactions:
                let fetchAll = state.$transactions
                let query = state.transactionsQuery
                return .run { _ in
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
struct TransactionsListView: View {

    let store: StoreOf<TransactionsList>

    var body: some View {
        NavigationStack {
            List {
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
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    } footer: {
                        if day == store.days.last {
                            Spacer(minLength: 80)
                        }
                    }
                }
            }
            .onAppear { send(.onAppear) }
            .navigationTitle(store.date.formatted(Date.FormatStyle().month(.wide)))
            .listStyle(.grouped)
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
    private func sectionHeaderView(day: Int) -> some View {
        if
            store.transactionsByDay.keys.contains(day),
            let transaction = store.transactionsByDay[day]?.first,
            let headerDate = Date.localDate(year: transaction.localYear, month: transaction.localMonth, day: transaction.localDay)
        {
            VStack(spacing: 0) {
                HStack {
                    Text(headerDate.formattedRelativeDay())
                        .font(.caption.bold())
                        .textCase(nil)
                    Spacer()
                    ValueView(value: store.balanceByDay[day]!)
                        .font(.footnote)
                }
            }
        }
    }
}

#Preview {
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
    }
    TransactionsListView(
        store: Store(initialState: TransactionsList.State(date: .now)) {
            TransactionsList()
        }
    )
    .tint(.purple)
}
