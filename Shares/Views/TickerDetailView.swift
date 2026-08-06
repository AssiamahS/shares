import SwiftUI
import Charts

struct TickerDetailView: View {
    @Environment(Store.self) private var store
    let symbol: String
    @State private var bars: [BarPoint] = []
    @State private var barsError: String?
    @State private var showAddTransaction = false

    private var merged: Position? {
        store.mergedPositions.first { $0.symbol == symbol }
    }

    var body: some View {
        List {
            quoteSection
            chartSection
            positionSection
            lotsSection
        }
        .navigationTitle(symbol)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Trade", systemImage: "plus.forwardslash.minus") { showAddTransaction = true }
            }
        }
        .sheet(isPresented: $showAddTransaction) {
            AddTransactionView(prefilledSymbol: symbol)
        }
        .task {
            guard bars.isEmpty, let creds = AlpacaCredentials.stored() else { return }
            do {
                bars = try await AlpacaService.dailyBars(symbol: symbol, days: 180, creds: creds)
                barsError = nil
            } catch {
                barsError = error.localizedDescription
            }
        }
    }

    private var quoteSection: some View {
        Section {
            let quote = store.quotes[symbol]
            VStack(alignment: .leading, spacing: 4) {
                Text(quote?.price.usd ?? "—")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                if let quote, let prev = quote.prevClose {
                    let change = quote.price - prev
                    let pct = prev > 0 ? change / prev * 100 : 0
                    Text("\(change.signedUsd) (\(pct.formatted(.number.precision(.fractionLength(2))))%) today")
                        .font(.subheadline)
                        .foregroundStyle(change >= 0 ? .green : .red)
                }
                QuoteTimestampView()
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        Section("6 months") {
            if bars.count > 1 {
                let rising = (bars.last?.close ?? 0) >= (bars.first?.close ?? 0)
                let tint: Color = rising ? .green : .red
                Chart(bars) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Close", point.close))
                        .foregroundStyle(tint)
                    AreaMark(x: .value("Date", point.date), y: .value("Close", point.close))
                        .foregroundStyle(tint.opacity(0.12))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)
                .padding(.vertical, 4)
            } else if let barsError {
                Text(barsError).font(.caption).foregroundStyle(.orange)
            } else if AlpacaCredentials.stored() == nil {
                Text("Add Alpaca keys in Settings to load charts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private var positionSection: some View {
        if let merged {
            let quote = store.quotes[symbol]
            Section("Your position") {
                LabeledContent("Shares", value: merged.shares.qty)
                LabeledContent("Avg cost", value: merged.avgCost.usd)
                LabeledContent("Market value", value: merged.marketValue(quote)?.usd ?? "—")
                if let unrealized = merged.unrealized(quote) {
                    LabeledContent("Unrealized") {
                        Text(unrealized.signedUsd).foregroundStyle(unrealized >= 0 ? .green : .red)
                    }
                }
                if merged.realized != 0 {
                    LabeledContent("Realized") {
                        Text(merged.realized.signedUsd).foregroundStyle(merged.realized >= 0 ? .green : .red)
                    }
                }
            }
        }
    }

    private var lotsSection: some View {
        ForEach(store.portfolios) { portfolio in
            let lots = portfolio.lots.filter { $0.symbol == symbol && $0.sharesRemaining > 0 }
            if !lots.isEmpty {
                Section("Lots — \(portfolio.name)") {
                    ForEach(lots) { lot in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(lot.sharesRemaining.qty) sh @ \(lot.costPerShare.usd)")
                                Text(lot.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let quote = store.quotes[symbol] {
                                let gain = (quote.price - lot.costPerShare) * lot.sharesRemaining
                                Text(gain.signedUsd)
                                    .font(.subheadline)
                                    .foregroundStyle(gain >= 0 ? .green : .red)
                            }
                        }
                    }
                }
            }
        }
    }
}
