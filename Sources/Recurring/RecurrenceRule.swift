import Dependencies
import Foundation

// MARK: - Core Enums

enum RecurrenceFrequency: Int, CaseIterable, Sendable, Equatable {
    case daily
    case weekly
    case monthly
    case yearly

    var displayName: String {
        @Dependency(\.locale) var locale
        switch self {
        case .daily: return String(localized: "Daily", locale: locale)
        case .weekly: return String(localized: "Weekly", locale: locale)
        case .monthly: return String(localized: "Monthly", locale: locale)
        case .yearly: return String(localized: "Yearly", locale: locale)
        }
    }
}

enum Weekday: Int, CaseIterable, Sendable, Equatable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    var shortName: String {
        @Dependency(\.calendar) var calendar
        return calendar.shortWeekdaySymbols[rawValue - 1]
    }

    var fullName: String {
        @Dependency(\.calendar) var calendar
        return calendar.weekdaySymbols[rawValue - 1]
    }

    static var weekdays: Set<Weekday> {
        [.monday, .tuesday, .wednesday, .thursday, .friday]
    }

    static var weekends: Set<Weekday> {
        [.saturday, .sunday]
    }

    static var ordered: [Weekday] {
        @Dependency(\.calendar) var calendar
        let firstWeekday = calendar.firstWeekday
        let all = Weekday.allCases
        let firstIndex = all.firstIndex { $0.rawValue == firstWeekday } ?? 0
        return Array(all[firstIndex...]) + Array(all[..<firstIndex])
    }
}

enum Month: Int, CaseIterable, Sendable, Equatable, Identifiable {
    case january = 1
    case february = 2
    case march = 3
    case april = 4
    case may = 5
    case june = 6
    case july = 7
    case august = 8
    case september = 9
    case october = 10
    case november = 11
    case december = 12

    var id: Int { rawValue }

    var shortName: String {
        @Dependency(\.calendar) var calendar
        return calendar.shortMonthSymbols[rawValue - 1]
    }

    var fullName: String {
        @Dependency(\.calendar) var calendar
        return calendar.monthSymbols[rawValue - 1]
    }
}

enum WeekdayOrdinal: Int, CaseIterable, Sendable, Equatable {
    case first = 1
    case second = 2
    case third = 3
    case fourth = 4
    case last = -1

    var displayName: String {
        @Dependency(\.locale) var locale
        switch self {
        case .first: return String(localized: "first", locale: locale)
        case .second: return String(localized: "second", locale: locale)
        case .third: return String(localized: "third", locale: locale)
        case .fourth: return String(localized: "fourth", locale: locale)
        case .last: return String(localized: "last", locale: locale)
        }
    }
}

enum MonthlyMode: Int, Sendable, Equatable {
    case each
    case onThe
}

enum RecurrenceEndMode: Int, Sendable, Equatable {
    case never
    case onDate
    case afterOccurrences
}

// MARK: - Quick Presets

enum RecurrencePreset: Sendable, Equatable, Identifiable {
    case never
    case daily
    case weekdays
    case weekends
    case weekly
    case biweekly
    case monthly
    case everyThreeMonths
    case everySixMonths
    case yearly
    case custom

    var id: String {
        switch self {
        case .never: "never"
        case .daily: "daily"
        case .weekdays: "weekdays"
        case .weekends: "weekends"
        case .weekly: "weekly"
        case .biweekly: "biweekly"
        case .monthly: "monthly"
        case .everyThreeMonths: "every3months"
        case .everySixMonths: "every6months"
        case .yearly: "yearly"
        case .custom: "custom"
        }
    }

    var displayName: String {
        @Dependency(\.locale) var locale
        switch self {
        case .never: return String(localized: "Never", locale: locale)
        case .daily: return String(localized: "Daily", locale: locale)
        case .weekdays: return String(localized: "Weekdays", locale: locale)
        case .weekends: return String(localized: "Weekends", locale: locale)
        case .weekly: return String(localized: "Weekly", locale: locale)
        case .biweekly: return String(localized: "Biweekly", locale: locale)
        case .monthly: return String(localized: "Monthly", locale: locale)
        case .everyThreeMonths: return String(localized: "Every 3 Months", locale: locale)
        case .everySixMonths: return String(localized: "Every 6 Months", locale: locale)
        case .yearly: return String(localized: "Yearly", locale: locale)
        case .custom: return String(localized: "Custom", locale: locale)
        }
    }

    static var allPresets: [RecurrencePreset] {
        [.never, .daily, .weekdays, .weekends, .weekly, .biweekly, .monthly, .everyThreeMonths, .everySixMonths, .yearly, .custom]
    }
}

// MARK: - Recurrence Rule

struct RecurrenceRule: Sendable, Equatable {
    var frequency: RecurrenceFrequency
    var interval: Int

    // Weekly: selected days
    var weeklyDays: Set<Weekday>

    // Monthly
    var monthlyMode: MonthlyMode
    var monthlyDays: Set<Int>
    var monthlyOrdinal: WeekdayOrdinal
    var monthlyWeekday: Weekday

    // Yearly
    var yearlyMonths: Set<Month>
    var yearlyDaysOfWeekEnabled: Bool
    var yearlyOrdinal: WeekdayOrdinal
    var yearlyWeekday: Weekday

    // End condition
    var endMode: RecurrenceEndMode
    var endDate: Date?
    var endAfterOccurrences: Int

    init(
        frequency: RecurrenceFrequency = .daily,
        interval: Int = 1,
        weeklyDays: Set<Weekday> = [],
        monthlyMode: MonthlyMode = .each,
        monthlyDays: Set<Int> = [],
        monthlyOrdinal: WeekdayOrdinal = .first,
        monthlyWeekday: Weekday = .monday,
        yearlyMonths: Set<Month> = [],
        yearlyDaysOfWeekEnabled: Bool = false,
        yearlyOrdinal: WeekdayOrdinal = .first,
        yearlyWeekday: Weekday = .sunday,
        endMode: RecurrenceEndMode = .never,
        endDate: Date? = nil,
        endAfterOccurrences: Int = 1
    ) {
        self.frequency = frequency
        self.interval = interval
        self.weeklyDays = weeklyDays
        self.monthlyMode = monthlyMode
        self.monthlyDays = monthlyDays
        self.monthlyOrdinal = monthlyOrdinal
        self.monthlyWeekday = monthlyWeekday
        self.yearlyMonths = yearlyMonths
        self.yearlyDaysOfWeekEnabled = yearlyDaysOfWeekEnabled
        self.yearlyOrdinal = yearlyOrdinal
        self.yearlyWeekday = yearlyWeekday
        self.endMode = endMode
        self.endDate = endDate
        self.endAfterOccurrences = endAfterOccurrences
    }
}

// MARK: - Construction from RecurringTransaction

extension RecurrenceRule {
    /// Creates a RecurrenceRule from a database RecurringTransaction model
    static func from(recurringTransaction rt: RecurringTransaction) -> RecurrenceRule {
        RecurrenceRule(
            frequency: RecurrenceFrequency(rawValue: rt.frequency) ?? .monthly,
            interval: rt.interval,
            weeklyDays: parseWeekdays(rt.weeklyDays),
            monthlyMode: MonthlyMode(rawValue: rt.monthlyMode ?? 0) ?? .each,
            monthlyDays: parseDays(rt.monthlyDays),
            monthlyOrdinal: WeekdayOrdinal(rawValue: rt.monthlyOrdinal ?? 1) ?? .first,
            monthlyWeekday: Weekday(rawValue: rt.monthlyWeekday ?? 2) ?? .monday,
            yearlyMonths: parseMonths(rt.yearlyMonths),
            yearlyDaysOfWeekEnabled: rt.yearlyDaysOfWeekEnabled == 1,
            yearlyOrdinal: WeekdayOrdinal(rawValue: rt.yearlyOrdinal ?? 1) ?? .first,
            yearlyWeekday: Weekday(rawValue: rt.yearlyWeekday ?? 2) ?? .monday,
            endMode: RecurrenceEndMode(rawValue: rt.endMode) ?? .never,
            endDate: rt.endDate,
            endAfterOccurrences: rt.endAfterOccurrences ?? 1
        )
    }

    private static func parseWeekdays(_ string: String?) -> Set<Weekday> {
        guard let string, !string.isEmpty else { return [] }
        return Set(string.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.compactMap { Weekday(rawValue: $0) })
    }

    private static func parseDays(_ string: String?) -> Set<Int> {
        guard let string, !string.isEmpty else { return [] }
        return Set(string.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }

    private static func parseMonths(_ string: String?) -> Set<Month> {
        guard let string, !string.isEmpty else { return [] }
        return Set(string.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.compactMap { Month(rawValue: $0) })
    }
}

// MARK: - Preset Conversion

extension RecurrenceRule {
    static func from(preset: RecurrencePreset) -> RecurrenceRule? {
        switch preset {
        case .never:
            return nil
        case .daily:
            return RecurrenceRule(frequency: .daily, interval: 1)
        case .weekdays:
            return RecurrenceRule(frequency: .weekly, interval: 1, weeklyDays: Weekday.weekdays)
        case .weekends:
            return RecurrenceRule(frequency: .weekly, interval: 1, weeklyDays: Weekday.weekends)
        case .weekly:
            return RecurrenceRule(frequency: .weekly, interval: 1)
        case .biweekly:
            return RecurrenceRule(frequency: .weekly, interval: 2)
        case .monthly:
            return RecurrenceRule(frequency: .monthly, interval: 1)
        case .everyThreeMonths:
            return RecurrenceRule(frequency: .monthly, interval: 3)
        case .everySixMonths:
            return RecurrenceRule(frequency: .monthly, interval: 6)
        case .yearly:
            return RecurrenceRule(frequency: .yearly, interval: 1)
        case .custom:
            return RecurrenceRule()
        }
    }

    var matchingPreset: RecurrencePreset {
        if frequency == .daily && interval == 1 && weeklyDays.isEmpty {
            return .daily
        }
        if frequency == .weekly && interval == 1 && weeklyDays == Weekday.weekdays {
            return .weekdays
        }
        if frequency == .weekly && interval == 1 && weeklyDays == Weekday.weekends {
            return .weekends
        }
        if frequency == .weekly && interval == 1 && weeklyDays.isEmpty {
            return .weekly
        }
        if frequency == .weekly && interval == 2 && weeklyDays.isEmpty {
            return .biweekly
        }
        if frequency == .monthly && interval == 1 && monthlyDays.isEmpty && monthlyMode == .each {
            return .monthly
        }
        if frequency == .monthly && interval == 3 && monthlyDays.isEmpty && monthlyMode == .each {
            return .everyThreeMonths
        }
        if frequency == .monthly && interval == 6 && monthlyDays.isEmpty && monthlyMode == .each {
            return .everySixMonths
        }
        if frequency == .yearly && interval == 1 && yearlyMonths.isEmpty && !yearlyDaysOfWeekEnabled {
            return .yearly
        }
        return .custom
    }
}

// MARK: - Description

extension RecurrenceRule {
    var summaryDescription: String {
        @Dependency(\.locale) var locale

        switch frequency {
        case .daily:
            if interval == 1 {
                return String(localized: "Event will occur every day.", locale: locale)
            } else {
                return String(localized: "Event will occur every \(interval) days.", locale: locale)
            }

        case .weekly:
            if weeklyDays.isEmpty {
                if interval == 1 {
                    return String(localized: "Event will occur every week.", locale: locale)
                } else {
                    return String(localized: "Event will occur every \(interval) weeks.", locale: locale)
                }
            } else {
                let dayNames = weeklyDays
                    .sorted(by: { $0.rawValue < $1.rawValue })
                    .map(\.fullName)
                    .formatted(.list(type: .and).locale(locale))

                if interval == 1 {
                    return String(localized: "Event will occur every week on \(dayNames).", locale: locale)
                } else {
                    return String(localized: "Event will occur every \(interval) weeks on \(dayNames).", locale: locale)
                }
            }

        case .monthly:
            switch monthlyMode {
            case .each:
                if monthlyDays.isEmpty {
                    if interval == 1 {
                        return String(localized: "Event will occur every month.", locale: locale)
                    } else {
                        return String(localized: "Event will occur every \(interval) months.", locale: locale)
                    }
                } else {
                    let dayNumbers = monthlyDays
                        .sorted()
                        .map { ordinalString($0) }
                        .formatted(.list(type: .and).locale(locale))

                    if interval == 1 {
                        return String(localized: "Event will occur every month on the \(dayNumbers).", locale: locale)
                    } else {
                        return String(localized: "Event will occur every \(interval) months on the \(dayNumbers).", locale: locale)
                    }
                }
            case .onThe:
                let ordinal = monthlyOrdinal.displayName
                let weekday = monthlyWeekday.fullName

                if interval == 1 {
                    return String(localized: "Event will occur every month on the \(ordinal) \(weekday).", locale: locale)
                } else {
                    return String(localized: "Event will occur every \(interval) months on the \(ordinal) \(weekday).", locale: locale)
                }
            }

        case .yearly:
            if yearlyMonths.isEmpty && !yearlyDaysOfWeekEnabled {
                if interval == 1 {
                    return String(localized: "Event will occur every year.", locale: locale)
                } else {
                    return String(localized: "Event will occur every \(interval) years.", locale: locale)
                }
            } else if yearlyDaysOfWeekEnabled {
                let ordinal = yearlyOrdinal.displayName
                let weekday = yearlyWeekday.fullName

                if yearlyMonths.isEmpty {
                    if interval == 1 {
                        return String(localized: "Event will occur every year on the \(ordinal) \(weekday).", locale: locale)
                    } else {
                        return String(localized: "Event will occur every \(interval) years on the \(ordinal) \(weekday).", locale: locale)
                    }
                } else {
                    let monthNames = yearlyMonths
                        .sorted(by: { $0.rawValue < $1.rawValue })
                        .map(\.fullName)
                        .formatted(.list(type: .and).locale(locale))

                    if interval == 1 {
                        return String(localized: "Event will occur every year on the \(ordinal) \(weekday) of \(monthNames).", locale: locale)
                    } else {
                        return String(localized: "Event will occur every \(interval) years on the \(ordinal) \(weekday) of \(monthNames).", locale: locale)
                    }
                }
            } else {
                let monthNames = yearlyMonths
                    .sorted(by: { $0.rawValue < $1.rawValue })
                    .map(\.fullName)
                    .formatted(.list(type: .and).locale(locale))

                if interval == 1 {
                    return String(localized: "Event will occur every year in \(monthNames).", locale: locale)
                } else {
                    return String(localized: "Event will occur every \(interval) years in \(monthNames).", locale: locale)
                }
            }
        }
    }

    private func ordinalString(_ day: Int) -> String {
        @Dependency(\.locale) var locale
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: day)) ?? "\(day)"
    }
}
