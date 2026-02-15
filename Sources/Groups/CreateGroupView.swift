import ComposableArchitecture
import Currency
import SQLiteData
import SwiftUI

@Reducer
struct CreateGroupReducer: Reducer {
    @ObservableState
    struct State: Equatable {
        @Presents var alert: AlertState<Action.Alert>?
        var name = ""
        var description = ""
        var creatorName = "Me"
        var defaultCurrencyCode = "USD"
        var isSaving = false

        let currencyCodes: [String] = CurrencyRegistry.all.keys.sorted()
    }

    enum Action: BindableAction, ViewAction {
        @CasePathable
        enum Alert {
            case dismiss
        }
        @CasePathable
        enum Delegate {
            case created(TransactionGroup.ID)
        }
        @CasePathable
        enum View {
            case cancelTapped
            case saveTapped
        }

        case alert(PresentationAction<Alert>)
        case binding(BindingAction<State>)
        case delegate(Delegate)
        case view(View)
        case setError(String)
    }

    @Dependency(\.dismiss) var dismiss
    @Dependency(\.groupClient) var groupClient

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .alert:
                return .none

            case .binding:
                return .none

            case .delegate:
                return .none

            case let .setError(message):
                state.isSaving = false
                state.alert = AlertState {
                    TextState("Could not create group")
                } actions: {
                    ButtonState(action: .dismiss) {
                        TextState("OK")
                    }
                } message: {
                    TextState(message)
                }
                return .none

            case let .view(view):
                switch view {
                case .cancelTapped:
                    return .run { _ in await dismiss() }

                case .saveTapped:
                    let name = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let creatorName = state.creatorName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else {
                        return .send(.setError("Please enter a group name."))
                    }

                    state.isSaving = true
                    return .run { [description = state.description, defaultCurrencyCode = state.defaultCurrencyCode] send in
                        do {
                            let groupID = try await groupClient.createGroup(
                                name,
                                description,
                                defaultCurrencyCode,
                                creatorName.isEmpty ? "Me" : creatorName
                            )
                            await send(.delegate(.created(groupID)))
                        } catch {
                            await send(.setError(error.localizedDescription))
                        }
                    }
                }
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}

@ViewAction(for: CreateGroupReducer.self)
struct CreateGroupView: View {
    @Bindable var store: StoreOf<CreateGroupReducer>

    var body: some View {
        Form {
            Section("Details") {
                TextField("Group name", text: $store.name)
                TextField("Description", text: $store.description, axis: .vertical)
                TextField("Your name in this group", text: $store.creatorName)
            }

            Section("Currency") {
                Picker("Default currency", selection: $store.defaultCurrencyCode) {
                    ForEach(store.currencyCodes, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
            }
        }
        .navigationTitle("New Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    send(.cancelTapped)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    send(.saveTapped)
                }
                .disabled(store.isSaving || store.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .alert($store.scope(state: \.alert, action: \.alert))
    }
}

#Preview {
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
    }
    NavigationStack {
        CreateGroupView(
            store: Store(initialState: CreateGroupReducer.State()) {
                CreateGroupReducer()
            }
        )
    }
}
