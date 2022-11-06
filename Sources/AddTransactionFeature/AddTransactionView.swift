import ComposableArchitecture
import SwiftUI

public struct AddTransaction: ReducerProtocol {
  public struct State: Equatable {
    public var value: Int?

    public init(
      value: Int? = nil
    ) {
      self.value = value
    }
  }

  public enum Action: Equatable {
    case saveButtonTapped
    case setValue(String)
  }

  public init() {}
  
  public func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
    switch action {
    case .saveButtonTapped:
      return .none

    case let .setValue(value):
      if value.isEmpty {
        state.value = nil
      } else if let value = Int(value) {
        state.value = value
      } else {
        // TODO: show error
      }
      return .none
    }
  }
}

public struct AddTransactionView: View {

  @FocusState private var valueInFocus: Bool
  @State private var pickerSelection = 0
  @State private var description: String = ""
  @State private var date: String = "Today"
  @Environment(\.dismiss) private var dismiss

  private let store: StoreOf<AddTransaction>
  @ObservedObject private var viewStore: ViewStore<ViewState, AddTransaction.Action>

  private struct ViewState: Equatable {
    let value: String

    init(state: AddTransaction.State) {
        self.value = state.value?.description ?? ""
    }
  }

  public init(
    store: StoreOf<AddTransaction>
  ) {
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

      TextField("Description", text: $description)
        .font(.system(size: 30))
        .submitLabel(.done)
        .onSubmit {
          dismiss()
        }

      Spacer()

      Button("Save") {
        dismiss()
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
