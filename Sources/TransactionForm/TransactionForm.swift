import ComposableArchitecture
import CoreLocationClient
import Currency
import Foundation
import MapKit
import Sharing
import SwiftUI

@Reducer
struct TransactionFormReducer: Reducer {
    /// Controls how the form behaves regarding recurring options
    enum FormMode: Equatable {
        /// Creating a new transaction from Transactions List - toggle is available
        case newTransaction
        /// Creating a new recurring template from Recurring Tab - toggle locked ON
        case newRecurring
        /// Editing an existing transaction - toggle hidden
        case editTransaction
        /// Editing an existing recurring template - toggle locked ON
        case editRecurring(RecurringTransaction)
        /// Posting a transaction from a recurring template (virtual instance)
        case postFromRecurring(RecurringTransaction)
    }

    @Reducer
    enum Destination {
        case categoryPicker(CategoryPicker)
        case currencyPicker(CurrencyPicker)
        case locationPicker(LocationPickerReducer)
        case customRecurrenceEditor(CustomRecurrenceEditorReducer)
    }

    @ObservableState
    struct State: Equatable {
        enum Field {
            case value, description
        }

        var formMode: FormMode
        var isDatePickerVisible: Bool = false
        var isPresentingTagsPopover: Bool = false
        var focus: Field? = .value
        var transaction: Transaction.Draft
        var isLoadingDetails = false
        var category: Category?
        var tags: [Tag] = []

        // Recurring-specific state (nil preset = not recurring)
        var recurrencePreset: RecurrencePreset?
        var recurrenceRule: RecurrenceRule?

        /// Whether this is a recurring transaction (derived from preset)
        var isRecurring: Bool { recurrencePreset != nil }

        var isLocationEnabled: Bool
        /// The location of the transaction we load when editing an existing transaction.
        var location: TransactionLocation?
        /// A location the user picked in this session, not yet persisted.
        var pickedLocation: TransactionLocation.Draft?
        /// The current location of the user, for automatically filling in the location.
        @SharedReader(.currentLocation) var currentLocation: GeocodedLocation?
        /// The user's default currency for converted values.
        @Shared(.defaultCurrency) var defaultCurrency: String

        @Presents var destination: Destination.State?

        /// UI is currently whole-dollars only (cents ignored), e.g. "12".

        /// Whether the repeat picker should be shown
        var showsRepeatPicker: Bool {
            switch formMode {
            case .newTransaction: true
            case .newRecurring: true
            case .editTransaction: false  // Hidden for existing transactions
            case .editRecurring: true
            case .postFromRecurring: false  // Hidden, posting creates regular transaction
            }
        }

        /// Whether the location section should be shown (hidden when recurring)
        var showsLocationSection: Bool {
            !isRecurring
        }

        /// Navigation title based on form mode
        var navigationTitle: LocalizedStringKey {
            switch formMode {
            case .newTransaction: "New Transaction"
            case .newRecurring: "New Recurring"
            case .editTransaction: "Edit Transaction"
            case .editRecurring: "Edit Recurring"
            case .postFromRecurring: "Post Transaction"
            }
        }

        init(
            transaction: Transaction.Draft,
            formMode: FormMode = .newTransaction,
            category: Category? = nil,
            tags: [Tag] = []
        ) {
            self.formMode = formMode
            self.transaction = transaction
            self.category = category
            self.tags = tags

            switch formMode {
            case .newTransaction:
                self.recurrencePreset = nil
                self.recurrenceRule = nil
                // For new transactions, enable location; for edits, it'll be set after loading
                self.isLocationEnabled = transaction.id == nil
            case .newRecurring:
                self.recurrencePreset = .monthly
                self.recurrenceRule = RecurrenceRule.from(preset: .monthly)
                self.isLocationEnabled = false
            case .editTransaction:
                self.recurrencePreset = nil
                self.recurrenceRule = nil
                // Will be updated in .task after loading existing location
                self.isLocationEnabled = false
            case let .editRecurring(recurringTransaction):
                let recurrenceRule = RecurrenceRule.from(recurringTransaction: recurringTransaction)
                self.recurrenceRule = recurrenceRule
                self.recurrencePreset = recurrenceRule.matchingPreset
                self.isLocationEnabled = false
            case .postFromRecurring:
                self.recurrencePreset = nil
                self.recurrenceRule = nil
                self.isLocationEnabled = true  // Enable location capture for posted transaction
            }
        }

        var locationPickerCenter: CLLocationCoordinate2D? {
            pickedLocation?.coordinate
            ?? location?.coordinate
            ?? currentLocation?.location.coordinate
        }
    }

    enum Action: ViewAction, BindableAction {
        @CasePathable
        enum Delegate {
        }
        @CasePathable
        enum View {
            case dateButtonTapped
            case categoriesButtonTapped
            case currencyButtonTapped
            case tagsButtonTapped
            case nextDayButtonTapped
            case previousDayButtonTapped
            case locationMiniMapTapped
            case saveButtonTapped
            case task
            case endRepeatModeSelected(RecurrenceEndMode)
            case endDateChanged(Date)
            case endAfterOccurrencesChanged(Int)
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
    @Dependency(\.exchangeRate) private var exchangeRate

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding(\.recurrencePreset):
                guard let preset = state.recurrencePreset else {
                    state.recurrenceRule = nil
                    state.isLocationEnabled = true
                    return .none
                }

                if preset == .custom {
                    // Open custom editor sheet
//                    state.focus = nil
                    let initialRule = state.recurrenceRule ?? RecurrenceRule.from(preset: .monthly)
                    state.destination = .customRecurrenceEditor(
                        CustomRecurrenceEditorReducer.State(rule: initialRule)
                    )
                } else {
                    state.recurrenceRule = RecurrenceRule.from(preset: preset)
                }

                // Disable location when switching to recurring
                state.isLocationEnabled = false
                state.location = nil
                state.pickedLocation = nil
                return .none

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

            case let .destination(.presented(.customRecurrenceEditor(.delegate(.ruleUpdated(rule))))):
                state.recurrenceRule = rule
                state.recurrencePreset = .custom
                return .none

            case .destination(.dismiss):
                return .none

            case let .destination(.presented(.categoryPicker(.delegate(delegateAction)))):
                switch delegateAction {
                case let .categorySelected(category):
                    state.category = category
                    state.destination = nil
                    return .none
                }

            case let .destination(.presented(.currencyPicker(.delegate(delegateAction)))):
                switch delegateAction {
                case let .currencySelected(currencyCode):
                    state.transaction.currencyCode = currencyCode
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

                    // Load details for editing a recurring transaction
                    if case let .editRecurring(recurringTransaction) = state.formMode {
                        state.isLoadingDetails = true
                        return .run { send in
                            let result = try await database.read { db -> (Category?, [Tag]) in
                                let categoryID = try RecurringTransactionCategory
                                    .where { $0.recurringTransactionID.eq(recurringTransaction.id) }
                                    .select { $0.categoryID }
                                    .fetchOne(db)

                                let category = try categoryID.flatMap {
                                    try Category.find($0).fetchOne(db)
                                }

                                let tagIDs = try RecurringTransactionTag
                                    .where { $0.recurringTransactionID.eq(recurringTransaction.id) }
                                    .select { $0.tagID }
                                    .fetchAll(db)
                                let tags = try tagIDs.compactMap {
                                    try Tag.find($0).fetchOne(db)
                                }

                                return (category, tags)
                            }

                            await send(.detailsLoaded(result.0, result.1, nil))
                        }
                    }

                    // Load details for editing a regular transaction
                    guard let transactionID = state.transaction.id else { return .none }
                    state.isLoadingDetails = true
                    return .run { send in
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

                            // Load location by transactionID (shared PK pattern)
                            let location = try TransactionLocation.find(transactionID).fetchOne(db)

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

                case .currencyButtonTapped:
                    state.destination = .currencyPicker(CurrencyPicker.State(
                        selectedCurrencyCode: state.transaction.currencyCode
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
                    switch state.formMode {
                    case .editRecurring(let existing):
                        return updateRecurringTransaction(&state, existing: existing)
                    case .newRecurring:
                        return saveRecurringTransaction(&state)
                    case .newTransaction where state.isRecurring:
                        return saveRecurringTransaction(&state)
                    case .postFromRecurring(let recurringTransaction):
                        return postFromRecurringTransaction(&state, template: recurringTransaction)
                    default:
                        return saveRegularTransaction(&state)
                    }

                case let .endRepeatModeSelected(mode):
                    state.recurrenceRule?.endMode = mode
                    if mode == .onDate && state.recurrenceRule?.endDate == nil {
                        @Dependency(\.date.now) var now
                        @Dependency(\.calendar) var calendar
                        // Default to 1 month from now
                        state.recurrenceRule?.endDate = calendar.date(byAdding: .month, value: 1, to: now)
                    }
                    return .none

                case let .endDateChanged(date):
                    state.recurrenceRule?.endDate = date
                    return .none

                case let .endAfterOccurrencesChanged(count):
                    state.recurrenceRule?.endAfterOccurrences = count
                    return .none
                }

            case let .detailsLoaded(category, tags, location):
                state.category = category
                state.tags = tags
                state.location = location
                // TODO: not to sure about this
                state.isLocationEnabled = location != nil
                state.isLoadingDetails = false
                return .none

            }
        }
        .ifLet(\.$destination, action: \.destination)
    }

    // MARK: - Save Helpers

    private func saveRegularTransaction(_ state: inout State) -> Effect<Action> {
        let defaultCurrency = state.defaultCurrency
        return .run { [state = state] send in
            var updatedTransaction = state.transaction

            if updatedTransaction.currencyCode != defaultCurrency {
                do {
                    let rate = try await exchangeRate.getRate(
                        updatedTransaction.currencyCode,
                        defaultCurrency,
                        updatedTransaction.localDate
                    )
                    updatedTransaction.convertedValueMinorUnits = Int(
                        Double(updatedTransaction.valueMinorUnits) * rate
                    )
                    updatedTransaction.convertedCurrencyCode = defaultCurrency
                } catch {
                    updatedTransaction.convertedValueMinorUnits = nil
                    updatedTransaction.convertedCurrencyCode = nil
                }
            } else {
                updatedTransaction.convertedValueMinorUnits = updatedTransaction.valueMinorUnits
                updatedTransaction.convertedCurrencyCode = updatedTransaction.currencyCode
            }

            withErrorReporting {
                try database.write { db in
                    // First, save the transaction to get its ID
                    let transactionID = try Transaction.upsert { updatedTransaction }
                        .returning(\.id)
                        .fetchOne(db)!

                    // Handle location (shared PK pattern: location.transactionID = transaction.id)
                    if state.isLocationEnabled {
                        // Determine what location data to use
                        let locationData: TransactionLocation?
                        if let pickedLocation = state.pickedLocation {
                            locationData = TransactionLocation(
                                transactionID: transactionID,
                                latitude: pickedLocation.latitude,
                                longitude: pickedLocation.longitude,
                                city: pickedLocation.city,
                                countryCode: pickedLocation.countryCode
                            )
                        } else if state.location != nil {
                            // Keep existing location (already has correct transactionID)
                            locationData = nil
                        } else if let currentLocation = state.currentLocation {
                            locationData = TransactionLocation(
                                transactionID: transactionID,
                                latitude: currentLocation.location.coordinate.latitude,
                                longitude: currentLocation.location.coordinate.longitude,
                                city: currentLocation.city,
                                countryCode: currentLocation.countryCode
                            )
                        } else {
                            locationData = nil
                        }

                        // Upsert the location if we have new data
                        if let locationData {
                            try TransactionLocation.upsert { locationData }.execute(db)
                        }
                    } else {
                        // Location disabled, delete any existing location
                        try TransactionLocation.find(transactionID).delete().execute(db)
                    }

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
                            TransactionTag.Draft(transactionID: transactionID, tagID: tag.id)
                        }
                    }
                    .execute(db)
                }
            }
            await dismiss()
        }
    }

    private func saveRecurringTransaction(_ state: inout State) -> Effect<Action> {
        @Dependency(\.date.now) var now

        let rule = state.recurrenceRule ?? RecurrenceRule()
        let transactionDate = state.transaction.localDate
        let dateIsToday = calendar.isDate(transactionDate, inSameDayAs: now) || transactionDate < now
        let nextDueDate = dateIsToday
            ? rule.nextOccurrence(after: now)
            : transactionDate

        // Capture current location for auto-posting first instance
        let currentLocation = state.currentLocation

        // Convert dates to local components
        let startLocal = transactionDate.localDateComponents()
        let nextDueLocal = nextDueDate.localDateComponents()

        // Pre-build the recurring transaction draft to help the compiler
        var rtDraft = RecurringTransaction.Draft(
            description: state.transaction.description,
            valueMinorUnits: state.transaction.valueMinorUnits,
            currencyCode: state.transaction.currencyCode,
            type: state.transaction.type,
            frequency: rule.frequency.rawValue,
            interval: rule.interval,
            yearlyDaysOfWeekEnabled: rule.yearlyDaysOfWeekEnabled ? 1 : 0,
            endMode: rule.endMode.rawValue,
            startLocalYear: startLocal.year,
            startLocalMonth: startLocal.month,
            startLocalDay: startLocal.day,
            nextDueLocalYear: nextDueLocal.year,
            nextDueLocalMonth: nextDueLocal.month,
            nextDueLocalDay: nextDueLocal.day,
            postedCount: dateIsToday ? 1 : 0,
            status: .active,
            createdAtUTC: now,
            updatedAtUTC: now
        )
        rtDraft.weeklyDays = rule.weeklyDays.isEmpty ? nil : rule.weeklyDays.map { String($0.rawValue) }.joined(separator: ",")
        rtDraft.monthlyMode = rule.monthlyMode.rawValue
        rtDraft.monthlyDays = rule.monthlyDays.isEmpty ? nil : rule.monthlyDays.sorted().map { String($0) }.joined(separator: ",")
        rtDraft.monthlyOrdinal = rule.monthlyOrdinal.rawValue
        rtDraft.monthlyWeekday = rule.monthlyWeekday.rawValue
        rtDraft.yearlyMonths = rule.yearlyMonths.isEmpty ? nil : rule.yearlyMonths.map { String($0.rawValue) }.sorted().joined(separator: ",")
        rtDraft.yearlyOrdinal = rule.yearlyOrdinal.rawValue
        rtDraft.yearlyWeekday = rule.yearlyWeekday.rawValue
        rtDraft.endDate = rule.endDate
        rtDraft.endAfterOccurrences = rule.endAfterOccurrences

        return .run { [state = state, rtDraft = rtDraft] send in
            withErrorReporting {
                try database.write { db in
                    // Create the recurring transaction template
                    let recurringTransactionID = try RecurringTransaction.insert { rtDraft }
                        .returning(\.id)
                        .fetchOne(db)!

                    // Create category join record
                    if let category = state.category {
                        try RecurringTransactionCategory.insert {
                            RecurringTransactionCategory.Draft(
                                recurringTransactionID: recurringTransactionID,
                                categoryID: category.id
                            )
                        }
                        .execute(db)
                    }

                    // Create tag join records
                    try RecurringTransactionTag.insert {
                        state.tags.map { tag in
                            RecurringTransactionTag.Draft(
                                recurringTransactionID: recurringTransactionID,
                                tagID: tag.id
                            )
                        }
                    }
                    .execute(db)

                    // If date is today or in the past, auto-post the first instance
                    if dateIsToday {
                        // Create the first transaction instance
                        let nowLocal = now.localDateComponents()
                        var txDraft = Transaction.Draft(
                            description: state.transaction.description,
                            valueMinorUnits: state.transaction.valueMinorUnits,
                            currencyCode: state.transaction.currencyCode,
                            convertedValueMinorUnits: state.transaction.valueMinorUnits,
                            convertedCurrencyCode: state.transaction.currencyCode,
                            type: state.transaction.type,
                            createdAtUTC: now,
                            localYear: nowLocal.year,
                            localMonth: nowLocal.month,
                            localDay: nowLocal.day
                        )
                        txDraft.recurringTransactionID = recurringTransactionID

                        let transactionID = try Transaction.insert { txDraft }
                            .returning(\.id)
                            .fetchOne(db)!

                        // Create location if available (shared PK pattern)
                        if let location = currentLocation {
                            try TransactionLocation.insert {
                                TransactionLocation(
                                    transactionID: transactionID,
                                    latitude: location.location.coordinate.latitude,
                                    longitude: location.location.coordinate.longitude,
                                    city: location.city,
                                    countryCode: location.countryCode
                                )
                            }
                            .execute(db)
                        }

                        // Create category join record for the transaction
                        if let category = state.category {
                            try TransactionCategory.insert {
                                TransactionCategory.Draft(
                                    transactionID: transactionID,
                                    categoryID: category.id
                                )
                            }
                            .execute(db)
                        }

                        // Create tag join records for the transaction
                        try TransactionTag.insert {
                            state.tags.map { tag in
                                TransactionTag.Draft(transactionID: transactionID, tagID: tag.id)
                            }
                        }
                        .execute(db)
                    }
                }
            }
            await dismiss()
        }
    }

    private func updateRecurringTransaction(_ state: inout State, existing: RecurringTransaction) -> Effect<Action> {
        @Dependency(\.date.now) var now

        let rule = state.recurrenceRule ?? RecurrenceRule()

        // Build the update for the recurring transaction
        var rtDraft = RecurringTransaction.Draft(
            id: existing.id,
            description: state.transaction.description,
            valueMinorUnits: state.transaction.valueMinorUnits,
            currencyCode: state.transaction.currencyCode,
            type: state.transaction.type,
            frequency: rule.frequency.rawValue,
            interval: rule.interval,
            yearlyDaysOfWeekEnabled: rule.yearlyDaysOfWeekEnabled ? 1 : 0,
            endMode: rule.endMode.rawValue,
            startLocalYear: existing.startLocalYear,
            startLocalMonth: existing.startLocalMonth,
            startLocalDay: existing.startLocalDay,
            nextDueLocalYear: existing.nextDueLocalYear,
            nextDueLocalMonth: existing.nextDueLocalMonth,
            nextDueLocalDay: existing.nextDueLocalDay,
            postedCount: existing.postedCount,
            status: existing.status,
            createdAtUTC: existing.createdAtUTC,
            updatedAtUTC: now
        )
        rtDraft.weeklyDays = rule.weeklyDays.isEmpty ? nil : rule.weeklyDays.map { String($0.rawValue) }.joined(separator: ",")
        rtDraft.monthlyMode = rule.monthlyMode.rawValue
        rtDraft.monthlyDays = rule.monthlyDays.isEmpty ? nil : rule.monthlyDays.sorted().map { String($0) }.joined(separator: ",")
        rtDraft.monthlyOrdinal = rule.monthlyOrdinal.rawValue
        rtDraft.monthlyWeekday = rule.monthlyWeekday.rawValue
        rtDraft.yearlyMonths = rule.yearlyMonths.isEmpty ? nil : rule.yearlyMonths.map { String($0.rawValue) }.sorted().joined(separator: ",")
        rtDraft.yearlyOrdinal = rule.yearlyOrdinal.rawValue
        rtDraft.yearlyWeekday = rule.yearlyWeekday.rawValue
        rtDraft.endDate = rule.endDate
        rtDraft.endAfterOccurrences = rule.endAfterOccurrences

        return .run { [state = state, rtDraft = rtDraft, recurringTransactionID = existing.id] send in
            withErrorReporting {
                try database.write { db in
                    // Update the recurring transaction template
                    try RecurringTransaction.upsert { rtDraft }
                        .execute(db)

                    // Delete existing category join records and recreate
                    try RecurringTransactionCategory
                        .where { $0.recurringTransactionID.eq(recurringTransactionID) }
                        .delete()
                        .execute(db)

                    if let category = state.category {
                        try RecurringTransactionCategory.insert {
                            RecurringTransactionCategory.Draft(
                                recurringTransactionID: recurringTransactionID,
                                categoryID: category.id
                            )
                        }
                        .execute(db)
                    }

                    // Delete existing tag join records and recreate
                    try RecurringTransactionTag
                        .where { $0.recurringTransactionID.eq(recurringTransactionID) }
                        .delete()
                        .execute(db)

                    try RecurringTransactionTag.insert {
                        state.tags.map { tag in
                            RecurringTransactionTag.Draft(
                                recurringTransactionID: recurringTransactionID,
                                tagID: tag.id
                            )
                        }
                    }
                    .execute(db)
                }
            }
            await dismiss()
        }
    }

    private func postFromRecurringTransaction(_ state: inout State, template: RecurringTransaction) -> Effect<Action> {
        @Dependency(\.date.now) var now

        let dateComponents = calendar.dateComponents([.year, .month, .day], from: state.transaction.localDate)

        var txDraft = Transaction.Draft(
            description: state.transaction.description,
            valueMinorUnits: state.transaction.valueMinorUnits,
            currencyCode: state.transaction.currencyCode,
            convertedValueMinorUnits: state.transaction.valueMinorUnits,
            convertedCurrencyCode: state.transaction.currencyCode,
            type: state.transaction.type,
            createdAtUTC: now,
            localYear: dateComponents.year!,
            localMonth: dateComponents.month!,
            localDay: dateComponents.day!
        )
        txDraft.recurringTransactionID = template.id

        return .run { [state = state, txDraft = txDraft, templateID = template.id] send in
            withErrorReporting {
                try database.write { db in
                    // Create the transaction first
                    let transactionID = try Transaction.insert { txDraft }
                        .returning(\.id)
                        .fetchOne(db)!

                    // Create location if enabled (shared PK pattern)
                    if state.isLocationEnabled {
                        let locationData: TransactionLocation?
                        if let pickedLocation = state.pickedLocation {
                            locationData = TransactionLocation(
                                transactionID: transactionID,
                                latitude: pickedLocation.latitude,
                                longitude: pickedLocation.longitude,
                                city: pickedLocation.city,
                                countryCode: pickedLocation.countryCode
                            )
                        } else if let currentLocation = state.currentLocation {
                            locationData = TransactionLocation(
                                transactionID: transactionID,
                                latitude: currentLocation.location.coordinate.latitude,
                                longitude: currentLocation.location.coordinate.longitude,
                                city: currentLocation.city,
                                countryCode: currentLocation.countryCode
                            )
                        } else {
                            locationData = nil
                        }

                        if let locationData {
                            try TransactionLocation.insert { locationData }.execute(db)
                        }
                    }

                    // Create category join record
                    if let category = state.category {
                        try TransactionCategory.insert {
                            TransactionCategory.Draft(
                                transactionID: transactionID,
                                categoryID: category.id
                            )
                        }
                        .execute(db)
                    }

                    // Create tag join records
                    try TransactionTag.insert {
                        state.tags.map { tag in
                            TransactionTag.Draft(transactionID: transactionID, tagID: tag.id)
                        }
                    }
                    .execute(db)

                    // Update the recurring template
                    let rule = RecurrenceRule.from(recurringTransaction: template)
                    let nextDueDate = rule.nextOccurrence(after: template.nextDueDate)
                    let nextDueLocal = nextDueDate.localDateComponents()

                    try RecurringTransaction
                        .where { $0.id.eq(templateID) }
                        .update {
                            $0.nextDueLocalYear = nextDueLocal.year
                            $0.nextDueLocalMonth = nextDueLocal.month
                            $0.nextDueLocalDay = nextDueLocal.day
                            $0.postedCount = template.postedCount + 1
                        }
                        .execute(db)

                    // TODO: Check end conditions and update status if needed
                }
            }
            await dismiss()
        }
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
            if store.showsRepeatPicker {
                repeatSection
            }
            categoriesSection
            tagsSection
            if store.showsLocationSection {
                locationSection
            }
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
                state: \.destination?.currencyPicker,
                action: \.destination.currencyPicker
            )
        ) { store in
            NavigationStack {
                CurrencyPickerView(store: store)
            }
            .presentationDragIndicator(.visible)
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
        .sheet(
            item: $store.scope(
                state: \.destination?.customRecurrenceEditor,
                action: \.destination.customRecurrenceEditor
            )
        ) { editorStore in
            NavigationStack {
                CustomRecurrenceEditorView(store: editorStore)
            }
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var valueInput: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                send(.currencyButtonTapped)
            } label: {
                Text(store.transaction.currencyCode)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityLabel("Currency")
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle)

            FormattedIntegerField(value: $store.transaction.wholeUnits)
                .focused($focus, equals: .value)
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
    private var repeatSection: some View {
        Section {
            // Repeat picker
            Picker(selection: $store.recurrencePreset.animation()) {
                Text("Never").tag(RecurrencePreset?.none)
                Divider()
                ForEach(RecurrencePreset.standardPresets) { preset in
                    Text(preset.displayName).tag(RecurrencePreset?.some(preset))
                }
                Divider()
                Text("Custom").tag(RecurrencePreset?.some(.custom))
            } label: {
                Label {
                    Text("Repeat")
                } icon: {
                    Image(systemName: "repeat")
                        .foregroundStyle(.secondary)
                }
            }

            // Show rule summary for custom rules
            if store.recurrencePreset == .custom, let rule = store.recurrenceRule {
                Text(rule.summaryDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // End Repeat picker (only when recurring)
            if store.isRecurring {
                Picker(
                    selection: Binding(
                        get: { store.recurrenceRule?.endMode ?? .never },
                        set: { send(.endRepeatModeSelected($0)) }
                    ).animation()
                ) {
                    Text("Never").tag(RecurrenceEndMode.never)
                    Text("On Date").tag(RecurrenceEndMode.onDate)
                    Text("After").tag(RecurrenceEndMode.afterOccurrences)
                } label: {
                    Label {
                        Text("End Repeat")
                    } icon: {
                        Image(systemName: "repeat.badge.xmark")
                            .foregroundStyle(.secondary)
                    }
                }

                // End Date picker (when endMode is .onDate)
                if let recurrenceRule = store.recurrenceRule, recurrenceRule.endMode == .onDate {
                    DatePicker(
                        "End Date",
                        selection: Binding(
                            get: { recurrenceRule.endDate ?? Date() },
                            set: { send(.endDateChanged($0)) }
                        ),
                        displayedComponents: .date
                    )
                }

                // Occurrences picker (when endMode is .afterOccurrences)
                if let recurrenceRule = store.recurrenceRule, recurrenceRule.endMode == .afterOccurrences {
                    Stepper(
                        value: Binding(
                            get: { recurrenceRule.endAfterOccurrences },
                            set: { send(.endAfterOccurrencesChanged($0)) }
                        ),
                        in: 1...999
                    ) {
                        Text("After \(recurrenceRule.endAfterOccurrences) occurrences")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var endRepeatDisplayText: String {
        guard let rule = store.recurrenceRule else { return "Never" }
        switch rule.endMode {
        case .never:
            return "Never"
        case .onDate:
            return "On Date"
        case .afterOccurrences:
            return "After"
        }
    }

    @ViewBuilder
    private var dateTimePicker: some View {
        Section {
            Label {
                HStack {
                    Button {
                        send(.dateButtonTapped, animation: .default)
                    } label: {
                        Text(store.transaction.localDate.formattedRelativeDay())
                            .frame(maxWidth: .infinity, alignment: .leading)
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
            } icon: {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
            }

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
    private var categoriesSection: some View {
        Section {
            Button {
                send(.categoriesButtonTapped, animation: .default)
            } label: {
                HStack {
                    Label {
                        Text("Categories")
                    } icon: {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let category = store.category {
                        Text(category.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
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
                    Label {
                        Text("Tags")
                    } icon: {
                        Image(systemName: "number")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let tagsDetail {
                        tagsDetail
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
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
            Toggle(isOn: $store.isLocationEnabled.animation()) {
                Label {
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
                } icon: {
                    Image(systemName: "location")
                        .foregroundStyle(.secondary)
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
