import ComposableArchitecture
import MapKit
import SQLiteData
import SwiftUI

@Reducer
struct TransactionsMap: Reducer {
    @ObservableState
    struct State: Equatable {
        @FetchAll(
            TransactionsListRow
                .where { $0.location.isNot(nil) },
            animation: .default
        )
        var rows: [TransactionsListRow]

        init() {
        }
    }

    enum Action: BindableAction, ViewAction {
        enum View {
            case onAppear
        }

        case binding(BindingAction<State>)
        case view(View)
    }

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .view(.onAppear):
                return .none
            }
        }
    }
}

@ViewAction(for: TransactionsMap.self)
struct TransactionsMapView: View {
    @Bindable var store: StoreOf<TransactionsMap>

    var body: some View {
        TransactionsMKMapView(rows: store.rows)
            .ignoresSafeArea()
            .onAppear { send(.onAppear) }
    }
}

private struct TransactionsMKMapView: UIViewRepresentable {
    let rows: [TransactionsListRow]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.register(
            TransactionAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: TransactionAnnotationView.reuseIdentifier
        )
        mapView.register(
            TransactionClusterAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: TransactionClusterAnnotationView.reuseIdentifier
        )
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.apply(rows: rows, to: mapView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var currentIDs: Set<UUID> = []

        func apply(rows: [TransactionsListRow], to mapView: MKMapView) {
            let newIDs = Set(rows.map(\.transaction.id))
            guard newIDs != currentIDs else { return }
            currentIDs = newIDs

            // Remove old transaction annotations (keep user location + anything else)
            let transactionAnnotations = mapView.annotations.compactMap { $0 as? TransactionAnnotation }
            mapView.removeAnnotations(transactionAnnotations)

            // Add fresh transaction annotations
            let newAnnotations: [TransactionAnnotation] = rows.compactMap { row in
                guard let location = row.location else { return nil }
                return TransactionAnnotation(
                    id: row.transaction.id,
                    coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                    isExpense: row.transaction.type == .expense,
                    valueText: valueText(for: row.transaction)
                )
            }
            mapView.addAnnotations(newAnnotations)
        }

        private func valueText(for transaction: Transaction) -> String {
            // Whole dollars, no decimals
            let dollars = transaction.valueMinorUnits / 100
            return transaction.type == .expense ? "-\(dollars)" : "\(dollars)"
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            if let cluster = annotation as? MKClusterAnnotation {
                let view =
                    mapView.dequeueReusableAnnotationView(
                        withIdentifier: TransactionClusterAnnotationView.reuseIdentifier,
                        for: cluster
                    ) as? TransactionClusterAnnotationView
                view?.annotation = cluster
                view?.configure(count: cluster.memberAnnotations.count)
                return view
            }

            if let transaction = annotation as? TransactionAnnotation {
                let view =
                    mapView.dequeueReusableAnnotationView(
                        withIdentifier: TransactionAnnotationView.reuseIdentifier,
                        for: transaction
                    ) as? TransactionAnnotationView
                view?.annotation = transaction
                view?.configure(valueText: transaction.valueText, isExpense: transaction.isExpense)
                return view
            }

            return nil
        }
    }
}

private final class TransactionAnnotation: NSObject, MKAnnotation {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let isExpense: Bool
    let valueText: String

    init(id: UUID, coordinate: CLLocationCoordinate2D, isExpense: Bool, valueText: String) {
        self.id = id
        self.coordinate = coordinate
        self.isExpense = isExpense
        self.valueText = valueText
        super.init()
    }
}

private final class TransactionAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "TransactionAnnotationView"
    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        clusteringIdentifier = "transactions"
        collisionMode = .rectangle
        canShowCallout = false

        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textAlignment = .center
        label.textColor = .white

        addSubview(label)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }

    func configure(valueText: String, isExpense: Bool) {
        label.text = valueText

        let size = CGSize(width: max(28, 10 + CGFloat(valueText.count) * 8), height: 24)
        frame = CGRect(origin: frame.origin, size: size)

        layer.cornerRadius = 10
        layer.masksToBounds = true

        if isExpense {
            backgroundColor = UIColor.clear
            label.textColor = UIColor(Color.expense)
            layer.borderWidth = 2
            layer.borderColor = UIColor(Color.expense).cgColor
        } else {
            backgroundColor = UIColor(Color.income)
            label.textColor = UIColor.white
            layer.borderWidth = 0
            layer.borderColor = nil
        }
    }
}

private final class TransactionClusterAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "TransactionClusterAnnotationView"
    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        collisionMode = .rectangle
        canShowCallout = false

        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        label.textAlignment = .center
        label.textColor = .white

        addSubview(label)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }

    func configure(count: Int) {
        label.text = "\(count)"
        let size = CGSize(width: 28, height: 28)
        frame = CGRect(origin: frame.origin, size: size)

        backgroundColor = UIColor(Color.purple)
        layer.cornerRadius = size.height / 2
        layer.masksToBounds = true
        layer.borderWidth = 2
        layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
    }
}

#Preview {
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
        try seedSampleData()
    }

    TransactionsMapView(
        store: Store(initialState: TransactionsMap.State()) {
            TransactionsMap()
                ._printChanges()
        }
    )
}


