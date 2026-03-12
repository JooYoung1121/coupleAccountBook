const { setGlobalOptions } = require("firebase-functions");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { defineString } = require("firebase-functions/params");
const admin = require("firebase-admin");
const { getFirestore } = require("firebase-admin/firestore");
const axios = require("axios");
const crypto = require("crypto");

admin.initializeApp();
setGlobalOptions({ maxInstances: 10, region: "asia-northeast3" });

const db = getFirestore(admin.app(), "coupleaccountbankdb");

// MARK: - Secrets
const CODEF_CLIENT_ID = defineSecret("CODEF_CLIENT_ID");
const CODEF_CLIENT_SECRET = defineSecret("CODEF_CLIENT_SECRET");
const CODEF_PUBLIC_KEY = defineSecret("CODEF_PUBLIC_KEY");

// MARK: - CODEF 환경 전환 (앱 설정 없이 배포 시에만 변경)
// .env 또는 firebase functions:config:set params.CODEF_MODE=production
// 값: sandbox | development | production
const CODEF_MODE = defineString("CODEF_MODE", { default: "sandbox" });

const CODEF_API_BASES = {
  sandbox: "https://sandbox.codef.io",
  development: "https://development.codef.io",
  production: "https://api.codef.io",
};

function getCodefApiBase() {
  const mode = (CODEF_MODE.value() || "sandbox").toLowerCase();
  return CODEF_API_BASES[mode] || CODEF_API_BASES.sandbox;
}

// MARK: - CODEF 설정
// SANDBOX: 아무 ID/PW로 고정 응답 테스트 가능
// DEMO:    development.codef.io — CODEF 제공 실제 테스트 계정 필요
// PROD:    api.codef.io — 실제 은행 계정
const CODEF_TOKEN_URL = "https://oauth.codef.io/oauth/token";

// MARK: - 토큰 발급
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

// MARK: - RSA 비밀번호 암호화 (데모버전 필수)
function encryptPassword(password, publicKeyBase64) {
  const pem = `-----BEGIN PUBLIC KEY-----\n${publicKeyBase64}\n-----END PUBLIC KEY-----`;
  const buffer = Buffer.from(password, "utf8");
  const encrypted = crypto.publicEncrypt(
    { key: pem, padding: crypto.constants.RSA_PKCS1_PADDING },
    buffer
  );
  return encrypted.toString("base64");
}

// MARK: - 금융기관 계정 연결 (connectedId 발급) — ID/PW 또는 인증서
exports.createCodefAccount = onCall(
  { secrets: [CODEF_CLIENT_ID, CODEF_CLIENT_SECRET, CODEF_PUBLIC_KEY], invoker: "public" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");

    const { organization, businessType, loginType, id, password, derFile } = request.data;
    const isCertificate = (loginType || "1") === "0";

    if (!organization) {
      throw new HttpsError("invalid-argument", "organization이 필요합니다.");
    }
    if (isCertificate) {
      if (!derFile || typeof derFile !== "string") {
        throw new HttpsError("invalid-argument", "인증서(derFile)가 필요합니다.");
      }
      if (!password || typeof password !== "string") {
        throw new HttpsError("invalid-argument", "인증서 비밀번호가 필요합니다.");
      }
    } else {
      if (!id || !password) {
        throw new HttpsError("invalid-argument", "organization, id, password가 필요합니다.");
      }
    }

    let encryptedPassword;
    try {
      const pubKey = CODEF_PUBLIC_KEY.value();
      encryptedPassword = encryptPassword(password, pubKey);
    } catch (err) {
      console.error("RSA 암호화 실패:", err.message);
      throw new HttpsError("internal", `RSA 암호화 실패: ${err.message}`);
    }

    let token;
    try {
      token = await getCodefToken(CODEF_CLIENT_ID.value(), CODEF_CLIENT_SECRET.value());
    } catch (err) {
      console.error("토큰 발급 실패:", err.message);
      throw new HttpsError("internal", `토큰 발급 실패: ${err.message}`);
    }

    const apiBase = getCodefApiBase();
    const accountPayload = {
      countryCode: "KR",
      businessType: businessType ?? "BK",
      clientType: "P",
      organization,
      loginType: isCertificate ? "0" : "1",
      password: encryptedPassword,
    };
    if (isCertificate) {
      accountPayload.derFile = derFile;
      accountPayload.id = id || "";
    } else {
      accountPayload.id = id;
    }

    let decoded;
    try {
      const response = await axios.post(
        `${apiBase}/v1/account/create`,
        { accountList: [accountPayload] },
        { headers: { Authorization: `Bearer ${token}` } }
      );
      const raw = response.data;
      decoded = typeof raw === "string" ? JSON.parse(decodeURIComponent(raw)) : raw;
      console.log("createCodefAccount CODEF response:", JSON.stringify(decoded));
    } catch (err) {
      if (err.response) {
        throw new HttpsError("internal", JSON.stringify(err.response.data));
      }
      throw new HttpsError("internal", err.message);
    }

    const connectedId = decoded?.data?.connectedId;
    if (!connectedId) {
      throw new HttpsError("internal", `계정 연결 실패: ${JSON.stringify(decoded)}`);
    }

    if (request.auth) {
      await db
        .collection("users")
        .doc(request.auth.uid)
        .set({ connectedId }, { merge: true });
    }

    return { connectedId };
  }
);

// MARK: - 카드 승인내역 조회
exports.fetchCardTransactions = onCall(
  { secrets: [CODEF_CLIENT_ID, CODEF_CLIENT_SECRET], invoker: "public" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");

    const { organization, startDate, endDate, connectedIdOverride } = request.data;
    const uid = request.auth.uid;
    console.log("fetchCardTransactions called:", { uid, organization, startDate, endDate, connectedIdOverride });

    let connectedId = connectedIdOverride;
    if (!connectedId) {
      const userDoc = await db.collection("users").doc(uid).get();
      connectedId = userDoc.data()?.connectedId;
      console.log("fetchCardTransactions connectedId from DB:", connectedId);
    }
    if (!connectedId) throw new HttpsError("failed-precondition", "금융기관 계정 연결이 필요합니다.");

    console.log("fetchCardTransactions using connectedId:", connectedId);

    const token = await getCodefToken(
      CODEF_CLIENT_ID.value(),
      CODEF_CLIENT_SECRET.value()
    );
    console.log("fetchCardTransactions token obtained, length:", token?.length);

    try {
      const apiBase = getCodefApiBase();
      const requestBody = { connectedId, organization, startDate, endDate, orderBy: "0", inquiryType: "1" };
      console.log("fetchCardTransactions request:", apiBase, JSON.stringify(requestBody));
      const response = await axios.post(
        `${apiBase}/v1/kr/card/p/account/approval-list`,
        requestBody,
        { headers: { Authorization: `Bearer ${token}` } }
      );
      const raw = response.data;
      console.log("fetchCardTransactions raw response type:", typeof raw);
      const decoded = typeof raw === "string"
        ? JSON.parse(decodeURIComponent(raw))
        : raw;
      console.log("fetchCardTransactions result code:", decoded?.result?.code, "message:", decoded?.result?.message);
      console.log("fetchCardTransactions full response:", JSON.stringify(decoded).substring(0, 2000));
      return decoded;
    } catch (err) {
      console.error("fetchCardTransactions error:", err.message);
      if (err.response) {
        console.error("Card error status:", err.response.status);
        console.error("Card error response:", JSON.stringify(err.response.data));
        throw new HttpsError("internal", JSON.stringify(err.response.data));
      }
      throw new HttpsError("internal", err.message);
    }
  }
);

// MARK: - 은행 입출금 내역 조회
exports.fetchBankTransactions = onCall(
  { secrets: [CODEF_CLIENT_ID, CODEF_CLIENT_SECRET, CODEF_PUBLIC_KEY], invoker: "public" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    console.log("fetchBankTransactions called, auth:", request.auth.uid);

    const {
      organization,
      account,
      startDate,
      endDate,
      accountPassword = "",
      birthDate = "",
      inquiryType = "1",
      connectedIdOverride,   // 테스트용 수동 connectedId
    } = request.data;
    const uid = request.auth.uid;

    // connectedId: 수동 입력 우선, 없으면 Firestore에서 조회
    let connectedId = connectedIdOverride;
    if (!connectedId) {
      const userDoc = await db.collection("users").doc(uid).get();
      connectedId = userDoc.data()?.connectedId;
    }
    if (!connectedId) throw new HttpsError("failed-precondition", "금융기관 계정 연결이 필요합니다.");

    const token = await getCodefToken(
      CODEF_CLIENT_ID.value(),
      CODEF_CLIENT_SECRET.value()
    );

    // 계좌 비밀번호 RSA 암호화 (있을 경우)
    const encryptedAccountPassword = accountPassword
      ? encryptPassword(accountPassword, CODEF_PUBLIC_KEY.value())
      : "";

    try {
      const apiBase = getCodefApiBase();
      const response = await axios.post(
        `${apiBase}/v1/kr/bank/p/account/transaction-list`,
        {
          connectedId,
          organization,
          account,
          startDate,
          endDate,
          orderBy: "0",
          inquiryType,
          accountPassword: encryptedAccountPassword,
          birthDate,
        },
        { headers: { Authorization: `Bearer ${token}` } }
      );
      console.log("CODEF status:", response.status);
      // CODEF 개발 API는 URL-encoded 문자열로 응답함 → JSON으로 디코딩
      const raw = response.data;
      const decoded = typeof raw === "string"
        ? JSON.parse(decodeURIComponent(raw))
        : raw;
      console.log("CODEF decoded result code:", decoded?.result?.code);
      if (!decoded) {
        throw new HttpsError("internal", "CODEF가 빈 응답을 반환했습니다.");
      }
      return decoded;
    } catch (err) {
      if (err.response) {
        console.error("CODEF error response:", JSON.stringify(err.response.data));
        throw new HttpsError("internal", JSON.stringify(err.response.data));
      }
      throw new HttpsError("internal", err.message);
    }
  }
);
