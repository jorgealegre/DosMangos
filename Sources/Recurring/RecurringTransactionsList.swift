import ComposableArchitecture
import Currency
import Dependencies
import SQLiteData
import SwiftUI

@Reducer
struct RecurringTransactionsList: Reducer {
    @Reducer
    enum Destination {
        case transactionForm(TransactionFormReducer)
    }

    @ObservableState
    struct State: Equatable {
        @FetchAll(
            RecurringTransaction
                .where { $0.status.in([RecurringTransactionStatus.active, .paused]) }
                .order(by: \.nextDueLocalYear)
                .order(by: \.nextDueLocalMonth)
                .order(by: \.nextDueLocalDay),
            animation: .default
        )
        var recurringTransactions: [RecurringTransaction]

        @Presents var destination: Destination.State?

        var groupedByStatus: [RecurringTransactionStatus: [RecurringTransaction]] {
            Dictionary(grouping: recurringTransactions, by: \.status)
        }
    }

    enum Action: ViewAction {
        enum View {
            case onAppear
            case addButtonTapped
            case transactionTapped(RecurringTransaction)
            case deleteRecurringTransactions([UUID])
        }
        case view(View)
        case destination(PresentationAction<Destination.Action>)
    }

    @Dependency(\.defaultDatabase) private var database

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.onAppear):
                return .none

            case .view(.addButtonTapped):
                let draft = Transaction.Draft()
                state.destination = .transactionForm(
                    TransactionFormReducer.State(
                        transaction: draft,
                        formMode: .newRecurring
                    )
                )
                return .none

            case let .view(.transactionTapped(recurringTransaction)):
                // Create a draft from the recurring transaction
                var draft = Transaction.Draft()
                draft.description = recurringTransaction.description
                draft.valueMinorUnits = recurringTransaction.valueMinorUnits
                draft.currencyCode = recurringTransaction.currencyCode
                draft.type = recurringTransaction.type

                state.destination = .transactionForm(
                    TransactionFormReducer.State(
                        transaction: draft,
                        formMode: .editRecurring(recurringTransaction)
                    )
                )
                return .none

            case let .view(.deleteRecurringTransactions(ids)):
                return .run { _ in
                    await withErrorReporting {
                        try await database.write { db in
                            // Soft delete: set status to deleted
                            try RecurringTransaction
                                .where { $0.id.in(ids) }
                                .update { $0.status = .deleted }
                                .execute(db)
                        }
                    }
                }

            case .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension RecurringTransactionsList.Destination.State: Equatable {}

@ViewAction(for: RecurringTransactionsList.self)
struct RecurringTransactionsListView: View {
    @Bindable var store: StoreOf<RecurringTransactionsList>

    var body: some View {
        NavigationStack {
            List {
                let grouped = store.groupedByStatus

                if let active = grouped[.active], !active.isEmpty {
                    Section {
                        ForEach(active) { transaction in
                            RecurringTransactionRow(transaction: transaction)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    send(.transactionTapped(transaction))
                                }
                        }
                        .onDelete { indexSet in
                            let ids = indexSet.map { active[$0].id }
                            send(.deleteRecurringTransactions(ids), animation: .default)
                        }
                    } header: {
                        Text("Active")
                    }
                }

                if let paused = grouped[.paused], !paused.isEmpty {
                    Section {
                        ForEach(paused) { transaction in
                            RecurringTransactionRow(transaction: transaction)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    send(.transactionTapped(transaction))
                                }
                        }
                        .onDelete { indexSet in
                            let ids = indexSet.map { paused[$0].id }
                            send(.deleteRecurringTransactions(ids), animation: .default)
                        }
                    } header: {
                        Text("Paused")
                    }
                }

                if store.recurringTransactions.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("No Recurring Transactions")
                        } icon: {
                            Image(systemName: "repeat.circle")
                        }
                    } description: {
                        Text("Tap + to create a recurring transaction template.")
                    }
                }
            }
            .navigationTitle(Text("Recurring"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        send(.addButtonTapped)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                send(.onAppear)
            }
            .sheet(
                item: $store.scope(
                    state: \.destination?.transactionForm,
                    action: \.destination.transactionForm
                )
            ) { formStore in
                NavigationStack {
                    TransactionFormView(store: formStore)
                        .navigationTitle(formStore.navigationTitle)
                        .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDragIndicator(.visible)
            }
        }
    }
}

// MARK: - Row View

private struct RecurringTransactionRow: View {
    let transaction: RecurringTransaction

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(transaction.description.isEmpty ? "Untitled" : transaction.description)
                    .font(.headline)

                Spacer()

                Text(formattedAmount)
                    .font(.headline)
                    .foregroundStyle(transaction.type == .income ? .green : .primary)
            }

            HStack {
                Text(frequencySummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if transaction.status == .paused {
                    Label {
                        Text("Paused")
                    } icon: {
                        Image(systemName: "pause.circle.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                } else {
                    Label {
                        Text(nextDueText)
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedAmount: String {
        let money = Money(
            value: Int64(transaction.valueMinorUnits),
            currencyCode: transaction.currencyCode
        )
        return "\(money.amount.description) \(money.currencyCode)"
    }

    private var frequencySummary: String {
        let rule = RecurrenceRule.from(recurringTransaction: transaction)
        return rule.summaryDescription
    }

    private var nextDueText: String {
        @Dependency(\.date.now) var now
        @Dependency(\.calendar) var calendar

        let nextDue = transaction.nextDueDate
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        if calendar.isDate(nextDue, inSameDayAs: now) {
            return String(localized: "Due today")
        } else if calendar.isDate(nextDue, inSameDayAs: tomorrow) {
            return String(localized: "Due tomorrow")
        } else if calendar.isDate(nextDue, inSameDayAs: yesterday) {
            return String(localized: "Due yesterday")
        } else if nextDue < now {
            let days = calendar.dateComponents([.day], from: nextDue, to: now).day ?? 0
            return String(localized: "\(days) days overdue")
        } else {
            return nextDue.formatted(date: .abbreviated, time: .omitted)
        }
    }
}

// MARK: - Preview

#Preview {
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
        try seedSampleData()
    }
    RecurringTransactionsListView(
        store: Store(initialState: RecurringTransactionsList.State()) {
            RecurringTransactionsList()
        }
    )
}
