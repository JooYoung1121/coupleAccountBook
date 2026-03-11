import SwiftUI
import FirebaseAuth

/// 은행·카드 연동 및 내역 가져오기 화면
struct BankLinkView: View {
    @Environment(AuthService.self) private var authService

    // 등록된 계좌/카드 목록
    @State private var linkedAccounts: [LinkedAccount] = []
    @State private var selectedAccount: LinkedAccount?

    // 계정 연결 (샌드박스 기본값)
    @State private var createOrg = "0020"
    @State private var createBizType = "BK"
    @State private var createId = "testuser01"
    @State private var createPassword = "test1234"

    // 은행 내역 가져오기 (샌드박스 기본값)
    @State private var bankOrg = "0020"
    @State private var account = "1002440000000"
    @State private var bankStart = ""
    @State private var bankEnd = ""
    @State private var accountPassword = ""

    // 카드 내역 가져오기 (샌드박스 기본값)
    @State private var cardOrg = "0309"
    @State private var cardStart = ""
    @State private var cardEnd = ""

    @State private var isLoading = false
    @State private var message = "계정을 연결한 뒤, 내역을 가져오세요."
    @State private var messageType: MessageType = .info

    private var connectedId: String {
        selectedAccount?.connectedId ?? authService.currentUser?.connectedId ?? ""
    }
    private var effectiveCoupleID: String? {
        authService.currentUser?.effectiveCoupleID
    }
    private var currentUserName: String {
        authService.currentUser?.name ?? "사용자"
    }

    let bankCodes: [(String, String)] = [
        ("0020", "우리은행"),
        ("0004", "국민은행"),
        ("0088", "신한은행"),
        ("0081", "하나은행"),
        ("0011", "농협"),
    ]
    let cardCodes: [(String, String)] = [
        ("0309", "신한카드"),
        ("0301", "KB카드"),
        ("0310", "현대카드"),
        ("0311", "삼성카드"),
        ("0313", "롯데카드"),
    ]

    enum MessageType { case info, success, error }

    var body: some View {
        List {
            if !linkedAccounts.isEmpty {
                linkedAccountsSection
            }
            statusSection
            connectSection
            bankFetchSection
            cardFetchSection
            resultSection
        }
        .navigationTitle("금융 연동")
        .onAppear {
            resetFields()
            Task { await loadLinkedAccounts() }
        }
    }

    // MARK: - Sections

    private var linkedAccountsSection: some View {
        Section {
            ForEach(linkedAccounts) { acct in
                Button {
                    selectAccount(acct)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: acct.isBank ? "building.columns.fill" : "creditcard.fill")
                            .foregroundStyle(acct.isBank ? .blue : .purple)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(acct.displayName)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(acct.isBank ? "은행" : "카드")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedAccount?.id == acct.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await deleteAccount(acct) }
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("등록된 계좌/카드")
        } footer: {
            Text("선택하면 해당 계좌/카드로 바로 조회할 수 있어요.")
        }
    }

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: connectedId.isEmpty ? "link.badge.plus" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(connectedId.isEmpty ? .orange : .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connectedId.isEmpty ? "미연동" : "연동됨")
                        .font(.subheadline.weight(.medium))
                    if !connectedId.isEmpty {
                        Text("은행·카드 내역을 가져올 수 있어요")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
        } header: {
            Text("연동 상태")
        }
    }

    private var connectSection: some View {
        Section {
            Picker("기관", selection: $createOrg) {
                ForEach(bankCodes + cardCodes, id: \.0) { code, name in
                    Text(name).tag(code)
                }
            }
            Picker("업종", selection: $createBizType) {
                Text("은행 (BK)").tag("BK")
                Text("카드 (CD)").tag("CD")
            }
            TextField("ID", text: $createId)
                .textContentType(.username)
                .autocorrectionDisabled()
            SecureField("비밀번호", text: $createPassword)
                .textContentType(.password)
            if createBizType == "BK" {
                TextField("계좌번호", text: $account).keyboardType(.numberPad)
                TextField("계좌 비밀번호 (선택)", text: $accountPassword).keyboardType(.numberPad)
            }
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
            Text("1. 계정 연결")
        } footer: {
            Text("은행·카드를 각각 연결해야 합니다. 같은 connectedId에 추가됩니다.")
        }
    }

    private var bankFetchSection: some View {
        Section {
            Picker("은행", selection: $bankOrg) {
                ForEach(bankCodes, id: \.0) { code, name in
                    Text(name).tag(code)
                }
            }
            if selectedAccount == nil || selectedAccount?.isCard == true {
                TextField("계좌번호", text: $account).keyboardType(.numberPad)
            }
            dateRangeRow(start: $bankStart, end: $bankEnd)
            if selectedAccount?.accountPassword == nil {
                TextField("계좌 비밀번호 (선택)", text: $accountPassword).keyboardType(.numberPad)
            }
            Button {
                Task { await fetchBank() }
            } label: {
                HStack {
                    Text("은행 내역 가져오기")
                    Spacer()
                    if isLoading { ProgressView().scaleEffect(0.8) }
                }
            }
            .disabled(connectedId.isEmpty || account.isEmpty || bankStart.isEmpty || bankEnd.isEmpty || isLoading)
        } header: {
            Text("2. 은행 입출금 내역")
        }
    }

    private var cardFetchSection: some View {
        Section {
            Picker("카드사", selection: $cardOrg) {
                ForEach(cardCodes, id: \.0) { code, name in
                    Text(name).tag(code)
                }
            }
            dateRangeRow(start: $cardStart, end: $cardEnd)
            Button {
                Task { await fetchCard() }
            } label: {
                HStack {
                    Text("카드 내역 가져오기")
                    Spacer()
                    if isLoading { ProgressView().scaleEffect(0.8) }
                }
            }
            .disabled(connectedId.isEmpty || cardStart.isEmpty || cardEnd.isEmpty || isLoading)
        } header: {
            Text("3. 카드 승인내역")
        } footer: {
            Text("카드사 계정도 1단계에서 업종 'CD'로 연결해야 합니다.")
        }
    }

    private var resultSection: some View {
        Section {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(messageColor)
                .textSelection(.enabled)
        } header: {
            Text("결과")
        }
    }

    private func dateRangeRow(start: Binding<String>, end: Binding<String>) -> some View {
        HStack {
            TextField("시작일", text: start)
                .keyboardType(.numberPad)
                .placeholder(when: start.wrappedValue.isEmpty) { Text("20240101").foregroundStyle(.tertiary) }
            Text("~")
            TextField("종료일", text: end)
                .keyboardType(.numberPad)
                .placeholder(when: end.wrappedValue.isEmpty) { Text("20241231").foregroundStyle(.tertiary) }
        }
    }

    // MARK: - Helpers

    private var messageColor: Color {
        switch messageType {
        case .info: .primary
        case .success: .green
        case .error: .red
        }
    }

    private func resetFields() {
        let (s, e) = defaultDateRange()
        bankStart = s; bankEnd = e
        cardStart = s; cardEnd = e
        accountPassword = ""
        message = "계정을 연결한 뒤, 내역을 가져오세요."
        messageType = .info
    }

    private func defaultDateRange() -> (String, String) {
        let now = Date()
        let start = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
        return (f.string(from: start), f.string(from: now))
    }

    private func orgName(for code: String) -> String {
        let all = bankCodes + cardCodes
        return all.first(where: { $0.0 == code })?.1 ?? code
    }

    // MARK: - LinkedAccount Management

    private func loadLinkedAccounts() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            linkedAccounts = try await FirebaseService.shared.fetchLinkedAccounts(uid: uid)
        } catch {
            // 조용히 실패 — 첫 사용 시 빈 목록
        }
    }

    private func selectAccount(_ acct: LinkedAccount) {
        selectedAccount = acct
        if acct.isBank {
            bankOrg = acct.organization
            if let acc = acct.accountNumber { account = acc }
            if let pw = acct.accountPassword { accountPassword = pw }
        } else {
            cardOrg = acct.organization
        }
        message = "\(acct.displayName) 선택됨. 내역을 가져올 수 있어요."
        messageType = .info
    }

    private func deleteAccount(_ acct: LinkedAccount) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await FirebaseService.shared.deleteLinkedAccount(uid: uid, accountId: acct.id)
            linkedAccounts.removeAll { $0.id == acct.id }
            if selectedAccount?.id == acct.id { selectedAccount = nil }
            message = "\(acct.displayName) 삭제됨"
            messageType = .info
        } catch {
            message = "삭제 실패: \(error.localizedDescription)"
            messageType = .error
        }
    }

    // MARK: - Actions

    private func createConnectedId() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let cid = try await CODEFService.shared.connectAccount(
                organization: createOrg, businessType: createBizType,
                id: createId, password: createPassword
            )
            try await AuthService.shared.loadUserAfterConnect(connectedId: cid)

            // LinkedAccount 자동 저장
            let linked = LinkedAccount(
                connectedId: cid,
                businessType: createBizType,
                organization: createOrg,
                organizationName: orgName(for: createOrg),
                accountNumber: createBizType == "BK" ? (account.isEmpty ? nil : account) : nil,
                accountPassword: createBizType == "BK" ? (accountPassword.isEmpty ? nil : accountPassword) : nil,
                loginId: createId
            )
            try await FirebaseService.shared.saveLinkedAccount(uid: uid, account: linked)
            linkedAccounts.insert(linked, at: 0)
            selectedAccount = linked

            message = "연동 완료! \(linked.displayName)이(가) 등록되었어요."
            messageType = .success
        } catch {
            message = error.localizedDescription
            messageType = .error
        }
    }

    private func fetchBank() async {
        guard let uid = Auth.auth().currentUser?.uid,
              let coupleID = effectiveCoupleID else {
            message = "로그인 상태를 확인해 주세요."; messageType = .error; return
        }
        isLoading = true; defer { isLoading = false }
        message = "은행 내역을 가져오는 중..."; messageType = .info

        let effectivePassword = selectedAccount?.accountPassword ?? accountPassword

        do {
            let list = try await CODEFService.shared.fetchBankTransactions(
                organization: bankOrg, account: account,
                startDate: bankStart, endDate: bankEnd,
                accountPassword: effectivePassword,
                connectedIdOverride: connectedId
            )

            // 기존 내역 모두 삭제 후 새로 저장 (중복 완전 방지)
            _ = try await FirebaseService.shared.deleteAllImportedTransactions(coupleID: coupleID)

            var saved = 0
            for item in list {
                guard let tx = CODEFBankTransaction.from(dict: item) else { continue }
                let t = tx.toTransaction(ownerID: uid, ownerName: currentUserName, coupleID: coupleID, accountNumber: account)
                try? await FirebaseService.shared.saveTransaction(t)
                saved += 1
            }
            message = "은행 \(saved)건 저장 완료. '내역' 탭에서 확인하세요."
            messageType = .success
        } catch {
            message = "은행 가져오기 실패: \(error.localizedDescription)"
            messageType = .error
        }
    }

    private func fetchCard() async {
        guard let uid = Auth.auth().currentUser?.uid,
              let coupleID = effectiveCoupleID else {
            message = "로그인 상태를 확인해 주세요."; messageType = .error; return
        }
        isLoading = true; defer { isLoading = false }
        message = "카드 내역을 가져오는 중..."; messageType = .info

        do {
            let list = try await CODEFService.shared.fetchCardTransactions(
                organization: cardOrg, startDate: cardStart, endDate: cardEnd,
                connectedIdOverride: connectedId
            )

            var saved = 0
            for item in list {
                guard let approval = CODEFCardApproval.from(dict: item) else { continue }
                let t = approval.toTransaction(ownerID: uid, ownerName: currentUserName, coupleID: coupleID, cardOrg: cardOrg)
                try? await FirebaseService.shared.saveTransaction(t)
                saved += 1
            }
            message = "카드 \(saved)건 저장 완료. '내역' 탭에서 확인하세요."
            messageType = .success
        } catch {
            message = "카드 가져오기 실패: \(error.localizedDescription)"
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
