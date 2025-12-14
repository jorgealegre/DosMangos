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
}


