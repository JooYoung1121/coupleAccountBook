const { setGlobalOptions } = require("firebase-functions");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const axios = require("axios");

admin.initializeApp();
setGlobalOptions({ maxInstances: 10, region: "asia-northeast3" });

// MARK: - Secrets (Google Secret Manager에 저장)
const CODEF_CLIENT_ID = defineSecret("CODEF_CLIENT_ID");
const CODEF_CLIENT_SECRET = defineSecret("CODEF_CLIENT_SECRET");

// MARK: - CODEF 설정
// 샌드박스 테스트 완료 후 "https://codef.io"로 변경
const CODEF_API_BASE = "https://sandbox.codef.io";
const CODEF_TOKEN_URL = "https://oauth.codef.io/oauth/token";

// MARK: - 토큰 발급 (내부 헬퍼)
async function getCodefToken(clientId, clientSecret) {
  const credentials = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");
  const response = await axios.post(
    CODEF_TOKEN_URL,
    "grant_type=client_credentials&scope=read",
    {
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Authorization: `Basic ${credentials}`,
      },
    }
  );
  return response.data.access_token;
}

// MARK: - 금융기관 계정 연결 (connectedId 발급)
// iOS에서 호출: FirebaseFunctions.functions().httpsCallable("createCodefAccount")
// 요청 데이터: { organization: "0301", loginType: "0", id: "...", password: "..." }
exports.createCodefAccount = onCall(
  { secrets: [CODEF_CLIENT_ID, CODEF_CLIENT_SECRET] },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");

    const { organization, businessType, loginType, id, password } = request.data;
    if (!organization || !id || !password) {
      throw new HttpsError("invalid-argument", "organization, id, password가 필요합니다.");
    }

    const token = await getCodefToken(
      CODEF_CLIENT_ID.value(),
      CODEF_CLIENT_SECRET.value()
    );

    const response = await axios.post(
      `${CODEF_API_BASE}/v1/account/create`,
      {
        accountList: [{
          countryCode: "KR",
          businessType: businessType ?? "BK",  // BK: 은행, CD: 카드
          clientType: "P",                      // P: 개인
          organization,
          loginType: loginType ?? "0",          // 0: ID/PW, 1: 인증서
          id,
          password,
        }],
      },
      { headers: { Authorization: `Bearer ${token}` } }
    );

    const connectedId = response.data.data?.connectedId;
    if (!connectedId) {
      throw new HttpsError("internal", `계정 연결 실패: ${JSON.stringify(response.data)}`);
    }

    // Firestore users/{uid}에 connectedId 저장
    await admin.firestore()
      .collection("users")
      .doc(request.auth.uid)
      .set({ connectedId }, { merge: true });

    return { connectedId };
  }
);

// MARK: - 카드 승인내역 조회
// 요청 데이터: { organization: "0301", startDate: "20250101", endDate: "20250228" }
exports.fetchCardTransactions = onCall(
  { secrets: [CODEF_CLIENT_ID, CODEF_CLIENT_SECRET] },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");

    const { organization, startDate, endDate } = request.data;
    const uid = request.auth.uid;

    const userDoc = await admin.firestore().collection("users").doc(uid).get();
    const connectedId = userDoc.data()?.connectedId;
    if (!connectedId) throw new HttpsError("failed-precondition", "금융기관 계정 연결이 필요합니다.");

    const token = await getCodefToken(
      CODEF_CLIENT_ID.value(),
      CODEF_CLIENT_SECRET.value()
    );

    const response = await axios.post(
      `${CODEF_API_BASE}/v1/kr/card/p/account/approval-list`,
      { connectedId, organization, startDate, endDate },
      { headers: { Authorization: `Bearer ${token}` } }
    );

    return response.data;
  }
);

// MARK: - 은행 입출금 내역 조회
// 요청 데이터: { organization: "0004", accountNumber: "...", startDate: "20250101", endDate: "20250228" }
exports.fetchBankTransactions = onCall(
  { secrets: [CODEF_CLIENT_ID, CODEF_CLIENT_SECRET] },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");

    const { organization, accountNumber, startDate, endDate } = request.data;
    const uid = request.auth.uid;

    const userDoc = await admin.firestore().collection("users").doc(uid).get();
    const connectedId = userDoc.data()?.connectedId;
    if (!connectedId) throw new HttpsError("failed-precondition", "금융기관 계정 연결이 필요합니다.");

    const token = await getCodefToken(
      CODEF_CLIENT_ID.value(),
      CODEF_CLIENT_SECRET.value()
    );

    const response = await axios.post(
      `${CODEF_API_BASE}/v1/kr/bank/p/account/transaction-list`,
      { connectedId, organization, accountNumber, startDate, endDate, orderBy: "0" },
      { headers: { Authorization: `Bearer ${token}` } }
    );

    return response.data;
  }
);
