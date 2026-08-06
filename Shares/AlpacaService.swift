import Foundation

struct AlpacaCredentials: Sendable {
    let key: String
    let secret: String

    static func stored() -> AlpacaCredentials? {
        guard let key = Keychain.get("alpaca.key"), !key.isEmpty,
              let secret = Keychain.get("alpaca.secret"), !secret.isEmpty else { return nil }
        return AlpacaCredentials(key: key, secret: secret)
    }
}

enum AlpacaError: LocalizedError {
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            switch code {
            case 401, 403: return "Alpaca rejected the API keys (\(code)). Re-check them in Settings."
            case 429: return "Alpaca rate limit hit — try again in a minute."
            default: return "Alpaca error \(code): \(body.prefix(120))"
            }
        case .badResponse:
            return "Unexpected response from Alpaca."
        }
    }
}

/// Alpaca Market Data v2, free plan (IEX feed). Docs: docs.alpaca.markets
enum AlpacaService {
    private static let base = "https://data.alpaca.markets"

    private static func request(path: String, query: [URLQueryItem], creds: AlpacaCredentials) async throws -> Data {
        var components = URLComponents(string: base + path)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.setValue(creds.key, forHTTPHeaderField: "APCA-API-KEY-ID")
        request.setValue(creds.secret, forHTTPHeaderField: "APCA-API-SECRET-KEY")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AlpacaError.badResponse }
        guard http.statusCode == 200 else {
            throw AlpacaError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // MARK: - Snapshots (price + prev close + timestamp in one call)

    private struct RawBar: Decodable {
        let c: Double
        let t: String
    }

    private struct Snapshot: Decodable {
        struct Trade: Decodable {
            let p: Double
            let t: String
        }
        let latestTrade: Trade?
        let dailyBar: RawBar?
        let prevDailyBar: RawBar?
    }

    static func snapshots(symbols: [String], creds: AlpacaCredentials) async throws -> [String: Quote] {
        let data = try await request(
            path: "/v2/stocks/snapshots",
            query: [
                URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
                URLQueryItem(name: "feed", value: "iex"),
            ],
            creds: creds
        )
        let decoded = try JSONDecoder().decode([String: Snapshot].self, from: data)
        var quotes: [String: Quote] = [:]
        for (symbol, snap) in decoded {
            guard let price = snap.latestTrade?.p ?? snap.dailyBar?.c else { continue }
            let stamp = snap.latestTrade?.t ?? snap.dailyBar?.t
            quotes[symbol] = Quote(
                price: price,
                prevClose: snap.prevDailyBar?.c,
                asOf: stamp.flatMap(parseRFC3339) ?? Date()
            )
        }
        return quotes
    }

    // MARK: - Daily bars for charts

    private struct BarsResponse: Decodable {
        let bars: [RawBar]?
    }

    static func dailyBars(symbol: String, days: Int, creds: AlpacaCredentials) async throws -> [BarPoint] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let data = try await request(
            path: "/v2/stocks/\(symbol)/bars",
            query: [
                URLQueryItem(name: "timeframe", value: "1Day"),
                URLQueryItem(name: "start", value: ISO8601DateFormatter().string(from: start)),
                URLQueryItem(name: "limit", value: "1000"),
                URLQueryItem(name: "adjustment", value: "split"),
                URLQueryItem(name: "feed", value: "iex"),
            ],
            creds: creds
        )
        let decoded = try JSONDecoder().decode(BarsResponse.self, from: data)
        return (decoded.bars ?? [])
            .compactMap { bar in parseRFC3339(bar.t).map { BarPoint(date: $0, close: bar.c) } }
            .sorted { $0.date < $1.date }
    }

    static func verify(creds: AlpacaCredentials) async throws {
        _ = try await snapshots(symbols: ["AAPL"], creds: creds)
    }

    /// Alpaca stamps with RFC3339 and up to nanosecond fractions; trim to milliseconds first.
    private static func parseRFC3339(_ raw: String) -> Date? {
        let trimmed = raw.replacingOccurrences(
            of: #"(\.\d{1,3})\d*"#,
            with: "$1",
            options: .regularExpression
        )
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }
        let plain = ISO8601DateFormatter()
        return plain.date(from: raw)
    }
}
