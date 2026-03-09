import Foundation
import FirebaseFunctions

// MARK: - 기관코드 (자주 쓰는 것만)

enum BankCode: String {
    case kb      = "0004"  // 국민은행
    case shinhan = "0088"  // 신한은행
    case woori   = "0020"  // 우리은행
    case hana    = "0081"  // 하나은행
    case nh      = "0011"  // 농협
}

enum CardCode: String {
    case kb      = "0301"  // KB카드
    case shinhan = "0309"  // 신한카드
    case hyundai = "0310"  // 현대카드
    case samsung = "0311"  // 삼성카드
    case lotte   = "0313"  // 롯데카드
}

// MARK: - CODEFService

@MainActor
final class CODEFService {
    static let shared = CODEFService()
    private let functions = Functions.functions(region: "asia-northeast3")

    private init() {}

    // MARK: - 금융기관 계정 연결

    /// 은행 또는 카드사 계정을 CODEF에 연결하고 connectedId를 발급받습니다.
    /// - Parameters:
    ///   - organization: 기관코드 (예: "0004")
    ///   - businessType: "BK"(은행) 또는 "CD"(카드)
    ///   - id: 인터넷뱅킹 아이디
    ///   - password: 인터넷뱅킹 비밀번호
    func connectAccount(
        organization: String,
        businessType: String,
        id: String,
        password: String
    ) async throws -> String {
        let data: [String: Any] = [
            "organization": organization,
            "businessType": businessType,
            "loginType": "0",
            "id": id,
            "password": password
        ]
        let result = try await functions
            .httpsCallable("createCodefAccount")
            .call(data)

        guard let dict = result.data as? [String: Any],
              let connectedId = dict["connectedId"] as? String else {
            throw CODEFError.invalidResponse
        }
        return connectedId
    }

    // MARK: - 카드 승인내역 조회

    func fetchCardTransactions(
        organization: String,
        startDate: String,
        endDate: String
    ) async throws -> [[String: Any]] {
        let data: [String: Any] = [
            "organization": organization,
            "startDate": startDate,
            "endDate": endDate
        ]
        let result = try await functions
            .httpsCallable("fetchCardTransactions")
            .call(data)

        guard let dict = result.data as? [String: Any],
              let list = dict["data"] as? [[String: Any]] else {
            return []
        }
        return list
    }

    // MARK: - 은행 입출금 내역 조회

    func fetchBankTransactions(
        organization: String,
        accountNumber: String,
        startDate: String,
        endDate: String
    ) async throws -> [[String: Any]] {
        let data: [String: Any] = [
            "organization": organization,
            "accountNumber": accountNumber,
            "startDate": startDate,
            "endDate": endDate
        ]
        let result = try await functions
            .httpsCallable("fetchBankTransactions")
            .call(data)

        guard let dict = result.data as? [String: Any],
              let list = dict["data"] as? [[String: Any]] else {
            return []
        }
        return list
    }

    // MARK: - 날짜 포맷 헬퍼

    /// Date → CODEF 날짜 포맷 "yyyyMMdd"
    static func codefDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    // MARK: - Errors

    enum CODEFError: LocalizedError {
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "CODEF 응답을 파싱할 수 없습니다."
            }
        }
    }
}
