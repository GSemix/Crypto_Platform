//
//  UserSession.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 04.01.2026.
//
//  Сессия трейдера и данные портфеля. Все запросы идут через APIClient.

import SwiftUI
import Combine

// MARK: - /users/me

struct UserProfileResponse: Decodable {
    let id: Int
    let email: String
    let role: String
    let created_at: String

    enum CodingKeys: String, CodingKey { case id, email, role, created_at }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        email = try c.decode(String.self, forKey: .email)
        role = (try? c.decode(String.self, forKey: .role)) ?? ""
        created_at = (try? c.decode(String.self, forKey: .created_at)) ?? ""
    }
}

// MARK: - /portfolio/balance

struct PortfolioBalanceResponse: Decodable {
    let available_balance: Decimal
    let reserved_balance: Decimal
    let total_balance: Decimal

    enum CodingKeys: String, CodingKey { case available_balance, reserved_balance, total_balance }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        available_balance = c.decimal(.available_balance)
        reserved_balance = c.decimal(.reserved_balance)
        total_balance = c.decimal(.total_balance)
    }
}

// MARK: - /portfolio/unrealized-pnl

struct UnrealizedPnlPosition: Decodable {
    let symbol: String
    let available_quantity: Decimal
    let reserved_quantity: Decimal
    let total_quantity: Decimal
    let average_price: Decimal
    let latest_price: Decimal?
    let cost_basis: Decimal
    let market_value: Decimal?
    let unrealized_pnl: Decimal?

    enum CodingKeys: String, CodingKey {
        case symbol, available_quantity, reserved_quantity, total_quantity
        case average_price, latest_price, cost_basis, market_value, unrealized_pnl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try c.decode(String.self, forKey: .symbol)
        available_quantity = c.decimal(.available_quantity)
        reserved_quantity = c.decimal(.reserved_quantity)
        total_quantity = c.decimal(.total_quantity)
        average_price = c.decimal(.average_price)
        latest_price = c.decimalIfPresent(.latest_price)
        cost_basis = c.decimal(.cost_basis)
        market_value = c.decimalIfPresent(.market_value)
        unrealized_pnl = c.decimalIfPresent(.unrealized_pnl)
    }
}

struct UnrealizedPnlResponse: Decodable {
    let items: [UnrealizedPnlPosition]
    let total_unrealized_pnl: Decimal

    enum CodingKeys: String, CodingKey { case items, total_unrealized_pnl }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decode([UnrealizedPnlPosition].self, forKey: .items)) ?? []
        total_unrealized_pnl = c.decimal(.total_unrealized_pnl)
    }
}

// MARK: - /trades

struct TradeItem: Decodable, Identifiable {
    let id: Int
    let order_id: Int?
    let symbol: String
    let side: String
    let quantity: Decimal
    let price: Decimal
    let value: Decimal
    let executed_at: String?

    enum CodingKeys: String, CodingKey { case id, order_id, symbol, side, quantity, price, value, executed_at }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        order_id = try? c.decodeIfPresent(Int.self, forKey: .order_id)
        symbol = try c.decode(String.self, forKey: .symbol)
        side = try c.decode(String.self, forKey: .side)
        quantity = c.decimal(.quantity)
        price = c.decimal(.price)
        value = c.decimal(.value)
        executed_at = try? c.decodeIfPresent(String.self, forKey: .executed_at)
    }
}

struct Page<Item: Decodable>: Decodable {
    let items: [Item]
    let total: Int
    let limit: Int
    let offset: Int
}

// MARK: - /orders

struct OrderItem: Decodable, Identifiable {
    let id: Int
    let symbol: String
    let side: String
    let order_type: String
    let quantity: Decimal
    let limit_price: Decimal?
    let execution_price: Decimal?
    var status: String
    let created_at: String?
    let updated_at: String?

    enum CodingKeys: String, CodingKey {
        case id, symbol, side, order_type, quantity, limit_price, execution_price, status, created_at, updated_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        symbol = try c.decode(String.self, forKey: .symbol)
        side = try c.decode(String.self, forKey: .side)
        order_type = try c.decode(String.self, forKey: .order_type)
        status = try c.decode(String.self, forKey: .status)
        quantity = c.decimal(.quantity)
        limit_price = c.decimalIfPresent(.limit_price)
        execution_price = c.decimalIfPresent(.execution_price)
        created_at = try? c.decodeIfPresent(String.self, forKey: .created_at)
        updated_at = try? c.decodeIfPresent(String.self, forKey: .updated_at)
    }
}

// MARK: - /kyc

enum KYCState: Equatable {
    /// Заявки ещё нет (сервер отвечает 404)
    case notSubmitted
    case pending
    case approved
    case rejected(reason: String?)
    case reupload(reason: String?)

    /// Анкету можно отправить (снова)
    var canSubmit: Bool {
        switch self {
        case .notSubmitted, .rejected, .reupload: return true
        case .pending, .approved: return false
        }
    }
}

struct KYCStatusResponse: Decodable {
    let status: String
    let rejection_reason: String?
    let document_type: String?
    let submitted_at: String?
}

struct KYCRequest: Encodable {
    let first_name: String
    let second_name: String
    let citizenship: String
    let country_of_residence: String
    let document_type: String   // passport | national_id | residence_permit | driver_license
    let document_number: String
    let date_of_issue: String   // YYYY-MM-DD
    let expiration_date: String // YYYY-MM-DD
}

// MARK: - Сессия

@MainActor
final class UserSession: ObservableObject {

    let api = APIClient()

    @Published private(set) var isAuthenticated = false
    @Published var errorMessage: String?

    @Published var email = ""
    @Published var userId: Int?
    @Published var createdAt: String?
    @Published var role: String = ""
    @Published var currency: String = "USD"

    @Published var kycState: KYCState?
    @Published var isKYCLoading = false

    @Published var availableBalance: Decimal = 0
    @Published var reservedBalance: Decimal = 0
    @Published var totalBalance: Decimal?
    @Published var isBalanceLoading = true

    @Published var totalUnrealizedPnl: Decimal = 0
    @Published var positions: [UnrealizedPnlPosition] = []
    @Published var isUnrealizedPnlLoading = true

    @Published var trades: [TradeItem] = []
    @Published var tradesTotal: Int = 0
    @Published var isTradesLoading = true
    @Published private(set) var isTradesLoadingMore = false

    @Published var orders: [OrderItem] = []
    @Published var ordersTotal: Int = 0
    @Published var selectedOrder: OrderItem?
    @Published var isOrdersLoading = true
    @Published private(set) var isOrdersLoadingMore = false
    @Published var isOrdersDetailsLoading = true
    @Published var lastOrderMessage: String?

    /// Вызывается после выхода, чтобы другие сторы сбросили свои данные
    var onLogout: [() async -> Void] = []

    init() {
        api.onSessionExpired = { [weak self] in
            self?.resetState()
        }
    }

    // MARK: Вход и регистрация

    func loginUser(email: String, password: String) async {
        errorMessage = nil
        do {
            let auth = try await api.post("auth/login", body: ["email": email, "password": password], as: AccessTokenResponse.self)
            api.setAccessToken(auth.access_token)
            self.email = email
            isAuthenticated = true
            await fetchUser()
            await fetchBalance()
        } catch {
            errorMessage = message(for: error)
        }
    }

    func registerUser(email: String, password: String) async {
        errorMessage = nil
        do {
            try await api.send("POST", "auth/register", body: ["email": email, "password": password])
            await loginUser(email: email, password: password)
        } catch {
            errorMessage = message(for: error)
        }
    }

    /// Завершает сессию на сервере (отзыв refresh-токена) и локально.
    /// Локальная сессия чистится, даже если сервер не ответил.
    func logout() async {
        for hook in onLogout { await hook() }
        _ = try? await api.send("DELETE", "auth/logout")
        resetState()
    }

    private func resetState() {
        api.clearSession()
        isAuthenticated = false
        email = ""
        errorMessage = nil
        userId = nil
        role = ""
        createdAt = nil
        kycState = nil
        availableBalance = 0
        reservedBalance = 0
        totalBalance = nil
        isBalanceLoading = true
        totalUnrealizedPnl = 0
        positions = []
        isUnrealizedPnlLoading = true
        trades = []
        tradesTotal = 0
        isTradesLoading = true
        orders = []
        ordersTotal = 0
        selectedOrder = nil
        isOrdersLoading = true
        isOrdersDetailsLoading = true
        lastOrderMessage = nil
    }

    // MARK: Профиль

    func fetchUser() async {
        do {
            let profile = try await api.get("users/me", as: UserProfileResponse.self)
            userId = profile.id
            email = profile.email
            role = profile.role
            createdAt = profile.created_at
        } catch {
            errorMessage = message(for: error)
        }
    }

    // MARK: KYC

    func fetchKYC() async {
        isKYCLoading = true
        defer { isKYCLoading = false }
        do {
            let response = try await api.get("kyc", as: KYCStatusResponse.self)
            kycState = Self.kycState(from: response)
        } catch let error as APIError where error.status == 404 {
            kycState = .notSubmitted
        } catch {
            errorMessage = message(for: error)
        }
    }

    private static func kycState(from response: KYCStatusResponse) -> KYCState {
        switch response.status.lowercased() {
        case "approved": return .approved
        case "rejected": return .rejected(reason: response.rejection_reason)
        case "reupload": return .reupload(reason: response.rejection_reason)
        default:         return .pending
        }
    }

    func submitKYC(_ form: KYCRequest) async -> Bool {
        errorMessage = nil
        do {
            let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(form))
            try await api.send("POST", "kyc", body: body)
            await fetchKYC()
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    // MARK: Портфель

    func fetchBalance() async {
        isBalanceLoading = true
        defer { isBalanceLoading = false }
        do {
            let balance = try await api.get("portfolio/balance", as: PortfolioBalanceResponse.self)
            availableBalance = balance.available_balance
            reservedBalance = balance.reserved_balance
            totalBalance = balance.total_balance
        } catch {
            errorMessage = message(for: error)
        }
    }

    func fetchUnrealizedPnL() async {
        isUnrealizedPnlLoading = true
        defer { isUnrealizedPnlLoading = false }
        do {
            let pnl = try await api.get("portfolio/unrealized-pnl", as: UnrealizedPnlResponse.self)
            totalUnrealizedPnl = pnl.total_unrealized_pnl
            positions = pnl.items
        } catch {
            errorMessage = message(for: error)
        }
    }

    func fetchTrades(limit: Int = 20, offset: Int = 0) async {
        isTradesLoading = true
        defer { isTradesLoading = false }
        do {
            let page = try await api.get("trades", query: Self.pageQuery(limit, offset), as: Page<TradeItem>.self)
            trades = offset == 0 ? page.items : trades + page.items
            tradesTotal = page.total
        } catch {
            errorMessage = message(for: error)
        }
    }

    var canLoadMoreTrades: Bool { trades.count < tradesTotal }

    /// Следующая страница: список остаётся на экране, крутится только кнопка
    func loadMoreTrades() async {
        guard canLoadMoreTrades, !isTradesLoadingMore else { return }
        isTradesLoadingMore = true
        defer { isTradesLoadingMore = false }
        do {
            let page = try await api.get("trades", query: Self.pageQuery(20, trades.count), as: Page<TradeItem>.self)
            let known = Set(trades.map(\.id))
            trades += page.items.filter { !known.contains($0.id) }
            tradesTotal = page.total
        } catch {
            errorMessage = message(for: error)
        }
    }

    // MARK: Ордера

    var canLoadMoreOrders: Bool { orders.count < ordersTotal }

    func loadMoreOrders() async {
        guard canLoadMoreOrders, !isOrdersLoadingMore else { return }
        isOrdersLoadingMore = true
        defer { isOrdersLoadingMore = false }
        do {
            let page = try await api.get("orders", query: Self.pageQuery(20, orders.count), as: Page<OrderItem>.self)
            let known = Set(orders.map(\.id))
            orders += page.items.filter { !known.contains($0.id) }
            ordersTotal = page.total
        } catch {
            errorMessage = message(for: error)
        }
    }

    func fetchOrders(limit: Int = 20, offset: Int = 0) async {
        isOrdersLoading = true
        defer { isOrdersLoading = false }
        do {
            let page = try await api.get("orders", query: Self.pageQuery(limit, offset), as: Page<OrderItem>.self)
            orders = offset == 0 ? page.items : orders + page.items
            ordersTotal = page.total
        } catch {
            errorMessage = message(for: error)
        }
    }

    func fetchOrderDetails(orderId: Int) async {
        isOrdersDetailsLoading = true
        defer { isOrdersDetailsLoading = false }
        do {
            selectedOrder = try await api.get("orders/\(orderId)", as: OrderItem.self)
        } catch {
            errorMessage = message(for: error)
        }
    }

    func cancelOrder(orderId: Int) async -> Bool {
        do {
            let updated = try await api.delete("orders/\(orderId)", as: OrderItem.self)
            if let index = orders.firstIndex(where: { $0.id == orderId }) { orders[index] = updated }
            if selectedOrder?.id == orderId { selectedOrder = updated }
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    /// Рыночный ордер на покупку или продажу
    func createOrder(symbol: String, side: String, quantity: Decimal) async -> Bool {
        do {
            let order = try await api.post("orders", body: [
                "symbol": symbol,
                "side": side,
                "order_type": "MARKET",
                "quantity": quantity.plainString
            ], as: OrderItem.self)
            lastOrderMessage = String(localized: "Ордер №\(order.id): \(order.status)")
            orders.insert(order, at: 0)
            ordersTotal += 1
            await fetchBalance()
            return order.status != "REJECTED"
        } catch {
            let text = message(for: error)
            lastOrderMessage = text
            errorMessage = text
            return false
        }
    }

    // MARK: Вспомогательное

    private static func pageQuery(_ limit: Int, _ offset: Int) -> [URLQueryItem] {
        [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: String(offset))]
    }

    func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
