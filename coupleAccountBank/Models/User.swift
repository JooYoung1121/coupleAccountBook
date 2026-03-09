import Foundation

/// Firebase Auth + Firestore 기반 사용자 모델 (SwiftData 미사용)
/// Firestore 경로: users/{uid}
struct User: Codable, Identifiable, Hashable {
    var id: String          // Firebase UID
    var name: String
    var email: String
    var coupleID: String?   // 파트너와 연결 후 할당되는 공유 Room ID
    var profileImageURL: String?
    var createdAt: Date

    static let collectionName = "users"

    init(id: String, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
        self.coupleID = nil
        self.profileImageURL = nil
        self.createdAt = .now
    }

    var isPaired: Bool { coupleID != nil }
}
