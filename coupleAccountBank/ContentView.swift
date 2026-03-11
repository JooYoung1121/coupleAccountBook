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

            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gearshape.fill")
                }
        }
        .onAppear {
            let uid = authService.currentUser?.id
            let coupleID = authService.currentUser?.effectiveCoupleID
            let userName = authService.currentUser?.name
            Task {
                await FinanceSyncService.shared.performLaunchFetchIfNeeded(uid: uid, coupleID: coupleID, userName: userName)
            }
        }
    }
}

#Preview {
    ContentView()
}
