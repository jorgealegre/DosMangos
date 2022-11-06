import AppFeature
import SwiftUI

@main
struct MoneyTrackerApp: App {
  var body: some Scene {
    WindowGroup {
      AppView(
        store: .init(
          initialState: .init(transactions: []),
          reducer: AppFeature()
        )
      )
      .tint(.purple)
    }
  }
}
