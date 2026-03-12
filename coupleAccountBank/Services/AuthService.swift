import Foundation
import FirebaseAuth
import AuthenticationServices

@MainActor
@Observable
final class AuthService {
    static let shared = AuthService()

    var currentUser: User?
    var isLoading = false
    var error: String?

    nonisolated(unsafe) private var listenerHandle: AuthStateDidChangeListenerHandle?
    nonisolated(unsafe) private var stopUserDocListener: (() -> Void)?

    init() {
        listenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            guard let self else { return }
            if let firebaseUser {
                Task { await self.loadUser(uid: firebaseUser.uid) }
            } else {
                self.currentUser = nil
            }
        }
    }

    deinit {
        if let handle = listenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
        stopUserDocListener?()
    }

    var isSignedIn: Bool { currentUser != nil }

    // MARK: - Auth

    func signUp(email: String, password: String, name: String) async throws {
        isLoading = true
        defer { isLoading = false }
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let user = User(id: result.user.uid, name: name, email: email)
        try await FirebaseService.shared.saveUser(user)
        currentUser = user
    }

    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        await loadUser(uid: result.user.uid)
    }

    func signOut() async throws {
        let uid = Auth.auth().currentUser?.uid
        if let uid = uid {
            let accounts = try? await FirebaseService.shared.fetchLinkedAccounts(uid: uid)
            accounts?.forEach { KeychainService.shared.deleteAccountPassword(accountId: $0.id) }
        }
        stopUserDocListener?()
        stopUserDocListener = nil
        try Auth.auth().signOut()
        currentUser = nil
    }

    // MARK: - Apple Sign In

    func handleAppleSignIn(result: Result<ASAuthorization, Error>, nonce: String) async throws {
        isLoading = true
        defer { isLoading = false }

        switch result {
        case .success(let authorization):
            guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let idTokenData = appleCredential.identityToken,
                  let idTokenString = String(data: idTokenData, encoding: .utf8) else {
                throw AuthError.invalidCredential
            }

            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleCredential.fullName
            )
            let authResult = try await Auth.auth().signIn(with: firebaseCredential)

            // 이름 조합 (첫 로그인 시에만 fullName 제공됨)
            let givenName = appleCredential.fullName?.givenName ?? ""
            let familyName = appleCredential.fullName?.familyName ?? ""
            let fullName = [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")

            let user = User(
                id: authResult.user.uid,
                name: fullName.isEmpty ? "사용자" : fullName,
                email: authResult.user.email ?? ""
            )
            try await FirebaseService.shared.saveUser(user)
            currentUser = user

        case .failure(let error):
            throw error
        }
    }

    // MARK: - Private

    private func loadUser(uid: String) async {
        do {
            currentUser = try await FirebaseService.shared.fetchUser(uid: uid)
            startUserDocListener(uid: uid)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Firestore 사용자 문서를 실시간 감시하여 파트너 연결 등 변경사항을 즉시 반영합니다.
    private func startUserDocListener(uid: String) {
        stopUserDocListener?()
        stopUserDocListener = FirebaseService.shared.listenToUser(uid: uid) { [weak self] user in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let oldCoupleID = self.currentUser?.coupleID
                self.currentUser = user

                // coupleID가 새로 설정되면 기존 거래를 새 경로로 마이그레이션
                if oldCoupleID == nil, let newCoupleID = user.coupleID {
                    _ = try? await FirebaseService.shared.migrateTransactions(
                        fromCoupleID: user.id,
                        toCoupleID: newCoupleID
                    )
                }
            }
        }
    }

    /// 연동(connectedId 등) 반영을 위해 Firestore 사용자 정보를 다시 불러옵니다.
    func loadUserAfterConnect(connectedId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        currentUser = try await FirebaseService.shared.fetchUser(uid: uid)
    }

    // MARK: - Errors

    enum AuthError: LocalizedError {
        case invalidCredential

        var errorDescription: String? {
            switch self {
            case .invalidCredential: return "Apple 인증 정보를 가져올 수 없습니다."
            }
        }
    }
}
