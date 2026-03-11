# CODEF 연동 및 앱 구조 가이드

## 0. 데모/실제 데이터 테스트 절차 (요약)

실제 금융 데이터로 테스트하려면 아래 순서로 진행하면 됩니다.

1. **CODEF 가입 및 API 키**  
   [codef.io](https://codef.io)에서 사업자/개인 등록 후 **Client ID**, **Client Secret**, **공개키** 발급

2. **Firebase Secrets 설정**
   ```bash
   cd functions
   firebase functions:secrets:set CODEF_CLIENT_ID
   firebase functions:secrets:set CODEF_CLIENT_SECRET
   firebase functions:secrets:set CODEF_PUBLIC_KEY
   ```
   (각각 프롬프트에 따라 발급받은 값 입력)

3. **실제 API 모드로 Functions 배포**  
   `functions/` 디렉터리에 `.env` 파일 생성 후:
   ```bash
   echo "CODEF_MODE=production" > .env
   firebase deploy --only functions
   ```
   데모용만 쓰려면 `CODEF_MODE=development`로 설정.

4. **앱에서 연동**  
   앱 실행 → 로그인 → **설정 → 금융 연동**에서 은행/카드별로 인터넷뱅킹 ID·비밀번호로 "계정 연결하기" 후, "은행 내역 가져오기" / "카드 내역 가져오기"로 기간 선택해 수동 조회.  
   **앱 실행 시**에는 최근 1개월 구간으로 자동 1회 fetch 되고, 이후에는 수동 가져오기만 사용.

| 모드 | CODEF_MODE | 용도 |
|------|------------|------|
| 샌드박스(기본) | `sandbox` | 고정 응답 테스트, 키 없이 동작 |
| 데모 | `development` | CODEF 데모 계정으로 실제 연동 테스트 |
| 실제 | `production` | 실제 은행/카드 계정 연동 |

---

## 1. CODEF 환경 전환 (Sandbox → 데모/실제)

### 현재 상태
- **기본값**: `CODEF_MODE=sandbox` → `https://sandbox.codef.io` 사용
- 샌드박스에서는 실제 금융 연동 없이 고정 응답으로 테스트 가능

### 데모/실제 데이터 모드로 전환하는 방법

**방법 A – .env 파일 (권장)**  
`functions/` 폴더에 `.env` 또는 `.env.<프로젝트ID>` 파일을 만들고 다음 한 줄을 추가합니다.

```
CODEF_MODE=development
```
또는
```
CODEF_MODE=production
```

저장 후 `firebase deploy --only functions`로 배포하면 해당 환경으로 동작합니다.  
값을 넣지 않으면 배포 시 CLI가 물어보고, 입력한 값은 `.env.<projectId>`에 저장됩니다.

**방법 B – 배포 시 프롬프트**  
`.env`에 `CODEF_MODE`를 넣지 않으면, 배포 시 "CODEF_MODE에 넣을 값"을 묻습니다.  
그때 `development` 또는 `production`을 입력하면 됩니다.

**주의**
- **데모(development)**: CODEF 개발자센터에서 발급한 데모용 Client ID/Secret 사용
- **실제(production)**: 실제 서비스용 Client ID/Secret + 공개키 사용
- 시크릿은 환경별로 동일한 이름(`CODEF_CLIENT_ID` 등)을 쓰고, 값만 환경마다 다르게 넣으면 됨

---

## 2. 구조·설정 점검 (체크리스트)

### ✅ 이미 잘 되어 있는 부분
- Firebase Auth(Apple 로그인) + Firestore DB 분리
- CODEF 비밀번호 RSA 암호화 후 전송
- `createCodefAccount` 성공 시 `connectedId`를 Firestore `users/{uid}`에 저장
- 은행/카드 Functions에서 `connectedId`는 Firestore에서 조회 (테스트 시 override 가능)
- SwiftData + Firestore 하이브리드 구조 (거래/목표는 `coupleID` 기준)

### ⚠️ 수정·보완한 부분
1. **은행 입출금 응답 파싱**  
   CODEF 응답이 `data.resTrHistoryList` 배열인데, 클라이언트가 `data`를 배열로 기대하던 문제를 수정함.  
   → `CODEFService.fetchBankTransactions`에서 `data.resTrHistoryList`를 사용하도록 변경됨.

2. **CODEF 환경 전환**  
   하드코딩된 `CODEF_API_BASE` 제거 후, `CODEF_MODE`(params)로 sandbox/development/production 전환 가능하도록 수정함.

3. **카드 API 응답**  
   Sandbox에서 URL-encoded 문자열로 오는 경우를 대비해, Functions에서 디코딩 후 반환하도록 수정함.

### 🔶 추가로 확인하면 좋은 것
- **coupleID 미설정**  
  현재 사용자–커플 매칭(파트너 초대 등)이 없어 `coupleID`가 비어 있을 수 있음.  
  거래/목표를 Firestore에 쓸 때는 `coupleID`가 필수이므로, “커플 연결” 플로우를 만들기 전에는  
  - 단일 사용자용으로 임시 `coupleID = uid` 같은 값을 쓰거나,  
  - `listenToTransactions`/목표 리스트를 호출하는 쪽에서 `coupleID == nil`일 때 처리(빈 목록 등)를 해 두는 것이 좋음.

- **카드 응답 구조**  
  카드 승인내역 API는 은행과 필드가 다름.  
  실제 응답이 `data` 배열인지, `data.approvalList` 같은 중첩인지 한 번 로그로 확인한 뒤,  
  필요하면 Swift에서 은행과 같이 `data.xxx` 형태로 리스트를 추출하는 파싱을 추가하면 됨.

- **CODEFTestView**  
  개발용 테스트 화면이므로, 배포 앱에서는 설정 메뉴를 빌드 플래그로 숨기거나 제거하는 편이 좋음.

- **에러 메시지**  
  Functions에서 `HttpsError("internal", message)`로 던진 메시지가 iOS에서 그대로 노출되는지 확인해 두면,  
  CODEF/토큰 오류 시 사용자에게 안내하기 좋음.

---

## 3. 은행 입출금 내역 → 화면에 띄우기

### 3.1 데이터 흐름
1. **CODEF**  
   `fetchBankTransactions`(또는 Raw) 호출 → `data.resTrHistoryList` 배열 수신.
2. **모델 변환**  
   `CODEFBankTransaction` → `Transaction`  
   (이미 `CODEFResponse.swift`에 `toTransaction(ownerID:coupleID:)` 있음).
3. **표시**  
   - **A) Firestore 동기화**  
     변환한 `Transaction`을 Firestore에 저장 → 기존 `TransactionListView`가 `listenToTransactions`로 표시.  
     중복 방지를 위해 “거래일시+금액+적요” 등으로 키를 만들어 한 번만 저장하는 로직이 있으면 좋음.  
   - **B) CODEF만 표시**  
     가져온 리스트를 로컬에서만 보여주는 전용 화면(예: “은행 내역”)을 하나 두고,  
     이번에 가져온 `[CODEFBankTransaction]` 또는 `[Transaction]`을 리스트로만 표시.

### 3.2 화면 구성 제안 (내역 탭)

- **탭: “내역”**
  - **상단**  
    - “은행 내역 가져오기” 버튼 (기관/계좌/기간 선택 후 CODEF 호출).
  - **리스트**
    - Firestore에 저장된 거래 + (선택) 이번에 가져온 은행 내역을 합쳐서 표시.  
    - 셀 내용: **날짜**, **적요(메모)**, **금액**(수입/지출 색 구분), **카테고리**.
  - **정렬**  
    - 날짜 내림차순(최신 먼저).
  - **필터(선택)**  
    - 수입/지출, 기간, 카테고리.

즉, “내역”은 **Firestore 기반 리스트**를 메인으로 두고,  
“은행 내역 가져오기”로 CODEF 데이터를 가져와서 Firestore에 병합(중복 제거 후)해 두면,  
기존 `TransactionListView`만 확장해서도 구현 가능함.

### 3.3 구현 시 필요한 것
- `TransactionListView`에서  
  - `FirebaseService.listenToTransactions(coupleID:onChange:)` 사용  
  - (또는 임시로) `coupleID`가 없을 때는 빈 배열 등 처리.
- “은행 내역 가져오기” 플로우  
  - connectedId/계좌/기간 입력(또는 설정에 저장된 값 사용)  
  - `CODEFService.fetchBankTransactions` 호출  
  - `CODEFBankAccountResponse.from(dict:)` / `resTrHistoryList` → `toTransaction` → Firestore 저장.
- 거래 셀 UI  
  - `Transaction`의 `date`, `note`, `amount`, `type`, `category` 표시.

---

## 4. 카드 결제(승인) 내역 받아오기

### 4.1 현재 구현 상태
- **Functions**  
  `fetchCardTransactions` (카드 승인내역) 이미 구현됨.  
  `connectedId` + `organization`(카드사 코드) + `startDate`/`endDate`로 호출.
- **Swift**  
  `CODEFService.fetchCardTransactions(organization:startDate:endDate:)`로 호출 가능.  
  반환은 `[[String: Any]]`로 기대하고 있음.  
  실제 CODEF 응답이 `data`가 배열이면 그대로 쓰면 되고,  
  `data.list` 같은 구조면 은행처럼 `data.xxx`에서 배열을 꺼내서 반환하도록 한 번만 수정하면 됨.

### 4.2 카드사 연결
- 카드도 **계정 연결**이 필요함.  
  같은 `createCodefAccount`에 `businessType: "CD"`, `organization`: 카드사 코드(예: `0309` 신한카드)로  
  **별도로 한 번 더** 연결하면, 같은 `connectedId`에 카드가 추가되거나,  
  문서에 따라 카드용 connectedId가 따로 발급될 수 있음.  
  CODEF 가이드에서 “카드 계정 추가” 절차를 확인하는 것이 좋음.
- 연결 후에는 `fetchCardTransactions`에  
  `organization`: 카드사 코드, `startDate`/`endDate`: 조회 기간(yyyyMMdd)을 넘기면 됨.

### 4.3 카드 전용 모델/화면
- 카드 승인내역 필드는 은행과 다름(승인일시, 가맹점명, 승인금액 등).  
  CODEF 개발자 문서에서 응답 스키마를 확인한 뒤,  
  `CODEFCardApproval` 같은 모델을 만들고,  
  필요하면 `Transaction`과 매핑하거나 “카드 내역” 전용 리스트로만 표시할 수 있음.
- “내역” 탭에서 “은행 / 카드” 탭을 나누거나,  
  설정에 “카드 내역 가져오기”를 추가해 기간 선택 후 `fetchCardTransactions` 호출 → 리스트 표시하면 됨.

### 4.4 요약
- **받아오기**: 이미 가능. `CODEFService.fetchCardTransactions` + 기간/카드사 코드.
- **연결**: `createCodefAccount`에 업종 `CD`, organization에 카드사 코드로 한 번 더 연결.
- **화면**: 카드 API 응답 구조 확인 후 모델 정의 → “카드 내역” 리스트 화면 또는 “내역” 탭에 카드 섹션 추가.

---

### 4.5 카드사 코드 (CODEF 공식)
카드 API 및 카드사 코드는 [CODEF 카드 API 개요](https://developer.codef.io/products/card/overview)에서 확인.  
앱에 반영된 코드 예: 신한카드 0306, 우리카드 0309, 삼성카드 0303, KB카드 0301, 현대카드 0302, 롯데카드 0311, 하나카드 0313.

---

## 5. 참고 – CODEF 환경별 URL

| 모드        | URL                     | 용도                 |
|------------|-------------------------|----------------------|
| sandbox    | https://sandbox.codef.io | 고정 응답 테스트     |
| development| https://development.codef.io | 데모 계정 연동 테스트 |
| production | https://api.codef.io     | 실제 서비스          |

토큰 발급(`CODEF_TOKEN_URL`)은 환경과 관계없이 `https://oauth.codef.io/oauth/token`을 그대로 사용하면 됨.
