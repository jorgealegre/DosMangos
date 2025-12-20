import ComposableArchitecture
import Currency
import IdentifiedCollections
import SQLiteData
import SwiftUI

@Reducer
struct TransactionsList: Reducer {

    @Selection
    struct Row: Identifiable, Hashable, Sendable {
        var id: UUID { transaction.id }
        let transaction: Transaction
        @Column(as: [String].JSONRepresentation.self)
        let categories: [String]
        @Column(as: [String].JSONRepresentation.self)
        let tags: [String]
    }

    @ObservableState
    struct State: Equatable {
        var date: Date

        @FetchAll(Row.none) // this query is dynamic
        var rows: [Row]

        var rowsByDay: [Int: [Row]] {
            var byDay = Dictionary(grouping: rows) { row in
                row.transaction.localDay
            }
            for (day, dayRows) in byDay {
                byDay[day] = dayRows.sorted { $0.transaction.createdAtUTC > $1.transaction.createdAtUTC }
            }
            return byDay
        }

        var balanceByDay: [Int: USD] {
            var balanceByDay: [Int: USD] = [:]
            for (day, rows) in rowsByDay {
                balanceByDay[day] = rows
                    .map { $0.transaction.value }
                    .reduce(USD(integerLiteral: 0)) { total, value in
                        total.adding(value)
                    }
            }
            return balanceByDay
        }
        var days: [Int] {
            Array(rowsByDay.keys.sorted().reversed())
        }

        var rowsQuery: some Statement<Row> & Sendable {
            @Dependency(\.calendar) var calendar
            let components = calendar.dateComponents([.year, .month], from: date)
            let year = components.year!
            let month = components.month!

            return Transaction
                .order { $0.createdAtUTC.desc() }
                .where { $0.localYear.eq(year) && $0.localMonth.eq((month)) }
                .withCategories
                .withTags
                .select {
                    Row.Columns(
                        transaction: $0,
                        categories: $2.jsonTitles,
                        tags: $4.jsonTitles
                    )
                }
        }

        init(date: Date) {
            self.date = date
            self._rows = FetchAll(rowsQuery, animation: .default)
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
                let fetchAll = state.$rows
                let query = state.rowsQuery
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
    }
}

@ViewAction(for: TransactionsList.self)
struct TransactionsListView: View {

    let store: StoreOf<TransactionsList>

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.days, id: \.self) { day in
                    let rows = store.rowsByDay[day] ?? []
                    Section {
                        ForEach(rows) { row in
                            TransactionView(
                                transaction: row.transaction,
                                categories: row.categories,
                                tags: row.tags
                            )
                        }
                        .onDelete(perform: { indexSet in
                            let ids = indexSet.map { rows[$0].transaction.id }
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
            store.rowsByDay.keys.contains(day),
            let transaction = store.rowsByDay[day]?.first?.transaction,
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
                ._printChanges()
        }
    )
    .tint(.purple)
}
