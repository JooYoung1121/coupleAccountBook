import SwiftUI
import FirebaseFirestore

// MARK: - TransactionCategory Identifiable (for sheet(item:))
extension TransactionCategory: @retroactive Identifiable {
    public var id: String { rawValue }
}

// MARK: - BudgetView

struct BudgetView: View {
    @Environment(AuthService.self) private var authService
    @State private var budgets: [Budget] = []
    @State private var transactions: [TransactionDTO] = []
    @State private var budgetListener: ListenerRegistration?
    @State private var transactionListener: ListenerRegistration?
    @State private var selectedMonth = Date()
    @State private var editingCategory: TransactionCategory?

    private var effectiveCoupleID: String? {
        authService.currentUser?.effectiveCoupleID
    }

    private var monthKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: selectedMonth)
    }

    /// category.rawValue → Budget for this month
    private var monthBudgets: [String: Budget] {
        Dictionary(uniqueKeysWithValues:
            budgets
                .filter { $0.month == monthKey }
                .map { ($0.category, $0) }
        )
    }

    /// category.rawValue → 이번 달 실제 지출액
    private var actualByCategory: [String: Double] {
        var result: [String: Double] = [:]
        for dto in transactions where dto.type == TransactionType.expense.rawValue {
            result[dto.category, default: 0] += dto.amount
        }
        return result
    }

    private var totalBudget: Double { monthBudgets.values.reduce(0) { $0 + $1.budgetAmount } }
    private var totalActual: Double { actualByCategory.values.reduce(0, +) }

    private let budgetCategories: [TransactionCategory] = [
        .food, .transport, .housing, .shopping, .entertainment, .health, .education, .other
    ]

    var body: some View {
        NavigationStack {
            Group {
                if effectiveCoupleID == nil {
                    ContentUnavailableView("로그인이 필요합니다", systemImage: "person.circle")
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            monthNavigation
                            summaryCard
                            categorySection
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("예산 관리")
            .sheet(item: $editingCategory) { category in
                BudgetEditSheet(
                    category: category,
                    month: monthKey,
                    existing: monthBudgets[category.rawValue],
                    coupleID: effectiveCoupleID ?? ""
                )
            }
            .onAppear { startListeners() }
            .onDisappear {
                budgetListener?.remove()
                budgetListener = nil
                transactionListener?.remove()
                transactionListener = nil
            }
        }
    }

    // MARK: - Month Navigation

    private var monthNavigation: some View {
        HStack {
            Button { moveMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.medium))
            }
            Spacer()
            Text(monthDisplayString(selectedMonth))
                .font(.title3.weight(.bold))
            Spacer()
            Button { moveMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.medium))
            }
        }
        .padding(.horizontal, 4)
    }

    private func moveMonth(by value: Int) {
        guard let newMonth = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) else { return }
        selectedMonth = newMonth
        startTransactionListener()
    }

    private func monthDisplayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월"
        return f.string(from: date)
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        let remaining = totalBudget - totalActual
        let isOver = remaining < 0

        return VStack(spacing: 12) {
            Text("\(monthDisplayString(selectedMonth)) 예산 현황")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("설정 예산").font(.caption).foregroundStyle(.secondary)
                    Text(totalBudget == 0 ? "미설정" : formatAmount(totalBudget))
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 30)

                VStack(spacing: 4) {
                    Text("실제 지출").font(.caption).foregroundStyle(.secondary)
                    Text(formatAmount(totalActual))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOver ? .red : .primary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 30)

                VStack(spacing: 4) {
                    Text(isOver ? "초과" : "잔여").font(.caption).foregroundStyle(.secondary)
                    Text(formatAmount(abs(remaining)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOver ? .red : .green)
                }
                .frame(maxWidth: .infinity)
            }

            if totalBudget > 0 {
                let ratio = min(totalActual / totalBudget, 1.0)
                VStack(spacing: 4) {
                    ProgressView(value: ratio)
                        .tint(ratio >= 1 ? .red : ratio >= 0.8 ? .orange : .blue)
                    Text(String(format: "%.0f%% 사용", ratio * 100))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Category Section

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("카테고리별 예산")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("탭하여 편집")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 0) {
                ForEach(budgetCategories) { category in
                    BudgetCategoryRow(
                        category: category,
                        budget: monthBudgets[category.rawValue],
                        actual: actualByCategory[category.rawValue] ?? 0
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { editingCategory = category }

                    if category != budgetCategories.last {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Listeners

    private func startListeners() {
        startBudgetListener()
        startTransactionListener()
    }

    private func startBudgetListener() {
        budgetListener?.remove()
        guard let coupleID = effectiveCoupleID else { return }
        budgetListener = FirebaseService.shared.listenToBudgets(coupleID: coupleID) { list in
            budgets = list
        }
    }

    private func startTransactionListener() {
        transactionListener?.remove()
        guard let coupleID = effectiveCoupleID else { return }
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: selectedMonth)
        guard let start = cal.date(from: comps),
              let end = cal.date(byAdding: DateComponents(month: 1, second: -1), to: start) else { return }

        transactionListener = FirebaseService.shared.listenToTransactions(
            coupleID: coupleID,
            startDate: start,
            endDate: end
        ) { list in
            transactions = list
        }
    }

    private func formatAmount(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return (f.string(from: NSNumber(value: value)) ?? "\(Int(value))") + "원"
    }
}

// MARK: - BudgetCategoryRow

struct BudgetCategoryRow: View {
    let category: TransactionCategory
    let budget: Budget?
    let actual: Double

    private var budgetAmount: Double { budget?.budgetAmount ?? 0 }
    private var hasBudget: Bool { budgetAmount > 0 }
    private var progress: Double {
        guard hasBudget else { return 0 }
        return min(actual / budgetAmount, 1.0)
    }
    private var isOver: Bool { hasBudget && actual > budgetAmount }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.systemImage)
                .font(.title3)
                .foregroundStyle(isOver ? .red : .blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(category.rawValue)
                        .font(.body)
                    Spacer()
                    if hasBudget {
                        Text(formatAmount(actual))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isOver ? .red : .primary)
                        Text("/ \(formatAmount(budgetAmount))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(actual > 0 ? formatAmount(actual) : "예산 미설정")
                            .font(.subheadline)
                            .foregroundStyle(actual > 0 ? .secondary : .tertiary)
                    }
                }

                if hasBudget {
                    ProgressView(value: progress)
                        .tint(isOver ? .red : progress >= 0.8 ? .orange : .blue)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func formatAmount(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return (f.string(from: NSNumber(value: value)) ?? "\(Int(value))") + "원"
    }
}

// MARK: - BudgetEditSheet

struct BudgetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let category: TransactionCategory
    let month: String
    let existing: Budget?
    let coupleID: String

    @State private var amountStr = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: category.systemImage)
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 36)
                        Text(category.rawValue)
                            .font(.headline)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    HStack {
                        TextField("금액 입력", text: $amountStr)
                            .keyboardType(.numberPad)
                        Text("원").foregroundStyle(.secondary)
                    }
                    if existing != nil {
                        Text("0 입력 시 이 카테고리의 예산이 삭제됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("월 예산 금액")
                } footer: {
                    Text("설정한 금액을 초과하면 빨간색으로 표시됩니다.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("\(category.rawValue) 예산 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { Task { await save() } }
                        .disabled(amountStr.isEmpty || isSaving)
                }
            }
            .onAppear {
                if let b = existing {
                    amountStr = String(Int(b.budgetAmount))
                }
            }
        }
    }

    private func save() async {
        guard let amount = Double(amountStr) else {
            errorMessage = "올바른 금액을 입력해 주세요."
            return
        }
        isSaving = true
        defer { isSaving = false }

        do {
            if amount == 0, let existing {
                try await FirebaseService.shared.deleteBudget(id: existing.id, coupleID: coupleID)
            } else if amount > 0 {
                let budget = Budget(
                    id: existing?.id ?? UUID().uuidString,
                    month: month,
                    category: category.rawValue,
                    budgetAmount: amount,
                    coupleID: coupleID
                )
                try await FirebaseService.shared.saveBudget(budget)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    BudgetView()
        .environment(AuthService())
}
