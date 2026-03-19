//
//  ContentView.swift
//  coupleAccountBank
//
//  Created by JooYoung Kim on 3/9/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(AuthService.self) private var authService

    var body: some View {
        if authService.isSignedIn {
            mainTabView
        } else {
            AuthView()
        }
    }

    private var mainTabView: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("홈", systemImage: "house.fill")
                }

            TransactionListView()
                .tabItem {
                    Label("내역", systemImage: "list.bullet")
                }

            GoalListView()
                .tabItem {
                    Label("목표", systemImage: "target")
                }

            BudgetView()
                .tabItem {
                    Label("예산", systemImage: "chart.bar.fill")
                }

            AnalysisView()
                .tabItem {
                    Label("분석", systemImage: "waveform.path.ecg")
                }

            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gearshape.fill")
                }
        }
        // Fetch 전략 B: 진입 시 자동 fetch 없음. Firestore에 있는 이전 데이터만 표시.
        // 새로고침은 설정 > 금융 연동에서 "가져오기" 버튼으로 수동 요청.
    }
}

#Preview {
    ContentView()
}
