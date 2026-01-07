import ComposableArchitecture
import Currency
import SwiftUI

@Reducer
struct CurrencyPicker {
    @ObservableState
    struct State: Equatable {

        struct FilteredCurrency: Identifiable, Hashable {
            let currency: Currency
            let matchedCountry: Country?
            let priority: Int // 0 = country match, 1 = currency match, 2 = no match

            var id: String { currency.code }

            var orderedCountries: [Country] {
                guard let matchedCountry else {
                    return currency.countries
                }

                // Put matched country first, then all others
                var reordered = [matchedCountry]
                reordered.append(contentsOf: currency.countries.filter { $0 != matchedCountry })
                return reordered
            }

            var countriesForDisplay: [(country: Country, isMatched: Bool)] {
                orderedCountries.prefix(3).map { country in
                    (country: country, isMatched: country == matchedCountry)
                }
            }

            var remainingCount: Int {
                max(0, currency.countries.count - 3)
            }
        }

        var searchText: String = ""
        var selectedCurrencyCode: String
        var allCurrencies: [Currency]

        var filteredCurrencies: [FilteredCurrency] {
            let searchLower = searchText.lowercased()
            var results: [FilteredCurrency] = []

            if searchText.isEmpty {
                // No search - show all currencies in original order
                results = allCurrencies.map { FilteredCurrency(currency: $0, matchedCountry: nil, priority: 2) }
            } else {
                // Search active - categorize and prioritize results
                for currency in allCurrencies {
                    // Check if any country name matches (highest priority)
                    if let matchedCountry = currency.countries.first(where: {
                        $0.name.lowercased().contains(searchLower)
                    }) {
                        results.append(FilteredCurrency(currency: currency, matchedCountry: matchedCountry, priority: 0))
                        continue
                    }

                    // Check if currency name or code matches
                    if currency.name.lowercased().contains(searchLower) ||
                       currency.code.lowercased().contains(searchLower) {
                        results.append(FilteredCurrency(currency: currency, matchedCountry: nil, priority: 1))
                    }
                }

                // Sort by priority (country matches first)
                results.sort { $0.priority < $1.priority }
            }

            return results
        }

        var selectedCurrency: Currency? {
            allCurrencies.first { $0.code == selectedCurrencyCode }
        }

        init(selectedCurrencyCode: String) {
            self.selectedCurrencyCode = selectedCurrencyCode

            // Get all currencies from the registry and sort by name
            self.allCurrencies = CurrencyRegistry.all.values.sorted { $0.name < $1.name }
        }
    }

    enum Action: ViewAction, BindableAction {
        enum Delegate {
            case currencySelected(currencyCode: String)
        }

        enum View {
            case currencyTapped(String)
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
                case let .currencyTapped(currencyCode):
                    return .send(.delegate(.currencySelected(currencyCode: currencyCode)))
                }
            }
        }
    }
}

@ViewAction(for: CurrencyPicker.self)
struct CurrencyPickerView: View {
    @Bindable var store: StoreOf<CurrencyPicker>

    @FocusState private var isSearchBarFocused: Bool

    var body: some View {
        List {
            // Currently selected currency at the top
            if let selected = store.selectedCurrency,
               let filteredSelected = store.filteredCurrencies.first(where: { $0.currency.code == selected.code }) {
                Section("Current Currency") {
                    currencyRow(
                        filteredCurrency: filteredSelected,
                        isSelected: true
                    )
                }
            }

            // All currencies
            Section("All Currencies") {
                ForEach(store.filteredCurrencies) { filteredCurrency in
                    Button {
                        send(.currencyTapped(filteredCurrency.currency.code))
                    } label: {
                        currencyRow(
                            filteredCurrency: filteredCurrency,
                            isSelected: filteredCurrency.currency.code == store.selectedCurrencyCode
                        )
                    }
                }
            }
        }
        .listSectionSpacing(.compact)
        .searchable(text: $store.searchText, prompt: "Search by country or currency...")
        .searchFocused($isSearchBarFocused)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Select Currency")
        .scrollDismissesKeyboard(.immediately)
        .onAppear { isSearchBarFocused = true }
    }

    private func currencyRow(
        filteredCurrency: CurrencyPicker.State.FilteredCurrency,
        isSelected: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(filteredCurrency.currency.name)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)

                countriesSubtitle(for: filteredCurrency)
            }

            Spacer()

            Text(filteredCurrency.currency.code)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .font(.callout)
        }
    }

    @ViewBuilder
    private func countriesSubtitle(for filteredCurrency: CurrencyPicker.State.FilteredCurrency) -> some View {
        let countries = filteredCurrency.countriesForDisplay
        let remaining = filteredCurrency.remainingCount

        let combinedText = countries.enumerated().reduce(Text("")) { result, item in
            let (index, data) = item
            let (country, isMatched) = data

            var text = result

            // Add separator if not first
            if index > 0 {
                text = text + Text(", ")
            }

            // Add country with optional bold
            let countryText = Text("\(country.flag) \(country.name)")
            text = text + (isMatched ? countryText.bold() : countryText)

            return text
        }

        let finalText = remaining > 0 ? combinedText + Text(" +\(remaining)") : combinedText

        finalText
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

#Preview {
    NavigationStack {
        CurrencyPickerView(
            store: Store(initialState: CurrencyPicker.State(selectedCurrencyCode: "USD")) {
                CurrencyPicker()
                    ._printChanges()
            }
        )
    }
}

