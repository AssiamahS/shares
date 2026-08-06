import Foundation
import Observation

@MainActor @Observable
final class Store {
    var portfolios: [Portfolio] = []
    var quotes: [String: Quote] = [:]
    var lastRefresh: Date?
    var refreshError: String?
    var isRefreshing = false

    private static var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private let portfoliosURL = docs.appendingPathComponent("portfolios.json")
    private let quotesURL = docs.appendingPathComponent("quotes.json")

    init() {
        load()
        if portfolios.isEmpty {
            portfolios = [Portfolio(name: "Main")]
        }
    }

    // MARK: - Persistence

    private struct QuoteCache: Codable {
        var quotes: [String: Quote]
        var lastRefresh: Date?
    }

    func load() {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: portfoliosURL),
           let saved = try? decoder.decode([Portfolio].self, from: data) {
            portfolios = saved
        }
        if let data = try? Data(contentsOf: quotesURL),
           let cache = try? decoder.decode(QuoteCache.self, from: data) {
            quotes = cache.quotes
            lastRefresh = cache.lastRefresh
        }
    }

    func save() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(portfolios) {
            try? data.write(to: portfoliosURL, options: .atomic)
        }
        if let data = try? encoder.encode(QuoteCache(quotes: quotes, lastRefresh: lastRefresh)) {
            try? data.write(to: quotesURL, options: .atomic)
        }
    }

    // MARK: - Derived

    var allSymbols: [String] {
        Array(Set(portfolios.flatMap(\.openSymbols))).sorted()
    }

    func positions(in portfolio: Portfolio) -> [Position] {
        Dictionary(grouping: portfolio.lots, by: \.symbol)
            .map { Position.build(symbol: $0.key, lots: $0.value, portfolioName: portfolio.name) }
            .filter { $0.shares > 0 || $0.realized != 0 }
            .sorted { $0.symbol < $1.symbol }
    }

    /// The merged view: one row per symbol across every portfolio.
    var mergedPositions: [Position] {
        Dictionary(grouping: portfolios.flatMap(\.lots), by: \.symbol)
            .map { Position.build(symbol: $0.key, lots: $0.value, portfolioName: nil) }
            .filter { $0.shares > 0 }
            .sorted { $0.symbol < $1.symbol }
    }

    var totalCash: Double { portfolios.reduce(0) { $0 + $1.cash } }

    var holdingsValue: Double? {
        sum(mergedPositions) { $0.marketValue(quotes[$0.symbol]) }
    }

    var netWorth: Double? { holdingsValue.map { $0 + totalCash } }

    var totalDayChange: Double? {
        sum(mergedPositions) { $0.dayChange(quotes[$0.symbol]) }
    }

    var totalUnrealized: Double? {
        sum(mergedPositions) { $0.unrealized(quotes[$0.symbol]) }
    }

    var totalRealized: Double {
        portfolios.flatMap(\.lots).reduce(0) { $0 + $1.realized }
    }

    func value(of portfolio: Portfolio) -> Double? {
        sum(positions(in: portfolio).filter { $0.shares > 0 }) { $0.marketValue(quotes[$0.symbol]) }
            .map { $0 + portfolio.cash }
    }

    /// Sums an optional metric over positions; nil if any priced position is missing a quote.
    private func sum(_ positions: [Position], _ metric: (Position) -> Double?) -> Double? {
        var total = 0.0
        for position in positions {
            guard let value = metric(position) else { return nil }
            total += value
        }
        return total
    }

    // MARK: - Mutations

    func addPortfolio(named name: String) {
        portfolios.append(Portfolio(name: name))
        save()
    }

    func deletePortfolio(id: UUID) {
        portfolios.removeAll { $0.id == id }
        save()
    }

    func updateCash(portfolioID: UUID, cash: Double) {
        guard let i = portfolios.firstIndex(where: { $0.id == portfolioID }) else { return }
        portfolios[i].cash = cash
        save()
    }

    func buy(symbol: String, shares: Double, price: Double, date: Date, portfolioID: UUID, deductFromCash: Bool) {
        guard let i = portfolios.firstIndex(where: { $0.id == portfolioID }), shares > 0 else { return }
        portfolios[i].lots.append(Lot(symbol: symbol.uppercased(), shares: shares, costPerShare: price, date: date))
        if deductFromCash {
            portfolios[i].cash -= shares * price
        }
        save()
    }

    /// Lot-aware sell: the caller chooses exactly how many shares come out of each lot.
    func sell(allocations: [UUID: Double], price: Double, portfolioID: UUID, addToCash: Bool) {
        guard let i = portfolios.firstIndex(where: { $0.id == portfolioID }) else { return }
        var proceeds = 0.0
        for (lotID, qty) in allocations where qty > 0 {
            guard let j = portfolios[i].lots.firstIndex(where: { $0.id == lotID }) else { continue }
            let sold = min(qty, portfolios[i].lots[j].sharesRemaining)
            portfolios[i].lots[j].sharesSold += sold
            portfolios[i].lots[j].realized += (price - portfolios[i].lots[j].costPerShare) * sold
            proceeds += sold * price
        }
        if addToCash {
            portfolios[i].cash += proceeds
        }
        save()
    }

    // MARK: - Quotes

    func refreshQuotes() async {
        let symbols = allSymbols
        guard !symbols.isEmpty else { return }
        guard let creds = AlpacaCredentials.stored() else {
            refreshError = "Add your Alpaca API keys in Settings to get live prices."
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fresh = try await AlpacaService.snapshots(symbols: symbols, creds: creds)
            quotes.merge(fresh) { _, new in new }
            lastRefresh = Date()
            refreshError = nil
            save()
        } catch {
            refreshError = error.localizedDescription
        }
    }
}
