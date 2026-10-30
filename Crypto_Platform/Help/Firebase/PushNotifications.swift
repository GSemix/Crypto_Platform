//
//  PushNotifications.swift
//  Crypto_Platform
//
//  Push платформы: FCM-токен регистрируется на сервере после входа
//  (`POST /notifications/devices`) и удаляется при выходе, нажатие открывает
//  ордер, заявку или ленту уведомлений.

import SwiftUI
import Combine
import UserNotifications
import FirebaseMessaging

/// Куда ведёт нажатие на push
enum PushTarget: Identifiable, Equatable {
    case order(Int)
    case purchase(Int)
    case feed

    var id: String {
        switch self {
        case .order(let id): return "order-\(id)"
        case .purchase(let id): return "purchase-\(id)"
        case .feed: return "feed"
        }
    }

    /// `type` и `payload` (JSON-строка сущности) из блока data сообщения
    static func route(_ userInfo: [AnyHashable: Any]) -> PushTarget {
        let type = userInfo["type"] as? String ?? ""
        let payload = (userInfo["payload"] as? String)
            .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? [:]
        func number(_ key: String) -> Int? {
            if let n = payload[key] as? Int { return n }
            if let s = payload[key] as? String { return Int(s) }
            return nil
        }
        if type.hasPrefix("ORDER_"), let id = number("id") { return .order(id) }
        if type.hasPrefix("PURCHASE_REQUEST_"),
           let id = number("purchase_request_id") ?? number("request_id") ?? number("id") { return .purchase(id) }
        return .feed
    }
}

@MainActor
final class PushCenter: NSObject, ObservableObject {
    static let shared = PushCenter()

    /// Переход из push; без сессии ждёт входа
    @Published var pending: PushTarget?
    /// Уведомление из нажатого push — отмечается прочитанным
    var pendingNotificationId: Int?

    private weak var api: APIClient?
    private let recordKey = "push.device_record_id"
    private var fcmToken: String?

    func attach(_ api: APIClient) { self.api = api }

    /// После входа: разрешение на уведомления и регистрация в APNs
    func registerAfterLogin() {
        guard FirebaseSupport.isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in UIApplication.shared.registerForRemoteNotifications() }
        }
        Task { await sendToken() }
    }

    func setAPNsToken(_ token: Data) {
        Messaging.messaging().apnsToken = token
    }

    func tokenChanged(_ token: String?) {
        fcmToken = token
        Task { await sendToken() }
    }

    private func sendToken() async {
        guard FirebaseSupport.isAvailable, let api, api.hasSession else { return }
        var token = fcmToken
        if token == nil { token = try? await Messaging.messaging().token() }
        guard let token else { return }
        struct Device: Decodable { let id: Int }
        let device = UIDevice.current.identifierForVendor?.uuidString ?? ""
        if let record = try? await api.post("notifications/devices",
                                             body: ["platform": "ios", "push_token": token, "device_id": device],
                                             as: Device.self) {
            UserDefaults.standard.set(record.id, forKey: recordKey)
        }
    }

    /// Перед выходом: запись удаляется, пока сессия ещё действует, —
    /// иначе push об ордерах приходили бы следующему пользователю телефона
    func unregisterBeforeLogout() async {
        guard let api, let id = UserDefaults.standard.object(forKey: recordKey) as? Int else { return }
        _ = try? await api.send("DELETE", "notifications/devices/\(id)")
        UserDefaults.standard.removeObject(forKey: recordKey)
    }
}

final class PlatformAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseSupport.configure()
        UNUserNotificationCenter.current().delegate = self
        if FirebaseSupport.isAvailable { Messaging.messaging().delegate = self }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard FirebaseSupport.isAvailable else { return }
        Task { @MainActor in PushCenter.shared.setAPNsToken(deviceToken) }
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in PushCenter.shared.tokenChanged(fcmToken) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let target = PushTarget.route(info)
        let notificationId = (info["notification_id"] as? String).flatMap(Int.init) ?? info["notification_id"] as? Int
        await MainActor.run {
            PushCenter.shared.pendingNotificationId = notificationId
            PushCenter.shared.pending = target
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
