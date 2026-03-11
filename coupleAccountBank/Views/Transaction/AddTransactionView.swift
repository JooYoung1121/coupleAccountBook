import SwiftUI
import FirebaseAuth

struct AddTransactionView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    var preselectedDate: Date?

    @State private var amount = ""
    @State private var type: TransactionType = .expense
    @State private var category: TransactionCategory = .food
    @State private var note = ""
    @State private var date = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var effectiveCoupleID: String? {
        authService.currentUser?.effectiveCoupleID
    }

    var body: some View {
        NavigationStack {
            Form {
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

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("거래 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        Task { await save() }
                    }
                    .disabled(amount.isEmpty || isSaving)
                }
            }
            .onAppear {
                if let preselectedDate {
                    date = preselectedDate
                }
            }
        }
    }

    private func save() async {
        guard let amountValue = Double(amount), amountValue > 0 else {
            errorMessage = "올바른 금액을 입력해 주세요."
            return
        }
        guard let uid = Auth.auth().currentUser?.uid,
              let coupleID = effectiveCoupleID else {
            errorMessage = "로그인 상태를 확인해 주세요."
            return
        }

        isSaving = true
        defer { isSaving = false }

        let transaction = Transaction(
            amount: amountValue,
            type: type,
            category: category,
            note: note,
            date: date,
            ownerID: uid,
            ownerName: authService.currentUser?.name ?? "",
            coupleID: coupleID,
            isSynced: true
        )

        do {
            try await FirebaseService.shared.saveTransaction(transaction)
            dismiss()
        } catch {
            errorMessage = "저장 실패: \(error.localizedDescription)"
        }
    }
}

#Preview {
    AddTransactionView()
        .environment(AuthService())
}
