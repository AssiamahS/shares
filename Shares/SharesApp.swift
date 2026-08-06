import SwiftUI

@main
struct SharesApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environment(store)
        }
    }
}
