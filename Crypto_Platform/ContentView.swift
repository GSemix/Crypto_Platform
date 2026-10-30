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
    @EnvironmentObject var assetsStore: AssetsStore
    @ObservedObject private var network = NetworkMonitor.shared

    var body: some View {
        VStack(spacing: 0) {
        if !network.isOnline { OfflineBanner() }
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
        }
        .animation(.easeInOut(duration: 0.2), value: network.isOnline)
        .toast($toastManager.toast)
        // Связь вернулась — каталог перечитывается, если показан сохранённый
        .onChange(of: network.isOnline) { _, online in
            if online { Task { await assetsStore.loadAssets() } }
        }
    }
}

#Preview {
    ContentView()
}
