//
//  FirebaseSupport.swift
//  Crypto_Platform
//
//  Firebase необязателен: включается, только если в сборке есть
//  GoogleService-Info.plist. Без него приложение работает без push,
//  отчётов о сбоях и аналитики. Остальной код Firebase не знает.

import Foundation
import FirebaseCore
import FirebaseCrashlytics
import FirebaseAnalytics

enum FirebaseSupport {
    static let isAvailable = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil

    /// Отчёты о сбоях — только из Release, в Debug сбои видны в Xcode
    static func configure() {
        guard isAvailable else { return }
        FirebaseApp.configure()
        #if DEBUG
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
        #else
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        #endif
    }
}

/// События воронки покупки. Имена совпадают с Android.
enum AppAnalytics {
    static func log(_ name: String, _ params: [String: String] = [:]) {
        #if DEBUG
        print("[analytics] \(name) \(params)")
        #endif
        guard FirebaseSupport.isAvailable else { return }
        Analytics.logEvent(name, parameters: params)
    }
}
