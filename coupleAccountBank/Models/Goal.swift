import SwiftData
import Foundation

enum GoalStatus: String, Codable {
    case inProgress = "진행중"
    case achieved   = "달성"
    case cancelled  = "취소"
}

@Model
final class Goal {
    var id: String
    var title: String
    var targetAmount: Double
    var currentAmount: Double
    var deadline: Date?
    var status: GoalStatus
    /// Shared couple room ID
    var coupleID: String
    var createdAt: Date
    var isSynced: Bool

    // MARK: - Computed

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(currentAmount / targetAmount, 1.0)
    }

    var remainingAmount: Double {
        max(targetAmount - currentAmount, 0)
    }

    var isAchieved: Bool { currentAmount >= targetAmount }

    // MARK: - Init

    init(
        id: String = UUID().uuidString,
        title: String,
        targetAmount: Double,
        deadline: Date? = nil,
        coupleID: String,
        isSynced: Bool = false
    ) {
        self.id = id
        self.title = title
        self.targetAmount = targetAmount
        self.currentAmount = 0
        self.deadline = deadline
        self.status = .inProgress
        self.coupleID = coupleID
        self.createdAt = .now
        self.isSynced = isSynced
    }
}
