import ComposableArchitecture
import SharedModels
import SwiftUI

public typealias Transaction = SharedModels.Transaction

public struct AddTransaction: Reducer {
    public struct State: Equatable {
        public var isDatePickerVisible: Bool
        public var transaction: Transaction

        public init(
            isDatePickerVisible: Bool = false,
            transaction: Transaction? = nil
        ) {
            self.isDatePickerVisible = isDatePickerVisible
            self.transaction = transaction ?? Transaction(absoluteValue: 0, createdAt: Date(), description: "", transactionType: .expense)
        }
    }

    public enum Action: Equatable {
        case dateButtonTapped
        case saveButtonTapped
        case setCreationDate(Date)
        case setDescription(String)
        case setValue(String)
        case transactionTypeChanged(Transaction.TransactionType)
    }

    public init() {}

    public func reduce(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .dateButtonTapped:
            state.isDatePickerVisible.toggle()
            return .none

        case .saveButtonTapped:
            return .none

        case let .setCreationDate(creationDate):
            state.transaction.createdAt = creationDate
            state.isDatePickerVisible = false
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

    private let store: StoreOf<AddTransaction>
    @ObservedObject private var viewStore: ViewStore<ViewState, AddTransaction.Action>

    private struct ViewState: Equatable {
        let date: Date
        let description: String
        let isDatePickerVisible: Bool
        let transactionType: Transaction.TransactionType
        let value: String

        init(state: AddTransaction.State) {
            self.date = state.transaction.createdAt
            self.description = state.transaction.description
            self.isDatePickerVisible = state.isDatePickerVisible
            self.transactionType = state.transaction.transactionType
            self.value = state.transaction.absoluteValue == 0 ? "" : state.transaction.absoluteValue.description
        }
    }

    public init(store: StoreOf<AddTransaction>) {
        self.store = store
        self.viewStore = .init(store, observe: ViewState.init)
    }

    public var body: some View {
        VStack(spacing: 10) {
            Text("New Transaction")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    Form {

//                    header: {
//                            Text("Hola")
//                        }

                    }
//                    .formStyle(.columns)
//                    HStack(alignment: .lastTextBaseline) {
//                        Text("$")
//                            .font(.system(size: 40))
//                            .offset(y: -5)
//                        TextField("0", text: viewStore.binding(get: \.value, send: AddTransaction.Action.setValue))
//                            .font(.system(size: 80).bold())
//                            .keyboardType(.numberPad)
//                            .focused($valueInFocus, equals: .value)
//                    }
//
//                    Picker("Type", selection: viewStore.binding(get: \.transactionType, send: AddTransaction.Action.transactionTypeChanged)) {
//                        Text("Expense").tag(Transaction.TransactionType.expense)
//                        Text("Income").tag(Transaction.TransactionType.income)
//                    }
//                    .pickerStyle(.segmented)


                    TextField("0", text: viewStore.binding(get: \.value, send: AddTransaction.Action.setValue))
                        .font(.system(size: 80).bold())
                        .keyboardType(.numberPad)
                        .focused($valueInFocus, equals: .value)

                    if !viewStore.isDatePickerVisible {
                        Button {
                            viewStore.send(.dateButtonTapped)
                        } label: {
                            Text("\(viewStore.date.formatted(Date.FormatStyle().day().month(.wide).year()))")
                        }
                        .font(.title3.bold())
                        .padding(8)
                    } else {
                        DatePicker(
                            "",
                            selection: viewStore.binding(
                                get: \.date,
                                send: AddTransaction.Action.setCreationDate
                            ).animation(),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                    }

//                    Divider()

                    TextField(
                        "Description",
                        text: viewStore.binding(
                            get: \.description,
                            send: AddTransaction.Action.setDescription
                        ),
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 30))
                    .submitLabel(.done)
                    .focused($valueInFocus, equals: .description)
                    .onSubmit { viewStore.send(.saveButtonTapped) }

                    Button("Save") {
                        viewStore.send(.saveButtonTapped)
                    }
                    .font(.headline)
                    .frame(height: 50)
                }
            }
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
                    store: Store(initialState: AddTransaction.State()) {
                        AddTransaction()
                    }
                )
                .tint(.purple)
            }
    }
}
