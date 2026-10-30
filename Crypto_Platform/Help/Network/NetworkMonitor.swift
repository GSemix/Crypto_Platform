//
//  NetworkMonitor.swift
//  Crypto_Platform
//
//  Состояние сети для баннера «Нет подключения к интернету».

import SwiftUI
import Combine
import Network

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in NetworkMonitor.shared.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "network-monitor"))
    }
}

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "wifi.slash")
            Text("Нет подключения к интернету").font(.footnote.weight(.medium))
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(Palette.negative)
        .accessibilityElement(children: .combine)
    }
}

