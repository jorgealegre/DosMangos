import ComposableArchitecture
import CoreLocation
import CoreLocationClient
import Dependencies
import MapKit
import SwiftUI

@Reducer
struct LocationPickerReducer: Reducer {
    @ObservableState
    struct State: Equatable {
        var query: String = ""
        var results: [LocalSearchClient.Result] = []
        var isSearching: Bool = false

        var centerLatitude: Double
        var centerLongitude: Double
        var meters: Double = 300
        var mapUpdateID: UUID

        init(center: CLLocationCoordinate2D) {
            @Dependency(\.uuid) var uuid
            self.centerLatitude = center.latitude
            self.centerLongitude = center.longitude
            self.mapUpdateID = uuid()
        }

        var centerCoordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
        }
    }

    enum Action: ViewAction, BindableAction {
        enum Delegate: Equatable {
            case didPick(TransactionLocation.Draft)
        }

        enum View {
            case cancelButtonTapped
            case doneButtonTapped
            case resultTapped(LocalSearchClient.Result)
            case mapCameraChanged(latitude: Double, longitude: Double)
        }

        case binding(BindingAction<State>)
        case delegate(Delegate)
        case view(View)
        case searchResponse([LocalSearchClient.Result])
    }

    @Dependency(\.continuousClock) private var clock
    @Dependency(\.dismiss) private var dismiss
    @Dependency(\.geocodingClient) private var geocodingClient
    @Dependency(\.localSearch) private var localSearch
    @Dependency(\.uuid) private var uuid

    private enum CancelID { case search }

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding(\.query):
                let query = state.query
                guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    state.isSearching = false
                    state.results = []
                    return .cancel(id: CancelID.search)
                }
                let region = MKCoordinateRegion(
                    center: state.centerCoordinate,
                    latitudinalMeters: state.meters * 5,
                    longitudinalMeters: state.meters * 5
                )
                state.isSearching = true
                return .run { send in
                    try await clock.sleep(for: .milliseconds(300))
                    let results = try await localSearch.search(query, region)
                    await send(.searchResponse(results))
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case .binding:
                return .none

            case let .searchResponse(results):
                state.results = results
                state.isSearching = false
                return .none

            case let .view(view):
                switch view {
                case .cancelButtonTapped:
                    return .run { _ in
                        await dismiss()
                    }

                case let .resultTapped(result):
                    state.centerLatitude = result.latitude
                    state.centerLongitude = result.longitude
                    state.results = []
                    state.mapUpdateID = uuid()
                    return .none

                case let .mapCameraChanged(latitude, longitude):
                    state.centerLatitude = latitude
                    state.centerLongitude = longitude
                    return .none

                case .doneButtonTapped:
                    let coordinate = state.centerCoordinate
                    return .run { send in
                        let geocoded = try? await geocodingClient.reverseGeocode(coordinate)
                        let draft = TransactionLocation.Draft(
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude,
                            city: geocoded?.city,
                            countryCode: geocoded?.countryCode
                        )
                        await send(.delegate(.didPick(draft)))
                    }
                }

            case .delegate:
                return .none
            }
        }
    }
}

@ViewAction(for: LocationPickerReducer.self)
struct LocationPickerView: View {
    @Bindable var store: StoreOf<LocationPickerReducer>

    @State private var mapPosition: MapCameraPosition = .automatic

    var body: some View {
        Form {
            Section {
                ZStack {
                    Map(position: $mapPosition) {
                        // Map content can be empty; the pin is rendered as an overlay.
                    }
                    .onAppear {
                        mapPosition = .region(region(for: store.centerCoordinate, meters: store.meters))
                    }
                    .onChange(of: store.mapUpdateID) { _, _ in
                        mapPosition = .region(region(for: store.centerCoordinate, meters: store.meters))
                    }
                    .onMapCameraChange(frequency: .onEnd) { context in
                        send(
                            .mapCameraChanged(
                                latitude: context.region.center.latitude,
                                longitude: context.region.center.longitude
                            )
                        )
                    }

                    Image(systemName: "mappin")
                        .symbolRenderingMode(.multicolor)
                        .font(.title)
                        .shadow(radius: 2)
                }
                .frame(height: 320)
                .listRowInsets(EdgeInsets())
            }

            Section("Search") {
                TextField("Search for a place", text: $store.query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)

                if store.isSearching {
                    ProgressView()
                }
            }

            if !store.results.isEmpty {
                Section("Results") {
                    ForEach(store.results) { result in
                        Button {
                            send(.resultTapped(result), animation: .default)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                if let subtitle = result.subtitle, !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Adjust location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    send(.cancelButtonTapped)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    send(.doneButtonTapped)
                }
            }
        }
    }

    private func region(for coordinate: CLLocationCoordinate2D, meters: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: meters,
            longitudinalMeters: meters
        )
    }
}

#Preview {
    NavigationStack {
        LocationPickerView(
            store: Store(
                initialState: LocationPickerReducer.State(
                    center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
                )
            ) {
                LocationPickerReducer()
            }
        )
    }
}
