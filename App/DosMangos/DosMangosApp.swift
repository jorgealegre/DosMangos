import AppFeature
import ComposableArchitecture
import SwiftUI

@main
struct DosMangosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AppView(
                store: appDelegate.store
            )
            .tint(.purple)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    let store = Store(
        initialState: AppReducer.State(),
        reducer: AppReducer()
    )

    var viewStore: ViewStore<Void, AppReducer.Action> {
        ViewStore(store.stateless)
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        viewStore.send(.appDelegate(.didFinishLaunching))

        return true
    }
}
