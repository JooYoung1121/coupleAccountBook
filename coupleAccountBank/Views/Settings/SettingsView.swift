import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var authService

    private var isPaired: Bool {
        authService.currentUser?.coupleID != nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section("커플") {
                    NavigationLink {
                        CoupleSettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isPaired ? "heart.fill" : "heart")
                                .foregroundStyle(isPaired ? .pink : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("커플 연결")
                                Text(isPaired ? "연결됨" : "미연결")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("데이터") {
                    NavigationLink("금융 연동 (은행·카드)") {
                        BankLinkView()
                    }
                }
                Section("개발자") {
                    NavigationLink("CODEF 테스트 (DEV)") {
                        CODEFTestView()
                    }
                }
                Section {
                    Button(role: .destructive) {
                        try? authService.signOut()
                    } label: {
                        HStack {
                            Spacer()
                            Text("로그아웃")
                            Spacer()
                        }
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
