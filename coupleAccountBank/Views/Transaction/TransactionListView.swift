import SwiftUI
import FirebaseFirestore

struct TransactionListView: View {
    @Environment(AuthService.self) private var authService
    @State private var transactions: [TransactionDTO] = []
    @State private var listener: ListenerRegistration?

    private var effectiveCoupleID: String? {
        authService.currentUser?.effectiveCoupleID
    }

    var body: some View {
        NavigationStack {
            Group {
                if let coupleID = effectiveCoupleID {
                    if transactions.isEmpty {
                        emptyView
                    } else {
                        transactionList
                    }
                } else {
                    emptyView
                }
            }
            .navigationTitle("내역")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if effectiveCoupleID != nil {
                        NavigationLink {
                            BankLinkView()
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                            Text("가져오기")
                        }
                    }
                }
            }
            .onAppear {
                startListening()
            }
            .onDisappear {
                listener?.remove()
                listener = nil
            }
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("입출금 내역 없음", systemImage: "list.bullet.rectangle")
        } description: {
            if effectiveCoupleID == nil {
                Text("로그인 후 사용할 수 있어요.")
            } else {
                Text("설정 > 은행 연동에서 입출금 내역을 가져와 보세요.")
            }
        } actions: {
            if effectiveCoupleID != nil {
                NavigationLink("은행 연동하기") {
                    BankLinkView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transactionList: some View {
        List {
            ForEach(groupedByDate.keys.sorted(by: >), id: \.self) { dateKey in
                Section(header: sectionHeader(dateKey)) {
                    ForEach(groupedByDate[dateKey] ?? []) { dto in
                        TransactionRowView(dto: dto)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func sectionHeader(_ dateKey: String) -> some View {
        let date = formatSectionDate(dateKey)
        return HStack {
            Text(date)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let items = groupedByDate[dateKey] {
                let total = items.reduce(0.0) { sum, dto in
                    sum + (dto.type == TransactionType.income.rawValue ? dto.amount : -dto.amount)
                }
                Text(total >= 0 ? "+\(formatAmount(total))" : formatAmount(total))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(total >= 0 ? .green : .red)
            }
        }
        .padding(.vertical, 2)
    }

    private var groupedByDate: [String: [TransactionDTO]] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var grouped: [String: [TransactionDTO]] = [:]
        for dto in transactions {
            let key = formatter.string(from: dto.date.dateValue())
            grouped[key, default: []].append(dto)
        }
        for key in grouped.keys {
            grouped[key]?.sort { $0.date.dateValue() > $1.date.dateValue() }
        }
        return grouped
    }

    private func formatSectionDate(_ yyyyMMdd: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: yyyyMMdd) else { return yyyyMMdd }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "오늘" }
        if cal.isDateInYesterday(date) { return "어제" }
        formatter.dateFormat = "M월 d일 (EEE)"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }

    private func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: abs(value))) ?? "\(Int(value))"
    }

    private func startListening() {
        listener?.remove()
        guard let coupleID = effectiveCoupleID else { return }
        listener = FirebaseService.shared.listenToTransactions(coupleID: coupleID) { list in
            transactions = list
        }
    }
}

// MARK: - Row

struct TransactionRowView: View {
    let dto: TransactionDTO

    private var isIncome: Bool { dto.type == TransactionType.income.rawValue }
    private var category: TransactionCategory? {
        TransactionCategory(rawValue: dto.category)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category?.systemImage ?? "circle.fill")
                .font(.title3)
                .foregroundStyle(isIncome ? .green : .orange)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(dto.note.isEmpty ? "거래" : dto.note)
                    .lineLimit(1)
                    .font(.body)
                Text(dto.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(isIncome ? "+\(formatAmount(dto.amount))" : "-\(formatAmount(dto.amount))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isIncome ? .green : .primary)
        }
        .padding(.vertical, 4)
    }

    private func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}

// TransactionDTO Identifiable for ForEach
extension TransactionDTO: Identifiable {}

#Preview {
    TransactionListView()
        .environment(AuthService())
}
