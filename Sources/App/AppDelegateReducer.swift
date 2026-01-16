import ComposableArchitecture
import Foundation

@Reducer
struct AppDelegateReducer: Reducer {
    struct State: Equatable {
    }

    enum Action {
        case didFinishLaunching
        case sceneDelegate(SceneDelegate)

        @CasePathable
        enum SceneDelegate {
            case willEnterForeground
        }
    }

    @Dependency(\.exchangeRate) private var exchangeRate

    func reduce(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .didFinishLaunching:
            return .none

        case .sceneDelegate(.willEnterForeground):
            return prefetchExchangeRates()
        }
    }

    private func prefetchExchangeRates() -> Effect<Action> {
        return .run { _ in
            try? await exchangeRate.prefetchRatesForToday()
        }
    }
}
