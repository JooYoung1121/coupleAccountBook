import Foundation

/// 연동된 은행/카드 계좌 정보
/// Firestore 경로: users/{uid}/linkedAccounts/{id}
struct LinkedAccount: Codable, Identifiable {
    var id: String
    var connectedId: String      // CODEF connectedId
    var businessType: String     // "BK" or "CD"
    var organization: String     // 기관코드 "0020"
    var organizationName: String // "우리은행"
    var accountNumber: String?   // 은행만 (카드는 nil)
    var accountPassword: String? // 계좌 비밀번호 (은행만)
    var loginId: String?         // 인터넷뱅킹 ID (재연결용)
    var linkedAt: Date

    init(
        id: String = UUID().uuidString,
        connectedId: String,
        businessType: String,
        organization: String,
        organizationName: String,
        accountNumber: String? = nil,
        accountPassword: String? = nil,
        loginId: String? = nil,
        linkedAt: Date = .now
    ) {
        self.id = id
        self.connectedId = connectedId
        self.businessType = businessType
        self.organization = organization
        self.organizationName = organizationName
        self.accountNumber = accountNumber
        self.accountPassword = accountPassword
        self.loginId = loginId
        self.linkedAt = linkedAt
    }

    var isBank: Bool { businessType == "BK" }
    var isCard: Bool { businessType == "CD" }

    var displayName: String {
        if isBank, let acc = accountNumber {
            return "\(organizationName) \(acc.suffix(4))"
        }
        return organizationName
    }
}
