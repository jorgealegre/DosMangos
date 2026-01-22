import ComposableArchitecture
import Currency
import Sharing
import SwiftUI

@Reducer
struct DefaultCurrencyPickerReducer: Reducer {

    @Reducer
    enum Destination {
        case currencyPicker(CurrencyPicker)
    }

    @ObservableState
    struct State: Equatable {
        @Shared(.defaultCurrency) var defaultCurrency: String

        /// The currency the user wants to switch to (nil if no change pending)
        var pendingCurrency: String?

        @Presents var destination: Destination.State?

        /// The currency to display (pending takes precedence for showing what will be converted to)
        var displayCurrency: String {
            pendingCurrency ?? defaultCurrency
        }

        /// Whether a currency change is pending
        var hasPendingChange: Bool {
            pendingCurrency != nil && pendingCurrency != defaultCurrency
        }

        init() {}
    }

    enum Action: ViewAction {
        enum View {
            case changeCurrencyButtonTapped
            case cancelChangeTapped
        }
        case destination(PresentationAction<Destination.Action>)
        case view(View)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .destination(.dismiss):
                return .none

            case let .destination(.presented(.currencyPicker(.delegate(delegateAction)))):
                switch delegateAction {
                case let .currencySelected(currencyCode):
                    state.destination = nil
                    if currencyCode != state.defaultCurrency {
                        state.pendingCurrency = currencyCode
                    }
                    return .none
                }

            case .destination:
                return .none

            case let .view(view):
                switch view {
                case .changeCurrencyButtonTapped:
                    state.destination = .currencyPicker(CurrencyPicker.State(
                        selectedCurrencyCode: state.displayCurrency
                    ))
                    return .none

                case .cancelChangeTapped:
                    state.pendingCurrency = nil
                    return .none
                }
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}
extension DefaultCurrencyPickerReducer.Destination.State: Equatable {}

@ViewAction(for: DefaultCurrencyPickerReducer.self)
struct DefaultCurrencyPickerView: View {
    @Bindable var store: StoreOf<DefaultCurrencyPickerReducer>

    var body: some View {
        List {
            currentCurrencySection

            if store.hasPendingChange {
                pendingChangeSection
            }
        }
        .navigationTitle("Default Currency")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(
            item: $store.scope(
                state: \.destination?.currencyPicker,
                action: \.destination.currencyPicker
            )
        ) { store in
            NavigationStack {
                CurrencyPickerView(store: store)
            }
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var currentCurrencySection: some View {
        Section {
            Button {
                send(.changeCurrencyButtonTapped)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Currency")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let currency = CurrencyRegistry.all[store.defaultCurrency] {
                            Text(currency.name)
                                .font(.headline)
                            Text(currency.code)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(store.defaultCurrency)
                                .font(.headline)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } footer: {
            Text("All transactions are converted to this currency for totals and reports.")
        }
    }

    @ViewBuilder
    private var pendingChangeSection: some View {
        Section {
            if let pendingCode = store.pendingCurrency,
               let currency = CurrencyRegistry.all[pendingCode] {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("Change to \(currency.name) (\(currency.code))")
                            .font(.headline)
                    } icon: {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(.blue)
                    }

                    Text("Existing transactions will be converted using historical exchange rates.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Pending Change")
        } footer: {
            HStack {
                Button("Cancel") {
                    send(.cancelChangeTapped)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 8)
        }
    }
}

#Preview {
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
    }
    NavigationStack {
        DefaultCurrencyPickerView(
            store: Store(initialState: DefaultCurrencyPickerReducer.State()) {
                DefaultCurrencyPickerReducer()
                    ._printChanges()
            }
        )
    }
}
