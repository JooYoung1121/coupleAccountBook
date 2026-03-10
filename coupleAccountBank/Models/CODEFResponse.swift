import Foundation
import CryptoKit

// MARK: - 은행 계좌 응답

struct CODEFBankAccountResponse: Decodable {
    let resAccount: String
    let resAccountDisplay: String?
    let resAccountBalance: String?
    let resAccountHolder: String?
    let resAccountName: String?
    let resManagementBranch: String?
    let resTrHistoryList: [CODEFBankTransaction]?
}

// MARK: - 은행 거래내역 항목

struct CODEFBankTransaction: Decodable {
    let resAccountTrDate: String      // "20190601"
    let resAccountTrTime: String?     // "004219"
    let resAccountIn: String          // 입금액 (문자열)
    let resAccountOut: String         // 출금액 (문자열)
    let resAfterTranBalance: String?  // 거래 후 잔액
    let resAccountDesc1: String?
    let resAccountDesc2: String?      // 주 적요 (가장 유의미)
    let resAccountDesc3: String?
    let resAccountDesc4: String?      // 지점명 등

    // MARK: - 파생 값

    var amount: Double {
        let inAmt = Double(resAccountIn) ?? 0
        let outAmt = Double(resAccountOut) ?? 0
        return inAmt > 0 ? inAmt : outAmt
    }

    var transactionType: TransactionType {
        (Double(resAccountIn) ?? 0) > 0 ? .income : .expense
    }

    var description: String {
        // desc2가 가장 의미있는 내용 (이자원가, 이체 등)
        [resAccountDesc2, resAccountDesc1, resAccountDesc3]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .first ?? "은행 거래"
    }

    var date: Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.date(from: resAccountTrDate) ?? .now
    }

    // MARK: - Transaction 변환

    /// 중복 저장 방지를 위한 고정 ID (계좌+일시+금액+적요 기반)
    func stableId(account: String) -> String {
        let raw = "\(account)_\(resAccountTrDate)_\(resAccountTrTime ?? "")_\(amount)_\(description)"
        let data = Data(raw.utf8)
        let hash = SHA256.hash(data: data)
        let hex = hash.prefix(16).map { String(format: "%02x", $0) }.joined()
        return "bank_\(hex)"
    }

    func toTransaction(ownerID: String, coupleID: String, accountNumber: String) -> Transaction {
        Transaction(
            id: stableId(account: accountNumber),
            amount: amount,
            type: transactionType,
            category: inferCategory(),
            note: description,
            date: date,
            ownerID: ownerID,
            coupleID: coupleID,
            isSynced: true
        )
    }

    private func inferCategory() -> TransactionCategory {
        let text = description.lowercased()
        if text.contains("이자") { return .savings }
        if text.contains("급여") || text.contains("월급") { return .other }
        if text.contains("편의") || text.contains("마트") || text.contains("식") { return .food }
        if text.contains("교통") || text.contains("버스") || text.contains("지하철") { return .transport }
        if text.contains("병원") || text.contains("약") || text.contains("의료") { return .health }
        if text.contains("학") || text.contains("교육") { return .education }
        return .other
    }
}

// MARK: - 파싱 헬퍼

extension CODEFBankAccountResponse {
    static func from(dict: [String: Any]) -> CODEFBankAccountResponse? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let decoded = try? JSONDecoder().decode(CODEFBankAccountResponse.self, from: data) else {
            return nil
        }
        return decoded
    }
}

extension CODEFBankTransaction {
    static func from(dict: [String: Any]) -> CODEFBankTransaction? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let decoded = try? JSONDecoder().decode(CODEFBankTransaction.self, from: data) else {
            return nil
        }
        return decoded
    }
}
