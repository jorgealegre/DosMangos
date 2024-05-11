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

public struct TransactionsList: Reducer {
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

        public init(
            date: Date,
            transactions: IdentifiedArrayOf<SharedModels.Transaction> = []
        ) {
            self.date = date
            self.transactions = transactions
        }
    }

    public enum Action: Equatable {
        case deleteTransactions([UUID])
        case loadTransactions
        case nextMonthButtonTapped
        case onAppear
        case previousMonthButtonTapped
        case transactionsLoaded(TaskResult<IdentifiedArrayOf<SharedModels.Transaction>>)
    }

    @Dependency(\.transactionsStore) private var transactionsStore

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
//            case .addTransaction(.saveButtonTapped):
//                defer { state.addTransaction = nil }
//                guard let transaction = state.addTransaction?.transaction else { return .none }
//                state.transactions.insert(transaction, at: 0)
//                return .run { _ in
//                    do {
//                        try await transactionsStore.saveTransaction(transaction)
//                    } catch {
//                        print(error)
//                        // TODO: should try to recover
//                    }
//                }

            case let .deleteTransactions(ids):
                ids.forEach { state.transactions.remove(id: $0) }
                return .run { _ in
                    do {
                        try await transactionsStore.deleteTransactions(ids)
                    } catch {
                        print(error)
                        // TODO: should try to recover
                    }
                }

            case .nextMonthButtonTapped:
                state.date = Calendar.current.date(byAdding: .month, value: 1, to: state.date)!
                return .send(.loadTransactions)

            case .onAppear:
                return .send(.loadTransactions)

            case .loadTransactions:
                return .run { [date = state.date] send in
                    await send(
                        .transactionsLoaded(
                            TaskResult { try await transactionsStore.fetchTransactions(date) }
                        )
                    )
                }

            case .previousMonthButtonTapped:
                state.date = Calendar.current.date(byAdding: .month, value: -1, to: state.date)!
                return .send(.loadTransactions)

            case let .transactionsLoaded(.failure(error)):
                print(error)
                return .none

            case let .transactionsLoaded(.success(transactions)):
                state.transactions = transactions
                return .none
            }
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

public struct TransactionsListView: View {

    private struct ViewState: Equatable {
        let currentDate: Date
        let summary: Summary
        let transactionsByDay: [Int: [SharedModels.Transaction]]
        let balanceByDay: [Int: Int]
        let days: [Int]

        init(state: TransactionsList.State) {
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

    private let store: StoreOf<TransactionsList>
    @ObservedObject private var viewStore: ViewStore<ViewState, TransactionsList.Action>

    public init(store: StoreOf<TransactionsList>) {
        self.store = store
        self.viewStore = .init(store, observe: ViewState.init)
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        //                    Divider()
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
                            //                        HStack {
                            //                            Text("Monthly Balance")
                            //                            Spacer()
                            //                            ValueView(value: viewStore.summary.monthlyBalance)
                            //                        }
                            //                        HStack {
                            //                            Text("Worth")
                            //                            Spacer()
                            //                            ValueView(value: viewStore.summary.worth)
                            //                        }
                        }
                        .padding(8)

                        Divider()

                        headerView()

                        Divider()

                        LazyVStack(pinnedViews: [.sectionHeaders]) {
                            ForEach(viewStore.days, id: \.self) { day in
                                Section {
                                    let transactions = viewStore.transactionsByDay[day] ?? []
                                    ForEach(transactions) { transaction in
                                        VStack(spacing: 0) {
                                            TransactionView(transaction: transaction)
                                                .padding()
                                            Divider()
                                        }
                                    }
                                } header: {
                                    sectionHeaderView(day: day)
                                } footer: {
                                    if day == viewStore.days.last {
                                        Spacer(minLength: 80)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .onAppear { viewStore.send(.onAppear) }
            .navigationTitle("Transactions")
        }
    }

    @ViewBuilder
    private func headerView() -> some View {
//        GeometryReader { proxy in
            HStack {
                Button {
                    viewStore.send(.previousMonthButtonTapped)
                } label: {
                    Image(systemName: "chevron.backward")
                        .renderingMode(.template)
                        .foregroundColor(.white)
//                        .font(.title)
                        .padding(16)
                }
                .background(
                    Circle()
                        .fill(Color.accentColor)
//                        .frame(width: proxy.size.height, height: proxy.size.height)
                )

                Spacer()

                Text(viewStore.currentDate.formatted(Date.FormatStyle().month(.wide).year()))
                    .font(.title.bold().smallCaps())

                Spacer()

                Button {
                    viewStore.send(.nextMonthButtonTapped)
                } label: {
                    Image(systemName: "chevron.forward")
                        .renderingMode(.template)
                        .foregroundColor(.white)
//                        .font(.title)
                        .padding(16)
                }
                .background(
                    Circle()
                        .fill(Color.accentColor)
//                        .frame(width: proxy.size.height, height: proxy.size.height)
                )
            }
            .padding(16)
//        }
    }

    @ViewBuilder
    private func sectionHeaderView(day: Int) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(viewStore.transactionsByDay[day]!.first!.createdAt.formatted(Date.FormatStyle().year().month().day()))")
                    .font(.caption.bold())
                Spacer()
                HStack {
                    Text("$\(viewStore.balanceByDay[day]!.formatted())")
                        .monospacedDigit()
                        .font(.caption.bold())
                }
            }
            .padding(8)
            .background(.background)
            Divider()
        }
    }
}

struct TransactionsView_Previews: PreviewProvider {

    static var previews: some View {
        TabView {
            TransactionsListView(
                store: Store(
                    initialState: TransactionsList.State(
                        date: .now
                    )
                ) {
                    TransactionsList()
                } withDependencies: {
                    $0.transactionsStore.fetchTransactions = { date in
                        [.mock(), .mock(), .mock(), .mock()]
                    }
                }
            )
            .tabItem {
                Label.init("Transactions", systemImage: "list.bullet.rectangle.portrait")
            }
        }
        .tint(.purple)
    }
}
