import SwiftUI
import FirebaseAuth

struct CoupleSettingsView: View {
    @Environment(AuthService.self) private var authService
    @State private var pairingCode: String?
    @State private var inputCode = ""
    @State private var partnerName: String?
    @State private var isLoading = false
    @State private var message: String?
    @State private var messageIsError = false

    private var isPaired: Bool {
        authService.currentUser?.coupleID != nil
    }

    var body: some View {
        List {
            if isPaired {
                pairedSection
            } else {
                createCodeSection
                joinCodeSection
            }

            if let message {
                Section {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(messageIsError ? .red : .green)
                }
            }
        }
        .navigationTitle("커플 연결")
        .onAppear {
            if isPaired { loadPartnerName() }
        }
    }

    // MARK: - Paired

    private var pairedSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("연결됨")
                        .font(.subheadline.weight(.semibold))
                    if let partnerName {
                        Text("파트너: \(partnerName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)

            Button(role: .destructive) {
                Task { await unpair() }
            } label: {
                HStack {
                    Text("연결 해제")
                    Spacer()
                    if isLoading { ProgressView().scaleEffect(0.8) }
                }
            }
            .disabled(isLoading)
        } header: {
            Text("커플 상태")
        }
    }

    // MARK: - Create Code

    private var createCodeSection: some View {
        Section {
            if let code = pairingCode {
                HStack {
                    Text(code)
                        .font(.title.weight(.bold).monospaced())
                        .tracking(4)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = code
                        message = "코드가 복사되었어요!"
                        messageIsError = false
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
                Text("파트너에게 이 코드를 보내 주세요. 5분간 유효합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await createCode() }
                } label: {
                    HStack {
                        Text("초대 코드 생성")
                        Spacer()
                        if isLoading { ProgressView().scaleEffect(0.8) }
                    }
                }
                .disabled(isLoading)
            }
        } header: {
            Text("초대하기")
        } footer: {
            Text("초대 코드를 생성하여 파트너에게 공유하세요.")
        }
    }

    // MARK: - Join Code

    private var joinCodeSection: some View {
        Section {
            TextField("6자리 코드 입력", text: $inputCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()

            Button {
                Task { await joinWithCode() }
            } label: {
                HStack {
                    Text("연결하기")
                    Spacer()
                    if isLoading { ProgressView().scaleEffect(0.8) }
                }
            }
            .disabled(inputCode.count != 6 || isLoading)
        } header: {
            Text("코드로 연결")
        } footer: {
            Text("파트너가 생성한 초대 코드를 입력하세요.")
        }
    }

    // MARK: - Actions

    private func createCode() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let code = try await FirebaseService.shared.createPairingCode(uid: uid)
            pairingCode = code
            message = nil
        } catch {
            message = "코드 생성 실패: \(error.localizedDescription)"
            messageIsError = true
        }
    }

    private func joinWithCode() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await FirebaseService.shared.joinWithPairingCode(uid: uid, code: inputCode.uppercased())
            // Reload user to get updated coupleID
            let updatedUser = try await FirebaseService.shared.fetchUser(uid: uid)
            authService.currentUser = updatedUser
            message = "커플 연결 완료!"
            messageIsError = false
            loadPartnerName()
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private func unpair() async {
        guard let uid = Auth.auth().currentUser?.uid,
              let coupleID = authService.currentUser?.coupleID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await FirebaseService.shared.unpairCouple(uid: uid, coupleID: coupleID)
            let updatedUser = try await FirebaseService.shared.fetchUser(uid: uid)
            authService.currentUser = updatedUser
            partnerName = nil
            message = "연결이 해제되었어요."
            messageIsError = false
        } catch {
            message = "해제 실패: \(error.localizedDescription)"
            messageIsError = true
        }
    }

    private func loadPartnerName() {
        guard let uid = Auth.auth().currentUser?.uid,
              let coupleID = authService.currentUser?.coupleID else { return }
        Task {
            if let name = try? await FirebaseService.shared.fetchPartnerName(myUID: uid, coupleID: coupleID) {
                partnerName = name
            }
        }
    }
}

#Preview {
    NavigationStack {
        CoupleSettingsView()
            .environment(AuthService())
    }
}
