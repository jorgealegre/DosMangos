import ComposableArchitecture
import SwiftUI

@Reducer
struct SettingsReducer: Reducer {
    @ObservableState
    struct State: Equatable {
        init() {}
    }

    enum Action: ViewAction {
        enum View {
            case categoriesTapped
            case tagsTapped
        }
        case view(View)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .view(view):
                switch view {
                case .categoriesTapped:
                    // TODO: Navigate to categories editor
                    return .none

                case .tagsTapped:
                    // TODO: Navigate to tags editor
                    return .none
                }
            }
        }
    }
}

@ViewAction(for: SettingsReducer.self)
struct SettingsView: View {
    let store: StoreOf<SettingsReducer>

    var body: some View {
        NavigationStack {
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
                }
                .padding()
            }
            .navigationTitle("Settings")
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

