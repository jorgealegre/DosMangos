import App
import ComposableArchitecture
import SwiftUI

@main
struct DosMangosApp: SwiftUI.App {
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
    let store = Store(initialState: App.State()) {
        App()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        store.send(.appDelegate(.didFinishLaunching))

        return true
    }
}
