import SwiftUI
import FirebaseFirestore

// MARK: - GoalDTO Identifiable
extension GoalDTO: @retroactive Identifiable {}

// MARK: - GoalListView

struct GoalListView: View {
    @Environment(AuthService.self) private var authService
    @State private var goals: [GoalDTO] = []
    @State private var listener: ListenerRegistration?
    @State private var showAddSheet = false
    @State private var editingGoal: GoalDTO?
    @State private var depositingGoal: GoalDTO?
    @State private var statusFilter: GoalStatus = .inProgress

    private var effectiveCoupleID: String? {
        authService.currentUser?.effectiveCoupleID
    }

    private var filteredGoals: [GoalDTO] {
        goals.filter { $0.status == statusFilter.rawValue }
    }

    private var totalTarget: Double { filteredGoals.reduce(0) { $0 + $1.targetAmount } }
    private var totalCurrent: Double { filteredGoals.reduce(0) { $0 + $1.currentAmount } }

    var body: some View {
        NavigationStack {
            Group {
                if effectiveCoupleID == nil {
                    ContentUnavailableView("로그인이 필요합니다", systemImage: "person.circle")
                } else if goals.isEmpty {
                    emptyFirstView
                } else {
                    VStack(spacing: 0) {
                        statusPicker
                        if !filteredGoals.isEmpty {
                            summaryBar
                        }
                        if filteredGoals.isEmpty {
                            ContentUnavailableView {
                                Label(emptyLabel, systemImage: "target")
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            goalList
                        }
                    }
                }
            }
            .navigationTitle("저축 목표")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if effectiveCoupleID != nil {
                        Button { showAddSheet = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddGoalView()
            }
            .sheet(item: $editingGoal) { goal in
                AddGoalView(editing: goal)
            }
            .sheet(item: $depositingGoal) { goal in
                DepositGoalView(goal: goal)
            }
            .onAppear { startListening() }
            .onDisappear {
                listener?.remove()
                listener = nil
            }
        }
    }

    // MARK: - Sub Views

    private var emptyFirstView: some View {
        ContentUnavailableView {
            Label("목표 없음", systemImage: "target")
        } description: {
            Text("+ 버튼을 눌러 첫 저축 목표를 만들어보세요.")
        } actions: {
            Button("목표 추가") { showAddSheet = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyLabel: String {
        switch statusFilter {
        case .inProgress: return "진행 중인 목표 없음"
        case .achieved:   return "달성한 목표 없음"
        case .cancelled:  return "취소된 목표 없음"
        }
    }

    private var statusPicker: some View {
        Picker("상태", selection: $statusFilter) {
            ForEach([GoalStatus.inProgress, .achieved, .cancelled], id: \.self) { s in
                Text(s.rawValue).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var summaryBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("총 목표").font(.caption).foregroundStyle(.secondary)
                Text(formatAmount(totalTarget)).font(.subheadline.weight(.semibold))
            }
            Spacer()
            VStack(alignment: .center, spacing: 2) {
                Text("적립").font(.caption).foregroundStyle(.secondary)
                Text(formatAmount(totalCurrent))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("잔여").font(.caption).foregroundStyle(.secondary)
                Text(formatAmount(max(totalTarget - totalCurrent, 0)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var goalList: some View {
        List {
            ForEach(filteredGoals) { goal in
                GoalRowView(goal: goal)
                    .contentShape(Rectangle())
                    .onTapGesture { editingGoal = goal }
                    .swipeActions(edge: .leading) {
                        if goal.status == GoalStatus.inProgress.rawValue {
                            Button { depositingGoal = goal } label: {
                                Label("적립", systemImage: "plus.circle.fill")
                            }
                            .tint(.blue)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await deleteGoal(goal) }
                        } label: {
                            Label("삭제", systemImage: "trash")
                        }
                        if goal.status == GoalStatus.inProgress.rawValue {
                            Button {
                                Task { await updateStatus(goal, to: .achieved) }
                            } label: {
                                Label("달성", systemImage: "checkmark.circle.fill")
                            }
                            .tint(.green)
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Actions

    private func deleteGoal(_ goal: GoalDTO) async {
        guard let coupleID = effectiveCoupleID else { return }
        try? await FirebaseService.shared.deleteGoal(id: goal.id, coupleID: coupleID)
    }

    private func updateStatus(_ goal: GoalDTO, to status: GoalStatus) async {
        guard let coupleID = effectiveCoupleID else { return }
        try? await FirebaseService.shared.updateGoalStatus(id: goal.id, coupleID: coupleID, status: status)
    }

    private func startListening() {
        listener?.remove()
        guard let coupleID = effectiveCoupleID else { return }
        listener = FirebaseService.shared.listenToGoals(coupleID: coupleID) { list in
            goals = list
        }
    }

    private func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return (formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))") + "원"
    }
}

// MARK: - GoalRowView

struct GoalRowView: View {
    let goal: GoalDTO

    private var progress: Double {
        guard goal.targetAmount > 0 else { return 0 }
        return min(goal.currentAmount / goal.targetAmount, 1.0)
    }

    private var daysLeft: Int? {
        guard let deadline = goal.deadline?.dateValue() else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: deadline).day
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(goal.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer()
                statusBadge
            }

            ProgressView(value: progress)
                .tint(progressColor)

            HStack {
                Text("\(formatAmount(goal.currentAmount)) / \(formatAmount(goal.targetAmount))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let days = daysLeft {
                    Group {
                        if days >= 0 {
                            Text("D-\(days)")
                                .foregroundStyle(days <= 7 ? .red : .secondary)
                        } else {
                            Text("D+\(abs(days))")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.caption.weight(.medium))
                    Text("·").font(.caption).foregroundStyle(.tertiary)
                }
                Text(String(format: "%.0f%%", progress * 100))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(progressColor)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        let status = GoalStatus(rawValue: goal.status) ?? .inProgress
        let (label, color): (String, Color) = switch status {
        case .inProgress: ("진행중", .blue)
        case .achieved:   ("달성", .green)
        case .cancelled:  ("취소", .gray)
        }
        return Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var progressColor: Color {
        if progress >= 1.0 { return .green }
        if progress >= 0.7 { return .blue }
        return .orange
    }

    private func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return (formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))") + "원"
    }
}

#Preview {
    GoalListView()
        .environment(AuthService())
}
