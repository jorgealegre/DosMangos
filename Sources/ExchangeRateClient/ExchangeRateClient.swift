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

    /// Prefetch all USD rates for today
    var prefetchRatesForToday: @Sendable () async throws -> Void
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

// MARK: - Models

struct RatesResponse: Codable {
    let base: String
    let date: String
    let rates: [String: [String: Double]]
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

                // Check cache first for direct rate
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

                logger.debug("Cache miss: \(from) → \(to), checking for inverse rate...")

                // Try inverse rate (TO → FROM exists, so FROM → TO = 1 / rate)
                let inverseRate = try? await database.read { db in
                    try ExchangeRate
                        .where {
                            $0.fromCurrency.eq(to) &&
                            $0.toCurrency.eq(from) &&
                            $0.date.eq(normalizedDate)
                        }
                        .fetchOne(db)
                }

                if let inverseRate {
                    let rate = 1.0 / inverseRate.rate
                    logger.debug("Inverse rate found: \(to) → \(from) = \(inverseRate.rate), computing \(from) → \(to) = \(rate)")

                    // Cache the inverse rate
                    try? await database.write { db in
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

                logger.debug("No inverse rate, checking for USD interpolation...")

                // Try to interpolate via USD if both legs are available
                if from != "USD" && to != "USD" {
                    let fromToUSD = try? await database.read { db in
                        try ExchangeRate
                            .where {
                                $0.fromCurrency.eq(from) &&
                                $0.toCurrency.eq("USD") &&
                                $0.date.eq(normalizedDate)
                            }
                            .fetchOne(db)
                    }

                    let usdToTo = try? await database.read { db in
                        try ExchangeRate
                            .where {
                                $0.fromCurrency.eq("USD") &&
                                $0.toCurrency.eq(to) &&
                                $0.date.eq(normalizedDate)
                            }
                            .fetchOne(db)
                    }

                    if let fromToUSD, let usdToTo {
                        let interpolatedRate = fromToUSD.rate * usdToTo.rate
                        logger.debug("Interpolated \(from) → \(to) via USD: \(interpolatedRate)")

                        // Cache the interpolated rate
                        try? await database.write { db in
                            try ExchangeRate.insert {
                                ExchangeRate.Draft(
                                    fromCurrency: from,
                                    toCurrency: to,
                                    rate: interpolatedRate,
                                    date: normalizedDate,
                                    fetchedAt: Date()
                                )
                            }.execute(db)
                        }

                        return interpolatedRate
                    }
                }

                logger.debug("No interpolation possible, fetching from backend...")
                // Not cached and can't interpolate, fetch from backend API
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
            },
            prefetchRatesForToday: {
                @Dependency(\.calendar) var calendar
                @Dependency(\.date.now) var now

                let today = calendar.startOfDay(for: now)

                // Check if we already have rates for today
                let existingCount = try await database.read { db in
                    try ExchangeRate
                        .where { $0.date.eq(today) && $0.fromCurrency.eq("USD") }
                        .fetchCount(db)
                }

                if existingCount > 0 {
                    logger.debug("Rates already cached for today, skipping prefetch")
                    return
                }

                logger.info("Prefetching exchange rates for today...")

                // Fetch all USD rates from backend
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                let dateStr = formatter.string(from: today)

                var components = URLComponents(string: "\(backendURL)/rates")!
                components.queryItems = [
                    URLQueryItem(name: "base", value: "USD"),
                    URLQueryItem(name: "date", value: dateStr)
                ]

                let (data, _) = try await URLSession.shared.data(from: components.url!)
                let ratesResponse = try JSONDecoder().decode(RatesResponse.self, from: data)

                // Bulk insert all official rates
                let count = try await database.write { db in
                    var count = 0
                    for (currency, rateTypes) in ratesResponse.rates {
                        if let officialRate = rateTypes["official"] {
                            try ExchangeRate.insert {
                                ExchangeRate.Draft(
                                    fromCurrency: "USD",
                                    toCurrency: currency,
                                    rate: officialRate,
                                    date: today,
                                    fetchedAt: Date()
                                )
                            }.execute(db)
                            count += 1
                        }
                    }
                    return count
                }

                logger.info("Prefetched \(count) exchange rates for today")
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
        },
        prefetchRatesForToday: { }
    )
}

// MARK: - Dependency Registration

extension DependencyValues {
    var exchangeRate: ExchangeRateClient {
        get { self[ExchangeRateClient.self] }
        set { self[ExchangeRateClient.self] = newValue }
    }
}

nonisolated private let logger = Logger(subsystem: "dev.alegre.DosMangos", category: "ExchangeRateClient")
