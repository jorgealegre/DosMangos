import ComposableArchitecture
import SharedModels
import SwiftUI

@Reducer
public struct TransactionForm: Reducer {
    @ObservableState
    public struct State: Equatable {
        public enum Field {
            case value, description
        }

        public var isDatePickerVisible: Bool
        public var focus: Field?
        public var transaction: SharedModels.Transaction

        var value: String {
            transaction.absoluteValue == 0 ? "" : transaction.absoluteValue.description
        }

        public init(
            isDatePickerVisible: Bool = false,
            focus: Field? = .value,
            transaction: SharedModels.Transaction? = nil
        ) {
            self.isDatePickerVisible = isDatePickerVisible
            self.focus = focus
            self.transaction = transaction ?? SharedModels.Transaction(absoluteValue: 0, createdAt: Date(), description: "", transactionType: .expense)
        }
    }

    public enum Action: ViewAction, BindableAction {
        public enum Delegate {
            case saveTransaction(SharedModels.Transaction)
        }
        @CasePathable
        public enum View: Equatable {
            case dateButtonTapped
            case nextDayButtonTapped
            case previousDayButtonTapped
            case saveButtonTapped
            case setCreationDate(Date)
            case setDescription(String)
            case setValue(String)
            case valueInputFinished
        }
        case binding(BindingAction<State>)
        case delegate(Delegate)
        case view(View)
        case transactionTypeChanged(SharedModels.Transaction.TransactionType)
    }

    public init() {}

    public var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .delegate:
                return .none

            case let .view(view):
                switch view {
                case .dateButtonTapped:
                    state.isDatePickerVisible.toggle()
                    return .none

                case .nextDayButtonTapped:
                    state.transaction.createdAt.addTimeInterval(60*60*24)
                    return .none

                case .previousDayButtonTapped:
                    state.transaction.createdAt.addTimeInterval(-60*60*24)
                    return .none

                case .saveButtonTapped:
                    return .send(.delegate(.saveTransaction(state.transaction)))

                case let .setCreationDate(creationDate):
                    state.transaction.createdAt = creationDate
                    return .none

                case let .setDescription(description):
                    state.transaction.description = description
                    return .none

                case let .setValue(value):
                    // Reset state
                    guard !value.isEmpty else {
                        return .none
                    }

                    guard let value = Int(value) else {
                        // TODO: show error
                        return .none
                    }

                    state.transaction.absoluteValue = value
                    return .none

                case .valueInputFinished:
                    state.focus = .description
                    return .none
                }

            case let .transactionTypeChanged(transactionType):
                state.transaction.transactionType = transactionType
                return .none
            }
        }
        ._printChanges()
    }
}

@ViewAction(for: TransactionForm.self)
public struct TransactionFormView: View {

    @FocusState var focus: TransactionForm.State.Field?

    @Bindable public var store: StoreOf<TransactionForm>

    public init(store: StoreOf<TransactionForm>) {
        self.store = store
    }

    public var body: some View {
        Form {
            valueInput
            typePicker
            dateTimePicker
            descriptionInput
            saveButton
        }
        .bind($store.focus, to: $focus)
    }

    @ViewBuilder
    private var valueInput: some View {
        TextField("0", text: $store.value.sending(\.view.setValue))
            .font(.system(size: 80).bold())
            .keyboardType(.numberPad)
            .focused($focus, equals: .value)
            .onSubmit { send(.valueInputFinished) }
    }

    @ViewBuilder
    private var typePicker: some View {
        Picker("Type", selection: $store.transaction.transactionType) {
            Text("Expense").tag(Transaction.TransactionType.expense)
            Text("Income").tag(Transaction.TransactionType.income)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var dateTimePicker: some View {
        Section {
            HStack {
                Button {
                    send(.dateButtonTapped, animation: .default)
                } label: {
                    // TODO: show this as Today, Yesterday, etc
                    Text("\(store.transaction.createdAt.formatted(Date.FormatStyle().day().month(.wide).year()))")
                }

                Spacer()

                Button {
                    send(.previousDayButtonTapped)
                } label: {
                    Image(systemName: "chevron.backward")
                        .renderingMode(.template)
                        .foregroundColor(.accentColor)
                        .padding(8)
                }
                Button {
                    send(.nextDayButtonTapped)
                } label: {
                    Image(systemName: "chevron.forward")
                        .renderingMode(.template)
                        .foregroundColor(.accentColor)
                        .padding(8)
                }
            }
            .buttonStyle(BorderlessButtonStyle())

            if store.isDatePickerVisible {
                DatePicker(
                    "",
                    selection: $store.transaction.createdAt.sending(\.view.setCreationDate),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .transition(.identity)
            }
        }
    }

    @ViewBuilder
    private var descriptionInput: some View {
        Section {
            TextField(
                "Description",
                text: Binding(
                    get: {
                        store.transaction.description
                    },
                    set: { newDescription in
                        if Set(newDescription).subtracting(Set(store.transaction.description)).contains("\n") {
                            // submit happened
                            send(.saveButtonTapped)
                        } else {
                            send(.setDescription(newDescription))
                        }
                    }
                ),
                axis: .vertical
            )
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($focus, equals: .description)
        }
    }

    @ViewBuilder
    private var saveButton: some View {
        Section {
            Button("Save") {
                send(.saveButtonTapped)
            }
        }
    }
}

struct TransactionFormView_Previews: PreviewProvider {
    static var previews: some View {
        Color.black
            .ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                NavigationStack {
                    TransactionFormView(
                        store: Store(initialState: TransactionForm.State()) {
                            TransactionForm()
                        }
                    )
                    .navigationTitle("New Transaction")
                }
                .tint(.purple)
                .preferredColorScheme(.dark)
            }
    }
}
