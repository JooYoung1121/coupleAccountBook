import SwiftUI

struct GoalListView: View {
    var body: some View {
        NavigationStack {
            Text("저축 / 투자 목표")
                .foregroundStyle(.secondary)
                .navigationTitle("목표")
        }
    }
}

#Preview {
    GoalListView()
}
