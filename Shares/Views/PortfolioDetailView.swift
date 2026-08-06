import SwiftUI

struct PortfolioDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let portfolioID: UUID
    @State private var cashText = ""
    @State private var editingCash = false

    private var portfolio: Portfolio? {
        store.portfolios.first { $0.id == portfolioID }
    }

    var body: some View {
        if let portfolio {
            List {
                Section {
                    LabeledContent("Value", value: store.value(of: portfolio)?.usd ?? "—")
                    HStack {
                        Text("Cash")
                        Spacer()
                        if editingCash {
                            TextField("0.00", text: $cashText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 120)
                            Button("Save") {
                                store.updateCash(portfolioID: portfolioID, cash: Double(cashText) ?? portfolio.cash)
                                editingCash = false
                            }
                        } else {
                            Button(portfolio.cash.usd) {
                                cashText = String(format: "%.2f", portfolio.cash)
                                editingCash = true
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Realized P&L") {
                        let realized = portfolio.lots.reduce(0) { $0 + $1.realized }
                        Text(realized.signedUsd)
                            .foregroundStyle(realized >= 0 ? .green : .red)
                    }
                }

                Section("Positions") {
                    let positions = store.positions(in: portfolio).filter { $0.shares > 0 }
                    if positions.isEmpty {
                        Text("No open positions.").foregroundStyle(.secondary)
                    }
                    ForEach(positions) { position in
                        NavigationLink {
                            TickerDetailView(symbol: position.symbol)
                        } label: {
                            PositionRowView(position: position)
                        }
                    }
                }

                Section {
                    Button("Delete portfolio", role: .destructive) {
                        store.deletePortfolio(id: portfolioID)
                        dismiss()
                    }
                }
            }
            .navigationTitle(portfolio.name)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Portfolio deleted", systemImage: "folder.badge.questionmark")
        }
    }
}
