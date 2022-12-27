import ComposableArchitecture
import SharedModels
import SwiftUI

public typealias Transaction = SharedModels.Transaction

public struct AddTransaction: ReducerProtocol {
  public struct State: Equatable {
    public var transaction: Transaction?
    public var description: String

    public init(
      value: Transaction? = nil
    ) {
      self.description = value?.description ?? ""
      self.transaction = value
    }
  }

  public enum Action: Equatable {
    case saveButtonTapped
    case setDescription(String)
    case setValue(String)
  }

  public init() {}
  
  public func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
    switch action {
    case .saveButtonTapped:
      return .none

    case let .setDescription(description):
      state.description = description
      state.transaction?.description = description
      return .none

    case let .setValue(value):
      // Reset state
      guard !value.isEmpty else {
        state.transaction = nil
        return .none
      }

      guard let value = Int(value) else {
        // TODO: show error
        return .none
      }

      if var transaction = state.transaction {
        transaction.value = value
        state.transaction = transaction
      } else {
        state.transaction = .init(
          date: Date(),
          description: state.description,
          value: value
        )
      }

      return .none
    }
  }
}

public struct AddTransactionView: View {

  @FocusState private var valueInFocus: Bool
  @State private var pickerSelection = 0
  @State private var date: String = "Today"

  private let store: StoreOf<AddTransaction>
  @ObservedObject private var viewStore: ViewStore<ViewState, AddTransaction.Action>

  private struct ViewState: Equatable {
    let value: String
    let description: String

    init(state: AddTransaction.State) {
      self.value = state.transaction?.value.description ?? ""
      self.description = state.description
    }
  }

  public init(store: StoreOf<AddTransaction>) {
    self.store = store
    self.viewStore = .init(store.scope(state: ViewState.init))
  }

  public var body: some View {
    VStack(spacing: 10) {
      Text("New Transaction")

      HStack(alignment: .lastTextBaseline) {
        Text("$")
          .font(.system(size: 40))
          .offset(y: -5)
        TextField("0", text: viewStore.binding(get: \.value, send: AddTransaction.Action.setValue))
          .font(.system(size: 80).bold())
          .keyboardType(.numberPad)
          .focused($valueInFocus)
      }

      Picker("", selection: $pickerSelection) {
        Text("Expense").tag(0)
        Text("Income").tag(1)
      }
      .pickerStyle(.segmented)

      TextField("Date", text: $date)
        .font(.system(size: 30))

      Divider()

      TextField("Description", text: viewStore.binding(get: \.description, send: AddTransaction.Action.setDescription))
        .font(.system(size: 30))
        .submitLabel(.done)
        .onSubmit {
          viewStore.send(.saveButtonTapped)
        }

      Spacer()

      Button("Save") {
        viewStore.send(.saveButtonTapped)
      }
      .frame(height: 50)
    }
    .padding(.horizontal)
    .padding(.top)
    .onAppear {
      valueInFocus = true
    }
  }
}

struct AddTransactionView_Previews: PreviewProvider {
  static var previews: some View {
    Color.black
      .ignoresSafeArea()
      .sheet(isPresented: .constant(true)) {
        AddTransactionView(
          store: .init(
            initialState: .init(),
            reducer: AddTransaction()
          )
        )
        .tint(.purple)
      }
  }
}
