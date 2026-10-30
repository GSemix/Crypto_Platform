//
//  NotificationsStore.swift
//  Crypto_Platform
//
//  Лента уведомлений, счётчик непрочитанных и настройки каналов.

import SwiftUI
import Combine

// MARK: - Модели

struct AppNotification: Decodable, Identifiable, Equatable {
    let id: Int
    let type: String
    let title: String
    let body: String
    let is_read: Bool
    let created_at: Date?

    enum CodingKeys: String, CodingKey { case id, type, title, body, is_read, created_at }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        type = (try? c.decode(String.self, forKey: .type)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        body = (try? c.decode(String.self, forKey: .body)) ?? ""
        is_read = (try? c.decode(Bool.self, forKey: .is_read)) ?? false
        created_at = try? ServerTime.decode(c, .created_at)
    }

    func markedRead() -> AppNotification {
        AppNotification(id: id, type: type, title: title, body: body, is_read: true, created_at: created_at)
    }

    private init(id: Int, type: String, title: String, body: String, is_read: Bool, created_at: Date?) {
        self.id = id; self.type = type; self.title = title; self.body = body
        self.is_read = is_read; self.created_at = created_at
    }
}

struct NotificationPage: Decodable {
    let items: [AppNotification]
    let total: Int
}

struct UnreadCountResponse: Decodable {
    let unread_count: Int
}

struct NotificationSetting: Decodable, Equatable {
    let notification_type: String
    let channel: String
    let enabled: Bool
}

struct NotificationSettingsBody: Decodable {
    let items: [NotificationSetting]
}

/// Каналы, которыми управляет мобильное приложение
enum NotificationChannel: String, CaseIterable {
    case inApp = "in_app"
    case mobilePush = "mobile_push"

    var title: LocalizedStringKey {
        switch self {
        case .inApp:      return "В приложении"
        case .mobilePush: return "Push-уведомления"
        }
    }
}

/// Типы событий, о которых сервер шлёт уведомления
enum NotificationEvent {
    static let all: [String] = [
        "ORDER_CREATED", "ORDER_EXECUTED", "ORDER_REJECTED", "ORDER_CANCELLED",
        "PURCHASE_REQUEST_PAYMENT_FORM_CREATED", "PURCHASE_REQUEST_REJECTED",
        "PURCHASE_REQUEST_EXPIRED", "PURCHASE_REQUEST_SETTLED"
    ]

    static func title(_ type: String) -> String {
        switch type {
        case "ORDER_CREATED":                         return String(localized: "Ордер создан")
        case "ORDER_EXECUTED":                        return String(localized: "Ордер исполнен")
        case "ORDER_REJECTED":                        return String(localized: "Ордер отклонён")
        case "ORDER_CANCELLED":                       return String(localized: "Ордер отменён")
        case "PURCHASE_REQUEST_PAYMENT_FORM_CREATED": return String(localized: "Выставлена форма оплаты")
        case "PURCHASE_REQUEST_REJECTED":             return String(localized: "Заявка отклонена брокером")
        case "PURCHASE_REQUEST_EXPIRED":              return String(localized: "Время на оплату вышло")
        case "PURCHASE_REQUEST_SETTLED":              return String(localized: "Заявка выполнена")
        default:                                      return type
        }
    }
}

// MARK: - Хранилище

@MainActor
final class NotificationsStore: ObservableObject {

    private let api: APIClient

    @Published private(set) var items: [AppNotification] = []
    @Published private(set) var total = 0
    @Published private(set) var unreadCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var error: String?

    /// Сохранённые на сервере пары «тип × канал»
    @Published private(set) var settings: [NotificationSetting] = []
    @Published private(set) var isLoadingSettings = false
    @Published var settingsError: String?

    static let pageSize = 20

    init(api: APIClient) {
        self.api = api
    }

    var canLoadMore: Bool { items.count < total }

    func reset() {
        items = []
        total = 0
        unreadCount = 0
        error = nil
        settings = []
        settingsError = nil
    }

    // MARK: Лента

    func load() async {
        isLoading = items.isEmpty
        defer { isLoading = false }
        do {
            let page = try await fetchPage(offset: 0)
            items = page.items
            total = page.total
            error = nil
            await refreshUnreadCount()
        } catch is CancellationError {
        } catch {
            self.error = PurchaseErrorText.message(for: error)
        }
    }

    func loadMore() async {
        guard canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        if let page = try? await fetchPage(offset: items.count) {
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            total = page.total
        }
    }

    private func fetchPage(offset: Int) async throws -> NotificationPage {
        try await api.get("notifications", query: [
            URLQueryItem(name: "limit", value: String(Self.pageSize)),
            URLQueryItem(name: "offset", value: String(offset))
        ], as: NotificationPage.self)
    }

    func refreshUnreadCount() async {
        if let response = try? await api.get("notifications/unread-count", as: UnreadCountResponse.self) {
            unreadCount = response.unread_count
        }
    }

    func markRead(_ notification: AppNotification) async {
        guard !notification.is_read else { return }
        do {
            _ = try await api.put("notifications/read/\(notification.id)", as: AppNotification.self)
            if let index = items.firstIndex(where: { $0.id == notification.id }) {
                items[index] = items[index].markedRead()
            }
            unreadCount = max(0, unreadCount - 1)
        } catch {
            self.error = PurchaseErrorText.message(for: error)
        }
    }

    /// Отметка по id — для уведомления, открытого из push
    func markRead(id: Int) async {
        _ = try? await api.put("notifications/read/\(id)", as: AppNotification.self)
        if let index = items.firstIndex(where: { $0.id == id }) { items[index] = items[index].markedRead() }
        await refreshUnreadCount()
    }

    func markAllRead() async {
        do {
            try await api.send("PUT", "notifications/read-all")
            items = items.map { $0.markedRead() }
            unreadCount = 0
        } catch {
            self.error = PurchaseErrorText.message(for: error)
        }
    }

    // MARK: Настройки

    func loadSettings() async {
        isLoadingSettings = settings.isEmpty
        defer { isLoadingSettings = false }
        do {
            settings = try await api.get("notifications/settings", as: NotificationSettingsBody.self).items
            settingsError = nil
        } catch is CancellationError {
        } catch {
            settingsError = PurchaseErrorText.message(for: error)
        }
    }

    /// Нет сохранённой пары — канал включён: так считает сервер
    func isEnabled(_ type: String, _ channel: NotificationChannel) -> Bool {
        if let own = settings.first(where: { $0.notification_type == type && $0.channel == channel.rawValue }) {
            return own.enabled
        }
        if let common = settings.first(where: { $0.notification_type == "all" && $0.channel == channel.rawValue }) {
            return common.enabled
        }
        return true
    }

    /// Изменение сохраняется сразу; если сервер не принял — переключатель возвращается
    func set(_ type: String, _ channel: NotificationChannel, enabled: Bool) async {
        let previous = settings
        let item = NotificationSetting(notification_type: type, channel: channel.rawValue, enabled: enabled)
        settings.removeAll { $0.notification_type == type && $0.channel == channel.rawValue }
        settings.append(item)
        do {
            _ = try await api.put("notifications/settings", body: [
                "items": [["notification_type": type, "channel": channel.rawValue, "enabled": enabled]]
            ], as: NotificationSettingsBody.self)
            settingsError = nil
        } catch {
            settings = previous
            settingsError = PurchaseErrorText.message(for: error)
        }
    }
}
