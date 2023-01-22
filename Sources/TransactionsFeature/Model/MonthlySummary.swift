import Foundation

struct Summary: Equatable {
    let monthlyIncome: Int
    let monthlyExpenses: Int
    let monthlyBalance: Int
    let worth: Int
    
    init(monthlyIncome: Int, monthlyExpenses: Int, monthlyBalance: Int, worth: Int) {
        self.monthlyIncome = monthlyIncome
        self.monthlyExpenses = monthlyExpenses
        self.monthlyBalance = monthlyBalance
        self.worth = worth
    }
}
