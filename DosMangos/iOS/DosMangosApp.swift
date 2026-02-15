import ComposableArchitecture
import CloudKit
import CoreLocationClient
import Dependencies
import SQLiteData
import Sharing
import SwiftUI

@main
struct DosMangosApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate

    @Dependency(\.context) var context

    @State private var bootstrapError: Error?

    init() {
        if context == .live {
            // Need to touch the location client so that it starts up in the main thread.
            _ = LocationManagerClient.live

            do {
                try prepareDependencies {
                    try $0.bootstrapDatabase()

                    #if DEBUG || TESTFLIGHT
                    // Apply debug date override if set
                    @Shared(.debugDateOverride) var debugDate
                    if let debugDate {
                        $0.date = DateGenerator { debugDate }
                    }
                    #endif
                }
            } catch {
                _bootstrapError = State(initialValue: error)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if context == .live {
                AppView(store: delegate.store)
                    #if DEBUG || TESTFLIGHT
                    .alert(item: $bootstrapError, title: { Text($0.localizedDescription) }, actions: { error in
                        Button("Copy to Clipboard") {
                            UIPasteboard.general.string = String(error.localizedDescription)
                        }
                        Button("OK", role: .cancel) {}
                    })
                    #endif
            }
        }
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate, ObservableObject {
    @Dependency(\.context) var context

    static weak var shared: AppDelegate?

    lazy var store = Store(initialState: AppReducer.State()) {
        AppReducer()
#if DEBUG
            ._printChanges()
#endif
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        AppDelegate.shared = self
        if context == .live {
            store.send(.appDelegate(.didFinishLaunching))
        }
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
    @Dependency(\.context) var context
    @Dependency(\.defaultSyncEngine) var syncEngine
    var window: UIWindow?
    weak var store: StoreOf<AppReducer>?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard context != .test else { return }
        // Get store reference from static property
        self.store = AppDelegate.shared?.store

        guard let cloudKitShareMetadata = connectionOptions.cloudKitShareMetadata
        else { return }
        Task {
            try await syncEngine.acceptShare(metadata: cloudKitShareMetadata)
            await store?.send(.appDelegate(.sceneDelegate(.didAcceptShare)))
        }
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        store?.send(.appDelegate(.sceneDelegate(.willEnterForeground)))
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task {
            try await syncEngine.acceptShare(metadata: cloudKitShareMetadata)
            await store?.send(.appDelegate(.sceneDelegate(.didAcceptShare)))
        }
    }
}
