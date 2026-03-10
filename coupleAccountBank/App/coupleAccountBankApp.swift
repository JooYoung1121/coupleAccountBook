import SwiftUI
import SwiftData

@main
struct coupleAccountBankApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            // AuthService.shared는 body 평가 시점에 처음 접근 →
            // AppDelegate.application(_:didFinishLaunchingWithOptions:) 이후 보장
            ContentView()
                .environment(AuthService.shared)
        }
        .modelContainer(for: [Transaction.self, Goal.self])
    }
}
