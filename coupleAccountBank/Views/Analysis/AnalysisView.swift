import SwiftUI
import FirebaseFirestore

// MARK: - AnalysisView (Container)

struct AnalysisView: View {
    @State private var selectedTab: AnalysisTab = .spending

    enum AnalysisTab: String, CaseIterable {
        case spending = "지출 분석"
        case tax      = "연말정산"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("분석 유형", selection: $selectedTab) {
                    ForEach(AnalysisTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedTab == .spending {
                    SpendingAnalysisView()
                } else {
                    TaxSimulatorView()
                }
            }
            .navigationTitle("분석")
        }
    }
}

// MARK: - SpendingAnalysisView

struct SpendingAnalysisView: View {
    @Environment(AuthService.self) private var authService
    @State private var transactions: [TransactionDTO] = []
    @State private var listener: ListenerRegistration?
    @State private var selectedYear = Calendar.current.component(.year, from: Date())

    private var effectiveCoupleID: String? { authService.currentUser?.effectiveCoupleID }

    private var totalExpense: Double {
        transactions.filter { $0.type == TransactionType.expense.rawValue }.reduce(0) { $0 + $1.amount }
    }

    private var totalIncome: Double {
        transactions.filter { $0.type == TransactionType.income.rawValue }.reduce(0) { $0 + $1.amount }
    }

    private var categoryExpenses: [(TransactionCategory, Double)] {
        var result: [String: Double] = [:]
        for dto in transactions where dto.type == TransactionType.expense.rawValue {
            result[dto.category, default: 0] += dto.amount
        }
        return TransactionCategory.allCases.compactMap { cat in
            let amt = result[cat.rawValue] ?? 0
            return amt > 0 ? (cat, amt) : nil
        }.sorted { $0.1 > $1.1 }
    }

    // 월별 지출 (1~12)
    private var monthlyExpenses: [Double] {
        (1...12).map { month in
            transactions.filter { dto in
                guard dto.type == TransactionType.expense.rawValue else { return false }
                let d = dto.date.dateValue()
                return Calendar.current.component(.month, from: d) == month
            }.reduce(0) { $0 + $1.amount }
        }
    }

    private var peakMonth: Int? {
        guard let max = monthlyExpenses.max(), max > 0 else { return nil }
        return monthlyExpenses.firstIndex(of: max).map { $0 + 1 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                yearSelector
                summaryCard
                monthlyChart
                categoryCard
            }
            .padding()
        }
        .onAppear { startListening() }
        .onDisappear { listener?.remove(); listener = nil }
    }

    // MARK: - Year Selector

    private var yearSelector: some View {
        HStack(spacing: 8) {
            ForEach([selectedYear - 1, selectedYear], id: \.self) { year in
                Button {
                    selectedYear = year
                    startListening()
                } label: {
                    Text("\(year)년")
                        .font(.subheadline.weight(selectedYear == year ? .bold : .regular))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(selectedYear == year ? Color.blue : Color.gray.opacity(0.12),
                                    in: Capsule())
                        .foregroundStyle(selectedYear == year ? .white : .secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        let net = totalIncome - totalExpense
        return VStack(spacing: 12) {
            Text("\(selectedYear)년 합계")
                .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 0) {
                summaryItem(title: "수입", value: "+\(fmt(totalIncome))", color: .green)
                Divider().frame(height: 30)
                summaryItem(title: "지출", value: "-\(fmt(totalExpense))", color: .red)
                Divider().frame(height: 30)
                summaryItem(title: "순이익", value: "\(net >= 0 ? "+" : "")\(fmt(net))",
                            color: net >= 0 ? .blue : .red)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func summaryItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Monthly Bar Chart

    private var monthlyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("월별 지출")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            let maxVal = monthlyExpenses.max() ?? 1

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<12, id: \.self) { i in
                    let val = monthlyExpenses[i]
                    let ratio = maxVal > 0 ? val / maxVal : 0
                    let isPeak = (i + 1) == peakMonth

                    VStack(spacing: 4) {
                        if val > 0 {
                            Text(shortFmt(val))
                                .font(.system(size: 7))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isPeak ? Color.red.opacity(0.7) : Color.blue.opacity(0.5))
                            .frame(height: max(CGFloat(ratio) * 80, val > 0 ? 4 : 0))
                        Text("\(i + 1)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 110, alignment: .bottom)

            if let peak = peakMonth {
                Text("가장 많이 쓴 달: \(peak)월 (\(fmt(monthlyExpenses[peak - 1]))원)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Category Card

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("카테고리별 지출")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            if categoryExpenses.isEmpty {
                Text("지출 내역이 없습니다")
                    .font(.subheadline).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 20)
            } else {
                ForEach(categoryExpenses, id: \.0) { cat, amount in
                    CategoryBarRow(category: cat, amount: amount, total: totalExpense)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func startListening() {
        listener?.remove()
        guard let coupleID = effectiveCoupleID else { return }
        let cal = Calendar.current
        var s = DateComponents(); s.year = selectedYear; s.month = 1; s.day = 1
        var e = DateComponents(); e.year = selectedYear; e.month = 12; e.day = 31
        e.hour = 23; e.minute = 59; e.second = 59
        guard let startDate = cal.date(from: s), let endDate = cal.date(from: e) else { return }
        listener = FirebaseService.shared.listenToTransactions(coupleID: coupleID,
                                                               startDate: startDate,
                                                               endDate: endDate) { list in
            transactions = list
        }
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return (f.string(from: NSNumber(value: abs(v))) ?? "\(Int(abs(v)))") + "원"
    }

    private func shortFmt(_ v: Double) -> String {
        v >= 10_000_000 ? String(format: "%.0f만", v / 10000)
            : v >= 10000 ? String(format: "%.0f만", v / 10000)
            : "\(Int(v))"
    }
}

// MARK: - CategoryBarRow

struct CategoryBarRow: View {
    let category: TransactionCategory
    let amount: Double
    let total: Double

    private var ratio: Double { total > 0 ? min(amount / total, 1) : 0 }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: category.systemImage).font(.caption).foregroundStyle(.blue).frame(width: 16)
                Text(category.rawValue).font(.subheadline)
                Spacer()
                Text(amountStr).font(.subheadline.weight(.medium))
                Text(String(format: "(%.0f%%)", ratio * 100)).font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.12)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 4).fill(Color.blue.opacity(0.65))
                        .frame(width: geo.size.width * ratio, height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private var amountStr: String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return (f.string(from: NSNumber(value: amount)) ?? "\(Int(amount))") + "원"
    }
}

// MARK: - TaxSimulatorView

struct TaxSimulatorView: View {
    @Environment(AuthService.self) private var authService
    @State private var transactions: [TransactionDTO] = []
    @State private var listener: ListenerRegistration?
    @State private var annualSalaryStr = ""
    @State private var creditCardRatio: Double = 0.6
    @State private var selectedYear = Calendar.current.component(.year, from: Date())

    private var effectiveCoupleID: String? { authService.currentUser?.effectiveCoupleID }

    // 만원 단위 입력 → 원 단위
    private var annualSalary: Double { (Double(annualSalaryStr) ?? 0) * 10000 }

    private var totalExpense: Double {
        transactions.filter { $0.type == TransactionType.expense.rawValue }.reduce(0) { $0 + $1.amount }
    }

    private var transitExpense: Double {
        transactions.filter {
            $0.type == TransactionType.expense.rawValue &&
            $0.category == TransactionCategory.transport.rawValue
        }.reduce(0) { $0 + $1.amount }
    }

    // 공제 기준선: 총급여 × 25%
    private var threshold: Double { annualSalary * 0.25 }
    private var deductibleBase: Double { max(totalExpense - threshold, 0) }

    private var creditSpend: Double { deductibleBase * creditCardRatio }
    private var debitSpend: Double { deductibleBase * (1 - creditCardRatio) }

    private var creditDeduction: Double { creditSpend * 0.15 }
    private var debitDeduction: Double { debitSpend * 0.30 }
    private var transitDeduction: Double { min(transitExpense, 2_000_000) * 0.40 }

    private var maxLimit: Double {
        annualSalary <= 70_000_000 ? 3_000_000 : annualSalary <= 120_000_000 ? 2_500_000 : 2_000_000
    }

    private var totalDeduction: Double { min(creditDeduction + debitDeduction + transitDeduction, maxLimit) }
    private var estimatedTaxSaving: Double { totalDeduction * 0.15 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                inputSection
                if annualSalary > 0 {
                    resultSection
                    recommendationSection
                }
            }
            .padding()
        }
        .onAppear { startListening() }
        .onDisappear { listener?.remove(); listener = nil }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("기본 정보 입력").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            // 연도 선택
            HStack(spacing: 8) {
                ForEach([selectedYear - 1, selectedYear], id: \.self) { year in
                    Button {
                        selectedYear = year; startListening()
                    } label: {
                        Text("\(year)년").font(.subheadline)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(selectedYear == year ? Color.blue : Color.gray.opacity(0.12), in: Capsule())
                            .foregroundStyle(selectedYear == year ? .white : .primary)
                    }
                }
                Spacer()
            }

            // 총급여
            VStack(alignment: .leading, spacing: 6) {
                Text("총급여 (연봉)").font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("예: 4500", text: $annualSalaryStr).keyboardType(.numberPad)
                    Text("만원").foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }

            // 신용카드 비율
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("신용카드 비율").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "신용 %.0f%% / 체크 %.0f%%",
                                creditCardRatio * 100, (1 - creditCardRatio) * 100))
                        .font(.caption.weight(.medium)).foregroundStyle(.blue)
                }
                Slider(value: $creditCardRatio, in: 0...1, step: 0.05).tint(.blue)
                Text("카드 결제 중 신용카드(후불) 비율을 설정하세요")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            // 조회된 총 지출
            HStack {
                Text("\(selectedYear)년 총 지출").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(fmt(totalExpense) + "원").font(.subheadline.weight(.semibold))
            }
            .padding(12)
            .background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Result Section

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("소득공제 계산").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            deductionRow(label: "공제 기준선 (총급여 25%)", value: threshold, color: .secondary)

            Divider()

            if deductibleBase > 0 {
                deductionRow(label: "신용카드 공제 (15%)", value: creditDeduction, color: .orange)
                deductionRow(label: "체크카드/현금 공제 (30%)", value: debitDeduction, color: .blue)
                if transitExpense > 0 {
                    deductionRow(label: "대중교통 공제 (40%)", value: transitDeduction, color: .green)
                }

                Divider()

                HStack {
                    Text("예상 소득공제").font(.body.weight(.semibold))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(fmt(totalDeduction) + "원")
                            .font(.title3.weight(.bold)).foregroundStyle(.blue)
                        if totalDeduction >= maxLimit {
                            Text("한도 \(fmt(maxLimit))원 도달")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                    }
                }

                HStack {
                    Text("예상 절세액 (소득세율 15%)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("약 " + fmt(estimatedTaxSaving) + "원")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                }

            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("아직 공제 기준선(\(fmt(threshold))원)에 도달하지 않았습니다.")
                        .font(.subheadline).foregroundStyle(.orange)
                    Text("앞으로 \(fmt(max(threshold - totalExpense, 0)))원 더 사용해야 공제가 시작됩니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func deductionRow(label: String, value: Double, color: Color) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(fmt(value) + "원").font(.subheadline.weight(.semibold)).foregroundStyle(color)
        }
    }

    // MARK: - Recommendation Section

    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("절세 조언").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(recommendations.enumerated()), id: \.offset) { _, advice in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption).foregroundStyle(.yellow).padding(.top, 2)
                        Text(advice).font(.subheadline)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var recommendations: [String] {
        var list: [String] = []

        if deductibleBase <= 0 {
            let rem = max(threshold - totalExpense, 0)
            list.append("총급여의 25%(\(fmt(threshold))원)를 초과해야 공제가 시작됩니다. \(fmt(rem))원 더 사용이 필요합니다.")
        } else {
            if creditCardRatio > 0.5 {
                let diff = deductibleBase * creditCardRatio * 0.15
                let potential = deductibleBase * creditCardRatio * 0.30
                list.append("신용카드 대신 체크카드를 사용하면 최대 \(fmt(potential - diff))원 더 공제받을 수 있습니다.")
            }
            if transitExpense < 500_000 {
                list.append("교통카드(대중교통)는 40% 공제됩니다. 카드 결제 시 자동으로 반영됩니다.")
            }
            if totalDeduction >= maxLimit {
                list.append("소득공제 한도(\(fmt(maxLimit))원)에 이미 도달했습니다. 추가 지출로 공제를 더 늘리기 어렵습니다.")
            } else {
                list.append("한도까지 \(fmt(maxLimit - totalDeduction))원 더 공제받을 수 있습니다. 체크카드 위주로 사용하세요.")
            }
        }
        list.append("현금 결제 시 앱에 직접 등록하면 체크카드(30%) 공제율로 계산됩니다.")
        return list
    }

    // MARK: - Helpers

    private func startListening() {
        listener?.remove()
        guard let coupleID = effectiveCoupleID else { return }
        let cal = Calendar.current
        var s = DateComponents(); s.year = selectedYear; s.month = 1; s.day = 1
        var e = DateComponents(); e.year = selectedYear; e.month = 12; e.day = 31
        e.hour = 23; e.minute = 59; e.second = 59
        guard let sd = cal.date(from: s), let ed = cal.date(from: e) else { return }
        listener = FirebaseService.shared.listenToTransactions(coupleID: coupleID,
                                                               startDate: sd, endDate: ed) { list in
            transactions = list
        }
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: abs(v))) ?? "\(Int(abs(v)))"
    }
}

#Preview {
    AnalysisView()
        .environment(AuthService())
}
