import SwiftUI

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = Keychain.get("alpaca.key") ?? ""
    @State private var apiSecret = Keychain.get("alpaca.secret") ?? ""
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("API Key ID", text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("API Secret", text: $apiSecret)
                    Button {
                        Task { await testAndSave() }
                    } label: {
                        if testing {
                            ProgressView()
                        } else {
                            Text("Save & test connection")
                        }
                    }
                    .disabled(apiKey.isEmpty || apiSecret.isEmpty || testing)
                    if let testResult {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testResult.hasPrefix("✓") ? .green : .orange)
                    }
                } header: {
                    Text("Alpaca market data")
                } footer: {
                    Text("Free real-time IEX quotes. Create keys at alpaca.markets — a paper trading account is enough; keys are stored in the Keychain and never leave this device.")
                }

                Section("Data") {
                    LabeledContent("Symbols tracked", value: "\(store.allSymbols.count)")
                    LabeledContent("Last refresh") {
                        QuoteTimestampView()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func testAndSave() async {
        testing = true
        defer { testing = false }
        Keychain.set(apiKey.trimmingCharacters(in: .whitespaces), for: "alpaca.key")
        Keychain.set(apiSecret.trimmingCharacters(in: .whitespaces), for: "alpaca.secret")
        guard let creds = AlpacaCredentials.stored() else {
            testResult = "Keys not saved."
            return
        }
        do {
            try await AlpacaService.verify(creds: creds)
            testResult = "✓ Connected — live IEX quotes active."
            await store.refreshQuotes()
        } catch {
            testResult = error.localizedDescription
        }
    }
}
