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
    @StateObject var nav = NavigationState()
    @AppStorage("app_language") private var appLanguage = "system"
    @StateObject private var session = UserSession()
    @StateObject private var assetsStore = AssetsStore()
    @StateObject private var toastManager = ToastManager()
    @StateObject private var ordersAPI = OrdersAPI()
    @AppStorage("app_theme") private var appThemeRaw = AppTheme.system.rawValue
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(nav) // доступ во всё приложение
                .environment(\.locale, localeFromStorage())
                .environmentObject(session)
                .environmentObject(assetsStore)
                .environmentObject(toastManager)
                .environmentObject(ordersAPI)
                .task {
                    await assetsStore.loadAssets()
                    
                    if session.isAuthenticated {
                        await session.fetchBalance()
                    }
                }
                .preferredColorScheme(
                    AppTheme(rawValue: appThemeRaw)?.colorScheme
                )
                .onAppear {
                    NotificationService.shared.requestPermission()
                }
                .onOpenURL { url in
                    // Возврат из кошелька: hoazinplatform://payment/done?order_id=&tx=
                    handlePaymentCallback(url)
                }
        }
    }
    
    /// Кошелёк возвращает чек-сумму после перевода — кладём её в буфер,
    /// чтобы её осталось только вставить в поле подтверждения оплаты.
    private func handlePaymentCallback(_ url: URL) {
        guard
            url.scheme?.lowercased() == "hoazinplatform",
            url.host?.lowercased() == "payment",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let items = components.queryItems
        else { return }

        let values = Dictionary(
            uniqueKeysWithValues: items.compactMap { item -> (String, String)? in
                guard let value = item.value else { return nil }
                return (item.name.lowercased(), value)
            }
        )

        // Хеш принимаем только в ожидаемом формате
        if let tx = values["tx"], TransactionHash.isValid(tx) {
            UIPasteboard.general.string = TransactionHash.normalize(tx)
            toastManager.showSuccess("Чек-сумма из кошелька скопирована")
        }
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
