//
//  BrokerDashboardStore.swift
//  Crypto_Platform
//
//  Список заявок брокера: фильтры, обновление, бронирование пула.

import SwiftUI
import Combine

/// Фильтр по статусу. `nil` в `status` — показать все.
enum BrokerFilter: String, CaseIterable, Identifiable {
    case all
    case new
    case reserved
    case paid
    case rejected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:      return String(localized: "Все")
        case .new:      return String(localized: "Новые")
        case .reserved: return String(localized: "Забронированы")
        case .paid:     return String(localized: "Оплачены")
        case .rejected: return String(localized: "Отклонены")
        }
    }

    var status: BrokerOrderStatus? {
        switch self {
        case .all:      return nil
        case .new:      return .awaitingBroker
        case .reserved: return .paymentPending
        case .paid:     return .paid
        case .rejected: return .rejected
        }
    }
}

@MainActor
final class BrokerDashboardStore: ObservableObject {

    @Published var filter: BrokerFilter = .new
    @Published private(set) var orders: [BrokerOrder] = []
    @Published private(set) var total = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?
    @Published private(set) var unavailable = false
    @Published private(set) var lastUpdated: Date?

    /// Заявки, которые кто-то забрал раньше нас
    @Published private(set) var takenByOthers: Set<String> = []

    private let api: OrdersAPI
    private var refreshTask: Task<Void, Never>?
    private let pageSize = 20

    init(api: OrdersAPI) {
        self.api = api
    }

    deinit {
        refreshTask?.cancel()
    }

    var isEmpty: Bool {
        orders.isEmpty && !isLoading && errorMessage == nil && !unavailable
    }

    // MARK: Загрузка

    func load(token: String, showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        defer { isLoading = false }

        await fetch(token: token)
    }

    /// Pull-to-refresh: без общего спиннера, чтобы список не «моргал»
    func refresh(token: String) async {
        isRefreshing = true
        defer { isRefreshing = false }
        await fetch(token: token)
    }

    private func fetch(token: String) async {
        do {
            let page = try await api.fetchBrokerOrders(
                token: token,
                status: filter.status,
                limit: pageSize,
                offset: 0
            )

            orders = page.items
            total = page.total
            errorMessage = nil
            unavailable = false
            lastUpdated = Date()

        } catch APIError.notImplemented {
            // Брокерская часть API не задеплоена
            unavailable = true
            orders = []
            errorMessage = nil

        } catch APIError.cancelled {
            return

        } catch let error as APIError {
            errorMessage = error.localizedDescription

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Периодический опрос

    /// Пока push не подключён, список обновляется опросом.
    /// Интервал большой намеренно — сервер тяжёлый.
    func startAutoRefresh(token: String, every seconds: UInt64 = 30) {
        refreshTask?.cancel()

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.fetch(token: token)
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: Бронирование пула

    enum BookingResult {
        case booked(BrokerOrder)
        /// Заявку уже забрал другой брокер либо не хватило бумаг
        case conflict(String)
        case failed(String)
    }

    func bookPool(token: String, orderId: String, walletAddress: String? = nil) async -> BookingResult {
        do {
            let updated = try await api.acceptOrder(
                token: token,
                orderId: orderId,
                walletAddress: walletAddress
            )
            replace(updated)
            takenByOthers.remove(orderId)
            return .booked(updated)

        } catch APIError.conflict(let message) {
            // Гонка двух брокеров: помечаем и убираем из «новых»
            takenByOthers.insert(orderId)
            await fetch(token: token)
            return .conflict(message)

        } catch let error as APIError {
            return .failed(error.localizedDescription)

        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func reject(token: String, orderId: String, reason: String) async -> BookingResult {
        do {
            let updated = try await api.rejectOrder(
                token: token,
                orderId: orderId,
                reason: reason
            )
            replace(updated)
            return .booked(updated)

        } catch APIError.conflict(let message) {
            takenByOthers.insert(orderId)
            await fetch(token: token)
            return .conflict(message)

        } catch let error as APIError {
            return .failed(error.localizedDescription)

        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func replace(_ order: BrokerOrder) {
        if let index = orders.firstIndex(where: { $0.id == order.id }) {
            // Если заявка больше не подходит под фильтр — убираем из списка
            if let wanted = filter.status, order.status != wanted {
                orders.remove(at: index)
                total = max(0, total - 1)
            } else {
                orders[index] = order
            }
        }
    }
}
