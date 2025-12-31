import ComposableArchitecture
import CoreLocationClient
import Foundation
import Sharing
import SwiftUI

@Reducer
struct TransactionFormReducer: Reducer {
    @Reducer
    enum Destination {
        case categoryPicker(CategoryPicker)
    }

    @ObservableState
    struct State: Equatable {
        enum Field {
            case value, description
        }

        var isDatePickerVisible: Bool = false
        var isPresentingTagsPopover: Bool = false
        var focus: Field? = .value
        var transaction: Transaction.Draft
        var selectedCategory: Category?
        var selectedTags: [Tag] = []
        var loadedLocation: TransactionLocation?
        var hasLoadedDetails = false

        @Presents var destination: Destination.State?

        @SharedReader(.currentLocation) var currentLocation: GeocodedLocation?
        /// UI is currently whole-dollars only (cents ignored), e.g. "12".

        init(transaction: Transaction.Draft) {
            self.transaction = transaction
            // TODO: load the tags and categories for this transaction
        }
    }

    enum Action: ViewAction, BindableAction {
        enum Delegate {
        }
        enum View {
            case dateButtonTapped
            case categoriesButtonTapped
            case tagsButtonTapped
            case nextDayButtonTapped
            case previousDayButtonTapped
            case saveButtonTapped
            case valueInputFinished
            case onAppear
        }
        case binding(BindingAction<State>)
        case delegate(Delegate)
        case destination(PresentationAction<Destination.Action>)
        case view(View)
        case detailsLoaded(Category?, [Tag], TransactionLocation?)
    }

    @Dependency(\.calendar) private var calendar
    @Dependency(\.dismiss) private var dismiss
    @Dependency(\.defaultDatabase) private var database

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .delegate:
                return .none

            case let .destination(.presented(.categoryPicker(.delegate(delegateAction)))):
                switch delegateAction {
                case let .categorySelected(category):
                    state.selectedCategory = category
                    state.destination = nil
                    return .none
                }

            case .destination:
                return .none

            case let .view(view):
                switch view {
                case .onAppear:
                    guard !state.hasLoadedDetails else { return .none }
                    state.hasLoadedDetails = true
                    guard let transactionID = state.transaction.id else { return .none }
                    return .run { [locationID = state.transaction.locationID] send in
                        let result = try await database.read { db -> (Category?, [Tag], TransactionLocation?) in
                            let categoryID = try TransactionCategory
                                .where { $0.transactionID.eq(transactionID) }
                                .select { $0.categoryID }
                                .fetchOne(db)

                            let category = try categoryID.flatMap {
                                try Category.find($0).fetchOne(db)
                            }

                            let tagIDs = try TransactionTag
                                .where { $0.transactionID.eq(transactionID) }
                                .select { $0.tagID }
                                .fetchAll(db)
                            let tags = try tagIDs.compactMap {
                                try Tag.find($0).fetchOne(db)
                            }

                            let location = try locationID.flatMap {
                                try TransactionLocation.find($0).fetchOne(db)
                            }

                            return (category, tags, location)
                        }

                        await send(.detailsLoaded(result.0, result.1, result.2))
                    }

                case .categoriesButtonTapped:
                    state.focus = nil
                    state.destination = .categoryPicker(CategoryPicker.State(selectedCategory: state.selectedCategory))
                    return .none

                case .tagsButtonTapped:
                    state.focus = nil
                    state.isPresentingTagsPopover.toggle()
                    return .none

                case .dateButtonTapped:
                    state.focus = nil
                    state.isDatePickerVisible.toggle()
                    return .none

                case .nextDayButtonTapped:
                    state.focus = nil
                    state.transaction.localDate = calendar
                        .date(byAdding: .day, value: 1, to: state.transaction.localDate)!
                    return .none

                case .previousDayButtonTapped:
                    state.focus = nil
                    state.transaction.localDate = calendar
                        .date(byAdding: .day, value: -1, to: state.transaction.localDate)!
                    return .none

                case .saveButtonTapped:
                    state.focus = nil
                    let transaction = state.transaction
                    let selectedCategory = state.selectedCategory
                    let selectedTags = state.selectedTags
                    let loadedLocation = state.loadedLocation
                    // If we already have a persisted location, prefer it over a newly captured one.
                    let locationDraft: TransactionLocation.Draft? = loadedLocation == nil
                        ? state.currentLocation.map {
                            TransactionLocation.Draft(
                                latitude: $0.location.coordinate.latitude,
                                longitude: $0.location.coordinate.longitude,
                                city: $0.city,
                                countryCode: $0.countryCode
                            )
                        }
                        : nil

                    return .run { _ in
                        withErrorReporting {
                            try database.write { db in
                                var locationID: UUID? = loadedLocation?.id
                                if let locationDraft = locationDraft {
                                    locationID = try TransactionLocation.insert { locationDraft }
                                        .returning(\.id)
                                        .fetchOne(db)
                                }

                                var updatedTransaction = transaction
                                updatedTransaction.locationID = locationID

                                let transactionID = try Transaction.upsert { updatedTransaction }
                                    .returning(\.id)
                                    .fetchOne(db)!
                                try TransactionCategory
                                    .where { $0.transactionID.eq(transactionID) }
                                    .delete()
                                    .execute(db)
                                if let category = selectedCategory {
                                    try TransactionCategory.insert {
                                        TransactionCategory.Draft(transactionID: transactionID, categoryID: category.id)
                                    }
                                    .execute(db)
                                }
                                try TransactionTag
                                    .where { $0.transactionID.eq(transactionID) }
                                    .delete()
                                    .execute(db)
                                try TransactionTag.insert {
                                    selectedTags.map { tag in
                                        TransactionTag.Draft(transactionID: transactionID, tagID: tag.id)
                                    }
                                }
                                .execute(db)
                            }
                        }
                        await dismiss()
                    }

                case .valueInputFinished:
                    state.focus = .description
                    return .none
                }

            case let .detailsLoaded(category, tags, location):
                state.selectedCategory = category
                state.selectedTags = tags
                state.loadedLocation = location
                return .none

            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension TransactionFormReducer.Destination.State: Equatable {}

@ViewAction(for: TransactionFormReducer.self)
struct TransactionFormView: View {

    @FocusState var focus: TransactionFormReducer.State.Field?

    @Bindable var store: StoreOf<TransactionFormReducer>

    var body: some View {
        Form {
            valueInput
            typePicker
            descriptionInput
            dateTimePicker
            categoriesSection
            tagsSection
            locationSection
            saveButton
        }
        .listSectionSpacing(12)
        .scrollDismissesKeyboard(.immediately)
        .bind($store.focus, to: $focus)
        .onAppear {
            send(.onAppear)
        }
    }

    @ViewBuilder
    private var valueInput: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(store.transaction.currencyCode)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Currency")

            TextField("0", text: $store.transaction.valueText)
                .font(.system(size: 80).bold())
                .minimumScaleFactor(0.2)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
                .focused($focus, equals: .value)
                .onSubmit { send(.valueInputFinished) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var typePicker: some View {
        Picker("Type", selection: $store.transaction.type) {
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
                    Text(store.transaction.localDate.formattedRelativeDay())
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
                    selection: $store.transaction.localDate,
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
                text: $store.transaction.description
            )
            .autocorrectionDisabled()
            .keyboardType(.alphabet)
            .submitLabel(.done)
            .focused($focus, equals: .description)
            .onSubmit {
                send(.saveButtonTapped)
            }
        }
    }

    @ViewBuilder
    private var categoriesSection: some View {
        Section {
            Button {
                send(.categoriesButtonTapped, animation: .default)
            } label: {
                HStack {
                    Image(systemName: "folder.fill")
                        .font(.title)
                        .foregroundStyle(.gray)
                    Text("Categories")
                        .foregroundStyle(Color(.label))
                    Spacer()
                    if let category = store.selectedCategory {
                        Text(category.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .font(.callout)
                            .foregroundStyle(.gray)
                    }
                    Image(systemName: "chevron.right")
                }
            }
        }
        .popover(
            item: $store.scope(
                state: \.destination?.categoryPicker,
                action: \.destination.categoryPicker
            )
        ) { categoryPickerStore in
            NavigationStack {
                CategoryPickerView(store: categoryPickerStore)
                    .navigationTitle("Choose a category")
                // \(store.transaction.description)
            }
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        Section {
            Button {
                send(.tagsButtonTapped, animation: .default)
            } label: {
                HStack {
                    Image(systemName: "number.square.fill")
                        .font(.title)
                        .foregroundStyle(.gray)
                    Text("Tags")
                        .foregroundStyle(Color(.label))
                    Spacer()
                    if let tagsDetail {
                        tagsDetail
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .font(.callout)
                            .foregroundStyle(.gray)
                    }
                    Image(systemName: "chevron.right")
                }
            }
        }
        .popover(isPresented: $store.isPresentingTagsPopover) {
            NavigationStack {
                TagsView(selectedTags: $store.selectedTags)
            }
        }
    }

    private var tagsDetail: Text? {
        guard !store.selectedTags.isEmpty else { return nil }
        let allTags = store.selectedTags.map { "#\($0.title)" }.joined(separator: " ")
        return Text(allTags)
    }

    @ViewBuilder
    private var locationSection: some View {
        Section {
            HStack {
                Image(systemName: "location.fill")
                    .font(.title)
                    .foregroundStyle(.gray)

                if let loadedLocation = store.loadedLocation {
                    locationDetail(
                        city: loadedLocation.city,
                        countryName: loadedLocation.countryDisplayName,
                        fallbackLabel: "Location on file"
                    )
                } else if store.$currentLocation.isLoading {
                    ProgressView()
                        .padding(.leading, 8)
                    Text("Getting location...")
                        .foregroundStyle(.secondary)
                } else if store.$currentLocation.loadError != nil {
                    Text("Fetching your location failed")
                        .foregroundStyle(.secondary)
                } else if let currentLocation = store.currentLocation {
                    locationDetail(
                        city: currentLocation.city,
                        countryName: currentLocation.countryDisplayName,
                        fallbackLabel: "Location captured"
                    )
                } else {
                    Text("Location unavailable")
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    @ViewBuilder
    private func locationDetail(
        city: String?,
        countryName: String?,
        fallbackLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let city = city,
               let countryName = countryName {
                Text("\(city), \(countryName)")
                    .foregroundStyle(Color(.label))
            } else if let city = city {
                Text(city)
                    .foregroundStyle(Color(.label))
            } else {
                Text(fallbackLabel)
                    .foregroundStyle(.secondary)
            }
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

#Preview {
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
        try seedSampleData()
    }
    Color.clear
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            NavigationStack {
                TransactionFormView(
                    store: Store(
                        initialState: TransactionFormReducer.State(
                            transaction: Transaction.Draft()
                        )
                    ) {
                        TransactionFormReducer()
                            ._printChanges()
                    }
                )
                .navigationTitle("New transaction")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tint(.purple)
        }
}
