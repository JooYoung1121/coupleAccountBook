import SwiftUI
import FirebaseFirestore

struct HomeView: View {
    @Environment(AuthService.self) private var authService
    @State private var transactions: [TransactionDTO] = []
    @State private var listener: ListenerRegistration?
    @State private var displayedMonth: Date = Date()
    @State private var selectedDate: Date? = nil
    @State private var showAddSheet = false

    private var effectiveCoupleID: String? {
        authService.currentUser?.effectiveCoupleID
    }

    private let calendar = Calendar.current
    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    monthNavigation
                    calendarGrid
                    monthlySummary
                    if let selected = selectedDate {
                        selectedDateTransactions(for: selected)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("홈")
            .sheet(isPresented: $showAddSheet) {
                AddTransactionView(preselectedDate: selectedDate)
            }
            .onAppear { startListening() }
            .onDisappear {
                listener?.remove()
                listener = nil
            }
        }
    }

    // MARK: - Month Navigation

    private var monthNavigation: some View {
        HStack {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.medium))
            }

            Spacer()

            Text(monthYearString(displayedMonth))
                .font(.title3.weight(.bold))

            Spacer()

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.medium))
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        let days = daysInMonth()

        return VStack(spacing: 2) {
            // Weekday header
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(day == "일" ? .red : day == "토" ? .blue : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)

            // Date cells
            let rows = days.chunked(into: 7)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day = day {
                            dayCellView(day)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func dayCellView(_ date: Date) -> some View {
        let income = dailyIncome(for: date)
        let expense = dailyExpense(for: date)
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let isToday = calendar.isDateInToday(date)

        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.caption.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? .white : .primary)
                    .frame(width: 22, height: 22)
                    .background {
                        if isToday {
                            Circle().fill(.blue)
                        }
                    }

                if income > 0 {
                    Text(shortAmount(income))
                        .font(.system(size: 8))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }
                if expense > 0 {
                    Text(shortAmount(expense))
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
                if income == 0 && expense == 0 {
                    Spacer().frame(height: 14)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.blue.opacity(0.1))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Monthly Summary

    private var monthlySummary: some View {
        let monthTxs = transactionsForMonth(displayedMonth)
        let income = monthTxs
            .filter { $0.type == TransactionType.income.rawValue }
            .reduce(0.0) { $0 + $1.amount }
        let expense = monthTxs
            .filter { $0.type == TransactionType.expense.rawValue }
            .reduce(0.0) { $0 + $1.amount }
        let net = income - expense

        return VStack(spacing: 12) {
            Text("월 합계")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("수입")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("+\(formatAmount(income))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 30)

                VStack(spacing: 4) {
                    Text("지출")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("-\(formatAmount(expense))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 30)

                VStack(spacing: 4) {
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
    }

    // MARK: - Selected Date Transactions

    private func selectedDateTransactions(for date: Date) -> some View {
        let dayTxs = transactionsForDay(date)
        let dateStr = formatDateKorean(date)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(dateStr) 거래 내역")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
            .padding(.horizontal, 4)

            if dayTxs.isEmpty {
                Text("거래 내역이 없어요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                List {
                    ForEach(dayTxs) { dto in
                        TransactionRowView(dto: dto)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await deleteTransaction(dto) }
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: CGFloat(dayTxs.count) * 60)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func deleteTransaction(_ dto: TransactionDTO) async {
        guard let coupleID = effectiveCoupleID else { return }
        try? await FirebaseService.shared.deleteTransaction(id: dto.id, coupleID: coupleID)
    }

    // MARK: - Data Helpers

    private func transactionsForMonth(_ month: Date) -> [TransactionDTO] {
        transactions.filter { calendar.isDate($0.date.dateValue(), equalTo: month, toGranularity: .month) }
    }

    private func transactionsForDay(_ day: Date) -> [TransactionDTO] {
        transactions.filter { calendar.isDate($0.date.dateValue(), inSameDayAs: day) }
    }

    private func dailyIncome(for date: Date) -> Double {
        transactionsForDay(date)
            .filter { $0.type == TransactionType.income.rawValue }
            .reduce(0) { $0 + $1.amount }
    }

    private func dailyExpense(for date: Date) -> Double {
        transactionsForDay(date)
            .filter { $0.type == TransactionType.expense.rawValue }
            .reduce(0) { $0 + $1.amount }
    }

    // MARK: - Calendar Helpers

    private func daysInMonth() -> [Date?] {
        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let firstDay = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: firstDay) else { return [] }

        let weekdayOfFirst = calendar.component(.weekday, from: firstDay) - 1 // 0-based Sunday

        var days: [Date?] = Array(repeating: nil, count: weekdayOfFirst)

        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(date)
            }
        }

        // Pad to fill last row
        while days.count % 7 != 0 {
            days.append(nil)
        }

        return days
    }

    private func moveMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = newMonth
            selectedDate = nil
        }
    }

    // MARK: - Formatting

    private func monthYearString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: date)
    }

    private func formatDateKorean(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (EEE)"
        return formatter.string(from: date)
    }

    private func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: abs(value))) ?? "\(Int(abs(value)))"
    }

    private func shortAmount(_ value: Double) -> String {
        if value >= 10000 {
            let man = value / 10000
            return String(format: "%.0f만", man)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    // MARK: - Listener

    private func startListening() {
        listener?.remove()
        guard let coupleID = effectiveCoupleID else { return }
        listener = FirebaseService.shared.listenToTransactions(coupleID: coupleID) { list in
            transactions = list
        }
    }
}

// MARK: - Array Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

#Preview {
    HomeView()
        .environment(AuthService())
}
