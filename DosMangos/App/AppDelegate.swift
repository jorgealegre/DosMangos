import ComposableArchitecture
import Foundation

struct AppDelegateReducer: Reducer {
    struct State: Equatable {
    }

    enum Action {
        case didFinishLaunching
    }

    func reduce(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .didFinishLaunching:
            return .none
        }
    }
}
