import Foundation

extension Decimal {
  internal var int64Value: Int64 { return (self as NSNumber).int64Value }
}
