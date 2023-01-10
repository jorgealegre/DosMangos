import ComposableArchitecture
import Foundation

public struct AppDelegateReducer: ReducerProtocol {
    public struct State: Equatable {

    }

    public enum Action: Equatable {
        case didFinishLaunching
    }

    public init() {}

    public func reduce(into state: inout State, action: Action) -> Effect<Action, Never> {
        switch action {
        case .didFinishLaunching:
            return .none
        }
    }
}
