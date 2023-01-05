import Foundation

struct MonthlySummary: Equatable {
  let income: Double
  let expenses: Double
  let worth: Double

  init(income: Double, expenses: Double, worth: Double) {
    self.income = income
    self.expenses = expenses
    self.worth = worth
  }
}
