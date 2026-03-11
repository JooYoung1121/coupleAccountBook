import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct EditTransactionView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    let dto: TransactionDTO

    private var isImported: Bool { dto.isImported ?? false }

    @State private var amount: String
    @State private var type: TransactionType
    @State private var category: TransactionCategory
    @State private var note: String
    @State private var userMemo: String
    @State private var date: Date
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(dto: TransactionDTO) {
        self.dto = dto
        _amount = State(initialValue: String(format: "%.0f", dto.amount))
        _type = State(initialValue: TransactionType(rawValue: dto.type) ?? .expense)
        _category = State(initialValue: TransactionCategory(rawValue: dto.category) ?? .other)
        _note = State(initialValue: dto.note)
        _userMemo = State(initialValue: dto.userMemo ?? "")
        _date = State(initialValue: dto.date.dateValue())
    }

    var body: some View {
        NavigationStack {
            Form {
                if isImported {
                    importedInfoSection
                } else {
                    editableFormSections
                }

                Section("내 메모") {
                    TextField("메모를 남겨보세요", text: $userMemo, axis: .vertical)
                        .lineLimit(1...5)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(isImported ? "거래 상세" : "거래 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    // MARK: - Imported: 읽기 전용 정보 표시

    private var importedInfoSection: some View {
        Group {
            Section("거래 정보") {
                LabeledContent("금액", value: "\(type == .income ? "+" : "-")\(amount)원")
                LabeledContent("유형", value: type.rawValue)
                LabeledContent("카테고리", value: category.rawValue)
                LabeledContent("날짜", value: formatDate(date))
            }

            if !note.isEmpty {
                Section("원본 메모") {
                    Text(note)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Manual: 전체 편집 가능

    private var editableFormSections: some View {
        Group {
            Section("금액") {
                TextField("금액을 입력하세요", text: $amount)
                    .keyboardType(.numberPad)
            }

            Section("유형") {
                Picker("유형", selection: $type) {
                    Text("지출").tag(TransactionType.expense)
                    Text("수입").tag(TransactionType.income)
                }
                .pickerStyle(.segmented)
            }

            Section("카테고리") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                    ForEach(TransactionCategory.allCases, id: \.self) { cat in
                        Button {
                            category = cat
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: cat.systemImage)
                                    .font(.title3)
                                Text(cat.rawValue)
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(category == cat ? Color.accentColor.opacity(0.15) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(category == cat ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("메모") {
                TextField("메모 (선택)", text: $note)
            }

            Section("날짜") {
                DatePicker("날짜", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
            }
        }
    }

    // MARK: - Save

    private func save() async {
        let amountValue: Double
        if isImported {
            amountValue = dto.amount
        } else {
            guard let parsed = Double(amount), parsed > 0 else {
                errorMessage = "올바른 금액을 입력해 주세요."
                return
            }
            amountValue = parsed
        }

        isSaving = true
        defer { isSaving = false }

        let transaction = Transaction(
            id: dto.id,
            amount: isImported ? dto.amount : amountValue,
            type: isImported ? (TransactionType(rawValue: dto.type) ?? .expense) : type,
            category: isImported ? (TransactionCategory(rawValue: dto.category) ?? .other) : category,
            note: isImported ? dto.note : note,
            date: isImported ? dto.date.dateValue() : date,
            ownerID: dto.ownerID,
            ownerName: dto.ownerName ?? "",
            coupleID: dto.coupleID,
            isSynced: true,
            isImported: isImported,
            userMemo: userMemo
        )

        do {
            try await FirebaseService.shared.saveTransaction(transaction)
            dismiss()
        } catch {
            errorMessage = "수정 실패: \(error.localizedDescription)"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 (EEE)"
        return formatter.string(from: date)
    }
}
