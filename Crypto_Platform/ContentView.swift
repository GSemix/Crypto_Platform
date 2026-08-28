//
//  ContentView.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 18.11.2025.
//
//  Главный экран

import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var nav: NavigationState
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var toastManager: ToastManager

    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Главная", systemImage: "square.grid.2x2") }

            NavigationStack { MarketsView() }
                .tabItem { Label("Рынки", systemImage: "chart.xyaxis.line") }

            NavigationStack { TradesView() }
                .tabItem { Label("Сделки", systemImage: "arrow.left.arrow.right") }

            NavigationStack { ProfileView() }
                .tabItem { Label("Профиль", systemImage: "person") }
        }
        .tint(Palette.accent)
        .toast($toastManager.toast)
    }
}

#Preview {
    ContentView()
}
