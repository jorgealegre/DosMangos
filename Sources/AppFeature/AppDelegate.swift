import ComposableArchitecture
import Foundation
import FileClient

public struct AppDelegateReducer: ReducerProtocol {
    public struct State: Equatable {

    }

    public enum Action: Equatable {
        case didFinishLaunching
    }

    @Dependency(\.fileClient) var fileClient

    public init() {}

    public func reduce(into state: inout State, action: Action) -> Effect<Action, Never> {
        switch action {
        case .didFinishLaunching:
            return .none
        }
    }
}
