import AddTransactionFeature
import ComposableArchitecture
import SharedModels
import SwiftUI

public struct AppFeature: ReducerProtocol {
  public struct State: Equatable {
    public var addTransaction: AddTransaction.State?
    public var transactions: [SharedModels.Transaction]

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
      transactions: [SharedModels.Transaction] = []
    ) {
      self.addTransaction = addTransaction
      self.transactions = transactions
    }
  }

  public enum Action: Equatable {
    case addTransaction(AddTransaction.Action)
    case deleteTransactions(IndexSet)
    case newTransactionButtonTapped
    case setAddTransactionSheetPresented(Bool)
  }

  public init() {}

  public var body: some ReducerProtocol<State, Action> {
    Reduce { state, action in
      switch action {
      case .addTransaction(.saveButtonTapped):
        defer { state.addTransaction = nil }
        guard let transaction = state.addTransaction?.transaction else { return .none }
        state.transactions.insert(transaction, at: 0)
        return .none

      case .addTransaction:
        return .none

      case let .deleteTransactions(indices):
        state.transactions.remove(atOffsets: indices)
        return .none

      case .newTransactionButtonTapped:
        state.addTransaction = .init()
        return .none

      case let .setAddTransactionSheetPresented(presented):
        if !presented {
          state.addTransaction = nil
        }
        return .none
      }
    }
    .ifLet(\.addTransaction, action: /Action.addTransaction) {
      AddTransaction()
    }
    ._printChanges()
  }
}

public struct AppView: View {

  private struct ViewState: Equatable {
    let addTransaction: AddTransaction.State?
    let dates: [Date]
    let isAddingTransaction: Bool
    let monthlySummary: MonthlySummary
    let transactions: [Date: [SharedModels.Transaction]]

    init(state: AppFeature.State) {
      self.addTransaction = state.addTransaction
      self.isAddingTransaction = state.addTransaction != nil
      self.monthlySummary = state.monthlySummary
      let sortedTransactions = state.transactions.sorted(by: { $0.date < $1.date })
      self.transactions = Dictionary(grouping: sortedTransactions, by: \.date)
      self.dates = transactions.keys.sorted(by: { $0 < $1 })
    }
  }

  private let store: StoreOf<AppFeature>
  @ObservedObject private var viewStore: ViewStore<ViewState, AppFeature.Action>

  public init(store: StoreOf<AppFeature>) {
    self.store = store
    self.viewStore = .init(store.scope(state: ViewState.init))
  }

  public var body: some View {
    NavigationStack {
      ZStack(alignment: .bottom) {
        VStack {
          Divider()
          HStack {
            Spacer()
            HStack {
              Text("Income")
              Text("$\(viewStore.monthlySummary.income.formatted())")
                .monospacedDigit()
                .bold()
            }
            Spacer()
            HStack {
              Text("Expenses")
              Text("$\(viewStore.monthlySummary.expenses.formatted())")
                .monospacedDigit()
                .bold()
            }

            Spacer()
            HStack {
              Text("Worth")
              Text("$\(viewStore.monthlySummary.worth.formatted())")
                .monospacedDigit()
                .bold()
            }
            Spacer()
          }
          Divider()

          Text("October")
            .font(.largeTitle.bold().lowercaseSmallCaps())

          List {
            ForEach(viewStore.dates, id: \.self) { (date: Date) in
              Section {
                ForEach(viewStore.transactions[date] ?? [], content: TransactionView.init)
                  .onDelete { indices in
                    viewStore.send(.deleteTransactions(indices))
                  }
                  .listRowSeparator(.hidden)
              } header: {
                HStack {
                  Text("\(date.formatted(date: .long, time: .omitted))")
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
          .frame(width: 80, height: 80)
        }
      }
      .navigationTitle("Overview")
      .sheet(
        isPresented: viewStore.binding(
          get: \.isAddingTransaction,
          send: AppFeature.Action.setAddTransactionSheetPresented
        )
      ) {
        IfLetStore(
          store.scope(
            state: \.addTransaction,
            action: AppFeature.Action.addTransaction
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

struct AppView_Previews: PreviewProvider {
  static var previews: some View {
    AppView(
      store: .init(
        initialState: .init(
          transactions: [.mock]
        ),
        reducer: AppFeature()
      )
    )
  }
}
