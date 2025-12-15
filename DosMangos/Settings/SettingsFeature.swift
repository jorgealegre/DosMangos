import ComposableArchitecture
import SQLiteData
import SwiftUI

// MARK: - Settings (Tab Root)

@Reducer
struct Settings: Reducer {
    @ObservableState
    struct State: Equatable {
        var path = StackState<Path.State>()
    }

    enum Action: ViewAction {
        enum View {
            case categoriesTileTapped
            case tagsTileTapped
        }

        case path(StackActionOf<Path>)
        case view(View)
    }

    @Reducer
    enum Path {
        case categories(ManageCategories)
        case tags(ManageTags)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .path:
                return .none

            case let .view(view):
                switch view {
                case .categoriesTileTapped:
                    state.path.append(.categories(ManageCategories.State()))
                    return .none

                case .tagsTileTapped:
                    state.path.append(.tags(ManageTags.State()))
                    return .none
                }
            }
        }
        .forEach(\.path, action: \.path)
    }
}

extension Settings.Path.State: Equatable {}

@ViewAction(for: Settings.self)
struct SettingsView: View {
    @Bindable var store: StoreOf<Settings>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            ScrollView {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        Button {
                            send(.categoriesTileTapped)
                        } label: {
                            SettingsTile(
                                title: "Categories",
                                systemImage: "folder.fill"
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            send(.tagsTileTapped)
                        } label: {
                            SettingsTile(
                                title: "Tags",
                                systemImage: "number.square.fill"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            .navigationTitle("Settings")
        } destination: { store in
            switch store.case {
            case let .categories(store):
                ManageCategoriesView(store: store)
            case let .tags(store):
                ManageTagsView(store: store)
            }
        }
    }
}

private struct SettingsTile: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.tint)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.background)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Manage Categories

@Reducer
struct ManageCategories: Reducer {
    @ObservableState
    struct State: Equatable {
        @Presents var destination: Destination.State?

        @FetchAll(Category.order(by: \.title), animation: .default)
        var categories: [Category]
    }

    enum Action: ViewAction {
        enum View {
            case addButtonTapped
            case deleteButtonTapped(Category)
            case editButtonTapped(Category)
        }

        case destination(PresentationAction<Destination.Action>)
        case view(View)
    }

    @Reducer
    enum Destination {
        case editor(SettingsTitleEditor)
    }

    @Dependency(\.defaultDatabase) private var database

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .destination(.presented(.editor(.delegate(.didCancel)))):
                state.destination = nil
                return .none

            case let .destination(.presented(.editor(.delegate(.didSave(originalTitle, newTitle))))):
                state.destination = nil
                guard !newTitle.isEmpty else { return .none }
                return .run { _ in
                    withErrorReporting {
                        try database.write { db in
                            if let originalTitle {
                                try Category
                                    .update { $0.title = newTitle }
                                    .where { $0.title.eq(originalTitle) }
                                    .execute(db)
                            } else {
                                try Category.insert(or: .ignore) {
                                    Category(title: newTitle)
                                }
                                .execute(db)
                            }
                        }
                    }
                }

            case .destination:
                return .none

            case let .view(view):
                switch view {
                case .addButtonTapped:
                    state.destination = .editor(
                        SettingsTitleEditor.State(kind: .category, originalTitle: nil, title: "")
                    )
                    return .none

                case let .editButtonTapped(category):
                    state.destination = .editor(
                        SettingsTitleEditor.State(kind: .category, originalTitle: category.title, title: category.title)
                    )
                    return .none

                case let .deleteButtonTapped(category):
                    return .run { _ in
                        withErrorReporting {
                            try database.write { db in
                                try Category
                                    .where { $0.title.eq(category.title) }
                                    .delete()
                                    .execute(db)
                            }
                        }
                    }
                }
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension ManageCategories.Destination.State: Equatable {}

@ViewAction(for: ManageCategories.self)
struct ManageCategoriesView: View {
    @Bindable var store: StoreOf<ManageCategories>

    var body: some View {
        List {
            ForEach(store.categories) { category in
                Text(category.title)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", role: .destructive) {
                            send(.deleteButtonTapped(category))
                        }
                        Button("Edit") {
                            send(.editButtonTapped(category))
                        }
                    }
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    send(.addButtonTapped)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(
            item: $store.scope(state: \.destination?.editor, action: \.destination.editor)
        ) { store in
            NavigationStack {
                SettingsTitleEditorView(store: store)
            }
        }
    }
}

// MARK: - Manage Tags

@Reducer
struct ManageTags: Reducer {
    @ObservableState
    struct State: Equatable {
        @Presents var destination: Destination.State?

        @FetchAll(Tag.order(by: \.title), animation: .default)
        var tags: [Tag]
    }

    enum Action: ViewAction {
        enum View {
            case addButtonTapped
            case deleteButtonTapped(Tag)
            case editButtonTapped(Tag)
        }

        case destination(PresentationAction<Destination.Action>)
        case view(View)
    }

    @Reducer
    enum Destination {
        case editor(SettingsTitleEditor)
    }

    @Dependency(\.defaultDatabase) private var database

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .destination(.presented(.editor(.delegate(.didCancel)))):
                state.destination = nil
                return .none

            case let .destination(.presented(.editor(.delegate(.didSave(originalTitle, newTitle))))):
                state.destination = nil
                guard !newTitle.isEmpty else { return .none }
                return .run { _ in
                    withErrorReporting {
                        try database.write { db in
                            if let originalTitle {
                                try Tag
                                    .update { $0.title = newTitle }
                                    .where { $0.title.eq(originalTitle) }
                                    .execute(db)
                            } else {
                                try Tag.insert(or: .ignore) {
                                    Tag(title: newTitle)
                                }
                                .execute(db)
                            }
                        }
                    }
                }

            case .destination:
                return .none

            case let .view(view):
                switch view {
                case .addButtonTapped:
                    state.destination = .editor(
                        SettingsTitleEditor.State(kind: .tag, originalTitle: nil, title: "")
                    )
                    return .none

                case let .editButtonTapped(tag):
                    state.destination = .editor(
                        SettingsTitleEditor.State(kind: .tag, originalTitle: tag.title, title: tag.title)
                    )
                    return .none

                case let .deleteButtonTapped(tag):
                    return .run { _ in
                        withErrorReporting {
                            try database.write { db in
                                try Tag
                                    .where { $0.title.eq(tag.title) }
                                    .delete()
                                    .execute(db)
                            }
                        }
                    }
                }
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension ManageTags.Destination.State: Equatable {}

@ViewAction(for: ManageTags.self)
struct ManageTagsView: View {
    @Bindable var store: StoreOf<ManageTags>

    var body: some View {
        List {
            ForEach(store.tags) { tag in
                Text(tag.title)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", role: .destructive) {
                            send(.deleteButtonTapped(tag))
                        }
                        Button("Edit") {
                            send(.editButtonTapped(tag))
                        }
                    }
            }
        }
        .navigationTitle("Tags")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    send(.addButtonTapped)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(
            item: $store.scope(state: \.destination?.editor, action: \.destination.editor)
        ) { store in
            NavigationStack {
                SettingsTitleEditorView(store: store)
            }
        }
    }
}

// MARK: - Shared Editor

@Reducer
struct SettingsTitleEditor: Reducer {
    @ObservableState
    struct State: Equatable {
        enum Kind: Equatable {
            case category
            case tag

            var title: String {
                switch self {
                case .category: "Category"
                case .tag: "Tag"
                }
            }

            var placeholder: String {
                switch self {
                case .category: "Category name"
                case .tag: "Tag name"
                }
            }
        }

        var kind: Kind
        var originalTitle: String?
        var title: String
    }

    enum Action: BindableAction {
        enum Delegate: Equatable {
            case didCancel
            case didSave(originalTitle: String?, newTitle: String)
        }

        case binding(BindingAction<State>)
        case cancelButtonTapped
        case saveButtonTapped
        case delegate(Delegate)
    }

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .cancelButtonTapped:
                return .send(.delegate(.didCancel))

            case .saveButtonTapped:
                let trimmed = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return .send(.delegate(.didSave(originalTitle: state.originalTitle, newTitle: trimmed)))

            case .delegate:
                return .none
            }
        }
    }
}

struct SettingsTitleEditorView: View {
    @Bindable var store: StoreOf<SettingsTitleEditor>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField(store.kind.placeholder, text: $store.title)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle(store.originalTitle == nil ? "New \(store.kind.title)" : "Edit \(store.kind.title)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    store.send(.cancelButtonTapped)
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.send(.saveButtonTapped)
                    dismiss()
                }
                .disabled(store.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

#Preview {
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
    }

    SettingsView(
        store: Store(initialState: Settings.State()) {
            Settings()
        }
    )
    .tint(.purple)
}


