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

        // Due recurring transactions (reactive via @FetchAll)
        @FetchAll(DueRecurringRow.none)
        var dueRows: [DueRecurringRow]
        var dueRowsQuery: some Statement<DueRecurringRow> & Sendable {
            @Dependency(\.date.now) var now
            let today = now.localDateComponents()

            return DueRecurringRow
                .where {
                    let rt = $0.recurringTransaction
                    let isActive = rt.status.eq(RecurringTransactionStatus.active)

                    // Compare local date: nextDue <= today
                    // (year < todayYear) OR
                    // (year == todayYear AND month < todayMonth) OR
                    // (year == todayYear AND month == todayMonth AND day <= todayDay)
                    let yearBefore = rt.nextDueLocalYear.lt(today.year)
                    let sameYearMonthBefore = rt.nextDueLocalYear.eq(today.year) && rt.nextDueLocalMonth.lt(today.month)
                    let sameYearMonthDayOnOrBefore = rt.nextDueLocalYear.eq(today.year)
                        && rt.nextDueLocalMonth.eq(today.month)
                        && rt.nextDueLocalDay.lte(today.day)

                    let isDueOnOrBeforeToday = yearBefore || sameYearMonthBefore || sameYearMonthDayOnOrBefore

                    return isActive && isDueOnOrBeforeToday
                }
                .order(by: \.recurringTransaction.nextDueLocalYear)
                .order(by: \.recurringTransaction.nextDueLocalMonth)
                .order(by: \.recurringTransaction.nextDueLocalDay)
                .select { $0 }
        }

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

        var balanceByDay: [Int: Money] {
            var balanceByDay: [Int: Money] = [:]

            for (day, rows) in rowsByDay {
                // Always use converted values (default currency) for totals
                // Skip transactions without conversion (they'll need background processing)
                balanceByDay[day] = rows
                    .compactMap { $0.transaction.signedConvertedMoney }
                    .sum()
            }
            return balanceByDay
        }
        var days: [Int] {
            Array(rowsByDay.keys.sorted().reversed())
        }

        init(date: Date) {
            self.date = date
            self._rows = FetchAll(rowsQuery, animation: .default)
            self._dueRows = FetchAll(dueRowsQuery, animation: .default)
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
            case postDueRow(DueRecurringRow)
            case skipDueRow(DueRecurringRow)
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
                        transaction: Transaction.Draft(transaction),
                        formMode: .editTransaction
                    ))
                    return .none

                case .dismissTransactionDetailButtonTapped:
                    state.destination = nil
                    return .none

                case let .postDueRow(dueRow):
                    let rt = dueRow.recurringTransaction
                    var draft = Transaction.Draft()
                    draft.description = rt.description
                    draft.valueMinorUnits = rt.valueMinorUnits
                    draft.currencyCode = rt.currencyCode
                    draft.type = rt.type
                    // Set the date to the due date (user can change)
                    let dateComponents = calendar.dateComponents([.year, .month, .day], from: rt.nextDueDate)
                    draft.localYear = dateComponents.year!
                    draft.localMonth = dateComponents.month!
                    draft.localDay = dateComponents.day!

                    // Look up category and tags from the category/tag titles
                    let category: Category? = dueRow.category.flatMap { title in
                        // Extract just the title (after " › " if subcategory)
                        let categoryTitle = title.contains(" › ") ? String(title.split(separator: " › ").last ?? "") : title
                        return Category(title: categoryTitle, parentCategoryID: nil)
                    }
                    let tags: [Tag] = dueRow.tags.map { Tag(title: $0) }

                    state.destination = .transactionForm(TransactionFormReducer.State(
                        transaction: draft,
                        formMode: .postFromRecurring(rt),
                        category: category,
                        tags: tags
                    ))
                    return .none

                case let .skipDueRow(dueRow):
                    let recurringTransaction = dueRow.recurringTransaction
                    return .run { _ in
                        await withErrorReporting {
                            try await database.write { db in
                                let rule = RecurrenceRule.from(recurringTransaction: recurringTransaction)
                                let nextDueDate = rule.nextOccurrence(after: recurringTransaction.nextDueDate)
                                let nextDueLocal = nextDueDate.localDateComponents()

                                try RecurringTransaction
                                    .where { $0.id.eq(recurringTransaction.id) }
                                    .update {
                                        $0.nextDueLocalYear = nextDueLocal.year
                                        $0.nextDueLocalMonth = nextDueLocal.month
                                        $0.nextDueLocalDay = nextDueLocal.day
                                    }
                                    .execute(db)
                            }
                        }
                    }
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
                // Due section for recurring transactions
                if !store.dueRows.isEmpty {
                    Section {
                        ForEach(store.dueRows) { dueRow in
                            DueRecurringRowView(
                                dueRow: dueRow,
                                onPost: { send(.postDueRow(dueRow)) },
                                onSkip: { send(.skipDueRow(dueRow)) }
                            )
                        }
                    } header: {
                        HStack {
                            Label {
                                Text("Due", bundle: .main)
                                    .font(.caption.bold())
                                    .textCase(nil)
                            } icon: {
                                Image(systemName: "clock.badge.exclamationmark")
                            }
                            .foregroundStyle(.orange)

                            Spacer()

                            if store.dueRows.count > 1 {
                                Text("\(store.dueRows.count) items", bundle: .main)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Regular transactions by day
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
                        .navigationTitle(transactionFormStore.navigationTitle)
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
                .presentationDragIndicator(.visible)
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
                    if let balance = store.balanceByDay[day] {
                        ValueView(money: balance)
                            .font(.footnote)
                    }
                }
            }
        }
    }
}

// MARK: - Due Recurring Row View

private struct DueRecurringRowView: View {
    let dueRow: DueRecurringRow
    let onPost: () -> Void
    let onSkip: () -> Void

    private var rt: RecurringTransaction { dueRow.recurringTransaction }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rt.description.isEmpty ? "Untitled" : rt.description)
                        .font(.headline)

                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                            .font(.caption2)
                        Text(dueDateText)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text(formattedAmount)
                    .font(.headline)
                    .foregroundStyle(rt.type == .income ? .green : .primary)
            }

            HStack(spacing: 12) {
                Button {
                    onPost()
                } label: {
                    Label("Post", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    onSkip()
                } label: {
                    Label("Skip", systemImage: "forward.fill")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedAmount: String {
        let money = Money(
            value: Int64(rt.valueMinorUnits),
            currencyCode: rt.currencyCode
        )
        let prefix = rt.type == .expense ? "-" : "+"
        return "\(prefix)\(money.amount.description) \(money.currencyCode)"
    }

    private var dueDateText: String {
        @Dependency(\.date.now) var now
        @Dependency(\.calendar) var calendar

        let dueDate = rt.nextDueDate
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        if calendar.isDate(dueDate, inSameDayAs: now) {
            return String(localized: "Due today", bundle: .main)
        } else if calendar.isDate(dueDate, inSameDayAs: yesterday) {
            return String(localized: "Due yesterday", bundle: .main)
        } else {
            let days = calendar.dateComponents([.day], from: dueDate, to: now).day ?? 0
            if days > 0 {
                return String(localized: "\(days) days overdue", bundle: .main)
            } else {
                return dueDate.formatted(date: .abbreviated, time: .omitted)
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
