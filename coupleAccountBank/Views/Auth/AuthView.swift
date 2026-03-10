import SwiftUI
import AuthenticationServices
import CryptoKit

struct AuthView: View {
    @Environment(AuthService.self) private var authService
    @State private var currentNonce: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // 앱 아이콘 + 타이틀
            VStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.pink)

                Text("우리 가계부")
                    .font(.largeTitle.bold())

                Text("부부의 자산을 함께 관리하세요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 에러 메시지
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Apple 로그인 버튼
            SignInWithAppleButton(.signIn) { request in
                let nonce = Self.randomNonceString()
                currentNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = Self.sha256(nonce)
            } onCompletion: { result in
                Task {
                    do {
                        guard let nonce = currentNonce else { return }
                        try await authService.handleAppleSignIn(result: result, nonce: nonce)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .padding(.horizontal, 32)

            Spacer().frame(height: 32)
        }
    }

    // MARK: - Nonce 헬퍼

    private static func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            randoms.forEach { random in
                guard remainingLength > 0 else { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hash = SHA256.hash(data: inputData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    AuthView()
        .environment(AuthService())
}
