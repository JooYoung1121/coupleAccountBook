import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Text("계정 및 파트너 설정")
                .foregroundStyle(.secondary)
                .navigationTitle("설정")
        }
    }
}

#Preview {
    SettingsView()
}
