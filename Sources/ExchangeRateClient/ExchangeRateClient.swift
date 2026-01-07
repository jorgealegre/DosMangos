import Dependencies
import DependenciesMacros
import Foundation
import SQLiteData

@DependencyClient
struct ExchangeRateClient {
    /// Fetch rate for a specific date (from API or hardcoded)
    var fetchRate: @Sendable (
        _ from: String,
        _ to: String,
        _ date: Date
    ) async throws -> Double

    /// Get cached rate or fetch if not available
    var getRate: @Sendable (
        _ from: String,
        _ to: String,
        _ date: Date
    ) async throws -> Double
}

// MARK: - Error

enum ExchangeRateError: Error, LocalizedError {
    case rateNotAvailable(from: String, to: String, date: Date)

    var errorDescription: String? {
        switch self {
        case let .rateNotAvailable(from, to, date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "Exchange rate not available for \(from) → \(to) on \(formatter.string(from: date))"
        }
    }
}

// MARK: - Live Implementation

extension ExchangeRateClient: DependencyKey {
    static let liveValue: Self = {
        @Dependency(\.defaultDatabase) var database

        @Sendable func fetchRate(from: String, to: String, date: Date) async throws -> Double {
            // Same currency = 1.0
            guard from != to else { return 1.0 }
            if from == "ARS" && to == "USD" {
                return 1.0 / 1500.0
            }
            if from == "USD" && to == "ARS" {
                return 1500.0
            }

            throw ExchangeRateError.rateNotAvailable(from: from, to: to, date: date)
        }

        return Self(
            fetchRate: { from, to, date in
                try await fetchRate(from: from, to: to, date: date)
            },
            getRate: { from, to, date in
                // Same currency = 1.0
                guard from != to else { return 1.0 }

                // Normalize date to start of day for caching
                let calendar = Calendar.current
                let normalizedDate = calendar.startOfDay(for: date)

                // Check cache first
                let cached = try? await database.read { db in
                    try ExchangeRate
                        .where {
                            $0.fromCurrency.eq(from) &&
                            $0.toCurrency.eq(to) &&
                            $0.date.eq(normalizedDate)
                        }
                        .fetchOne(db)
                }

                if let cached {
                    return cached.rate
                }

                // Not cached, fetch from API
                let rate = try await fetchRate(from: from, to: to, date: normalizedDate)

                // Cache it
                try await database.write { db in
                    try ExchangeRate.insert {
                        ExchangeRate.Draft(
                            fromCurrency: from,
                            toCurrency: to,
                            rate: rate,
                            date: normalizedDate,
                            fetchedAt: Date() // TODO: pretty sure this is not needed
                        )
                    }.execute(db)
                }

                return rate
            }
        )
    }()
}

// MARK: - Test Implementation

extension ExchangeRateClient: TestDependencyKey {
    static let testValue = Self()

    static let previewValue = Self(
        fetchRate: { from, to, _ in
            guard from != to else { return 1.0 }
            if from == "ARS" && to == "USD" {
                return 1.0 / 1500.0
            }
            if from == "USD" && to == "ARS" {
                return 1500.0
            }
            return 1.0
        },
        getRate: { from, to, _ in
            guard from != to else { return 1.0 }
            if from == "ARS" && to == "USD" {
                return 1.0 / 1500.0
            }
            if from == "USD" && to == "ARS" {
                return 1500.0
            }
            return 1.0
        }
    )
}

// MARK: - Dependency Registration

extension DependencyValues {
    var exchangeRate: ExchangeRateClient {
        get { self[ExchangeRateClient.self] }
        set { self[ExchangeRateClient.self] = newValue }
    }
}

