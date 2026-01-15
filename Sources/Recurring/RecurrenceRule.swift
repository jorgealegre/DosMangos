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

    /// Standard presets (excludes Custom which is handled separately in menus)
    static var standardPresets: [RecurrencePreset] {
        [.daily, .weekdays, .weekends, .weekly, .biweekly, .monthly, .everyThreeMonths, .everySixMonths, .yearly]
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

// MARK: - Next Occurrence Calculation

extension RecurrenceRule {
    /// Calculates the next occurrence date after the given date based on this rule.
    func nextOccurrence(after date: Date) -> Date {
        @Dependency(\.calendar) var calendar

        switch frequency {
        case .daily:
            return nextDailyOccurrence(after: date, calendar: calendar)
        case .weekly:
            return nextWeeklyOccurrence(after: date, calendar: calendar)
        case .monthly:
            return nextMonthlyOccurrence(after: date, calendar: calendar)
        case .yearly:
            return nextYearlyOccurrence(after: date, calendar: calendar)
        }
    }

    // MARK: - Daily

    private func nextDailyOccurrence(after date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: interval, to: date) ?? date
    }

    // MARK: - Weekly

    private func nextWeeklyOccurrence(after date: Date, calendar: Calendar) -> Date {
        // If no specific days selected, just add interval weeks
        guard !weeklyDays.isEmpty else {
            return calendar.date(byAdding: .weekOfYear, value: interval, to: date) ?? date
        }

        let currentWeekday = calendar.component(.weekday, from: date)

        // Find the next selected weekday
        let sortedDays = weeklyDays.map(\.rawValue).sorted()

        // First, check if there's a day later this week
        if let nextDay = sortedDays.first(where: { $0 > currentWeekday }) {
            let daysToAdd = nextDay - currentWeekday
            return calendar.date(byAdding: .day, value: daysToAdd, to: date) ?? date
        }

        // Otherwise, go to the first selected day of the next interval week
        let firstDayOfNextCycle = sortedDays[0]
        let daysUntilEndOfWeek = 7 - currentWeekday + firstDayOfNextCycle
        let totalDays = daysUntilEndOfWeek + (interval - 1) * 7
        return calendar.date(byAdding: .day, value: totalDays, to: date) ?? date
    }

    // MARK: - Monthly

    private func nextMonthlyOccurrence(after date: Date, calendar: Calendar) -> Date {
        switch monthlyMode {
        case .each:
            return nextMonthlyEachOccurrence(after: date, calendar: calendar)
        case .onThe:
            return nextMonthlyOnTheOccurrence(after: date, calendar: calendar)
        }
    }

    private func nextMonthlyEachOccurrence(after date: Date, calendar: Calendar) -> Date {
        // If no specific days selected, just add interval months
        guard !monthlyDays.isEmpty else {
            return calendar.date(byAdding: .month, value: interval, to: date) ?? date
        }

        let currentDay = calendar.component(.day, from: date)
        let sortedDays = monthlyDays.sorted()

        // Check if there's a day later this month
        if let nextDay = sortedDays.first(where: { $0 > currentDay }) {
            // Check if this day exists in the current month
            let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
            let targetDay = min(nextDay, daysInMonth)
            if targetDay > currentDay {
                var components = calendar.dateComponents([.year, .month], from: date)
                components.day = targetDay
                if let result = calendar.date(from: components) {
                    return result
                }
            }
        }

        // Go to the first selected day of the next interval month
        guard var nextMonthDate = calendar.date(byAdding: .month, value: interval, to: date) else {
            return date
        }

        let firstDay = sortedDays[0]
        let daysInNextMonth = calendar.range(of: .day, in: .month, for: nextMonthDate)?.count ?? 31
        let targetDay = min(firstDay, daysInNextMonth)

        var components = calendar.dateComponents([.year, .month], from: nextMonthDate)
        components.day = targetDay
        return calendar.date(from: components) ?? nextMonthDate
    }

    private func nextMonthlyOnTheOccurrence(after date: Date, calendar: Calendar) -> Date {
        // "First Monday", "Last Friday", etc.
        guard var targetDate = calendar.date(byAdding: .month, value: interval, to: date) else {
            return date
        }

        return nthWeekdayOfMonth(
            ordinal: monthlyOrdinal,
            weekday: monthlyWeekday,
            inMonthOf: targetDate,
            calendar: calendar
        ) ?? targetDate
    }

    // MARK: - Yearly

    private func nextYearlyOccurrence(after date: Date, calendar: Calendar) -> Date {
        // If no specific months selected, just add interval years
        guard !yearlyMonths.isEmpty else {
            return calendar.date(byAdding: .year, value: interval, to: date) ?? date
        }

        let currentMonth = calendar.component(.month, from: date)
        let currentDay = calendar.component(.day, from: date)
        let sortedMonths = yearlyMonths.map(\.rawValue).sorted()

        // Check if there's a month later this year
        for monthRaw in sortedMonths where monthRaw > currentMonth {
            if let result = yearlyOccurrenceInMonth(monthRaw, year: calendar.component(.year, from: date), calendar: calendar) {
                return result
            }
        }

        // Check current month if day hasn't passed
        if sortedMonths.contains(currentMonth) {
            if yearlyDaysOfWeekEnabled {
                if let result = nthWeekdayOfMonth(ordinal: yearlyOrdinal, weekday: yearlyWeekday, month: currentMonth, year: calendar.component(.year, from: date), calendar: calendar),
                   calendar.component(.day, from: result) > currentDay {
                    return result
                }
            }
        }

        // Go to the first selected month of the next interval year
        let nextYear = calendar.component(.year, from: date) + interval
        let firstMonth = sortedMonths[0]

        if let result = yearlyOccurrenceInMonth(firstMonth, year: nextYear, calendar: calendar) {
            return result
        }

        // Fallback: just add interval years
        return calendar.date(byAdding: .year, value: interval, to: date) ?? date
    }

    private func yearlyOccurrenceInMonth(_ month: Int, year: Int, calendar: Calendar) -> Date? {
        if yearlyDaysOfWeekEnabled {
            return nthWeekdayOfMonth(ordinal: yearlyOrdinal, weekday: yearlyWeekday, month: month, year: year, calendar: calendar)
        } else {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            return calendar.date(from: components)
        }
    }

    // MARK: - Helpers

    private func nthWeekdayOfMonth(ordinal: WeekdayOrdinal, weekday: Weekday, inMonthOf date: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return nthWeekdayOfMonth(ordinal: ordinal, weekday: weekday, month: month, year: year, calendar: calendar)
    }

    private func nthWeekdayOfMonth(ordinal: WeekdayOrdinal, weekday: Weekday, month: Int, year: Int, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.weekday = weekday.rawValue

        switch ordinal {
        case .first:
            components.weekdayOrdinal = 1
        case .second:
            components.weekdayOrdinal = 2
        case .third:
            components.weekdayOrdinal = 3
        case .fourth:
            components.weekdayOrdinal = 4
        case .last:
            components.weekdayOrdinal = -1
        }

        return calendar.date(from: components)
    }
}

// MARK: - Preset Conversion

extension RecurrenceRule {
    static func from(preset: RecurrencePreset) -> RecurrenceRule {
        switch preset {
        case .daily:
            RecurrenceRule(frequency: .daily, interval: 1)
        case .weekdays:
            RecurrenceRule(frequency: .weekly, interval: 1, weeklyDays: Weekday.weekdays)
        case .weekends:
            RecurrenceRule(frequency: .weekly, interval: 1, weeklyDays: Weekday.weekends)
        case .weekly:
            RecurrenceRule(frequency: .weekly, interval: 1)
        case .biweekly:
            RecurrenceRule(frequency: .weekly, interval: 2)
        case .monthly:
            RecurrenceRule(frequency: .monthly, interval: 1)
        case .everyThreeMonths:
            RecurrenceRule(frequency: .monthly, interval: 3)
        case .everySixMonths:
            RecurrenceRule(frequency: .monthly, interval: 6)
        case .yearly:
            RecurrenceRule(frequency: .yearly, interval: 1)
        case .custom:
            RecurrenceRule()
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
