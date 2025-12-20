import Dependencies
import Foundation

extension Date {
    /// Extracts the calendar date components (year, month, day) for this date using the app's calendar dependency.
    ///
    /// Note: `Date` is an instant in time; this uses the injected `calendar` (and its timeZone) to interpret the
    /// instant into a local calendar day.
    func localDateComponents() -> (year: Int, month: Int, day: Int) {
        @Dependency(\.calendar) var calendar
        let components = calendar.dateComponents([.year, .month, .day], from: self)
        return (components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// Constructs a `Date` for the given local calendar date using the app's calendar dependency.
    ///
    /// Uses noon to avoid DST edge cases around midnight.
    static func localDate(year: Int, month: Int, day: Int, hour: Int = 12) -> Date? {
        @Dependency(\.calendar) var calendar
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
    }

    func formattedRelativeDay() -> String {
        @Dependency(\.calendar) var calendar
        @Dependency(\.date.now) var now

        // We only care about the calendar day, not the time-of-day.
        // Normalize both dates to the start of their day so RelativeDateTimeFormatter doesn't produce
        // "6 hours ago" for earlier-today times.
        let referenceDay = calendar.startOfDay(for: now)
        let selfDay = calendar.startOfDay(for: self)

        // We intentionally only special-case the named days ("today", "yesterday") using Apple's
        // RelativeDateTimeFormatter, and fall back to a date string for anything older.
        //
        // Docs: https://developer.apple.com/documentation/foundation/relativedatetimeformatter
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.formattingContext = .beginningOfSentence

        let dayDelta = calendar.dateComponents([.day], from: referenceDay, to: selfDay).day ?? 0
        if dayDelta == 0 || dayDelta == -1 || dayDelta == 1 {
            // 0 => today, -1 => yesterday, 1 => tomorrow (system-localized)
            return formatter.localizedString(from: DateComponents(day: dayDelta))
        }

        // Date-only fallback.
        return self.formatted(Date.FormatStyle().month().day().weekday(.wide))
    }
}
