import ComposableArchitecture
import SwiftUI

@Reducer
struct AddMemberReducer: Reducer {
    @ObservableState
    struct State: Equatable {
        var name = ""
    }

    enum Action: BindableAction, ViewAction {
        @CasePathable
        enum Delegate {
            case saved(String)
            case cancelled
        }
        @CasePathable
        enum View {
            case cancelTapped
            case saveTapped
        }
        case binding(BindingAction<State>)
        case delegate(Delegate)
        case view(View)
    }

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
            case .delegate:
                return .none
            case let .view(view):
                switch view {
                case .cancelTapped:
                    return .send(.delegate(.cancelled))
                case .saveTapped:
                    let name = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return .none }
                    return .send(.delegate(.saved(name)))
                }
            }
        }
    }
}

@ViewAction(for: AddMemberReducer.self)
struct AddMemberView: View {
    @Bindable var store: StoreOf<AddMemberReducer>

    var body: some View {
        Form {
            TextField("Member name", text: $store.name)
        }
        .navigationTitle("Add Member")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { send(.cancelTapped) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { send(.saveTapped) }
                    .disabled(store.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AddMemberView(
            store: Store(initialState: AddMemberReducer.State()) {
                AddMemberReducer()
            }
        )
    }
}
