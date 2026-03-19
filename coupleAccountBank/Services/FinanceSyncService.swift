import Foundation
import FirebaseAuth

/// 앱 실행 시 한 번, 연동된 은행/카드에서 최근 거래를 자동으로 가져옵니다.
/// 이후에는 설정 > 금융 연동에서 수동 "가져오기"만 사용합니다.
@MainActor
final class FinanceSyncService {
    static let shared = FinanceSyncService()

    /// 세션당 1회만 실행 (앱 프로세스 기준)
    private var didPerformLaunchFetchThisSession = false

    private init() {}

    /// 로그인 후 메인 탭 진입 시 호출. uid/coupleID/userName이 있으면 연동 계정 기준으로 1회 fetch.
    func performLaunchFetchIfNeeded(uid: String?, coupleID: String?, userName: String?) async {
        guard let uid = uid, let coupleID = coupleID, !uid.isEmpty, !coupleID.isEmpty else { return }
        if didPerformLaunchFetchThisSession { return }
        didPerformLaunchFetchThisSession = true
        await performFetch(uid: uid, coupleID: coupleID, userName: userName ?? "사용자")
    }

    /// 등록된 연동 계정 기준으로 최근 1개월 내역을 가져옵니다. 내역 탭 등에서 수동 호출용.
    func performManualFetch(uid: String?, coupleID: String?, userName: String?) async {
        guard let uid = uid, let coupleID = coupleID, !uid.isEmpty, !coupleID.isEmpty else { return }
        await performFetch(uid: uid, coupleID: coupleID, userName: userName ?? "사용자")
    }

    private func performFetch(uid: String, coupleID: String, userName: String) async {
        let accounts: [LinkedAccount]
        do {
            accounts = try await FirebaseService.shared.fetchLinkedAccounts(uid: uid)
        } catch {
            return
        }
        if accounts.isEmpty { return }

        let (start, end) = defaultDateRange()
        let bankAccounts = accounts.filter(\.isBank)
        let cardAccounts = accounts.filter(\.isCard)

        if let firstBank = bankAccounts.first,
           let accountNumber = firstBank.accountNumber, !accountNumber.isEmpty {
            let password = firstBank.accountPassword ?? ""
            do {
                let list = try await CODEFService.shared.fetchBankTransactions(
                    organization: firstBank.organization,
                    account: accountNumber,
                    startDate: start,
                    endDate: end,
                    accountPassword: password,
                    connectedIdOverride: firstBank.connectedId
                )
                _ = try await FirebaseService.shared.deleteAllImportedTransactions(coupleID: coupleID)

                // 가장 최근 거래(index 0)의 resAfterTranBalance를 잔액으로 저장
                if let firstItem = list.first,
                   let tx = CODEFBankTransaction.from(dict: firstItem),
                   let balanceStr = tx.resAfterTranBalance,
                   let balance = Double(balanceStr), balance > 0 {
                    try? await FirebaseService.shared.updateLinkedAccountBalance(
                        uid: uid, accountId: firstBank.id, balance: balance
                    )
                }

                for item in list {
                    guard let tx = CODEFBankTransaction.from(dict: item) else { continue }
                    let t = tx.toTransaction(ownerID: uid, ownerName: userName, coupleID: coupleID, accountNumber: accountNumber)
                    try? await FirebaseService.shared.saveTransaction(t)
                }
            } catch {
                // 은행 fetch 실패 시 다음 계속
            }
        }

        for acct in cardAccounts {
            do {
                let list = try await CODEFService.shared.fetchCardTransactions(
                    organization: acct.organization,
                    startDate: start,
                    endDate: end,
                    connectedIdOverride: acct.connectedId
                )
                for item in list {
                    guard let approval = CODEFCardApproval.from(dict: item) else { continue }
                    let t = approval.toTransaction(ownerID: uid, ownerName: userName, coupleID: coupleID, cardOrg: acct.organization)
                    try? await FirebaseService.shared.saveTransaction(t)
                }
            } catch {
                // 카드별 실패 시 다음 카드 계속
            }
        }
    }

    private func defaultDateRange() -> (String, String) {
        let now = Date()
        let start = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return (f.string(from: start), f.string(from: now))
    }
}
