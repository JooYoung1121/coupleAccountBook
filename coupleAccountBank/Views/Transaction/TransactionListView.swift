import SwiftUI
import FirebaseFirestore

// MARK: - Owner Filter

enum OwnerFilter: String, CaseIterable {
    case all = "전체"
    case mine = "나"
    case partner = "파트너"
}

// MARK: - Type Filter

enum TypeFilter: String, CaseIterable {
    case all = "전체"
    case income = "수입"
    case expense = "지출"
}

// MARK: - Sort Option

enum SortOption: String, CaseIterable {
    case dateDesc = "최신순"
    case dateAsc = "오래된순"
    case amountDesc = "금액높은순"
    case amountAsc = "금액낮은순"
}

struct TransactionListView: View {
    @Environment(AuthService.self) private var authService
    @State private var transactions: [TransactionDTO] = []
    @State private var listener: ListenerRegistration?
    @State private var ownerFilter: OwnerFilter = .all
    @State private var typeFilter: TypeFilter = .all
    @State private var showAddSheet = false
    @State private var editingDTO: TransactionDTO?
    @State private var sortOption: SortOption = .dateDesc
    @State private var selectedMonth: Date = Date()
    @State private var showAllMonths = false

    private var effectiveCoupleID: String? {
        authService.currentUser?.effectiveCoupleID
    }
    private var currentUID: String? {
        authService.currentUser?.id
    }

    // MARK: - Filtered Transactions

    private var filteredTransactions: [TransactionDTO] {
        transactions.filter { dto in
            // Owner filter
            switch ownerFilter {
            case .all: break
            case .mine:
                guard dto.ownerID == currentUID else { return false }
            case .partner:
                guard dto.ownerID != currentUID else { return false }
            }
            // Type filter
            switch typeFilter {
            case .all: break
            case .income:
                guard dto.type == TransactionType.income.rawValue else { return false }
            case .expense:
                guard dto.type == TransactionType.expense.rawValue else { return false }
            }
            return true
        }
    }

    // MARK: - Summary (월별 필터링된 데이터 기반)

    private var summaryIncome: Double {
        transactions
            .filter { $0.type == TransactionType.income.rawValue }
            .reduce(0) { $0 + $1.amount }
    }

    private var summaryExpense: Double {
        transactions
            .filter { $0.type == TransactionType.expense.rawValue }
            .reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            Group {
                if effectiveCoupleID != nil {
                    if transactions.isEmpty {
                        emptyView
                    } else {
                        VStack(spacing: 0) {
                            monthNavigation
                            summaryCard
                            filterBar
                            if filteredTransactions.isEmpty {
                                ContentUnavailableView("필터 결과 없음", systemImage: "line.3.horizontal.decrease.circle")
                                    .frame(maxHeight: .infinity)
                            } else {
                                transactionList
                            }
                        }
                    }
                } else {
                    emptyView
                }
            }
            .navigationTitle("내역")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if effectiveCoupleID != nil {
                        HStack(spacing: 16) {
                            Button {
                                showAddSheet = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            NavigationLink {
                                BankLinkView()
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddTransactionView()
            }
            .sheet(item: $editingDTO) { dto in
                EditTransactionView(dto: dto)
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

    // MARK: - Month Navigation

    private var monthNavigation: some View {
        HStack {
            if !showAllMonths {
                Button { moveMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.medium))
                }

                Spacer()

                Text(monthYearString(selectedMonth))
                    .font(.title3.weight(.bold))

                Spacer()

                Button { moveMonth(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.medium))
                }
            } else {
                Text("전체 내역")
                    .font(.title3.weight(.bold))
                Spacer()
            }

            Button {
                showAllMonths.toggle()
                startListening()
            } label: {
                Text(showAllMonths ? "월별" : "전체")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.blue.opacity(0.1), in: Capsule())
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func moveMonth(by value: Int) {
        if let newMonth = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) {
            selectedMonth = newMonth
            startListening()
        }
    }

    private func monthYearString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: date)
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(spacing: 12) {
            Text(showAllMonths ? "전체 요약" : "\(monthYearString(selectedMonth)) 요약")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("수입")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("+\(formatAmount(summaryIncome))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 30)

                VStack(spacing: 4) {
                    Text("지출")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("-\(formatAmount(summaryExpense))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 30)

                VStack(spacing: 4) {
                    let net = summaryIncome - summaryExpense
                    Text("순이익")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(net >= 0 ? "+" : "")\(formatAmount(net))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(net >= 0 ? .blue : .red)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            Picker("소유자", selection: $ownerFilter) {
                ForEach(OwnerFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Picker("유형", selection: $typeFilter) {
                ForEach(TypeFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("정렬")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("정렬", selection: $sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Views

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
            ForEach(sortedDateKeys, id: \.self) { dateKey in
                Section(header: sectionHeader(dateKey)) {
                    ForEach(groupedByDate[dateKey] ?? []) { dto in
                        TransactionRowView(dto: dto)
                            .contentShape(Rectangle())
                            .onTapGesture { editingDTO = dto }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await deleteTransaction(dto) }
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func deleteTransaction(_ dto: TransactionDTO) async {
        guard let coupleID = effectiveCoupleID else { return }
        try? await FirebaseService.shared.deleteTransaction(id: dto.id, coupleID: coupleID)
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
                Text(total >= 0 ? "+\(formatAmount(total))" : "-\(formatAmount(abs(total)))")
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
        for dto in filteredTransactions {
            let key = formatter.string(from: dto.date.dateValue())
            grouped[key, default: []].append(dto)
        }
        for key in grouped.keys {
            switch sortOption {
            case .dateDesc, .dateAsc:
                grouped[key]?.sort { $0.date.dateValue() > $1.date.dateValue() }
            case .amountDesc:
                grouped[key]?.sort { $0.amount > $1.amount }
            case .amountAsc:
                grouped[key]?.sort { $0.amount < $1.amount }
            }
        }
        return grouped
    }

    private var sortedDateKeys: [String] {
        let keys = groupedByDate.keys
        switch sortOption {
        case .dateDesc, .amountDesc, .amountAsc:
            return keys.sorted(by: >)
        case .dateAsc:
            return keys.sorted(by: <)
        }
    }

    private func formatSectionDate(_ yyyyMMdd: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: yyyyMMdd) else { return yyyyMMdd }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "오늘" }
        if cal.isDateInYesterday(date) { return "어제" }
        formatter.locale = Locale(identifier: "ko_KR")
        let isCurrentYear = cal.component(.year, from: date) == cal.component(.year, from: Date())
        formatter.dateFormat = isCurrentYear ? "M월 d일 (EEE)" : "yyyy년 M월 d일 (EEE)"
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

        if showAllMonths {
            listener = FirebaseService.shared.listenToTransactions(coupleID: coupleID) { list in
                transactions = list
            }
        } else {
            let cal = Calendar.current
            let comps = cal.dateComponents([.year, .month], from: selectedMonth)
            guard let startOfMonth = cal.date(from: comps),
                  let endOfMonth = cal.date(byAdding: DateComponents(month: 1, second: -1), to: startOfMonth) else { return }

            listener = FirebaseService.shared.listenToTransactions(
                coupleID: coupleID,
                startDate: startOfMonth,
                endDate: endOfMonth
            ) { list in
                transactions = list
            }
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
                HStack(spacing: 4) {
                    Text(dto.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let name = dto.ownerName, !name.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let memo = dto.userMemo, !memo.isEmpty {
                    Text(memo)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
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
extension TransactionDTO: @retroactive Identifiable {}

#Preview {
    TransactionListView()
        .environment(AuthService())
}
