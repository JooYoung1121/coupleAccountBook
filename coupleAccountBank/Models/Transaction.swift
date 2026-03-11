import SwiftData
import Foundation

enum TransactionType: String, Codable {
    case income = "수입"
    case expense = "지출"
}

enum TransactionCategory: String, Codable, CaseIterable {
    case food         = "식비"
    case transport    = "교통"
    case housing      = "주거"
    case shopping     = "쇼핑"
    case entertainment = "여가"
    case health       = "의료/건강"
    case education    = "교육"
    case savings      = "저축"
    case other        = "기타"

    var systemImage: String {
        switch self {
        case .food:          return "fork.knife"
        case .transport:     return "car.fill"
        case .housing:       return "house.fill"
        case .shopping:      return "bag.fill"
        case .entertainment: return "gamecontroller.fill"
        case .health:        return "cross.fill"
        case .education:     return "book.fill"
        case .savings:       return "banknote.fill"
        case .other:         return "ellipsis.circle.fill"
        }
    }
}

@Model
final class Transaction {
    var id: String
    var amount: Double
    var type: TransactionType
    var category: TransactionCategory
    var note: String
    var date: Date
    /// Firebase UID of the member who recorded this transaction
    var ownerID: String
    /// 거래를 기록한 사용자 이름 (커플 공유 시 구분용)
    var ownerName: String
    /// Shared couple room ID (used as Firestore document path prefix)
    var coupleID: String
    var isSynced: Bool
    /// CODEF 등 외부에서 가져온 거래 여부 (true이면 금액/날짜 수정 불가)
    var isImported: Bool
    /// 사용자가 추가로 남기는 메모 (가져온 거래에도 자유롭게 작성 가능)
    var userMemo: String

    init(
        id: String = UUID().uuidString,
        amount: Double,
        type: TransactionType,
        category: TransactionCategory,
        note: String = "",
        date: Date = .now,
        ownerID: String,
        ownerName: String = "",
        coupleID: String,
        isSynced: Bool = false,
        isImported: Bool = false,
        userMemo: String = ""
    ) {
        self.id = id
        self.amount = amount
        self.type = type
        self.category = category
        self.note = note
        self.date = date
        self.ownerID = ownerID
        self.ownerName = ownerName
        self.coupleID = coupleID
        self.isSynced = isSynced
        self.isImported = isImported
        self.userMemo = userMemo
    }
}
