import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            Text("이번 달 요약")
                .foregroundStyle(.secondary)
                .navigationTitle("홈")
        }
    }
}

#Preview {
    HomeView()
}
