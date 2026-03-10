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

    func signOut() throws {
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
        } catch {
            self.error = error.localizedDescription
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
