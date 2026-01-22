import Dependencies
import DependenciesTestSupport
import Foundation
import Testing

@testable import DosMangos

struct RecurrenceRuleTests {
    let calendar = Calendar(identifier: .gregorian)

    private func date(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func dateComponents(_ date: Date) -> (year: Int, month: Int, day: Int) {
        (
            calendar.component(.year, from: date),
            calendar.component(.month, from: date),
            calendar.component(.day, from: date)
        )
    }

    private func nextOccurrence(for rule: RecurrenceRule, after date: Date) -> Date {
        withDependencies {
            $0.calendar = calendar
        } operation: {
            rule.nextOccurrence(after: date)
        }
    }

    // MARK: - Daily Recurrence

    @Test("Daily - every day")
    func daily_everyDay() {
        let rule = RecurrenceRule(frequency: .daily, interval: 1)
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 15))
        #expect(dateComponents(next) == (2025, 1, 16))
    }

    @Test("Daily - every 3 days")
    func daily_everyThreeDays() {
        let rule = RecurrenceRule(frequency: .daily, interval: 3)
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 15))
        #expect(dateComponents(next) == (2025, 1, 18))
    }

    @Test("Daily - crosses month boundary")
    func daily_crossesMonthBoundary() {
        let rule = RecurrenceRule(frequency: .daily, interval: 1)
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 31))
        #expect(dateComponents(next) == (2025, 2, 1))
    }

    @Test("Daily - crosses year boundary")
    func daily_crossesYearBoundary() {
        let rule = RecurrenceRule(frequency: .daily, interval: 1)
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 12, day: 31))
        #expect(dateComponents(next) == (2026, 1, 1))
    }

    // MARK: - Weekly Recurrence (No Specific Days)

    @Test("Weekly - simple weekly")
    func weekly_simple() {
        let rule = RecurrenceRule(frequency: .weekly, interval: 1)
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 15))
        #expect(dateComponents(next) == (2025, 1, 22))
    }

    @Test("Weekly - biweekly")
    func weekly_biweekly() {
        let rule = RecurrenceRule(frequency: .weekly, interval: 2)
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 15))
        #expect(dateComponents(next) == (2025, 1, 29))
    }

    // MARK: - Weekly Recurrence (Specific Days)

    @Test("Weekly - specific days, later this week")
    func weekly_specificDays_laterThisWeek() {
        // January 15, 2025 is Wednesday, looking for Thursday/Friday
        let rule = RecurrenceRule(
            frequency: .weekly,
            interval: 1,
            weeklyDays: [.thursday, .friday]
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 15))
        #expect(dateComponents(next) == (2025, 1, 16)) // Thursday
    }

    @Test("Weekly - specific days, need next week")
    func weekly_specificDays_needNextWeek() {
        // January 17, 2025 is Friday, looking for Monday/Wednesday
        let rule = RecurrenceRule(
            frequency: .weekly,
            interval: 1,
            weeklyDays: [.monday, .wednesday]
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 17))
        #expect(dateComponents(next) == (2025, 1, 20)) // Monday
    }

    @Test("Weekly - weekdays only (Mon-Fri)")
    func weekly_weekdaysOnly() {
        // January 18, 2025 is Saturday
        let rule = RecurrenceRule(
            frequency: .weekly,
            interval: 1,
            weeklyDays: Weekday.weekdays
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 18))
        #expect(dateComponents(next) == (2025, 1, 20)) // Monday
    }

    @Test("Weekly - weekends only (Sat-Sun)")
    func weekly_weekendsOnly() {
        // January 15, 2025 is Wednesday
        let rule = RecurrenceRule(
            frequency: .weekly,
            interval: 1,
            weeklyDays: Weekday.weekends
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 15))
        #expect(dateComponents(next) == (2025, 1, 18)) // Saturday
    }

    @Test("Weekly - biweekly with specific days")
    func weekly_biweeklyWithSpecificDays() {
        // January 17, 2025 is Friday, looking for Monday every 2 weeks
        let rule = RecurrenceRule(
            frequency: .weekly,
            interval: 2,
            weeklyDays: [.monday]
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 17))
        #expect(dateComponents(next) == (2025, 1, 27)) // Monday in 2 weeks
    }

    // MARK: - Monthly Recurrence "Each" Mode (Specific Days)

    @Test("Monthly each - no specific days")
    func monthlyEach_noSpecificDays() {
        let rule = RecurrenceRule(frequency: .monthly, interval: 1, monthlyMode: .each)
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 15))
        #expect(dateComponents(next) == (2025, 2, 15))
    }

    @Test("Monthly each - specific day later this month")
    func monthlyEach_specificDayLaterThisMonth() {
        let rule = RecurrenceRule(
            frequency: .monthly,
            interval: 1,
            monthlyMode: .each,
            monthlyDays: [10, 20, 25]
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 15))
        #expect(dateComponents(next) == (2025, 1, 20))
    }

    @Test("Monthly each - specific day need next month")
    func monthlyEach_specificDayNeedNextMonth() {
        let rule = RecurrenceRule(
            frequency: .monthly,
            interval: 1,
            monthlyMode: .each,
            monthlyDays: [5, 10]
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 15))
        #expect(dateComponents(next) == (2025, 2, 5))
    }

    @Test("Monthly each - day 31 skips short months")
    func monthlyEach_day31SkipsShortMonths() {
        // From January 31, day 31 doesn't exist in February
        let rule = RecurrenceRule(
            frequency: .monthly,
            interval: 1,
            monthlyMode: .each,
            monthlyDays: [31]
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 31))
        #expect(dateComponents(next) == (2025, 3, 31)) // Skips February
    }

    @Test("Monthly each - day 30 skips February")
    func monthlyEach_day30SkipsFebruary() {
        let rule = RecurrenceRule(
            frequency: .monthly,
            interval: 1,
            monthlyMode: .each,
            monthlyDays: [30]
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 30))
        #expect(dateComponents(next) == (2025, 3, 30)) // Skips February
    }

    @Test("Monthly each - every 3 months (quarterly)")
    func monthlyEach_quarterly() {
        let rule = RecurrenceRule(frequency: .monthly, interval: 3, monthlyMode: .each)
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 15))
        #expect(dateComponents(next) == (2025, 4, 15))
    }

    // MARK: - Monthly Recurrence "On The" Mode (nth Weekday)

    @Test("Monthly on the - first Monday, future in current month")
    func monthlyOnThe_firstMonday_futureInCurrentMonth() {
        // January 5, 2025 - First Monday is January 6
        let rule = RecurrenceRule(
            frequency: .monthly,
            monthlyMode: .onThe,
            monthlyOrdinal: .first,
            monthlyWeekday: .monday
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 5))
        #expect(dateComponents(next) == (2025, 1, 6))
    }

    @Test("Monthly on the - third Monday, future in current month")
    func monthlyOnThe_thirdMonday_futureInCurrentMonth() {
        // January 5, 2025 - Third Monday is January 20
        let rule = RecurrenceRule(
            frequency: .monthly,
            monthlyMode: .onThe,
            monthlyOrdinal: .third,
            monthlyWeekday: .monday
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 5))
        #expect(dateComponents(next) == (2025, 1, 20))
    }

    @Test("Monthly on the - third Monday, passed in current month")
    func monthlyOnThe_thirdMonday_passedInCurrentMonth() {
        // January 21, 2025 - Third Monday was January 20
        let rule = RecurrenceRule(
            frequency: .monthly,
            monthlyMode: .onThe,
            monthlyOrdinal: .third,
            monthlyWeekday: .monday
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 21))
        #expect(dateComponents(next) == (2025, 2, 17))
    }

    @Test("Monthly on the - last Friday")
    func monthlyOnThe_lastFriday() {
        // January 15, 2025 - Last Friday of January is January 31
        let rule = RecurrenceRule(
            frequency: .monthly,
            monthlyMode: .onThe,
            monthlyOrdinal: .last,
            monthlyWeekday: .friday
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 15))
        #expect(dateComponents(next) == (2025, 1, 31))
    }

    @Test("Monthly on the - last Friday, passed")
    func monthlyOnThe_lastFriday_passed() {
        // February 1, 2025 - Last Friday of January was January 31
        let rule = RecurrenceRule(
            frequency: .monthly,
            monthlyMode: .onThe,
            monthlyOrdinal: .last,
            monthlyWeekday: .friday
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 2, day: 1))
        #expect(dateComponents(next) == (2025, 2, 28)) // Last Friday of February
    }

    @Test("Monthly on the - every 2 months")
    func monthlyOnThe_everyTwoMonths() {
        // January 21, 2025 after third Monday - next is March's third Monday
        let rule = RecurrenceRule(
            frequency: .monthly,
            interval: 2,
            monthlyMode: .onThe,
            monthlyOrdinal: .third,
            monthlyWeekday: .monday
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 21))
        #expect(dateComponents(next) == (2025, 3, 17))
    }

    // MARK: - Yearly Recurrence (Simple)

    @Test("Yearly - simple yearly")
    func yearly_simple() {
        let rule = RecurrenceRule(frequency: .yearly, interval: 1)
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 6, day: 15))
        #expect(dateComponents(next) == (2026, 6, 15))
    }

    @Test("Yearly - every 2 years")
    func yearly_everyTwoYears() {
        let rule = RecurrenceRule(frequency: .yearly, interval: 2)
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 6, day: 15))
        #expect(dateComponents(next) == (2027, 6, 15))
    }

    // MARK: - Yearly Recurrence (Specific Months)

    @Test("Yearly - specific months, later this year")
    func yearly_specificMonths_laterThisYear() {
        let rule = RecurrenceRule(
            frequency: .yearly,
            yearlyMonths: [.march, .june, .september]
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 4, day: 15))
        #expect(dateComponents(next) == (2025, 6, 1))
    }

    @Test("Yearly - specific months, need next year")
    func yearly_specificMonths_needNextYear() {
        let rule = RecurrenceRule(
            frequency: .yearly,
            yearlyMonths: [.january, .march]
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 10, day: 15))
        #expect(dateComponents(next) == (2026, 1, 1))
    }

    // MARK: - Yearly Recurrence (nth Weekday of Specific Months)

    @Test("Yearly nth weekday - third Sunday of January, future in current month")
    func yearlyNthWeekday_thirdSundayJanuary_futureInCurrentMonth() {
        // January 15, 2025 - Third Sunday is January 19
        let rule = RecurrenceRule(
            frequency: .yearly,
            yearlyMonths: [.january, .march],
            yearlyDaysOfWeekEnabled: true,
            yearlyOrdinal: .third,
            yearlyWeekday: .sunday
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 15))
        #expect(dateComponents(next) == (2025, 1, 19))
    }

    @Test("Yearly nth weekday - second Tuesday of multiple months")
    func yearlyNthWeekday_secondTuesday_multipleMonths() {
        // February 3, 2025 - Second Tuesday is February 11
        let rule = RecurrenceRule(
            frequency: .yearly,
            yearlyMonths: [.february, .june, .october],
            yearlyDaysOfWeekEnabled: true,
            yearlyOrdinal: .second,
            yearlyWeekday: .tuesday
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 2, day: 3))
        #expect(dateComponents(next) == (2025, 2, 11))
    }

    @Test("Yearly nth weekday - passed in current month, goes to next selected month")
    func yearlyNthWeekday_passedCurrentMonth_goesToNextSelectedMonth() {
        // January 20, 2025 - Third Sunday was January 19, next is March 16
        let rule = RecurrenceRule(
            frequency: .yearly,
            yearlyMonths: [.january, .march],
            yearlyDaysOfWeekEnabled: true,
            yearlyOrdinal: .third,
            yearlyWeekday: .sunday
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 20))
        #expect(dateComponents(next) == (2025, 3, 16))
    }

    @Test("Yearly nth weekday - last month of year, wraps to next year")
    func yearlyNthWeekday_lastMonth_wrapsToNextYear() {
        // December 20, 2025 - passed December, next is January 2026
        let rule = RecurrenceRule(
            frequency: .yearly,
            yearlyMonths: [.january, .december],
            yearlyDaysOfWeekEnabled: true,
            yearlyOrdinal: .first,
            yearlyWeekday: .monday
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 12, day: 20))
        #expect(dateComponents(next) == (2026, 1, 5)) // First Monday of January 2026
    }

    @Test("Yearly nth weekday - last weekday of month")
    func yearlyNthWeekday_lastWeekdayOfMonth() {
        // Looking for last Thursday of November (Thanksgiving-ish)
        let rule = RecurrenceRule(
            frequency: .yearly,
            yearlyMonths: [.november],
            yearlyDaysOfWeekEnabled: true,
            yearlyOrdinal: .last,
            yearlyWeekday: .thursday
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 1, day: 1))
        #expect(dateComponents(next) == (2025, 11, 27)) // Last Thursday of November 2025
    }

    // MARK: - Edge Cases

    @Test("Leap year - February 29")
    func leapYear_february29() {
        // 2024 is a leap year, 2025 is not
        let rule = RecurrenceRule(frequency: .yearly, interval: 1)
        let next = nextOccurrence(for: rule, after: date(year: 2024, month: 2, day: 29))
        // February 29, 2024 + 1 year = February 28, 2025 (no Feb 29 in 2025)
        #expect(dateComponents(next) == (2025, 2, 28))
    }

    @Test("Year boundary - December to January")
    func yearBoundary_decemberToJanuary() {
        let rule = RecurrenceRule(
            frequency: .monthly,
            interval: 1,
            monthlyMode: .each,
            monthlyDays: [15]
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 12, day: 20))
        #expect(dateComponents(next) == (2026, 1, 15))
    }

    @Test("Weekly - crosses year boundary")
    func weekly_crossesYearBoundary() {
        // December 31, 2025 is Wednesday
        let rule = RecurrenceRule(
            frequency: .weekly,
            interval: 1,
            weeklyDays: [.friday]
        )
        let next = nextOccurrence(for: rule, after: date(year: 2025, month: 12, day: 31))
        #expect(dateComponents(next) == (2026, 1, 2)) // Friday January 2, 2026
    }
}
