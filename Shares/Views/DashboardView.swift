import SwiftUI

struct DashboardView: View {
    @Environment(Store.self) private var store
    @State private var showSettings = false
    @State private var showAddTransaction = false
    @State private var newPortfolioName = ""
    @State private var showNewPortfolio = false

    var body: some View {
        NavigationStack {
            List {
                summarySection
                positionsSection
                portfoliosSection
            }
            .navigationTitle("Shares")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add trade", systemImage: "plus") { showAddTransaction = true }
                }
            }
            .refreshable { await store.refreshQuotes() }
            .task { await store.refreshQuotes() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showAddTransaction) { AddTransactionView() }
            .alert("New portfolio", isPresented: $showNewPortfolio) {
                TextField("Name", text: $newPortfolioName)
                Button("Add") {
                    let name = newPortfolioName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { store.addPortfolio(named: name) }
                    newPortfolioName = ""
                }
                Button("Cancel", role: .cancel) { newPortfolioName = "" }
            }
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.netWorth?.usd ?? "—")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                HStack(spacing: 12) {
                    if let day = store.totalDayChange {
                        Label(day.signedUsd, systemImage: day >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .foregroundStyle(day >= 0 ? .green : .red)
                    }
                    if let unrealized = store.totalUnrealized {
                        Text("\(unrealized.signedUsd) open")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                QuoteTimestampView()
            }
            .padding(.vertical, 4)
        } footer: {
            if let error = store.refreshError {
                Text(error).foregroundStyle(.orange)
            }
        }
    }

    private var positionsSection: some View {
        Section("All positions") {
            if store.mergedPositions.isEmpty {
                Text("No holdings yet — tap + to log your first buy.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.mergedPositions) { position in
                NavigationLink(value: position.symbol) {
                    PositionRowView(position: position)
                }
            }
        }
        .navigationDestination(for: String.self) { symbol in
            TickerDetailView(symbol: symbol)
        }
    }

    private var portfoliosSection: some View {
        Section("Portfolios") {
            ForEach(store.portfolios) { portfolio in
                NavigationLink {
                    PortfolioDetailView(portfolioID: portfolio.id)
                } label: {
                    HStack {
                        Text(portfolio.name)
                        Spacer()
                        Text(store.value(of: portfolio)?.usd ?? "—")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button("New portfolio", systemImage: "folder.badge.plus") { showNewPortfolio = true }
        }
    }
}

struct PositionRowView: View {
    @Environment(Store.self) private var store
    let position: Position

    var body: some View {
        let quote = store.quotes[position.symbol]
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(position.symbol).font(.headline)
                Text("\(position.shares.qty) sh @ \(position.avgCost.usd)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(position.marketValue(quote)?.usd ?? "—")
                    .font(.headline)
                if let day = position.dayChange(quote) {
                    Text(day.signedUsd)
                        .font(.caption)
                        .foregroundStyle(day >= 0 ? .green : .red)
                }
            }
        }
    }
}

/// The anti-stale-data feature: always show when prices were actually fetched.
struct QuoteTimestampView: View {
    @Environment(Store.self) private var store

    var body: some View {
        if let stamp = store.lastRefresh {
            let stale = Date().timeIntervalSince(stamp) > 15 * 60
            Label("as of \(stamp.formatted(date: .omitted, time: .shortened))",
                  systemImage: stale ? "clock.badge.exclamationmark" : "clock")
                .font(.caption2)
                .foregroundStyle(stale ? .orange : .secondary)
        } else {
            Label("no live prices yet", systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
