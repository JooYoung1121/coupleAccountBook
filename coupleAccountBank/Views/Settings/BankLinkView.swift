import SwiftUI
import FirebaseAuth

/// 은행 연동 및 입출금 내역 가져오기 화면
struct BankLinkView: View {
    @Environment(AuthService.self) private var authService

    // 계정 연결 (샌드박스 기본값)
    @State private var createOrg = "0020"
    @State private var createBizType = "BK"
    @State private var createId = "testuser01"
    @State private var createPassword = "test1234"

    // 내역 가져오기 (샌드박스 기본값)
    @State private var organization = "0020"
    @State private var account = "1002440000000"
    @State private var startDate = ""
    @State private var endDate = ""
    @State private var accountPassword = ""
    @State private var birthDate = ""

    @State private var isLoading = false
    @State private var message = "은행 계정을 연결한 뒤, 조회 기간을 선택하고 내역을 가져오세요."
    @State private var messageType: MessageType = .info

    private var connectedId: String {
        authService.currentUser?.connectedId ?? ""
    }

    private var effectiveCoupleID: String? {
        authService.currentUser?.effectiveCoupleID
    }

    let bankCodes: [(String, String)] = [
        ("0020", "우리은행"),
        ("0004", "국민은행"),
        ("0088", "신한은행"),
        ("0081", "하나은행"),
        ("0011", "농협"),
    ]

    enum MessageType {
        case info
        case success
        case error
    }

    var body: some View {
        List {
            // 상태 요약
            Section {
                HStack(spacing: 12) {
                    Image(systemName: connectedId.isEmpty ? "link.badge.plus" : "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(connectedId.isEmpty ? .orange : .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connectedId.isEmpty ? "은행 미연동" : "은행 연동됨")
                            .font(.subheadline.weight(.medium))
                        if !connectedId.isEmpty {
                            Text("내역 가져오기를 사용할 수 있어요")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            } header: {
                Text("연동 상태")
            }

            // ① 계정 연결
            Section {
                Picker("은행", selection: $createOrg) {
                    ForEach(bankCodes, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                TextField("인터넷뱅킹 ID", text: $createId)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                SecureField("비밀번호", text: $createPassword)
                    .textContentType(.password)
                Button {
                    Task { await createConnectedId() }
                } label: {
                    HStack {
                        Text("계정 연결하기")
                        Spacer()
                        if isLoading { ProgressView().scaleEffect(0.8) }
                    }
                }
                .disabled(createId.isEmpty || createPassword.isEmpty || isLoading)
            } header: {
                Text("1. 은행 계정 연결")
            } footer: {
                Text("연동 후 발급된 ID로 입출금 내역을 가져옵니다.")
            }

            // ② 내역 가져오기
            Section {
                Picker("은행", selection: $organization) {
                    ForEach(bankCodes, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                TextField("계좌번호", text: $account)
                    .keyboardType(.numberPad)
                HStack {
                    TextField("시작일", text: $startDate)
                        .keyboardType(.numberPad)
                        .placeholder(when: startDate.isEmpty) { Text("20240101").foregroundStyle(.tertiary) }
                    Text("~")
                    TextField("종료일", text: $endDate)
                        .keyboardType(.numberPad)
                        .placeholder(when: endDate.isEmpty) { Text("20241231").foregroundStyle(.tertiary) }
                }
                TextField("계좌 비밀번호 (선택)", text: $accountPassword)
                    .keyboardType(.numberPad)
                Button {
                    Task { await fetchAndSaveBankTransactions() }
                } label: {
                    HStack {
                        Text("내역 가져와서 저장하기")
                        Spacer()
                        if isLoading { ProgressView().scaleEffect(0.8) }
                    }
                }
                .disabled(connectedId.isEmpty || account.isEmpty || startDate.isEmpty || endDate.isEmpty || effectiveCoupleID == nil || isLoading)
            } header: {
                Text("2. 입출금 내역 가져오기")
            } footer: {
                Text("날짜는 yyyyMMdd 형식(예: 20240101)입니다. 가져온 내역은 '내역' 탭에서 볼 수 있어요.")
            }

            // 결과 메시지
            Section {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(messageColor)
                    .textSelection(.enabled)
            } header: {
                Text("결과")
            }
        }
        .navigationTitle("은행 연동")
        .onAppear {
            resetFields()
        }
    }

    private var messageColor: Color {
        switch messageType {
        case .info: return .primary
        case .success: return .green
        case .error: return .red
        }
    }

    private func resetFields() {
        let (s, e) = defaultDateRange()
        startDate = s
        endDate = e
        accountPassword = ""
        birthDate = ""
        message = "은행 계정을 연결한 뒤, 조회 기간을 선택하고 내역을 가져오세요."
        messageType = .info
    }

    private func defaultDateRange() -> (String, String) {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(byAdding: .month, value: -1, to: now) ?? now
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return (formatter.string(from: start), formatter.string(from: now))
    }

    private func createConnectedId() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let cid = try await CODEFService.shared.connectAccount(
                organization: createOrg,
                businessType: createBizType,
                id: createId,
                password: createPassword
            )
            try await AuthService.shared.loadUserAfterConnect(connectedId: cid)
            message = "연동이 완료되었습니다. 이제 '내역 가져와서 저장하기'를 사용할 수 있어요."
            messageType = .success
        } catch {
            message = error.localizedDescription
            messageType = .error
        }
    }

    private func fetchAndSaveBankTransactions() async {
        guard let uid = Auth.auth().currentUser?.uid,
              let coupleID = effectiveCoupleID else {
            message = "로그인 상태와 커플 정보를 확인해 주세요."
            messageType = .error
            return
        }
        let cid = connectedId
        if cid.isEmpty {
            message = "먼저 '계정 연결하기'를 완료해 주세요."
            messageType = .error
            return
        }

        isLoading = true
        defer { isLoading = false }
        messageType = .info
        message = "내역을 가져오는 중..."

        do {
            let list = try await CODEFService.shared.fetchBankTransactions(
                organization: organization,
                account: account,
                startDate: startDate,
                endDate: endDate,
                accountPassword: accountPassword,
                birthDate: birthDate.isEmpty ? "" : birthDate,
                connectedIdOverride: cid
            )

            // stableId 기반으로 저장 (동일 ID → 덮어쓰기 = 중복 없음)
            var newIds = Set<String>()
            var saved = 0
            for item in list {
                guard let codefItem = CODEFBankTransaction.from(dict: item) else { continue }
                let t = codefItem.toTransaction(ownerID: uid, coupleID: coupleID, accountNumber: account)
                newIds.insert(t.id)
                try? await FirebaseService.shared.saveTransaction(t)
                saved += 1
            }

            // stableId 도입 이전에 UUID로 저장된 구 데이터 정리
            let existing = try await FirebaseService.shared.fetchTransactionIds(coupleID: coupleID)
            var cleaned = 0
            for oldId in existing {
                if !oldId.hasPrefix("bank_") && !newIds.contains(oldId) {
                    continue
                }
                if !oldId.hasPrefix("bank_") {
                    try? await FirebaseService.shared.deleteTransaction(id: oldId, coupleID: coupleID)
                    cleaned += 1
                }
            }

            let msg = cleaned > 0
                ? "\(saved)건 저장, \(cleaned)건 중복 정리 완료."
                : "\(saved)건의 내역을 저장했습니다."
            message = "\(msg) '내역' 탭에서 확인하세요."
            messageType = .success
        } catch {
            message = "가져오기 실패: \(error.localizedDescription)"
            messageType = .error
        }
    }
}

// Placeholder modifier
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

#Preview {
    NavigationStack {
        BankLinkView()
            .environment(AuthService())
    }
}
