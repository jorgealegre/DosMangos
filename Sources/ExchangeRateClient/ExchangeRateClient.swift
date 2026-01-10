import Dependencies
import DependenciesMacros
import Foundation
import OSLog
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

        #if DEBUG
        let backendURL = "http://localhost:8000"
        #else
        let backendURL = "https://dosmangos.alegre.dev"
        #endif

        @Sendable func fetchRate(from: String, to: String, date: Date) async throws -> Double {
            // Same currency = 1.0
            guard from != to else { return 1.0 }

            // Format date as YYYY-MM-DD
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            let dateStr = formatter.string(from: date)

            logger.debug("Fetching rate: \(from) → \(to) for \(dateStr)")

            // Build API URL: GET /rates?base=FROM&symbols=TO&date=YYYY-MM-DD
            var components = URLComponents(string: "\(backendURL)/rates")!
            components.queryItems = [
                URLQueryItem(name: "base", value: from),
                URLQueryItem(name: "symbols", value: to),
                URLQueryItem(name: "date", value: dateStr)
            ]

            guard let url = components.url else {
                throw ExchangeRateError.rateNotAvailable(from: from, to: to, date: date)
            }

            // Make HTTP request
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw ExchangeRateError.rateNotAvailable(from: from, to: to, date: date)
            }

            // Parse JSON response
            struct RatesResponse: Codable {
                let base: String
                let date: String
                let rates: [String: [String: Double]]
            }

            logger.debug("Response received: \(String(data: data, encoding: .utf8) ?? "")")
            let ratesResponse: RatesResponse
            do {
                ratesResponse = try JSONDecoder().decode(RatesResponse.self, from: data)
            } catch {
                reportIssue(error)
                throw ExchangeRateError.rateNotAvailable(from: from, to: to, date: date)
            }

            // TODO: support more than just official rates
            guard let rate = ratesResponse.rates[to]?["official"] else {
                logger.error("Rate not found in response: \(from) → \(to)")
                throw ExchangeRateError.rateNotAvailable(from: from, to: to, date: date)
            }

            logger.debug("Fetched rate: \(from) → \(to) = \(rate)")
            return rate
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
                    logger.debug("Cache hit: \(from) → \(to) = \(cached.rate)")
                    return cached.rate
                }

                logger.debug("Cache miss: \(from) → \(to), fetching...")
                // Not cached, fetch from backend API
                let rate = try await fetchRate(from: from, to: to, date: normalizedDate)

                // Cache it locally
                try await database.write { db in
                    try ExchangeRate.insert {
                        ExchangeRate.Draft(
                            fromCurrency: from,
                            toCurrency: to,
                            rate: rate,
                            date: normalizedDate,
                            fetchedAt: Date()
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

nonisolated private let logger = Logger(subsystem: "DosMangos", category: "ExchangeRateClient")
