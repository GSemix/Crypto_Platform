//
//  UserSession.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 04.01.2026.
//

import SwiftUI
import Combine

struct LoginResponse: Decodable {
    let access_token: String
}

struct MessageResponse: Decodable {
    let message: String?
    let error: String?
}

// MARK: - /api/users/me

struct UserProfileResponse: Decodable {
    let id: Int
    let email: String
    let role: String
    let balance: Double
    let reserved_balance: Double
    let created_at: String

    enum CodingKeys: String, CodingKey {
        case id, email, role, balance, reserved_balance, created_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(Int.self, forKey: .id)
        email = try c.decode(String.self, forKey: .email)
        role = (try? c.decode(String.self, forKey: .role)) ?? ""
        balance = (try? c.decode(NumberOrString.self, forKey: .balance))?.doubleValue ?? 0
        reserved_balance = (try? c.decode(NumberOrString.self, forKey: .reserved_balance))?.doubleValue ?? 0
        created_at = (try? c.decode(String.self, forKey: .created_at)) ?? ""
    }
}

// MARK: - /api/portfolio/balance

struct PortfolioBalanceResponse: Decodable {
    let available_balance: Double
    let reserved_balance: Double
    let total_balance: Double

    enum CodingKeys: String, CodingKey {
        case available_balance, reserved_balance, total_balance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        available_balance = (try? c.decode(NumberOrString.self, forKey: .available_balance))?.doubleValue ?? 0
        reserved_balance = (try? c.decode(NumberOrString.self, forKey: .reserved_balance))?.doubleValue ?? 0
        total_balance = (try? c.decode(NumberOrString.self, forKey: .total_balance))?.doubleValue ?? 0
    }
}

// MARK: - /api/portfolio/unrealized-pnl

struct UnrealizedPnlPosition: Decodable {
    let symbol: String
    let available_quantity: Double
    let reserved_quantity: Double
    let total_quantity: Double
    let average_price: Double
    let latest_price: Double?
    let cost_basis: Double
    let market_value: Double?
    let unrealized_pnl: Double?

    enum CodingKeys: String, CodingKey {
        case symbol
        case available_quantity, reserved_quantity, total_quantity
        case average_price, latest_price, cost_basis, market_value, unrealized_pnl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        symbol = try c.decode(String.self, forKey: .symbol)
        available_quantity = (try? c.decode(NumberOrString.self, forKey: .available_quantity))?.doubleValue ?? 0
        reserved_quantity = (try? c.decode(NumberOrString.self, forKey: .reserved_quantity))?.doubleValue ?? 0
        total_quantity = (try? c.decode(NumberOrString.self, forKey: .total_quantity))?.doubleValue ?? 0
        average_price = (try? c.decode(NumberOrString.self, forKey: .average_price))?.doubleValue ?? 0
        latest_price = (try? c.decodeIfPresent(NumberOrString.self, forKey: .latest_price))?.doubleValue
        cost_basis = (try? c.decode(NumberOrString.self, forKey: .cost_basis))?.doubleValue ?? 0
        market_value = (try? c.decodeIfPresent(NumberOrString.self, forKey: .market_value))?.doubleValue
        unrealized_pnl = (try? c.decodeIfPresent(NumberOrString.self, forKey: .unrealized_pnl))?.doubleValue
    }
}

struct UnrealizedPnlResponse: Decodable {
    let items: [UnrealizedPnlPosition]
    let total_unrealized_pnl: Double

    enum CodingKeys: String, CodingKey {
        case items, total_unrealized_pnl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        items = (try? c.decode([UnrealizedPnlPosition].self, forKey: .items)) ?? []
        total_unrealized_pnl = (try? c.decode(NumberOrString.self, forKey: .total_unrealized_pnl))?.doubleValue ?? 0
    }
}

// MARK: - /api/trades

struct TradeItem: Decodable, Identifiable {
    let id: Int
    let order_id: Int?
    let symbol: String
    let side: String
    let quantity: Double
    let price: Double
    let value: Double
    let executed_at: String?

    enum CodingKeys: String, CodingKey {
        case id, order_id, symbol, side, quantity, price, value, executed_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(Int.self, forKey: .id)
        order_id = try? c.decodeIfPresent(Int.self, forKey: .order_id)
        symbol = try c.decode(String.self, forKey: .symbol)
        side = try c.decode(String.self, forKey: .side)
        quantity = (try? c.decode(NumberOrString.self, forKey: .quantity))?.doubleValue ?? 0
        price = (try? c.decode(NumberOrString.self, forKey: .price))?.doubleValue ?? 0
        value = (try? c.decode(NumberOrString.self, forKey: .value))?.doubleValue ?? 0
        executed_at = try? c.decodeIfPresent(String.self, forKey: .executed_at)
    }
}

struct TradesResponse: Decodable {
    let items: [TradeItem]
    let total: Int
    let limit: Int
    let offset: Int
}

// MARK: - /api/orders

struct OrderItem: Decodable, Identifiable {
    let id: Int
    let symbol: String
    let side: String
    let order_type: String
    let quantity: Double
    let limit_price: Double?
    let execution_price: Double?
    var status: String
    let created_at: String?
    let updated_at: String?

    enum CodingKeys: String, CodingKey {
        case id, symbol, side, order_type, quantity
        case limit_price, execution_price, status, created_at, updated_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(Int.self, forKey: .id)
        symbol = try c.decode(String.self, forKey: .symbol)
        side = try c.decode(String.self, forKey: .side)
        order_type = try c.decode(String.self, forKey: .order_type)
        status = try c.decode(String.self, forKey: .status)

        quantity = (try? c.decode(NumberOrString.self, forKey: .quantity))?.doubleValue ?? 0
        limit_price = (try? c.decodeIfPresent(NumberOrString.self, forKey: .limit_price))?.doubleValue
        execution_price = (try? c.decodeIfPresent(NumberOrString.self, forKey: .execution_price))?.doubleValue
        created_at = try? c.decodeIfPresent(String.self, forKey: .created_at)
        updated_at = try? c.decodeIfPresent(String.self, forKey: .updated_at)
    }
}

struct OrdersResponse: Decodable {
    let items: [OrderItem]
    let total: Int
    let limit: Int
    let offset: Int
}

struct CreateOrderRequest: Encodable {
    let symbol: String
    let side: String        // "BUY" | "SELL"
    let order_type: String  // "MARKET" | "LIMIT"
    let quantity: String    // Numeric(20, 8) — сервер ждёт строку
    let limit_price: String?
}

// MARK: - /api/kyc

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

struct KYCResponse: Decodable {
    let success: Bool
    let status: String?

    enum CodingKeys: String, CodingKey {
        case success, status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = (try? c.decode(Bool.self, forKey: .success)) ?? false
        status = (try? c.decodeIfPresent(StringOrInt.self, forKey: .status))?.value
    }
}

struct APIErrorResponse: Decodable {
    let error: String?
    let message: String?
    let msg: String?
}

@MainActor
final class UserSession: ObservableObject {

    // Храним
    @AppStorage("email") var email = ""
    @AppStorage("access_token") private var storedAccessToken = ""
    @AppStorage("kyc_uploaded") var kycUploaded = false
    @AppStorage("kyc_completed") var kycCompleted = false
    
    // UI состояние
    var isAuthenticated: Bool {
        !accessToken.isEmpty
    }

    @Published var errorMessage: String?
    @Published private(set) var accessToken: String = ""
    
    @Published var userId: Int?
    @Published var createdAt: String?

    @Published var role: String = ""
    @Published var currency: String = "USD"

    @Published var availableBalance: Double = 0
    @Published var reservedBalance: Double = 0
    @Published var totalBalance: Double?
    @Published var isBalanceLoading = true

    @Published var totalUnrealizedPnl: Double = 0
    @Published var positions: [UnrealizedPnlPosition] = []
    @Published var isUnrealizedPnlLoading = true

    @Published var trades: [TradeItem] = []
    @Published var tradesTotal: Int = 0
    @Published var isTradesLoading = true

    @Published var orders: [OrderItem] = []
    @Published var ordersTotal: Int = 0
    @Published var selectedOrder: OrderItem?
    @Published var isOrdersLoading = true
    @Published var isOrdersDetailsLoading = true
    @Published var lastOrderMessage: String?

    @Published var kycStatus: String?

    private let baseURL = "https://hse-server.tw1.ru/api"

    init() {
        self.accessToken = storedAccessToken
    }
    
    // MARK: - LOGIN

    func loginUser(email: String, password: String) async {
        errorMessage = nil

        guard let url = URL(string: "\(baseURL)/auth/login") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "email": email,
            "password": password
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            
            if status == 200 {
                let auth = try JSONDecoder().decode(LoginResponse.self, from: data)

                self.email = email
                self.accessToken = auth.access_token
                storedAccessToken = self.accessToken

                await fetchBalance()
            } else {
                errorMessage = extractError(from: data)
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - REGISTER

    func registerUser(email: String, password: String) async {
        errorMessage = nil

        guard let url = URL(string: "\(baseURL)/auth/register") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "email": email,
            "password": password
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 201 {
                await loginUser(email: email, password: password)
            } else {
                errorMessage = extractError(from: data)
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - KYC

    func submitKYC(
        firstName: String,
        secondName: String,
        citizenship: String,
        countryOfResidence: String,
        documentType: String,
        documentNumber: String,
        dateOfIssue: String,
        expirationDate: String
    ) async -> Bool {
        errorMessage = nil

        guard let url = URL(string: "\(baseURL)/kyc") else { return false }

        let payload = KYCRequest(
            first_name: firstName,
            second_name: secondName,
            citizenship: citizenship,
            country_of_residence: countryOfResidence,
            document_type: documentType,
            document_number: documentNumber,
            date_of_issue: dateOfIssue,
            expiration_date: expirationDate
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 200 {
                let result = try JSONDecoder().decode(KYCResponse.self, from: data)
                self.kycStatus = result.status
                self.kycUploaded = true
                // KYC считается пройденным только когда сервер вернул approved
                self.kycCompleted = (result.status?.lowercased() == "approved")
                return true
            } else if status == 401 {
                let refreshed = await refreshAccessToken()
                if refreshed {
                    return await submitKYC(
                        firstName: firstName,
                        secondName: secondName,
                        citizenship: citizenship,
                        countryOfResidence: countryOfResidence,
                        documentType: documentType,
                        documentNumber: documentNumber,
                        dateOfIssue: dateOfIssue,
                        expirationDate: expirationDate
                    )
                }
                logout()
                return false
            } else {
                errorMessage = extractError(from: data)
                return false
            }
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - FETСH USER

    func fetchUser() async {
        guard let url = URL(string: "\(baseURL)/users/me") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 200 {
                let profile = try JSONDecoder().decode(UserProfileResponse.self, from: data)

                self.userId = profile.id
                self.email = profile.email
                self.role = profile.role
                self.createdAt = profile.created_at
            } else if status == 401 {
                let refreshed = await refreshAccessToken()
                if refreshed {
                    await fetchUser()
                } else {
                    logout()
                }
            } else {
                errorMessage = extractError(from: data)
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - FETCH BALANCE

    func fetchBalance() async {
        self.isBalanceLoading = true
        defer { self.isBalanceLoading = false }

        guard let url = URL(string: "\(baseURL)/portfolio/balance") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 200 {
                let balance = try JSONDecoder().decode(PortfolioBalanceResponse.self, from: data)

                self.availableBalance = balance.available_balance
                self.reservedBalance = balance.reserved_balance
                self.totalBalance = balance.total_balance
            } else if status == 401 {
                let refreshed = await refreshAccessToken()
                if refreshed {
                    await fetchBalance()
                } else {
                    logout()
                }
            } else {
                errorMessage = extractError(from: data)
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - FETCH PNL

    func fetchUnrealizedPnL() async {
        self.isUnrealizedPnlLoading = true
        defer { self.isUnrealizedPnlLoading = false }

        guard let url = URL(string: "\(baseURL)/portfolio/unrealized-pnl") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 200 {
                let pnl = try JSONDecoder().decode(UnrealizedPnlResponse.self, from: data)

                self.totalUnrealizedPnl = pnl.total_unrealized_pnl
                self.positions = pnl.items
            } else if status == 401 {
                let refreshed = await refreshAccessToken()
                if refreshed {
                    await fetchUnrealizedPnL()
                } else {
                    logout()
                }
            } else {
                errorMessage = extractError(from: data)
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - FETCH TRADES

    func fetchTrades(limit: Int = 20, offset: Int = 0) async {
        self.isTradesLoading = true
        defer { self.isTradesLoading = false }

        var components = URLComponents(string: "\(baseURL)/trades")
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        guard let url = components?.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 200 {
                let result = try JSONDecoder().decode(TradesResponse.self, from: data)
                self.trades = result.items
                self.tradesTotal = result.total
            } else if status == 401 {
                let refreshed = await refreshAccessToken()
                if refreshed {
                    await fetchTrades(limit: limit, offset: offset)
                } else {
                    logout()
                }
            } else {
                errorMessage = extractError(from: data)
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - FETCH ORDERS

    func fetchOrders(limit: Int = 20, offset: Int = 0) async {
        self.isOrdersLoading = true
        defer { self.isOrdersLoading = false }

        var components = URLComponents(string: "\(baseURL)/orders")
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        guard let url = components?.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 200 {
                let result = try JSONDecoder().decode(OrdersResponse.self, from: data)
                self.orders = result.items
                self.ordersTotal = result.total
            } else if status == 401 {
                let refreshed = await refreshAccessToken()
                if refreshed {
                    await fetchOrders(limit: limit, offset: offset)
                } else {
                    logout()
                }
            } else {
                errorMessage = extractError(from: data)
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - FETCH ORDER DETAILS

    func fetchOrderDetails(orderId: Int) async {
        self.isOrdersDetailsLoading = true
        defer { self.isOrdersDetailsLoading = false }

        guard let url = URL(string: "\(baseURL)/orders/\(orderId)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 200 {
                self.selectedOrder = try JSONDecoder().decode(OrderItem.self, from: data)
            } else if status == 401 {
                let refreshed = await refreshAccessToken()
                if refreshed {
                    await fetchOrderDetails(orderId: orderId)
                } else {
                    logout()
                }
            } else {
                errorMessage = extractError(from: data)
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - CANCEL ORDER

    func cancelOrder(orderId: Int) async -> Bool {
        guard let url = URL(string: "\(baseURL)/orders/\(orderId)") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 200 {
                // сервер возвращает обновлённый ордер
                if let updated = try? JSONDecoder().decode(OrderItem.self, from: data) {
                    if let index = orders.firstIndex(where: { $0.id == orderId }) {
                        orders[index] = updated
                    }
                    if selectedOrder?.id == orderId {
                        selectedOrder = updated
                    }
                } else if let index = orders.firstIndex(where: { $0.id == orderId }) {
                    orders[index].status = "CANCELLED"
                }
                return true
            } else if status == 401 {
                let refreshed = await refreshAccessToken()
                return refreshed ? await cancelOrder(orderId: orderId) : false
            } else {
                errorMessage = extractError(from: data)
                return false
            }
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - CREATE ORDER

    func createOrder(
        symbol: String,
        side: String,
        quantity: Double,
        orderType: String = "MARKET",
        limitPrice: Double? = nil
    ) async -> Bool {

        guard let url = URL(string: "\(baseURL)/orders") else { return false }

        let payload = CreateOrderRequest(
            symbol: symbol,
            side: side,
            order_type: orderType,
            quantity: Self.decimalString(quantity),
            limit_price: limitPrice.map(Self.decimalString)
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            if statusCode == 201 {
                let order = try JSONDecoder().decode(OrderItem.self, from: data)

                lastOrderMessage = "Ордер #\(order.id): \(order.status)"
                orders.insert(order, at: 0)
                ordersTotal += 1

                return order.status != "REJECTED"
            } else if statusCode == 401 {
                let refreshed = await refreshAccessToken()
                return refreshed
                    ? await createOrder(
                        symbol: symbol,
                        side: side,
                        quantity: quantity,
                        orderType: orderType,
                        limitPrice: limitPrice
                    )
                    : false
            } else {
                let msg = extractError(from: data)
                lastOrderMessage = msg
                errorMessage = msg
                return false
            }
        } catch is CancellationError {
            return false
        } catch {
            lastOrderMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Numeric(20, 8) без экспоненциальной записи и лишних нулей
    private static func decimalString(_ value: Double) -> String {
        var s = String(format: "%.8f", value)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }

    // MARK: - REFRESH, если статус 401

    /*
     if status == 401 {
         let refreshed = await refreshAccessToken()
         if refreshed {
             return await loginUser(email: email, password: password)
         } else {
             logout()
             //throw URLError(.userAuthenticationRequired)
         }
     }
    */

    func refreshAccessToken() async -> Bool {
        guard let url = URL(string: "\(baseURL)/jwt/refresh") else {
            return false
        }

        // Refresh возможен только при наличии CSRF-куки, полученной при логине
        guard let csrf = HTTPCookieStorage.shared.cookies?
            .first(where: { $0.name == "csrf_refresh_token" })?
            .value
        else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(csrf, forHTTPHeaderField: "X-CSRF-TOKEN")
        request.httpShouldHandleCookies = true

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 200 {
                let json = try JSONDecoder().decode([String: String].self, from: data)
                accessToken = json["access_token"] ?? ""
                storedAccessToken = accessToken
                return true
            }

            return false
        } catch {
            return false
        }
    }
    
    // MARK: - LOGOUT

    func logout() {
        accessToken = ""
        storedAccessToken = ""
        kycUploaded = false
        kycCompleted = false
        kycStatus = nil
        email = ""
        errorMessage = nil
        userId = nil
        role = ""
        createdAt = nil
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

    // MARK: - Helper
    
    private func extractError(from data: Data) -> String {
        if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
            return apiError.error ?? apiError.message ?? apiError.msg ?? "Неизвестная ошибка"
        }

        return String(data: data, encoding: .utf8) ?? "Неизвестная ошибка"
    }
}

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
