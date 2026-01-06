import ComposableArchitecture
import CoreLocationClient
import Foundation
import MapKit
import Sharing
import SwiftUI

@Reducer
struct TransactionFormReducer: Reducer {
    @Reducer
    enum Destination {
        case categoryPicker(CategoryPicker)
        case locationPicker(LocationPickerReducer)
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
        var isLoadingDetails = false
        var category: Category?
        var tags: [Tag] = []

        var isLocationEnabled: Bool
        /// The location of the transaction we load when editing an existing transaction.
        var location: TransactionLocation?
        /// A location the user picked in this session, not yet persisted.
        var pickedLocation: TransactionLocation.Draft?
        /// The current location of the user, for automatically filling in the location.
        @SharedReader(.currentLocation) var currentLocation: GeocodedLocation?

        @Presents var destination: Destination.State?

        /// UI is currently whole-dollars only (cents ignored), e.g. "12".

        init(transaction: Transaction.Draft) {
            self.transaction = transaction
            self.isLocationEnabled = transaction.id == nil || transaction.locationID != nil
        }

        var locationPickerCenter: CLLocationCoordinate2D? {
            pickedLocation?.coordinate
            ?? location?.coordinate
            ?? currentLocation?.location.coordinate
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
            case locationMiniMapTapped
            case saveButtonTapped
            case valueInputFinished
            case task
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
            case .binding(\.isLocationEnabled):
                if !state.isLocationEnabled {
                    state.focus = nil
                    state.location = nil
                    state.pickedLocation = nil
                }
                return .none

            case .binding:
                return .none

            case .delegate:
                return .none

            case let .destination(.presented(.categoryPicker(.delegate(delegateAction)))):
                switch delegateAction {
                case let .categorySelected(category):
                    state.category = category
                    state.destination = nil
                    return .none
                }

            case let .destination(.presented(.locationPicker(.delegate(delegateAction)))):
                switch delegateAction {
                case let .didPick(pickedLocation):
                    state.focus = nil
                    state.pickedLocation = pickedLocation
                    state.location = nil
                    state.destination = nil
                    return .none
                }

            case .destination:
                return .none

            case let .view(view):
                switch view {
                case .task:
                    guard !state.isLoadingDetails else { return .none }
                    guard let transactionID = state.transaction.id else { return .none }
                    state.isLoadingDetails = true
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
                    state.destination = .categoryPicker(CategoryPicker.State(
                        selectedCategory: state.category
                    ))
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

                case .locationMiniMapTapped:
                    state.focus = nil
                    guard state.isLocationEnabled, let center = state.locationPickerCenter else {
                        return .none
                    }
                    state.destination = .locationPicker(
                        LocationPickerReducer.State(center: center)
                    )
                    return .none

                case .saveButtonTapped:
                    state.focus = nil

                    // If we already have a persisted location, prefer it over a newly captured one.
                    let newTransactionLocation: TransactionLocation.Draft?
                    if state.isLocationEnabled, let pickedLocation = state.pickedLocation {
                        newTransactionLocation = pickedLocation
                    } else if state.isLocationEnabled, state.location == nil, let location = state.currentLocation {
                        // If we don't have an existing location for this transaction
                        // but location is enabled, create a new one
                        newTransactionLocation = TransactionLocation.Draft(
                            latitude: location.location.coordinate.latitude,
                            longitude: location.location.coordinate.longitude,
                            city: location.city,
                            countryCode: location.countryCode
                        )
                    } else {
                        newTransactionLocation = nil
                    }

                    return .run { [state = state] _ in
                        withErrorReporting {
                            try database.write { db in
                                // Delete any existing location if location is disabled or a new one should replace it
                                if (!state.isLocationEnabled || newTransactionLocation != nil),
                                    let oldID = state.transaction.locationID {
                                    try TransactionLocation
                                        .find(oldID)
                                        .delete()
                                        .execute(db)
                                }

                                let locationID: UUID?
                                if let newTransactionLocation {
                                    locationID = try TransactionLocation.insert { newTransactionLocation }
                                        .returning(\.id)
                                        .fetchOne(db)
                                } else if state.isLocationEnabled {
                                    locationID = state.transaction.locationID
                                } else {
                                    locationID = nil
                                }

                                var updatedTransaction = state.transaction
                                updatedTransaction.locationID = locationID

                                let transactionID = try Transaction.upsert { updatedTransaction }
                                    .returning(\.id)
                                    .fetchOne(db)!

                                try TransactionCategory
                                    .where { $0.transactionID.eq(transactionID) }
                                    .delete()
                                    .execute(db)
                                if let category = state.category {
                                    try TransactionCategory.insert {
                                        TransactionCategory.Draft(
                                            transactionID: transactionID,
                                            categoryID: category.id
                                        )
                                    }
                                    .execute(db)
                                }
                                try TransactionTag
                                    .where { $0.transactionID.eq(transactionID) }
                                    .delete()
                                    .execute(db)
                                try TransactionTag.insert {
                                    state.tags.map { tag in
                                        TransactionTag.Draft(
                                            transactionID: transactionID,
                                            tagID: tag.id
                                        )
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
                state.category = category
                state.tags = tags
                state.location = location
                state.isLoadingDetails = false
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

    @State private var mapPosition: MapCameraPosition = .automatic

    var body: some View {
        Form {
            valueInput
            typePicker
            descriptionInput
            dateTimePicker
            categoriesSection
            tagsSection
            locationSection
        }
        .listSectionSpacing(12)
        .scrollDismissesKeyboard(.immediately)
        .bind($store.focus, to: $focus)
        .task { await send(.task).finish() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    send(.saveButtonTapped)
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel("Save")
                .buttonStyle(.glassProminent)
            }
        }
        .sheet(
            item: $store.scope(
                state: \.destination?.locationPicker,
                action: \.destination.locationPicker
            )
        ) { store in
            NavigationStack {
                LocationPickerView(store: store)
            }
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var valueInput: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {

            } label: {
                Text(store.transaction.currencyCode)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityLabel("Currency")
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle)

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
                Image(systemName: "calendar")
                    .font(.title)
                    .foregroundStyle(.foreground)

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
                    Image(systemName: "folder")
                        .font(.title)
                        .foregroundStyle(.foreground)
                    Text("Categories")
                        .foregroundStyle(Color(.label))
                    Spacer()
                    if let category = store.category {
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
                    Image(systemName: "number.square")
                        .font(.title)
                        .foregroundStyle(.foreground)
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
                TagsView(selectedTags: $store.tags)
            }
        }
    }

    private var tagsDetail: Text? {
        guard !store.tags.isEmpty else { return nil }
        let allTags = store.tags.map { "#\($0.title)" }.joined(separator: " ")
        return Text(allTags)
    }

    @ViewBuilder
    private var locationSection: some View {
        Section {
            HStack {
                Image(systemName: "location")
                    .font(.title)
                    .foregroundStyle(.foreground)

                Spacer()

                Toggle(isOn: $store.isLocationEnabled.animation()) {
                    VStack(alignment: .leading) {
                        Text("Location")
                            .font(store.isLocationEnabled ? .caption : nil)
                            .fontWeight(store.isLocationEnabled ? .light : nil)

                        if store.isLocationEnabled {
                            Group {
                                if let pickedLocation = store.pickedLocation {
                                    locationTitle(
                                        city: pickedLocation.city,
                                        countryName: pickedLocation.countryDisplayName,
                                        fallbackLabel: "Chosen location"
                                    )
                                } else if let loadedLocation = store.location {
                                    locationTitle(
                                        city: loadedLocation.city,
                                        countryName: loadedLocation.countryDisplayName,
                                        fallbackLabel: "Location on file"
                                    )
                                } else if store.$currentLocation.isLoading {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                        Text("Getting location...")
                                    }
                                } else if store.$currentLocation.loadError != nil {
                                    Text("Fetching your location failed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if let currentLocation = store.currentLocation {
                                    locationTitle(
                                        city: currentLocation.city,
                                        countryName: currentLocation.countryDisplayName,
                                        fallbackLabel: "Current location"
                                    )
                                }
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                        }
                    }
                }
            }

            if store.isLocationEnabled {
                locationMiniMap
            }
        }
    }

    private var locationPickerCenterLocation: Location? {
        store.locationPickerCenter.map { Location(coordinate: $0) }
    }

    private func region(for coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 50,
            longitudinalMeters: 50
        )
    }

    @ViewBuilder
    private var locationMiniMap: some View {
        Map(
            position: $mapPosition,
            interactionModes: []
        ) {
            if let coordinate = locationPickerCenterLocation?.coordinate {
                Marker("", coordinate: coordinate)
            }
        }
        .mapStyle(
            .standard(
                elevation: .realistic,
                emphasis: .automatic,
                pointsOfInterest: .all,
                showsTraffic: false
            )
        )
        .frame(height: 120)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .onAppear {
            if let coordinate = locationPickerCenterLocation?.coordinate {
                mapPosition = .region(region(for: coordinate))
            }
        }
        .onChange(of: locationPickerCenterLocation) { _, newValue in
            guard let coordinate = newValue?.coordinate else { return }
            mapPosition = .region(region(for: coordinate))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            send(.locationMiniMapTapped)
        }
    }

    private func locationTitle(
        city: String?,
        countryName: String?,
        fallbackLabel: String
    ) -> Text {
        if let city, let countryName {
            Text("\(city), \(countryName)")
        } else if let city {
            Text(city)
        } else {
            Text(fallbackLabel)
        }
    }

}

#Preview {
    let transaction = try! prepareDependencies {
        try $0.bootstrapDatabase()
        try seedSampleData()

        $0.geocodingClient.reverseGeocode = { _ in
            try await Task.sleep(for: .seconds(2))
            return ("Córdoba", "AR")
        }

        return try $0.defaultDatabase.read { db in
            try Transaction
                .order(by: \.createdAtUTC)
                .fetchOne(db)!
        }
    }
    Color.clear
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            NavigationStack {
                TransactionFormView(
                    store: Store(
                        initialState: TransactionFormReducer.State(
                            transaction: Transaction.Draft(transaction)
                        )
                    ) {
                        TransactionFormReducer()
                            ._printChanges()
                    }
                )
                .navigationTitle("New transaction")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
}
