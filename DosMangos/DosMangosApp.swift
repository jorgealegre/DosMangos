import ComposableArchitecture
import Dependencies
import SwiftUI

@main
struct DosMangosApp: SwiftUI.App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate

    @Dependency(\.context) var context

    init() {
        if context == .live {
            try! prepareDependencies {
                try $0.bootstrapDatabase()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            AppView(
                store: delegate.store
            )
            .tint(.purple)
        }
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate, ObservableObject {
    lazy var store = Store(
        initialState: App.State(
            //            destination: .transactionForm(.init(focus: .description, transaction: .init(absoluteValue: 123, createdAt: Date(), description: "", transactionType: .expense)))
        )
    ) {
        App()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        store.send(.appDelegate(.didFinishLaunching))
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
//    @Dependency(\.defaultSyncEngine) var syncEngine
    var window: UIWindow?

//    func windowScene(
//        _ windowScene: UIWindowScene,
//        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
//    ) {
//        Task {
//            try await syncEngine.acceptShare(metadata: cloudKitShareMetadata)
//        }
//    }
//
//    func scene(
//        _ scene: UIScene,
//        willConnectTo session: UISceneSession,
//        options connectionOptions: UIScene.ConnectionOptions
//    ) {
//        guard let cloudKitShareMetadata = connectionOptions.cloudKitShareMetadata
//        else {
//            return
//        }
//        Task {
//            try await syncEngine.acceptShare(metadata: cloudKitShareMetadata)
//        }
//    }
}
