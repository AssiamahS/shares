import SwiftUI

struct AddTransactionView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var prefilledSymbol: String = ""

    private enum Mode: String, CaseIterable {
        case buy = "Buy"
        case sell = "Sell"
    }

    @State private var mode: Mode = .buy
    @State private var symbol = ""
    @State private var portfolioID: UUID?
    @State private var sharesText = ""
    @State private var priceText = ""
    @State private var date = Date()
    @State private var moveCash = true
    @State private var sellAllocations: [UUID: Double] = [:]

    private var selectedPortfolio: Portfolio? {
        store.portfolios.first { $0.id == portfolioID }
    }

    private var cleanSymbol: String {
        symbol.trimmingCharacters(in: .whitespaces).uppercased()
    }

    private var sellableLots: [Lot] {
        selectedPortfolio?.lots.filter { $0.symbol == cleanSymbol && $0.sharesRemaining > 0 } ?? []
    }

    private var totalSellShares: Double {
        sellAllocations.values.reduce(0, +)
    }

    private var canSave: Bool {
        guard portfolioID != nil, !cleanSymbol.isEmpty, let price = Double(priceText), price > 0 else { return false }
        switch mode {
        case .buy: return Double(sharesText).map { $0 > 0 } ?? false
        case .sell: return totalSellShares > 0
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Action", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                Section {
                    TextField("Symbol (e.g. AAPL)", text: $symbol)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Picker("Portfolio", selection: $portfolioID) {
                        ForEach(store.portfolios) { portfolio in
                            Text(portfolio.name).tag(Optional(portfolio.id))
                        }
                    }
                    TextField("Price per share", text: $priceText)
                        .keyboardType(.decimalPad)
                    if mode == .buy {
                        TextField("Shares", text: $sharesText)
                            .keyboardType(.decimalPad)
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                    }
                }

                if mode == .sell {
                    sellSection
                }

                Section {
                    Toggle(mode == .buy ? "Deduct from cash" : "Add proceeds to cash", isOn: $moveCash)
                }
            }
            .navigationTitle(mode == .buy ? "Log buy" : "Log sell")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .onAppear {
                symbol = prefilledSymbol
                portfolioID = portfolioID ?? store.portfolios.first?.id
                if priceText.isEmpty, let quote = store.quotes[cleanSymbol] {
                    priceText = String(format: "%.2f", quote.price)
                }
            }
            .onChange(of: mode) { sellAllocations = [:] }
            .onChange(of: portfolioID) { sellAllocations = [:] }
            .onChange(of: symbol) { sellAllocations = [:] }
        }
    }

    @ViewBuilder
    private var sellSection: some View {
        Section {
            if sellableLots.isEmpty {
                Text("No open lots of \(cleanSymbol.isEmpty ? "this symbol" : cleanSymbol) in \(selectedPortfolio?.name ?? "this portfolio").")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sellableLots) { lot in
                    Stepper(value: allocationBinding(for: lot), in: 0...lot.sharesRemaining, step: 1) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\((sellAllocations[lot.id] ?? 0).qty) of \(lot.sharesRemaining.qty) sh")
                            Text("bought \(lot.date.formatted(date: .abbreviated, time: .omitted)) @ \(lot.costPerShare.usd)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Sell all (FIFO)") {
                    sellAllocations = Dictionary(uniqueKeysWithValues: sellableLots.map { ($0.id, $0.sharesRemaining) })
                }
                LabeledContent("Selling", value: "\(totalSellShares.qty) sh")
            }
        } header: {
            Text("Pick lots")
        } footer: {
            Text("You choose which lots to sell from — no forced FIFO.")
        }
    }

    private func allocationBinding(for lot: Lot) -> Binding<Double> {
        Binding(
            get: { sellAllocations[lot.id] ?? 0 },
            set: { sellAllocations[lot.id] = min($0, lot.sharesRemaining) }
        )
    }

    private func save() {
        guard let portfolioID, let price = Double(priceText) else { return }
        switch mode {
        case .buy:
            guard let shares = Double(sharesText) else { return }
            store.buy(symbol: cleanSymbol, shares: shares, price: price, date: date,
                      portfolioID: portfolioID, deductFromCash: moveCash)
        case .sell:
            store.sell(allocations: sellAllocations, price: price,
                       portfolioID: portfolioID, addToCash: moveCash)
        }
        dismiss()
        Task { await store.refreshQuotes() }
    }
}
