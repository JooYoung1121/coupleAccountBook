//
//  ContentView.swift
//  coupleAccountBank
//
//  Created by JooYoung Kim on 3/9/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
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
    }
}

#Preview {
    ContentView()
}
