import Dependencies
import Foundation

extension Date {
    func get(_ components: Calendar.Component...) -> DateComponents {
        @Dependency(\.calendar) var calendar
        return calendar.dateComponents(Set(components), from: self)
    }

    func get(_ component: Calendar.Component) -> Int {
        @Dependency(\.calendar) var calendar
        return calendar.component(component, from: self)
    }
}
