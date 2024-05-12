import ComposableArchitecture
import SharedModels
import SwiftUI

@Reducer
public struct TransactionForm: Reducer {
    @ObservableState
    public struct State: Equatable {
        public var isDatePickerVisible: Bool
        public var transaction: SharedModels.Transaction

        var value: String {
            transaction.absoluteValue == 0 ? "" : transaction.absoluteValue.description
        }

        public init(
            isDatePickerVisible: Bool = false,
            transaction: SharedModels.Transaction? = nil
        ) {
            self.isDatePickerVisible = isDatePickerVisible
            self.transaction = transaction ?? SharedModels.Transaction(absoluteValue: 0, createdAt: Date(), description: "", transactionType: .expense)
        }
    }

    public enum Action: Equatable {
        case dateButtonTapped
        case saveButtonTapped
        case setCreationDate(Date)
        case setDescription(String)
        case setValue(String)
        case transactionTypeChanged(SharedModels.Transaction.TransactionType)
    }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
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
}

public struct TransactionFormView: View {

    enum Field {
        case value, description
    }

    @FocusState private var valueInFocus: Field?

    @Bindable var store: StoreOf<TransactionForm>

    public init(store: StoreOf<TransactionForm>) {
        self.store = store
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


                    TextField("0", text: $store.value.sending(\.setValue))
                        .font(.system(size: 80).bold())
                        .keyboardType(.numberPad)
                        .focused($valueInFocus, equals: .value)

                    if !store.isDatePickerVisible {
                        Button {
                            store.send(.dateButtonTapped)
                        } label: {
                            Text("\(store.transaction.createdAt.formatted(Date.FormatStyle().day().month(.wide).year()))")
                        }
                        .font(.title3.bold())
                        .padding(8)
                    } else {
                        DatePicker(
                            "",
                            selection: $store.transaction.createdAt.sending(\.setCreationDate),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                    }

//                    Divider()

                    TextField(
                        "Description",
                        text: $store.transaction.description.sending(\.setDescription),
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 30))
                    .submitLabel(.done)
                    .focused($valueInFocus, equals: .description)
                    .onSubmit { store.send(.saveButtonTapped) }

                    Button("Save") {
                        store.send(.saveButtonTapped)
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

struct TransactionFormView_Previews: PreviewProvider {
    static var previews: some View {
        Color.black
            .ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                TransactionFormView(
                    store: Store(initialState: TransactionForm.State()) {
                        TransactionForm()
                    }
                )
                .tint(.purple)
            }
    }
}
