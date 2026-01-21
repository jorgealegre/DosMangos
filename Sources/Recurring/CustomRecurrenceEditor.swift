import ComposableArchitecture
import SwiftUI

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
        .navigationTitle(Text("Custom"))
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
                Text("Frequency")
            }

            Stepper(
                value: $store.rule.interval,
                in: 1...99
            ) {
                Text("Every \(store.rule.interval)")
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
                    Text("Each")
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
                    Text("On the...")
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
                Text("Ordinal")
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            Picker(selection: $store.rule.monthlyWeekday) {
                ForEach(Weekday.ordered) { weekday in
                    Text(weekday.fullName).tag(weekday)
                }
            } label: {
                Text("Weekday")
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
                Text("Days of Week")
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
                Text("Ordinal")
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            Picker(selection: $store.rule.yearlyWeekday) {
                ForEach(Weekday.ordered) { weekday in
                    Text(weekday.fullName).tag(weekday)
                }
            } label: {
                Text("Weekday")
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 150)
    }
}

// MARK: - Previews

#Preview("Custom Editor - Weekly") {
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

#Preview("Custom Editor - Monthly") {
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

#Preview("Custom Editor - Yearly") {
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
