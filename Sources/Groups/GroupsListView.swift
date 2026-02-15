import ComposableArchitecture
import SQLiteData
import SwiftUI

@Reducer
struct GroupsReducer: Reducer {
    @ObservableState
    struct State: Equatable {
        var path = StackState<Path.State>()
        @Presents var destination: Destination.State?
        @FetchAll(
            TransactionGroup
                .order { $0.createdAtUTC.desc() }
        )
        var groups: [TransactionGroup]
    }

    @Reducer
    enum Destination {
        case createGroup(CreateGroupReducer)
    }

    @Reducer
    enum Path {
        case groupDetail(GroupDetailReducer)
    }

    enum Action: ViewAction {
        @CasePathable
        enum View {
            case addGroupTapped
            case groupTapped(TransactionGroup.ID)
            case deleteGroups(IndexSet)
        }
        case destination(PresentationAction<Destination.Action>)
        case path(StackActionOf<Path>)
        case view(View)
    }

    @Dependency(\.groupClient) var groupClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .destination(.presented(.createGroup(.delegate(.created(groupID))))):
                state.destination = nil
                state.path.append(.groupDetail(GroupDetailReducer.State(groupID: groupID)))
                return .none

            case .destination:
                return .none

            case let .path(.element(id: _, action: .groupDetail(.delegate(.deleted(groupID))))):
                for index in state.path.indices.reversed() {
                    if case let .groupDetail(groupDetailState) = state.path[index],
                       groupDetailState.groupID == groupID {
                        state.path.remove(at: index)
                    }
                }
                return .none

            case .path:
                return .none

            case let .view(view):
                switch view {
                case .addGroupTapped:
                    state.destination = .createGroup(CreateGroupReducer.State())
                    return .none

                case let .groupTapped(groupID):
                    state.path.append(.groupDetail(GroupDetailReducer.State(groupID: groupID)))
                    return .none

                case let .deleteGroups(indexSet):
                    let ids = indexSet.compactMap { index in
                        state.groups.indices.contains(index) ? state.groups[index].id : nil
                    }
                    return .run { _ in
                        for id in ids {
                            try await groupClient.deleteGroup(id)
                        }
                    }
                }
            }
        }
        .ifLet(\.$destination, action: \.destination)
        .forEach(\.path, action: \.path)
    }
}

extension GroupsReducer.Path.State: Equatable {}
extension GroupsReducer.Destination.State: Equatable {}

@ViewAction(for: GroupsReducer.self)
struct GroupsView: View {
    @Bindable var store: StoreOf<GroupsReducer>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            List {
                if store.groups.isEmpty {
                    ContentUnavailableView("No groups yet", systemImage: "person.3")
                } else {
                    ForEach(store.groups) { group in
                        Button {
                            send(.groupTapped(group.id))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name)
                                    .font(.headline)
                                if !group.description.isEmpty {
                                    Text(group.description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        send(.deleteGroups(indexSet), animation: .default)
                    }
                }
            }
            .navigationTitle("Groups")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        send(.addGroupTapped)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(
                item: $store.scope(
                    state: \.destination?.createGroup,
                    action: \.destination.createGroup
                )
            ) { createStore in
                NavigationStack {
                    CreateGroupView(store: createStore)
                }
            }
        } destination: { store in
            switch store.case {
            case let .groupDetail(groupStore):
                GroupDetailView(store: groupStore)
            }
        }
    }
}

#Preview {
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
        try seedSampleData()

        try $0.defaultDatabase.write { db in
            try db.seed {
                TransactionGroup(
                    id: UUID(0),
                    name: "Friends",
                    description: "",
                    defaultCurrencyCode: "USD",
                    simplifyDebts: true,
                    createdAtUTC: Date()
                )
            }
        }
    }
    GroupsView(
        store: Store(initialState: GroupsReducer.State()) {
            GroupsReducer()
        }
    )
}
