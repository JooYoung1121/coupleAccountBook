# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**coupleAccountBank** — iOS 17+ SwiftUI 기반 부부 자산 관리 앱.
SwiftData로 로컬 저장, Firebase(Auth + Firestore)로 파트너 간 실시간 데이터 공유.

## Build & Run

```bash
# Xcode에서 열기
open coupleAccountBank.xcodeproj

# CLI 빌드
xcodebuild -project coupleAccountBank.xcodeproj \
  -scheme coupleAccountBank \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build

# 테스트
xcodebuild -project coupleAccountBank.xcodeproj \
  -scheme coupleAccountBank \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

Firebase SDK는 Swift Package Manager로 추가: `File > Add Package Dependencies > Firebase iOS SDK`
필요 패키지: `FirebaseAuth`, `FirebaseFirestore`

## Architecture (MVVM)

```
coupleAccountBank/
├── App/                        # @main, AppDelegate (Firebase 초기화)
├── Models/                     # SwiftData @Model, Codable struct
│   ├── Transaction.swift       # 수입/지출 내역
│   ├── User.swift              # Firebase 사용자 (SwiftData 미사용)
│   └── Goal.swift              # 공동 목표
├── ViewModels/                 # @Observable 또는 ObservableObject
├── Views/
│   ├── Home/
│   ├── Transaction/
│   ├── Goal/
│   └── Settings/
├── Services/
│   ├── FirebaseService.swift   # Firestore CRUD + 실시간 리스너
│   └── AuthService.swift       # Firebase Auth
└── Utilities/Extensions/
```

## Data Layer

| 레이어 | 담당 |
|---|---|
| SwiftData | `Transaction`, `Goal` 로컬 캐시. `isSynced` 플래그로 Firebase 동기화 상태 추적 |
| Firestore | `users/{uid}`, `couples/{coupleID}/transactions/{id}`, `couples/{coupleID}/goals/{id}` |
| Firebase Auth | 이메일/구글 로그인. `User.id == Firebase UID` |

**ModelContainer** 등록: `App/coupleAccountBankApp.swift`에서 `[Transaction.self, Goal.self]`

## Key Design Decisions

- `User`는 Firestore 전용 struct (로컬 SwiftData 불필요) — Auth 상태는 `AuthService`가 싱글톤으로 관리
- `coupleID`: 두 사용자가 공유하는 Firestore 룸 ID. 파트너 연결 전에는 `nil`
- `isSynced`: 오프라인 상태에서 로컬 저장 후, 네트워크 복구 시 Firestore에 업로드하기 위한 플래그
- iOS 17 전용: `@Model`, `#Preview`, `@Observable` 자유롭게 사용
