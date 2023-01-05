import AppFeature
import SwiftUI

@main
struct DosMangosApp: App {
  var body: some Scene {
    WindowGroup {
      AppView(
        store: .init(
          initialState: .init(transactions: [.mock]),
          reducer: AppFeature()
        )
      )
      .tint(.purple)
    }
  }
}
