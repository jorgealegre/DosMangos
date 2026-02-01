import ComposableArchitecture
import SQLiteData
import SwiftUI

@Reducer
struct SettingsReducer: Reducer {
    @ObservableState
    struct State: Equatable {
        var path = StackState<Path.State>()
        @FetchOne var userSettings: UserSettings?

        init() {}
    }

    @Reducer
    enum Path {
        case categories(CategoriesReducer)
        case defaultCurrencyPicker(DefaultCurrencyPickerReducer)
    }

    enum Action: ViewAction {
        enum View {
            case categoriesTapped
            case defaultCurrencyTapped
            case tagsTapped
        }
        case path(StackActionOf<Path>)
        case view(View)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .path:
                return .none

            case let .view(view):
                switch view {
                case .categoriesTapped:
                    state.path.append(.categories(CategoriesReducer.State()))
                    return .none

                case .defaultCurrencyTapped:
                    state.path.append(.defaultCurrencyPicker(DefaultCurrencyPickerReducer.State()))
                    return .none

                case .tagsTapped:
                    // TODO: Navigate to tags editor
                    return .none
                }
            }
        }
        .forEach(\.path, action: \.path)
    }
}
extension SettingsReducer.Path.State: Equatable {}

@ViewAction(for: SettingsReducer.self)
struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsReducer>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            ScrollView {
                Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow {
                        SettingsToolView(
                            icon: "folder.fill",
                            title: "Categories",
                            subtitle: "Edit or create new categories"
                        ) {
                            send(.categoriesTapped)
                        }

                        SettingsToolView(
                            icon: "tag.fill",
                            title: "Tags",
                            subtitle: "Edit or create new tags"
                        ) {
                            send(.tagsTapped)
                        }
                    }

                    GridRow {
                        SettingsToolView(
                            icon: "dollarsign.circle.fill",
                            title: "Default Currency",
                            subtitle: "Currently: \(store.userSettings?.defaultCurrency ?? "USD")"
                        ) {
                            send(.defaultCurrencyTapped)
                        }

                        Color.clear
                            .gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
                .padding()
            }
            .navigationTitle("Settings")
        } destination: { store in
            switch store.case {
            case let .categories(store):
                CategoriesView(store: store)
            case let .defaultCurrencyPicker(store):
                DefaultCurrencyPickerView(store: store)
            }
        }
    }
}

struct SettingsToolView: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .frame(width: 50, height: 50)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(Color(.systemBackground))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
    }
    SettingsView(
        store: Store(initialState: SettingsReducer.State()) {
            SettingsReducer()
                ._printChanges()
        }
    )
}

