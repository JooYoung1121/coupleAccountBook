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
    var coupleID: String
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
    private let db = Firestore.firestore()

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
            "coupleID": t.coupleID
        ]
        try await coupleTransactions(t.coupleID).document(t.id).setData(data)
    }

    func deleteTransaction(id: String, coupleID: String) async throws {
        try await coupleTransactions(coupleID).document(id).delete()
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
