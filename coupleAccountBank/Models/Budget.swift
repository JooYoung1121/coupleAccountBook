import Foundation

struct Budget: Codable, Identifiable {
    var id: String
    var month: String          // "yyyy-MM" 형식
    var category: String       // TransactionCategory.rawValue
    var budgetAmount: Double
    var coupleID: String
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        month: String,
        category: String,
        budgetAmount: Double,
        coupleID: String
    ) {
        self.id = id
        self.month = month
        self.category = category
        self.budgetAmount = budgetAmount
        self.coupleID = coupleID
        self.createdAt = .now
    }
}
