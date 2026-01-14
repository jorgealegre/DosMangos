import ComposableArchitecture
import SwiftUI

@Reducer
struct RecurrencePickerReducer: Reducer {
    @Reducer
    enum Destination {
        case customEditor(CustomRecurrenceEditorReducer)
    }

    @ObservableState
    struct State: Equatable {
        var selectedPreset: RecurrencePreset = .never
        var rule: RecurrenceRule?
        @Presents var destination: Destination.State?
    }

    enum Action: ViewAction, BindableAction {
        enum View {
            case presetSelected(RecurrencePreset)
        }
        case binding(BindingAction<State>)
        case destination(PresentationAction<Destination.Action>)
        case view(View)
    }

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case let .destination(.presented(.customEditor(.delegate(delegateAction)))):
                switch delegateAction {
                case let .ruleUpdated(rule):
                    state.rule = rule
                    state.selectedPreset = rule.matchingPreset
                    return .none
                }

            case .destination(.dismiss):
                return .none

            case .destination:
                return .none

            case let .view(view):
                switch view {
                case let .presetSelected(preset):
                    state.selectedPreset = preset
                    if preset == .custom {
                        let initialRule = state.rule ?? RecurrenceRule()
                        state.destination = .customEditor(
                            CustomRecurrenceEditorReducer.State(rule: initialRule)
                        )
                    } else {
                        state.rule = RecurrenceRule.from(preset: preset)
                    }
                    return .none
                }
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension RecurrencePickerReducer.Destination.State: Equatable {}

@ViewAction(for: RecurrencePickerReducer.self)
struct RecurrencePickerView: View {
    @Bindable var store: StoreOf<RecurrencePickerReducer>

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    presetSection
                }

                if let rule = store.rule {
                    Section {
                        Text(rule.summaryDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Summary", bundle: .main)
                    }

                    endRepeatSection(rule: rule)
                }
            }
            .navigationTitle(Text("Recurrence", bundle: .main))
            .sheet(
                item: $store.scope(
                    state: \.destination?.customEditor,
                    action: \.destination.customEditor
                )
            ) { customStore in
                NavigationStack {
                    CustomRecurrenceEditorView(store: customStore)
                }
            }
        }
    }

    private var displayPreset: RecurrencePreset {
        store.rule?.matchingPreset ?? .never
    }

    @ViewBuilder
    private var presetSection: some View {
        ForEach(RecurrencePreset.allPresets) { preset in
            Button {
                send(.presetSelected(preset), animation: .default)
            } label: {
                HStack {
                    Text(preset.displayName)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if displayPreset == preset {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func endRepeatSection(rule: RecurrenceRule) -> some View {
        @Dependency(\.calendar) var calendar

        Section {
            Picker(selection: Binding(
                get: { rule.endMode },
                set: { newMode in
                    var updated = rule
                    updated.endMode = newMode
                    if newMode == .onDate && updated.endDate == nil {
                        updated.endDate = calendar.date(byAdding: .month, value: 1, to: Date()) ?? Date()
                    }
                    if newMode == .afterOccurrences && updated.endAfterOccurrences < 1 {
                        updated.endAfterOccurrences = 1
                    }
                    store.rule = updated
                }
            )) {
                Text("Never", bundle: .main).tag(RecurrenceEndMode.never)
                Text("On Date", bundle: .main).tag(RecurrenceEndMode.onDate)
                Text("After", bundle: .main).tag(RecurrenceEndMode.afterOccurrences)
            } label: {
                Text("End Repeat", bundle: .main)
            }
            .pickerStyle(.menu)

            if rule.endMode == .onDate {
                DatePicker(
                    selection: Binding(
                        get: { rule.endDate ?? Date() },
                        set: { newDate in
                            var updated = rule
                            updated.endDate = newDate
                            store.rule = updated
                        }
                    ),
                    displayedComponents: .date
                ) {
                    Text("End Date", bundle: .main)
                }
            }

            if rule.endMode == .afterOccurrences {
                Stepper(
                    value: Binding(
                        get: { rule.endAfterOccurrences },
                        set: { newValue in
                            var updated = rule
                            updated.endAfterOccurrences = newValue
                            store.rule = updated
                        }
                    ),
                    in: 1...999
                ) {
                    Text("After \(rule.endAfterOccurrences) occurrence(s)", bundle: .main)
                }
            }
        } header: {
            Text("End Repeat", bundle: .main)
        }
    }
}

// MARK: - Custom Recurrence Editor

@Reducer
struct CustomRecurrenceEditorReducer: Reducer {
    @ObservableState
    struct State: Equatable {
        var rule: RecurrenceRule
    }

    enum Action: ViewAction, BindableAction {
        enum Delegate {
            case ruleUpdated(RecurrenceRule)
        }
        enum View {
            case doneButtonTapped
            case weekdayToggled(Weekday)
            case monthlyDayToggled(Int)
            case monthToggled(Month)
        }
        case binding(BindingAction<State>)
        case delegate(Delegate)
        case view(View)
    }

    @Dependency(\.dismiss) private var dismiss

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
                case .doneButtonTapped:
                    return .run { [rule = state.rule] send in
                        await send(.delegate(.ruleUpdated(rule)))
                        await dismiss()
                    }

                case let .weekdayToggled(weekday):
                    if state.rule.weeklyDays.contains(weekday) {
                        state.rule.weeklyDays.remove(weekday)
                    } else {
                        state.rule.weeklyDays.insert(weekday)
                    }
                    return .none

                case let .monthlyDayToggled(day):
                    if state.rule.monthlyDays.contains(day) {
                        state.rule.monthlyDays.remove(day)
                    } else {
                        state.rule.monthlyDays.insert(day)
                    }
                    return .none

                case let .monthToggled(month):
                    if state.rule.yearlyMonths.contains(month) {
                        state.rule.yearlyMonths.remove(month)
                    } else {
                        state.rule.yearlyMonths.insert(month)
                    }
                    return .none
                }
            }
        }
    }
}

@ViewAction(for: CustomRecurrenceEditorReducer.self)
struct CustomRecurrenceEditorView: View {
    @Bindable var store: StoreOf<CustomRecurrenceEditorReducer>

    var body: some View {
        Form {
            frequencySection
            summaryText
            frequencySpecificOptions
        }
        .navigationTitle(Text("Custom", bundle: .main))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    send(.doneButtonTapped)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    // MARK: - Frequency Section

    @ViewBuilder
    private var frequencySection: some View {
        Section {
            Picker(selection: $store.rule.frequency) {
                ForEach(RecurrenceFrequency.allCases, id: \.self) { freq in
                    Text(freq.displayName).tag(freq)
                }
            } label: {
                Text("Frequency", bundle: .main)
            }

            Stepper(
                value: $store.rule.interval,
                in: 1...99
            ) {
                Text("Every \(store.rule.interval)", bundle: .main)
            }
        }
    }

    @ViewBuilder
    private var summaryText: some View {
        Text(store.rule.summaryDescription)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .listRowBackground(Color.clear)
    }

    // MARK: - Frequency-Specific Options

    @ViewBuilder
    private var frequencySpecificOptions: some View {
        switch store.rule.frequency {
        case .daily:
            EmptyView()
        case .weekly:
            weeklyOptions
        case .monthly:
            monthlyOptions
        case .yearly:
            yearlyOptions
        }
    }

    // MARK: - Weekly Options

    @ViewBuilder
    private var weeklyOptions: some View {
        Section {
            ForEach(Weekday.ordered) { weekday in
                Button {
                    send(.weekdayToggled(weekday), animation: .default)
                } label: {
                    HStack {
                        Text(weekday.fullName)
                            .foregroundStyle(Color.primary)
                        Spacer()
                        if store.rule.weeklyDays.contains(weekday) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Monthly Options

    @ViewBuilder
    private var monthlyOptions: some View {
        Section {
            Button {
                store.rule.monthlyMode = .each
            } label: {
                HStack {
                    Text("Each", bundle: .main)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if store.rule.monthlyMode == .each {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
            }

            Button {
                store.rule.monthlyMode = .onThe
            } label: {
                HStack {
                    Text("On the...", bundle: .main)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if store.rule.monthlyMode == .onThe {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
            }

            if store.rule.monthlyMode == .each {
                monthlyDaysGrid
            } else {
                monthlyOrdinalPicker
            }
        }
    }

    @ViewBuilder
    private var monthlyDaysGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(1...31, id: \.self) { day in
                Button {
                    send(.monthlyDayToggled(day), animation: .default)
                } label: {
                    Text("\(day)")
                        .font(.callout)
                        .frame(minWidth: 36, minHeight: 36)
                        .background(
                            store.rule.monthlyDays.contains(day)
                                ? Color.blue
                                : Color(.secondarySystemFill)
                        )
                        .foregroundStyle(
                            store.rule.monthlyDays.contains(day)
                                ? Color.white
                                : Color.primary
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var monthlyOrdinalPicker: some View {
        HStack {
            Picker(selection: $store.rule.monthlyOrdinal) {
                ForEach(WeekdayOrdinal.allCases, id: \.self) { ordinal in
                    Text(ordinal.displayName).tag(ordinal)
                }
            } label: {
                Text("Ordinal", bundle: .main)
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            Picker(selection: $store.rule.monthlyWeekday) {
                ForEach(Weekday.ordered) { weekday in
                    Text(weekday.fullName).tag(weekday)
                }
            } label: {
                Text("Weekday", bundle: .main)
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 150)
    }

    // MARK: - Yearly Options

    @ViewBuilder
    private var yearlyOptions: some View {
        Section {
            yearlyMonthsGrid
        }

        Section {
            Toggle(isOn: $store.rule.yearlyDaysOfWeekEnabled.animation()) {
                Text("Days of Week", bundle: .main)
            }

            if store.rule.yearlyDaysOfWeekEnabled {
                yearlyOrdinalPicker
            }
        }
    }

    @ViewBuilder
    private var yearlyMonthsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
            ForEach(Month.allCases) { month in
                Button {
                    send(.monthToggled(month), animation: .default)
                } label: {
                    Text(month.shortName)
                        .font(.callout)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(
                            store.rule.yearlyMonths.contains(month)
                                ? Color.blue
                                : Color(.secondarySystemFill)
                        )
                        .foregroundStyle(
                            store.rule.yearlyMonths.contains(month)
                                ? Color.white
                                : Color.primary
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var yearlyOrdinalPicker: some View {
        HStack {
            Picker(selection: $store.rule.yearlyOrdinal) {
                ForEach(WeekdayOrdinal.allCases, id: \.self) { ordinal in
                    Text(ordinal.displayName).tag(ordinal)
                }
            } label: {
                Text("Ordinal", bundle: .main)
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            Picker(selection: $store.rule.yearlyWeekday) {
                ForEach(Weekday.ordered) { weekday in
                    Text(weekday.fullName).tag(weekday)
                }
            } label: {
                Text("Weekday", bundle: .main)
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 150)
    }
}

// MARK: - Previews

#Preview("Recurrence Picker (English)") {
    let locale = Locale(identifier: "en_US")
    let _ = prepareDependencies {
        $0.locale = locale
        $0.calendar = {
            var cal = Calendar(identifier: .gregorian)
            cal.locale = locale
            return cal
        }()
    }
    RecurrencePickerView(
        store: Store(initialState: RecurrencePickerReducer.State()) {
            RecurrencePickerReducer()
                ._printChanges()
        }
    )
    .environment(\.locale, locale)
}

#Preview("Recurrence Picker (Spanish)") {
    let locale = Locale(identifier: "es_AR")
    let _ = prepareDependencies {
        $0.locale = locale
        $0.calendar = {
            var cal = Calendar(identifier: .gregorian)
            cal.locale = locale
            return cal
        }()
    }
    RecurrencePickerView(
        store: Store(initialState: RecurrencePickerReducer.State()) {
            RecurrencePickerReducer()
                ._printChanges()
        }
    )
    .environment(\.locale, locale)
}

#Preview("Custom Editor - Weekly (English)") {
    let locale = Locale(identifier: "en_US")
    let _ = prepareDependencies {
        $0.locale = locale
        $0.calendar = {
            var cal = Calendar(identifier: .gregorian)
            cal.locale = locale
            return cal
        }()
    }
    NavigationStack {
        CustomRecurrenceEditorView(
            store: Store(
                initialState: CustomRecurrenceEditorReducer.State(
                    rule: RecurrenceRule(
                        frequency: .weekly,
                        interval: 1,
                        weeklyDays: [.tuesday, .thursday]
                    )
                )
            ) {
                CustomRecurrenceEditorReducer()
            }
        )
    }
    .environment(\.locale, locale)
}

#Preview("Custom Editor - Weekly (Spanish)") {
    let locale = Locale(identifier: "es_AR")
    let _ = prepareDependencies {
        $0.locale = locale
        $0.calendar = {
            var cal = Calendar(identifier: .gregorian)
            cal.locale = locale
            return cal
        }()
    }
    NavigationStack {
        CustomRecurrenceEditorView(
            store: Store(
                initialState: CustomRecurrenceEditorReducer.State(
                    rule: RecurrenceRule(
                        frequency: .weekly,
                        interval: 1,
                        weeklyDays: [.tuesday, .thursday]
                    )
                )
            ) {
                CustomRecurrenceEditorReducer()
            }
        )
    }
    .environment(\.locale, locale)
}

#Preview("Custom Editor - Monthly (English)") {
    let locale = Locale(identifier: "en_US")
    let _ = prepareDependencies {
        $0.locale = locale
        $0.calendar = {
            var cal = Calendar(identifier: .gregorian)
            cal.locale = locale
            return cal
        }()
    }
    NavigationStack {
        CustomRecurrenceEditorView(
            store: Store(
                initialState: CustomRecurrenceEditorReducer.State(
                    rule: RecurrenceRule(
                        frequency: .monthly,
                        interval: 1,
                        monthlyMode: .onThe,
                        monthlyOrdinal: .first,
                        monthlyWeekday: .monday
                    )
                )
            ) {
                CustomRecurrenceEditorReducer()
            }
        )
    }
    .environment(\.locale, locale)
}

#Preview("Custom Editor - Yearly (Spanish)") {
    let locale = Locale(identifier: "es_AR")
    let _ = prepareDependencies {
        $0.locale = locale
        $0.calendar = {
            var cal = Calendar(identifier: .gregorian)
            cal.locale = locale
            return cal
        }()
    }
    NavigationStack {
        CustomRecurrenceEditorView(
            store: Store(
                initialState: CustomRecurrenceEditorReducer.State(
                    rule: RecurrenceRule(
                        frequency: .yearly,
                        interval: 1,
                        yearlyMonths: [.january, .july],
                        yearlyDaysOfWeekEnabled: true,
                        yearlyOrdinal: .first,
                        yearlyWeekday: .sunday
                    )
                )
            ) {
                CustomRecurrenceEditorReducer()
            }
        )
    }
    .environment(\.locale, locale)
}
