import ComposableArchitecture
import Foundation

public struct AppDelegateReducer: Reducer {
    public struct State: Equatable {
        public init() {}
    }

    public enum Action: Equatable {
        case didFinishLaunching
    }

    public init() {}

    public func reduce(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .didFinishLaunching:
            return .none
        }
    }
}
