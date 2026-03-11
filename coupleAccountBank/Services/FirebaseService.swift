import Foundation
import FirebaseFirestore

// MARK: - Firestore DTOs

struct TransactionDTO: Codable {
    var id: String
    var amount: Double
    var type: String
    var category: String
    var note: String
    var date: Timestamp
    var ownerID: String
    var ownerName: String?
    var coupleID: String
    var isImported: Bool?
    var userMemo: String?
}

struct GoalDTO: Codable {
    var id: String
    var title: String
    var targetAmount: Double
    var currentAmount: Double
    var deadline: Timestamp?
    var status: String
    var coupleID: String
    var createdAt: Timestamp
}

// MARK: - FirebaseService

final class FirebaseService {
    static let shared = FirebaseService()
    private let db = Firestore.firestore(database: "coupleaccountbankdb")

    private init() {}

    // MARK: - User

    func saveUser(_ user: User) async throws {
        var data: [String: Any] = [
            "id": user.id,
            "name": user.name,
            "email": user.email,
            "createdAt": Timestamp(date: user.createdAt)
        ]
        if let coupleID = user.coupleID { data["coupleID"] = coupleID }
        if let birthDate = user.birthDate { data["birthDate"] = birthDate }
        if let url = user.profileImageURL { data["profileImageURL"] = url }

        try await db.collection(User.collectionName).document(user.id).setData(data, merge: true)
    }

    func fetchUser(uid: String) async throws -> User {
        let snapshot = try await db.collection(User.collectionName).document(uid).getDocument()
        guard let data = snapshot.data() else { throw FirestoreError.documentNotFound }

        guard let id = data["id"] as? String,
              let name = data["name"] as? String,
              let email = data["email"] as? String else {
            throw FirestoreError.decodingFailed
        }
        var user = User(id: id, name: name, email: email)
        user.coupleID = data["coupleID"] as? String
        user.connectedId = data["connectedId"] as? String
        user.birthDate = data["birthDate"] as? String
        user.profileImageURL = data["profileImageURL"] as? String
        return user
    }

    func updateCoupleID(uid: String, coupleID: String) async throws {
        try await db.collection(User.collectionName).document(uid).updateData([
            "coupleID": coupleID
        ])
    }

    // MARK: - Transaction

    func saveTransaction(_ t: Transaction) async throws {
        let data: [String: Any] = [
            "id": t.id,
            "amount": t.amount,
            "type": t.type.rawValue,
            "category": t.category.rawValue,
            "note": t.note,
            "date": Timestamp(date: t.date),
            "ownerID": t.ownerID,
            "ownerName": t.ownerName,
            "coupleID": t.coupleID,
            "isImported": t.isImported,
            "userMemo": t.userMemo
        ]
        try await coupleTransactions(t.coupleID).document(t.id).setData(data)
    }

    func deleteTransaction(id: String, coupleID: String) async throws {
        try await coupleTransactions(coupleID).document(id).delete()
    }

    /// 해당 커플 방의 모든 자동 수집 거래를 삭제합니다 (재가져오기 전 정리용)
    func deleteAllImportedTransactions(coupleID: String) async throws -> Int {
        let snapshot = try await coupleTransactions(coupleID).getDocuments()
        var count = 0
        for doc in snapshot.documents {
            try await doc.reference.delete()
            count += 1
        }
        return count
    }

    func listenToTransactions(
        coupleID: String,
        onChange: @escaping ([TransactionDTO]) -> Void
    ) -> ListenerRegistration {
        coupleTransactions(coupleID)
            .order(by: "date", descending: true)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let dtos = docs.compactMap { doc -> TransactionDTO? in
                    try? doc.data(as: TransactionDTO.self)
                }
                onChange(dtos)
            }
    }

    // MARK: - Goal

    func saveGoal(_ g: Goal) async throws {
        var data: [String: Any] = [
            "id": g.id,
            "title": g.title,
            "targetAmount": g.targetAmount,
            "currentAmount": g.currentAmount,
            "status": g.status.rawValue,
            "coupleID": g.coupleID,
            "createdAt": Timestamp(date: g.createdAt)
        ]
        if let deadline = g.deadline { data["deadline"] = Timestamp(date: deadline) }

        try await coupleGoals(g.coupleID).document(g.id).setData(data)
    }

    func updateGoalAmount(id: String, coupleID: String, currentAmount: Double) async throws {
        try await coupleGoals(coupleID).document(id).updateData([
            "currentAmount": currentAmount
        ])
    }

    func listenToGoals(
        coupleID: String,
        onChange: @escaping ([GoalDTO]) -> Void
    ) -> ListenerRegistration {
        coupleGoals(coupleID)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let dtos = docs.compactMap { doc -> GoalDTO? in
                    try? doc.data(as: GoalDTO.self)
                }
                onChange(dtos)
            }
    }

    // MARK: - Pairing

    func createPairingCode(uid: String) async throws -> String {
        let code = String((0..<6).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! })
        let data: [String: Any] = [
            "ownerUID": uid,
            "createdAt": Timestamp(date: Date()),
            "expiresAt": Timestamp(date: Date().addingTimeInterval(300)) // 5분
        ]
        try await db.collection("pairingCodes").document(code).setData(data)
        return code
    }

    func joinWithPairingCode(uid: String, code: String) async throws {
        let docRef = db.collection("pairingCodes").document(code)
        let snapshot = try await docRef.getDocument()
        guard let data = snapshot.data(),
              let ownerUID = data["ownerUID"] as? String,
              let expiresAt = data["expiresAt"] as? Timestamp else {
            throw PairingError.invalidCode
        }
        guard expiresAt.dateValue() > Date() else {
            throw PairingError.codeExpired
        }
        guard ownerUID != uid else {
            throw PairingError.cannotPairWithSelf
        }
        // coupleID = 두 UID를 정렬하여 결합
        let coupleID = [uid, ownerUID].sorted().joined(separator: "_")
        try await updateCoupleID(uid: uid, coupleID: coupleID)
        try await updateCoupleID(uid: ownerUID, coupleID: coupleID)
        // 사용한 코드 삭제
        try await docRef.delete()
    }

    func unpairCouple(uid: String, coupleID: String) async throws {
        // coupleID에서 파트너 UID 추출
        let uids = coupleID.split(separator: "_").map(String.init)
        for id in uids {
            try await db.collection(User.collectionName).document(id).updateData([
                "coupleID": FieldValue.delete()
            ])
        }
    }

    func fetchPartnerName(myUID: String, coupleID: String) async throws -> String? {
        let uids = coupleID.split(separator: "_").map(String.init)
        guard let partnerUID = uids.first(where: { $0 != myUID }) else { return nil }
        let partner = try await fetchUser(uid: partnerUID)
        return partner.name
    }

    enum PairingError: LocalizedError {
        case invalidCode
        case codeExpired
        case cannotPairWithSelf

        var errorDescription: String? {
            switch self {
            case .invalidCode: return "유효하지 않은 초대 코드입니다."
            case .codeExpired: return "만료된 초대 코드입니다."
            case .cannotPairWithSelf: return "자기 자신과는 연결할 수 없습니다."
            }
        }
    }

    // MARK: - LinkedAccount

    func saveLinkedAccount(uid: String, account: LinkedAccount) async throws {
        var data: [String: Any] = [
            "id": account.id,
            "connectedId": account.connectedId,
            "businessType": account.businessType,
            "organization": account.organization,
            "organizationName": account.organizationName,
            "accountNumber": account.accountNumber as Any,
            "loginId": account.loginId as Any,
            "linkedAt": Timestamp(date: account.linkedAt)
        ]
        // accountPassword는 Keychain에 저장하므로 Firestore에 포함하지 않음
        if let pw = account.accountPassword, !pw.isEmpty {
            KeychainService.shared.saveAccountPassword(accountId: account.id, password: pw)
        }
        try await db.collection(User.collectionName)
            .document(uid)
            .collection("linkedAccounts")
            .document(account.id)
            .setData(data)
    }

    func fetchLinkedAccounts(uid: String) async throws -> [LinkedAccount] {
        let snapshot = try await db.collection(User.collectionName)
            .document(uid)
            .collection("linkedAccounts")
            .order(by: "linkedAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { doc -> LinkedAccount? in
            let d = doc.data()
            guard let id = d["id"] as? String,
                  let connectedId = d["connectedId"] as? String,
                  let businessType = d["businessType"] as? String,
                  let organization = d["organization"] as? String,
                  let organizationName = d["organizationName"] as? String else { return nil }
            let linkedAt = (d["linkedAt"] as? Timestamp)?.dateValue() ?? Date()
            let acct = LinkedAccount(
                id: id,
                connectedId: connectedId,
                businessType: businessType,
                organization: organization,
                organizationName: organizationName,
                accountNumber: d["accountNumber"] as? String,
                accountPassword: KeychainService.shared.loadAccountPassword(accountId: id),
                loginId: d["loginId"] as? String,
                linkedAt: linkedAt
            )
            return acct
        }
    }

    func deleteLinkedAccount(uid: String, accountId: String) async throws {
        try await db.collection(User.collectionName)
            .document(uid)
            .collection("linkedAccounts")
            .document(accountId)
            .delete()
        KeychainService.shared.deleteAccountPassword(accountId: accountId)
    }

    // MARK: - Helpers

    private func coupleTransactions(_ coupleID: String) -> CollectionReference {
        db.collection("couples").document(coupleID).collection("transactions")
    }

    private func coupleGoals(_ coupleID: String) -> CollectionReference {
        db.collection("couples").document(coupleID).collection("goals")
    }

    // MARK: - Errors

    enum FirestoreError: LocalizedError {
        case documentNotFound
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .documentNotFound: return "문서를 찾을 수 없습니다."
            case .decodingFailed:   return "데이터 변환에 실패했습니다."
            }
        }
    }
}
