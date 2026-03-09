import SwiftUI
import SwiftData

@main
struct coupleAccountBankApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Transaction.self, Goal.self])
    }
}
