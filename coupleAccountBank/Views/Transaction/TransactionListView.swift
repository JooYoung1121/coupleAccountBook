import SwiftUI

struct TransactionListView: View {
    var body: some View {
        NavigationStack {
            Text("입출금 내역")
                .foregroundStyle(.secondary)
                .navigationTitle("내역")
        }
    }
}

#Preview {
    TransactionListView()
}
