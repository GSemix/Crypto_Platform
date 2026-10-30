//
//  Crypto_PlatformApp.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 18.11.2025.
//
//  Точка входа приложения

import SwiftUI
import Combine
import SwiftData

class NavigationState: ObservableObject { // Для состояния скрытия ToolBar
    @Published var hideTabBar = false
}

@main
struct Crypto_PlatformApp: App {
    @UIApplicationDelegateAdaptor(PlatformAppDelegate.self) private var appDelegate
    @ObservedObject private var push = PushCenter.shared
    @StateObject var nav = NavigationState()
    @AppStorage("app_language") private var appLanguage = "system"
    @StateObject private var session: UserSession
    @StateObject private var purchases: PurchaseStore
    @StateObject private var notifications: NotificationsStore
    @StateObject private var assetsStore = AssetsStore()
    @StateObject private var toastManager = ToastManager()
    @AppStorage("app_theme") private var appThemeRaw = AppTheme.system.rawValue

    init() {
        let session = UserSession()
        _session = StateObject(wrappedValue: session)
        _purchases = StateObject(wrappedValue: PurchaseStore(api: session.api))
        _notifications = StateObject(wrappedValue: NotificationsStore(api: session.api))
        PushCenter.shared.attach(session.api)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(nav) // доступ во всё приложение
                .environment(\.locale, localeFromStorage())
                .environmentObject(session)
                .environmentObject(purchases)
                .environmentObject(notifications)
                .environmentObject(assetsStore)
                .environmentObject(toastManager)
                .task {
                    session.onLogout.append { [purchases, notifications] in
                        // Регистрация устройства удаляется, пока сессия ещё действует
                        await PushCenter.shared.unregisterBeforeLogout()
                        purchases.reset()
                        notifications.reset()
                    }
                    await assetsStore.loadAssets()
                }
                .preferredColorScheme(
                    AppTheme(rawValue: appThemeRaw)?.colorScheme
                )
                // Ссылка возврата из кошелька — в том числе при холодном старте
                // Universal Link приходит как веб-активность — тем же разбором
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL, let link = PurchaseReturnLinks.parse(url) {
                        purchases.pendingReturn = link
                    }
                }
                .onOpenURL { url in
                    if let link = PurchaseReturnLinks.parse(url) {
                        purchases.pendingReturn = link
                    }
                }
                .onChange(of: session.isAuthenticated, initial: true) { _, authenticated in
                    if authenticated { PushCenter.shared.registerAfterLogin() }
                }
                .sheet(item: $push.pending) { target in
                    PushTargetSheet(target: target)
                        .environmentObject(session)
                        .environmentObject(purchases)
                        .environmentObject(notifications)
                        .environmentObject(assetsStore)
                        .environment(\.locale, localeFromStorage())
                }
                .sheet(item: returnLinkBinding) { item in
                    ReturnLinkSheet(link: item.link)
                        .environmentObject(session)
                        .environmentObject(purchases)
                        .environmentObject(notifications)
                        .environment(\.locale, localeFromStorage())
                }
        }
    }

    private var returnLinkBinding: Binding<ReturnLinkItem?> {
        Binding(
            get: { purchases.pendingReturn.map(ReturnLinkItem.init) },
            set: { if $0 == nil { purchases.pendingReturn = nil } }
        )
    }

    private func localeFromStorage() -> Locale {
        switch appLanguage {
        case "ru":
            return Locale(identifier: "ru")
        case "en":
            return Locale(identifier: "en")
        default:
            return .current
        }
    }
}

struct ReturnLinkItem: Identifiable {
    let link: PurchaseReturnLinks.Link
    var id: String { "\(link.requestId)|\(link.txHash ?? "")" }
}

/// Заявка, на которую вернул кошелёк. Без сессии сначала вход, затем заявка.
struct ReturnLinkSheet: View {
    @EnvironmentObject var session: UserSession
    let link: PurchaseReturnLinks.Link

    var body: some View {
        NavigationStack {
            if session.isAuthenticated {
                PurchaseRequestView(requestId: link.requestId, returnedTxHash: link.txHash)
            } else {
                AuthView()
            }
        }
    }
}

/// Экран из push. Без сессии сначала вход, затем цель; уведомление отмечается прочитанным.
struct PushTargetSheet: View {
    @EnvironmentObject var session: UserSession
    @EnvironmentObject var notifications: NotificationsStore
    let target: PushTarget

    var body: some View {
        NavigationStack {
            if session.isAuthenticated {
                Group {
                    switch target {
                    case .order(let id): OrderDetailsView(orderId: id)
                    case .purchase(let id): PurchaseRequestView(requestId: id)
                    case .feed: NotificationsView()
                    }
                }
                .task {
                    if let id = PushCenter.shared.pendingNotificationId {
                        PushCenter.shared.pendingNotificationId = nil
                        await notifications.markRead(id: id)
                    }
                }
            } else {
                AuthView()
            }
        }
    }
}
