import CoreLocation
import Currency
import Foundation
import SQLiteData

// MARK: - Groups (CloudKit shared tables)

@Table("groups")
struct TransactionGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var description: String
    var defaultCurrencyCode: String
    var simplifyDebts: Bool
    var createdAtUTC: Date
}
extension TransactionGroup.Draft: Equatable {}

@Table("group_members")
struct GroupMember: Identifiable, Hashable, Sendable {
    let id: UUID
    var groupID: TransactionGroup.ID
    var name: String
    var cloudKitParticipantID: String?
}
extension GroupMember.Draft: Equatable {}

enum GroupTransactionType: Int, QueryBindable, Sendable {
    case expense = 0
    case transfer = 1
}

enum GroupSplitType: Int, QueryBindable, Sendable {
    case equal = 0
    case percentage = 1
    case fixed = 2
}

@Table("group_transactions")
struct GroupTransaction: Identifiable, Hashable, Sendable {
    let id: UUID
    var groupID: TransactionGroup.ID
    var description: String
    var valueMinorUnits: Int
    var currencyCode: String
    var convertedValueMinorUnits: Int?
    var convertedCurrencyCode: String?
    var type: GroupTransactionType
    var splitType: GroupSplitType
    var createdAtUTC: Date
    var localYear: Int
    var localMonth: Int
    var localDay: Int

    var money: Money {
        get {
            Money(value: Int64(valueMinorUnits), currencyCode: currencyCode)
        }
        set {
            self.valueMinorUnits = Int(newValue.value)
            self.currencyCode = newValue.currencyCode
        }
    }

    var convertedMoney: Money? {
        guard let converted = convertedValueMinorUnits, let code = convertedCurrencyCode else {
            return nil
        }
        return Money(value: Int64(converted), currencyCode: code)
    }

    var localDate: Date {
        get {
            Date.localDate(year: localYear, month: localMonth, day: localDay)!
        }
        set {
            let local = newValue.localDateComponents()
            localYear = local.year
            localMonth = local.month
            localDay = local.day
        }
    }
}
extension GroupTransaction.Draft: Equatable {}

@Table("group_transaction_locations")
struct GroupTransactionLocation: Hashable, Sendable {
    @Column(primaryKey: true)
    let groupTransactionID: GroupTransaction.ID
    var latitude: Double
    var longitude: Double
    var city: String?
    var countryCode: String?
}
extension GroupTransactionLocation: Identifiable {
    var id: UUID { groupTransactionID }
}
extension GroupTransactionLocation {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
extension GroupTransactionLocation.Draft: Equatable {}

@Table("group_transaction_splits")
struct GroupTransactionSplit: Identifiable, Hashable, Sendable {
    let id: UUID
    var groupTransactionID: GroupTransaction.ID
    // Intentionally not a FK due to CloudKit single-FK sharing constraints.
    var memberID: GroupMember.ID
    var paidAmountMinorUnits: Int
    var owedAmountMinorUnits: Int
    var owedPercentage: Double?
}
extension GroupTransactionSplit.Draft: Equatable {}
