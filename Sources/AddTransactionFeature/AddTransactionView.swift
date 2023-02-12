import ComposableArchitecture
import SharedModels
import SwiftUI

public typealias Transaction = SharedModels.Transaction

public struct AddTransaction: ReducerProtocol {
    public struct State: Equatable {
        public var transaction: Transaction

        public init(
            transaction: Transaction? = nil
        ) {
            self.transaction = transaction ?? Transaction(absoluteValue: 0, createdAt: Date(), description: "", transactionType: .expense)
        }
    }

    public enum Action: Equatable {
        case saveButtonTapped
        case setDescription(String)
        case setValue(String)
        case transactionTypeChanged(Transaction.TransactionType)
    }

    public init() {}

    public func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
        switch action {
        case .saveButtonTapped:
            return .none

        case let .setDescription(description):
            state.transaction.description = description
            return .none

        case let .setValue(value):
            // Reset state
            guard !value.isEmpty else {
//                state.transaction = nil
                return .none
            }

            guard let value = Int(value) else {
                // TODO: show error
                return .none
            }

            state.transaction.absoluteValue = value
            return .none

        case let .transactionTypeChanged(transactionType):
            state.transaction.transactionType = transactionType
            return .none
        }
    }
}

public struct AddTransactionView: View {

    enum Field {
        case value, description
    }

    @FocusState private var valueInFocus: Field?
    @State private var date: String = "Today"

    private let store: StoreOf<AddTransaction>
    @ObservedObject private var viewStore: ViewStore<ViewState, AddTransaction.Action>

    private struct ViewState: Equatable {
        let value: String
        let description: String
        var transactionType: Transaction.TransactionType

        init(state: AddTransaction.State) {
            self.value = state.transaction.absoluteValue == 0 ? "" : state.transaction.absoluteValue.description
            self.description = state.transaction.description
            self.transactionType = state.transaction.transactionType
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
                    .focused($valueInFocus, equals: .value)
            }

            Picker("Type", selection: viewStore.binding(get: \.transactionType, send: AddTransaction.Action.transactionTypeChanged)) {
                Text("Expense").tag(Transaction.TransactionType.expense)
                Text("Income").tag(Transaction.TransactionType.income)
            }
            .pickerStyle(.segmented)

            TextField("Date", text: $date)
                .font(.system(size: 30))

            Divider()

            TextField(
                "Description",
                text: viewStore.binding(
                    get: \.description,
                    send: AddTransaction.Action.setDescription
                )
            )
            .font(.system(size: 30))
            .submitLabel(.done)
            .focused($valueInFocus, equals: .description)
            .onSubmit { viewStore.send(.saveButtonTapped) }

            Spacer()

            Button("Save") {
                viewStore.send(.saveButtonTapped)
            }
            .frame(height: 50)
        }
        .padding(.horizontal)
        .padding(.top)
        .onAppear {
            valueInFocus = .value
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
