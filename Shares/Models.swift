import Foundation

struct Lot: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var symbol: String
    var shares: Double
    var costPerShare: Double
    var date: Date
    var sharesSold: Double = 0
    var realized: Double = 0

    var sharesRemaining: Double { max(0, shares - sharesSold) }
    var costRemaining: Double { sharesRemaining * costPerShare }
}

struct Portfolio: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var cash: Double = 0
    var lots: [Lot] = []

    var openSymbols: [String] {
        Array(Set(lots.filter { $0.sharesRemaining > 0 }.map(\.symbol))).sorted()
    }
}

struct Quote: Codable, Hashable, Sendable {
    var price: Double
    var prevClose: Double?
    var asOf: Date
}

/// A holding in one symbol — either scoped to a portfolio or merged across all of them.
struct Position: Identifiable, Sendable {
    let symbol: String
    let portfolioName: String?   // nil = merged across portfolios
    let shares: Double
    let avgCost: Double
    let realized: Double

    var id: String { "\(symbol)|\(portfolioName ?? "*")" }
    var costBasis: Double { shares * avgCost }

    func marketValue(_ quote: Quote?) -> Double? { quote.map { $0.price * shares } }
    func unrealized(_ quote: Quote?) -> Double? { quote.map { ($0.price - avgCost) * shares } }
    func dayChange(_ quote: Quote?) -> Double? {
        guard let quote, let prev = quote.prevClose else { return nil }
        return (quote.price - prev) * shares
    }

    static func build(symbol: String, lots: [Lot], portfolioName: String?) -> Position {
        let open = lots.filter { $0.sharesRemaining > 0 }
        let shares = open.reduce(0) { $0 + $1.sharesRemaining }
        let cost = open.reduce(0) { $0 + $1.costRemaining }
        return Position(
            symbol: symbol,
            portfolioName: portfolioName,
            shares: shares,
            avgCost: shares > 0 ? cost / shares : 0,
            realized: lots.reduce(0) { $0 + $1.realized }
        )
    }
}

struct BarPoint: Identifiable, Sendable {
    let date: Date
    let close: Double
    var id: Date { date }
}

extension Double {
    var usd: String {
        formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
    var signedUsd: String {
        (self >= 0 ? "+" : "") + usd
    }
    var qty: String {
        formatted(.number.precision(.fractionLength(0...4)))
    }
}
