import ComposableArchitecture
import Currency
import IdentifiedCollections
import IssueReporting
import SQLiteData
import SwiftUI

@Reducer
struct TransactionsList: Reducer {

    @Reducer
    enum Destination {
        case transactionForm(TransactionFormReducer)
    }

    @ObservableState
    struct State: Equatable {

        @Presents var destination: Destination.State?

        var date: Date

        @FetchAll(TransactionsListRow.none) // this query is dynamic
        var rows: [TransactionsListRow]
        var rowsQuery: some Statement<TransactionsListRow> & Sendable {
            @Dependency(\.calendar) var calendar
            let components = calendar.dateComponents([.year, .month], from: date)
            let year = components.year!
            let month = components.month!

            return TransactionsListRow
                .where { $0.transaction.localYear.eq(year) && $0.transaction.localMonth.eq((month)) }
                .select { $0 }
        }

        var rowsByDay: [Int: [TransactionsListRow]] {
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
                    .map { $0.transaction.signedValue }
                    .reduce(USD(integerLiteral: 0)) { total, value in
                        total.adding(value)
                    }
            }
            return balanceByDay
        }
        var days: [Int] {
            Array(rowsByDay.keys.sorted().reversed())
        }

        init(date: Date) {
            self.date = date
            self._rows = FetchAll(rowsQuery, animation: .default)
        }
    }

    enum Action: BindableAction, ViewAction {
        enum View {
            case nextMonthButtonTapped
            case onAppear
            case previousMonthButtonTapped
            case deleteTransactions([UUID])
            case transactionTapped(Transaction)
            case dismissTransactionDetailButtonTapped
        }

        case binding(BindingAction<State>)
        case view(View)
        case destination(PresentationAction<Destination.Action>)
    }

    @Dependency(\.calendar) private var calendar
    @Dependency(\.defaultDatabase) private var database

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .destination:
                return .none

            case let .view(viewAction):
                switch viewAction {
                case let .deleteTransactions(ids):
                    return .run { _ in
                        await withErrorReporting {
                            try await database.write { db in
                                try Transaction
                                    .where { $0.id.in(ids) }
                                    .delete()
                                    .execute(db)
                            }
                        }
                    }

                case .nextMonthButtonTapped:
                    state.date = calendar.date(byAdding: .month, value: 1, to: state.date)!
                    return loadTransactions(state: state)

                case .onAppear:
                    return loadTransactions(state: state)

                case .previousMonthButtonTapped:
                    state.date = calendar.date(byAdding: .month, value: -1, to: state.date)!
                    return loadTransactions(state: state)

                case let .transactionTapped(transaction):
                    state.destination = .transactionForm(TransactionFormReducer.State(
                        transaction: Transaction.Draft(transaction)
                    ))
                    return .none

                case .dismissTransactionDetailButtonTapped:
                    state.destination = nil
                    return .none
                }
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }

    private func loadTransactions(state: State) -> Effect<Action> {
        let fetchAll = state.$rows
        let query = state.rowsQuery
        return .run { _ in
            try await fetchAll.load(query, animation: .default)
        }
    }
}
extension TransactionsList.Destination.State: Equatable {}

@ViewAction(for: TransactionsList.self)
struct TransactionsListView: View {

    @Bindable var store: StoreOf<TransactionsList>

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.days, id: \.self) { day in
                    let rows = store.rowsByDay[day] ?? []
                    Section {
                        ForEach(rows) { row in
                            Button {
                                send(.transactionTapped(row.transaction))
                            } label: {
                                TransactionView(
                                    transaction: row.transaction,
                                    category: row.category,
                                    tags: row.tags,
                                    location: row.location
                                )
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { indexSet in
                            let ids = indexSet.map { rows[$0].transaction.id }
                            send(.deleteTransactions(ids), animation: .default)
                        }
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
            .sheet(
                item: $store.scope(
                    state: \.destination?.transactionForm,
                    action: \.destination.transactionForm
                )
            ) { transactionFormStore in
                NavigationStack {
                    TransactionFormView(store: transactionFormStore)
                        .navigationTitle("Edit transaction")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button {
                                    send(.dismissTransactionDetailButtonTapped)
                                } label: {
                                    Image(systemName: "xmark")
                                }
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeaderView(day: Int) -> some View {
        if let transaction = store.rowsByDay[day]?.first?.transaction {
            VStack(spacing: 0) {
                HStack {
                    Text(transaction.localDate.formattedRelativeDay())
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
        try seedSampleData()
    }
    TransactionsListView(
        store: Store(initialState: TransactionsList.State(date: .now)) {
            TransactionsList()
                ._printChanges()
        }
    )
    .tint(.purple)
}
