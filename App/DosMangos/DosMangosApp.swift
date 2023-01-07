import AppFeature
import SwiftUI

@main
struct DosMangosApp: App {
  var body: some Scene {
    WindowGroup {
      AppView(
        store: .init(
          initialState: .init(date: .now, transactions: [.mock]),
          reducer: AppFeature()
        )
      )
      .tint(.purple)
    }
  }
}
