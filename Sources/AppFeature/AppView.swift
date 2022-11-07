import AddTransactionFeature
import ComposableArchitecture
import SharedModels
import SwiftUI

public typealias Transaction = SharedModels.Transaction

public struct AppFeature: ReducerProtocol {
  public struct State: Equatable {
    public var addTransaction: AddTransaction.State?
    public var transactions: [Transaction]

    public init(
      addTransaction: AddTransaction.State? = nil,
      transactions: [Transaction] = []
    ) {
      self.addTransaction = addTransaction
      self.transactions = transactions
    }
  }

  public enum Action: Equatable {
    case addTransaction(AddTransaction.Action)
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
    let isAddingTransaction: Bool
    let transactions: [Transaction]

    init(state: AppFeature.State) {
      self.addTransaction = state.addTransaction
      self.isAddingTransaction = state.addTransaction != nil
      self.transactions = state.transactions
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
              Text("$0")
            }
            Spacer()
            HStack {
              Text("Expensas")
              Text("$0")
            }

            Spacer()
            HStack {
              Text("Worth")
              Text("$0")
            }
            Spacer()
          }
          Divider()

          Text("October")
            .font(.largeTitle.bold().lowercaseSmallCaps())

          List {
            ForEach(viewStore.transactions) { transaction in
              HStack {
                Text("\(transaction.description)")
                Spacer()
                Text("\(transaction.value)")
              }
            }
            .listRowSeparator(.hidden)
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

struct AppView_Previews: PreviewProvider {
  static var previews: some View {
    AppView(
      store: .init(
        initialState: .init(transactions: []),
        reducer: AppFeature()
      )
    )
  }
}
