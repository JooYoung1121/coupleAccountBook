import SwiftUI
import FirebaseFirestore

// MARK: - AddGoalView

struct AddGoalView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    var editing: GoalDTO? = nil

    @State private var title = ""
    @State private var targetAmountStr = ""
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var status: GoalStatus = .inProgress
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isEditing: Bool { editing != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("목표 이름") {
                    TextField("예: 제주도 여행 자금", text: $title)
                }

                Section("목표 금액") {
                    HStack {
                        TextField("금액 입력", text: $targetAmountStr)
                            .keyboardType(.numberPad)
                        Text("원").foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("기한 설정", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker(
                            "목표 기한",
                            selection: $deadline,
                            in: Date()...,
                            displayedComponents: .date
                        )
                    }
                } header: {
                    Text("기한")
                }

                if isEditing {
                    Section("상태") {
                        Picker("상태", selection: $status) {
                            ForEach([GoalStatus.inProgress, .achieved, .cancelled], id: \.self) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(isEditing ? "목표 수정" : "목표 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { Task { await save() } }
                        .disabled(title.isEmpty || targetAmountStr.isEmpty || isSaving)
                }
            }
            .onAppear { prefill() }
        }
    }

    private func prefill() {
        guard let g = editing else { return }
        title = g.title
        targetAmountStr = String(Int(g.targetAmount))
        status = GoalStatus(rawValue: g.status) ?? .inProgress
        if let dl = g.deadline?.dateValue() {
            hasDeadline = true
            deadline = dl
        }
    }

    private func save() async {
        guard let amount = Double(targetAmountStr), amount > 0 else {
            errorMessage = "올바른 금액을 입력해 주세요."
            return
        }
        guard let coupleID = authService.currentUser?.effectiveCoupleID else {
            errorMessage = "로그인 상태를 확인해 주세요."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            if let existing = editing {
                let goal = Goal(
                    id: existing.id,
                    title: title,
                    targetAmount: amount,
                    deadline: hasDeadline ? deadline : nil,
                    coupleID: coupleID,
                    isSynced: true
                )
                goal.currentAmount = existing.currentAmount
                goal.status = status
                goal.createdAt = existing.createdAt.dateValue()
                try await FirebaseService.shared.saveGoal(goal)
            } else {
                let goal = Goal(
                    title: title,
                    targetAmount: amount,
                    deadline: hasDeadline ? deadline : nil,
                    coupleID: coupleID,
                    isSynced: true
                )
                try await FirebaseService.shared.saveGoal(goal)
            }
            dismiss()
        } catch {
            errorMessage = "저장 실패: \(error.localizedDescription)"
        }
    }
}

// MARK: - DepositGoalView

struct DepositGoalView: View {
    @Environment(\.dismiss) private var dismiss
    let goal: GoalDTO

    @State private var amountStr = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var progress: Double {
        guard goal.targetAmount > 0 else { return 0 }
        return min(goal.currentAmount / goal.targetAmount, 1.0)
    }

    private var remaining: Double {
        max(goal.targetAmount - goal.currentAmount, 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(goal.title)
                            .font(.headline)

                        ProgressView(value: progress)
                            .tint(progress >= 1 ? .green : .blue)

                        HStack {
                            Text(formatAmount(goal.currentAmount))
                                .font(.subheadline).foregroundStyle(.blue)
                            Text("/").foregroundStyle(.secondary)
                            Text(formatAmount(goal.targetAmount))
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.0f%%", progress * 100))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(progress >= 1 ? .green : .blue)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("적립 금액") {
                    HStack {
                        TextField("금액 입력", text: $amountStr)
                            .keyboardType(.numberPad)
                        Text("원").foregroundStyle(.secondary)
                    }
                    if remaining > 0 {
                        Button("잔여 금액 전액 입력 (\(formatAmount(remaining)))") {
                            amountStr = String(Int(remaining))
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("적립하기")
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
        }
    }

    private func save() async {
        guard let amount = Double(amountStr), amount > 0 else {
            errorMessage = "올바른 금액을 입력해 주세요."
            return
        }
        isSaving = true
        defer { isSaving = false }

        let newAmount = goal.currentAmount + amount
        do {
            try await FirebaseService.shared.updateGoalAmount(
                id: goal.id, coupleID: goal.coupleID, currentAmount: newAmount
            )
            if newAmount >= goal.targetAmount {
                try await FirebaseService.shared.updateGoalStatus(
                    id: goal.id, coupleID: goal.coupleID, status: .achieved
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return (formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))") + "원"
    }
}
