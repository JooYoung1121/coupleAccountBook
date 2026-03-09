import Foundation
import FirebaseAuth

@MainActor
@Observable
final class AuthService {
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

    // MARK: - Private

    private func loadUser(uid: String) async {
        do {
            currentUser = try await FirebaseService.shared.fetchUser(uid: uid)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
