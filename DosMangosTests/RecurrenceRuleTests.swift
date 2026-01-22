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

    // MARK: - Yearly with Days of Week Bug

    @Test("Third Sunday of January and March - today is January 15")
    func thirdSundayOfJanuaryAndMarch_currentMonthHasFutureOccurrence() {
        // January 15, 2025 - Third Sunday is January 19 (4 days away)
        // Bug: Returns March 16 instead of January 19
        let rule = RecurrenceRule(
            frequency: .yearly,
            yearlyMonths: [.january, .march],
            yearlyDaysOfWeekEnabled: true,
            yearlyOrdinal: .third,
            yearlyWeekday: .sunday
        )

        let next = withDependencies {
            $0.calendar = calendar
        } operation: {
            rule.nextOccurrence(after: date(year: 2025, month: 1, day: 15))
        }

        #expect(dateComponents(next) == (2025, 1, 19))
    }

    @Test("Second Tuesday of February, June, October - today is February 3")
    func secondTuesdayMultipleMonths_currentMonthHasFutureOccurrence() {
        // February 3, 2025 - Second Tuesday is February 11 (8 days away)
        // Bug: Returns June 10 instead of February 11
        let rule = RecurrenceRule(
            frequency: .yearly,
            yearlyMonths: [.february, .june, .october],
            yearlyDaysOfWeekEnabled: true,
            yearlyOrdinal: .second,
            yearlyWeekday: .tuesday
        )

        let next = withDependencies {
            $0.calendar = calendar
        } operation: {
            rule.nextOccurrence(after: date(year: 2025, month: 2, day: 3))
        }

        #expect(dateComponents(next) == (2025, 2, 11))
    }

    @Test("First Monday of April and September - today is April 1 (Tuesday)")
    func firstMondayOfAprilAndSeptember_currentMonthHasFutureOccurrence() {
        // April 1, 2025 is a Tuesday - First Monday is April 7 (6 days away)
        // Bug: Returns September 1 instead of April 7
        let rule = RecurrenceRule(
            frequency: .yearly,
            yearlyMonths: [.april, .september],
            yearlyDaysOfWeekEnabled: true,
            yearlyOrdinal: .first,
            yearlyWeekday: .monday
        )

        let next = withDependencies {
            $0.calendar = calendar
        } operation: {
            rule.nextOccurrence(after: date(year: 2025, month: 4, day: 1))
        }

        #expect(dateComponents(next) == (2025, 4, 7))
    }

    // MARK: - Monthly "On The" (nth weekday) Bug

    @Test("Third Monday of each month - today is January 5")
    func thirdMondayOfMonth_currentMonthHasFutureOccurrence() {
        // January 5, 2025 - Third Monday is January 20 (15 days away)
        // Bug: Returns February 17 instead of January 20
        let rule = RecurrenceRule(
            frequency: .monthly,
            monthlyMode: .onThe,
            monthlyOrdinal: .third,
            monthlyWeekday: .monday
        )

        let next = withDependencies {
            $0.calendar = calendar
        } operation: {
            rule.nextOccurrence(after: date(year: 2025, month: 1, day: 5))
        }

        #expect(dateComponents(next) == (2025, 1, 20))
    }

    @Test("First Friday of each month - today is March 2")
    func firstFridayOfMonth_currentMonthHasFutureOccurrence() {
        // March 2, 2025 is a Sunday - First Friday is March 7 (5 days away)
        // Bug: Returns April 4 instead of March 7
        let rule = RecurrenceRule(
            frequency: .monthly,
            monthlyMode: .onThe,
            monthlyOrdinal: .first,
            monthlyWeekday: .friday
        )

        let next = withDependencies {
            $0.calendar = calendar
        } operation: {
            rule.nextOccurrence(after: date(year: 2025, month: 3, day: 2))
        }

        #expect(dateComponents(next) == (2025, 3, 7))
    }

    @Test("Third Monday of each month - today is January 21 (after third Monday)")
    func thirdMondayOfMonth_currentMonthOccurrenceHasPassed() {
        // January 21, 2025 - Third Monday was January 20 (yesterday)
        // Should correctly return February 17
        let rule = RecurrenceRule(
            frequency: .monthly,
            monthlyMode: .onThe,
            monthlyOrdinal: .third,
            monthlyWeekday: .monday
        )

        let next = withDependencies {
            $0.calendar = calendar
        } operation: {
            rule.nextOccurrence(after: date(year: 2025, month: 1, day: 21))
        }

        #expect(dateComponents(next) == (2025, 2, 17))
    }
}
