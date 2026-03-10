import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("데이터") {
                    NavigationLink("은행 연동") {
                        BankLinkView()
                    }
                }
                Section("개발자") {
                    NavigationLink("CODEF 테스트 (DEV)") {
                        CODEFTestView()
                    }
                }
            }
            .navigationTitle("설정")
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthService())
}
