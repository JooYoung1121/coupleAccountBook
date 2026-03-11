import SwiftUI
import FirebaseAuth

/// 개발용 CODEF 테스트 화면 - 배포 전 제거
struct CODEFTestView: View {
    // MARK: - connectedId 발급
    @State private var createOrg = "0020"
    @State private var createBizType = "BK"
    @State private var createId = "testuser01"
    @State private var createPassword = "test1234"

    // MARK: - 공통
    @State private var organization = "0020"
    @State private var connectedId = ""

    // MARK: - 은행 거래내역
    @State private var account = "1002440000000"
    @State private var startDate = "20190601"
    @State private var endDate = "20190619"
    @State private var accountPassword = ""
    @State private var birthDate = ""
    @State private var inquiryType = "1"

    // MARK: - 카드 승인내역 (CODEF 카드사 코드)
    @State private var cardOrg = "0306"
    @State private var cardConnectedId = ""
    @State private var cardStartDate = "20190101"
    @State private var cardEndDate = "20190630"

    // MARK: - 상태
    @State private var isLoading = false
    @State private var responseText = "조회 버튼을 눌러주세요"

    let bankCodes = [
        ("0020", "우리은행"),
        ("0004", "국민은행"),
        ("0088", "신한은행"),
        ("0081", "하나은행"),
        ("0011", "농협"),
    ]

    let cardCodes = [
        ("0306", "신한카드"),
        ("0309", "우리카드"),
        ("0303", "삼성카드"),
        ("0301", "KB카드"),
        ("0302", "현대카드"),
        ("0311", "롯데카드"),
        ("0313", "하나카드"),
    ]

    /// 업종에 따라 기관 목록 반환
    var createOrgCodes: [(String, String)] {
        createBizType == "CD" ? cardCodes : bankCodes
    }

    var body: some View {
        Form {
            Section {
                let uid = Auth.auth().currentUser?.uid
                Label(uid ?? "❌ 로그인 안 됨", systemImage: uid != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(uid != nil ? .green : .red)
                    .font(.caption.monospaced())
            } header: {
                Text("🔐 Firebase Auth 상태")
            } footer: {
                Text("일반 사용은 설정 > 은행 연동을 사용하세요.")
            }

            Section {
                Picker("업종", selection: $createBizType) {
                    Text("은행 (BK)").tag("BK")
                    Text("카드 (CD)").tag("CD")
                }
                .onChange(of: createBizType) { _, newValue in
                    createOrg = newValue == "CD" ? "0306" : "0020"
                }
                Picker("기관", selection: $createOrg) {
                    ForEach(createOrgCodes, id: \.0) { code, name in
                        Text("\(name) (\(code))").tag(code)
                    }
                }
                TextField("인터넷뱅킹 ID", text: $createId)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("비밀번호", text: $createPassword)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("connectedId 발급") {
                    Task { await createConnectedId() }
                }
                .disabled(isLoading)
                if !connectedId.isEmpty {
                    HStack {
                        Text("발급된 connectedId:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(connectedId)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text("① connectedId 발급 (개발환경 — 아무 ID/PW 입력 가능)")
            } footer: {
                Text("발급된 connectedId는 자동으로 아래 조회에 사용됩니다.")
            }

            Section("② 은행 수시입출 거래내역 조회") {
                Picker("기관", selection: $organization) {
                    ForEach(bankCodes, id: \.0) { code, name in
                        Text("\(name) (\(code))").tag(code)
                    }
                }
                TextField("connectedId (직접 입력 가능)", text: $connectedId)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.caption.monospaced())
                TextField("계좌번호", text: $account)
                    .keyboardType(.numberPad)
                HStack {
                    TextField("시작일 (yyyyMMdd)", text: $startDate).keyboardType(.numberPad)
                    Text("~")
                    TextField("종료일", text: $endDate).keyboardType(.numberPad)
                }
                TextField("계좌 비밀번호 (선택)", text: $accountPassword).keyboardType(.numberPad)
                TextField("생년월일 6자리 (선택)", text: $birthDate).keyboardType(.numberPad)
                Picker("조회 구분", selection: $inquiryType) {
                    Text("입출금 전체 (1)").tag("1")
                    Text("입금 (2)").tag("2")
                    Text("출금 (3)").tag("3")
                }
                Button("은행 입출금 조회") {
                    Task { await fetchBank() }
                }
                .disabled(connectedId.isEmpty || isLoading)
            }

            Section("③ 카드 승인내역 조회") {
                Picker("카드사", selection: $cardOrg) {
                    ForEach(cardCodes, id: \.0) { code, name in
                        Text("\(name) (\(code))").tag(code)
                    }
                }
                TextField("connectedId (카드용)", text: $cardConnectedId)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.caption.monospaced())
                HStack {
                    TextField("시작일 (yyyyMMdd)", text: $cardStartDate).keyboardType(.numberPad)
                    Text("~")
                    TextField("종료일", text: $cardEndDate).keyboardType(.numberPad)
                }
                Button("카드 승인내역 조회") {
                    Task { await fetchCard() }
                }
                .disabled(cardConnectedId.isEmpty || isLoading)
            }

            Section("API 응답") {
                if isLoading {
                    ProgressView("요청 중...")
                } else {
                    ScrollView {
                        Text(responseText)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 500)
                }
            }
        }
        .navigationTitle("CODEF 테스트 (DEV)")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Actions

    private func createConnectedId() async {
        isLoading = true
        defer { isLoading = false }
        print("[CODEF] connectedId 발급 요청: org=\(createOrg), bizType=\(createBizType), id=\(createId)")
        do {
            let cid = try await CODEFService.shared.connectAccount(
                organization: createOrg,
                businessType: createBizType,
                id: createId,
                password: createPassword
            )
            if createBizType == "CD" {
                cardConnectedId = cid
                cardOrg = createOrg
            } else {
                connectedId = cid
                organization = createOrg
            }
            responseText = "✅ connectedId 발급 완료 (\(createBizType)):\n\(cid)"
            print("[CODEF] connectedId 발급 완료: \(cid)")
        } catch {
            print("[CODEF] 발급 오류: \(error)")
            if let nsError = error as NSError? {
                print("[CODEF] domain: \(nsError.domain), code: \(nsError.code)")
                print("[CODEF] localizedDescription: \(nsError.localizedDescription)")
                if let details = nsError.userInfo["details"] {
                    print("[CODEF] details: \(details)")
                }
                for (k, v) in nsError.userInfo {
                    print("[CODEF] userInfo[\(k)]: \(v)")
                }
            }
            let detail = (error as NSError).userInfo["details"] as? String
                ?? (error as NSError).localizedDescription
            responseText = "❌ 발급 오류:\n\(detail)"
        }
    }

    private func fetchBank() async {
        isLoading = true
        defer { isLoading = false }

        let uid = Auth.auth().currentUser?.uid
        print("[CODEF] Auth UID: \(uid ?? "nil")")
        print("[CODEF] 요청: org=\(organization), account=\(account), \(startDate)~\(endDate), connectedId=\(connectedId)")

        do {
            let raw = try await CODEFService.shared.fetchBankTransactionsRaw(
                organization: organization,
                account: account,
                startDate: startDate,
                endDate: endDate,
                accountPassword: accountPassword,
                birthDate: birthDate,
                inquiryType: inquiryType,
                connectedIdOverride: connectedId
            )
            let json = try JSONSerialization.data(withJSONObject: raw, options: .prettyPrinted)
            let text = String(data: json, encoding: .utf8) ?? "파싱 실패"
            responseText = text
            print("[CODEF] 응답:\n\(text)")
        } catch {
            print("[CODEF] 오류: \(error)")
            responseText = "❌ 오류:\n\(error)"
        }
    }
    private func fetchCard() async {
        isLoading = true
        defer { isLoading = false }

        let uid = Auth.auth().currentUser?.uid
        print("[CODEF] Auth UID: \(uid ?? "nil")")
        print("[CODEF] 카드 조회 요청: org=\(cardOrg), \(cardStartDate)~\(cardEndDate), connectedId=\(cardConnectedId)")

        do {
            let raw = try await CODEFService.shared.fetchCardTransactionsRaw(
                organization: cardOrg,
                startDate: cardStartDate,
                endDate: cardEndDate,
                connectedIdOverride: cardConnectedId
            )
            let json = try JSONSerialization.data(withJSONObject: raw, options: .prettyPrinted)
            let text = String(data: json, encoding: .utf8) ?? "파싱 실패"
            responseText = text
            print("[CODEF] 카드 응답:\n\(text)")
        } catch {
            print("[CODEF] 카드 오류: \(error)")
            responseText = "❌ 카드 조회 오류:\n\(error)"
        }
    }
}

#Preview {
    NavigationStack { CODEFTestView() }
}
