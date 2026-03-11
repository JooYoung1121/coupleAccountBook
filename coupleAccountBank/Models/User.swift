import Foundation

/// Firebase Auth + Firestore 기반 사용자 모델 (SwiftData 미사용)
/// Firestore 경로: users/{uid}
struct User: Codable, Identifiable, Hashable {
    var id: String          // Firebase UID
    var name: String
    var email: String
    var coupleID: String?   // 파트너와 연결 후 할당되는 공유 Room ID
    var connectedId: String? // CODEF 금융 연동 ID (은행/카드 조회용)
    var birthDate: String?   // 생년월일 6자리 "YYMMDD" (CODEF 은행 조회용)
    var profileImageURL: String?
    var createdAt: Date

    static let collectionName = "users"

    init(id: String, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
        self.coupleID = nil
        self.connectedId = nil
        self.birthDate = nil
        self.profileImageURL = nil
        self.createdAt = .now
    }

    var isPaired: Bool { coupleID != nil }

    /// 커플 방 ID. 미연결 시 본인 uid로 단일 사용자 방 사용
    var effectiveCoupleID: String? { coupleID ?? id }
}
