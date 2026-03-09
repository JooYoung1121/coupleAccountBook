import SwiftUI
import SwiftData
import FirebaseCore

@main
struct coupleAccountBankApp: App {
    @State private var authService = AuthService()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
        }
        .modelContainer(for: [Transaction.self, Goal.self])
    }
}
