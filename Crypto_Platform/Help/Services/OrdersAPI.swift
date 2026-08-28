//
//  OrdersAPI.swift
//  Crypto_Platform
//
//  Слой сетевых методов для флоу заявок (пачка 1.4).
//
//  Часть эндпоинтов на сервере отсутствует — они помечены `Availability.stub`
//  и обслуживаются локально. Когда бэкенд их выкатит, достаточно убрать
//  ветку заглушки в соответствующем методе: сигнатуры и модели уже боевые.

import Foundation
import Combine

// MARK: - Ошибки

enum APIError: LocalizedError, Equatable {
    case unauthorized
    case notImplemented(String)      // 404 — эндпоинта нет на сервере
    case conflict(String)            // 409 — гонка статусов, нехватка пула
    case badRequest(String)
    case server(Int, String)
    case offline
    case timedOut
    case decoding(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return String(localized: "Сессия истекла, войдите заново")
        case .notImplemented(let path):
            return String(localized: "Метод \(path) ещё не реализован на сервере")
        case .conflict(let message):
            return message
        case .badRequest(let message):
            return message
        case .server(let code, let message):
            return message.isEmpty ? String(localized: "Ошибка сервера (\(code))") : message
        case .offline:
            return String(localized: "Нет соединения с интернетом")
        case .timedOut:
            return String(localized: "Сервер не ответил вовремя")
        case .decoding:
            return String(localized: "Сервер вернул неожиданный ответ")
        case .cancelled:
            return String(localized: "Запрос отменён")
        }
    }

    /// Есть ли смысл повторять запрос
    var isRetriable: Bool {
        switch self {
        case .offline, .timedOut, .server: return true
        default: return false
        }
    }
}

// MARK: - Модели

struct OrderPage: Decodable {
    let items: [BrokerOrder]
    let total: Int
    let limit: Int
    let offset: Int

    enum CodingKeys: String, CodingKey {
        case items, total, limit, offset
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decode([BrokerOrder].self, forKey: .items)) ?? []
        total = (try? c.decode(Int.self, forKey: .total)) ?? 0
        limit = (try? c.decode(Int.self, forKey: .limit)) ?? 20
        offset = (try? c.decode(Int.self, forKey: .offset)) ?? 0
    }

    init(items: [BrokerOrder], total: Int, limit: Int, offset: Int) {
        self.items = items
        self.total = total
        self.limit = limit
        self.offset = offset
    }
}

/// Форма на оплату. Модели `PaymentInvoice` на бэкенде пока нет —
/// структура повторяет то, что должно прийти, когда её добавят.
struct PaymentInvoice: Decodable, Equatable {
    let orderId: String
    let asset: String            // USDT
    let network: String          // TRON
    let walletAddress: String
    let amount: Double
    let expiresAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case asset, network, amount
        case walletAddress = "wallet_address"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        orderId = (try? c.decode(StringOrInt.self, forKey: .orderId))?.value ?? ""
        asset = (try? c.decode(String.self, forKey: .asset)) ?? "USDT"
        network = (try? c.decode(String.self, forKey: .network)) ?? "TRON"
        walletAddress = (try? c.decode(String.self, forKey: .walletAddress)) ?? ""
        amount = (try? c.decode(NumberOrString.self, forKey: .amount))?.doubleValue ?? 0

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let expiresRaw = (try? c.decode(String.self, forKey: .expiresAt)) ?? ""
        let createdRaw = (try? c.decode(String.self, forKey: .createdAt)) ?? ""
        expiresAt = iso.date(from: expiresRaw) ?? Date().addingTimeInterval(PaymentInvoice.defaultTTL)
        createdAt = iso.date(from: createdRaw) ?? Date()
    }

    init(
        orderId: String,
        asset: String,
        network: String,
        walletAddress: String,
        amount: Double,
        expiresAt: Date,
        createdAt: Date = Date()
    ) {
        self.orderId = orderId
        self.asset = asset
        self.network = network
        self.walletAddress = walletAddress
        self.amount = amount
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }

    /// 15 минут на оплату
    static let defaultTTL: TimeInterval = 15 * 60
}

struct BrokerInventoryItem: Decodable, Identifiable {
    let symbol: String
    let availableQuantity: Double
    let reservedQuantity: Double
    let saleEnabled: Bool

    var id: String { symbol }

    enum CodingKeys: String, CodingKey {
        case symbol
        case availableQuantity = "available_quantity"
        case reservedQuantity = "reserved_quantity"
        case saleEnabled = "sale_enabled"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol = (try? c.decode(String.self, forKey: .symbol)) ?? ""
        availableQuantity = (try? c.decode(NumberOrString.self, forKey: .availableQuantity))?.doubleValue ?? 0
        reservedQuantity = (try? c.decode(NumberOrString.self, forKey: .reservedQuantity))?.doubleValue ?? 0
        saleEnabled = (try? c.decode(Bool.self, forKey: .saleEnabled)) ?? true
    }
}

// MARK: - Клиент

@MainActor
final class OrdersAPI: ObservableObject {

    private let baseURL = "https://hse-server.tw1.ru/api"
    private let session: URLSession

    /// Разница между часами сервера и устройства (сервер минус устройство).
    /// Берётся из заголовка Date каждого ответа — таймер оплаты не должен
    /// зависеть от того, правильно ли выставлены часы на телефоне.
    private(set) var serverTimeOffset: TimeInterval = 0
    private(set) var didSyncTime = false

    /// Заявки, для которых форма оплаты сгенерирована локально
    private var stubbedInvoices: [String: PaymentInvoice] = [:]
    private var stubbedTxIds: [String: String] = [:]

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    /// Текущее время по часам сервера
    var serverNow: Date {
        Date().addingTimeInterval(serverTimeOffset)
    }

    // MARK: Транспорт

    private func makeRequest(
        _ method: String,
        _ path: String,
        token: String?,
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil
    ) -> URLRequest? {
        var components = URLComponents(string: baseURL + path)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20

        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    /// Единая точка: выполняет запрос, синхронизирует время, раскладывает коды ошибок
    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.decoding("нет HTTP-ответа")
            }

            syncTime(from: http)

            switch http.statusCode {
            case 200...299:
                return data
            case 401:
                throw APIError.unauthorized
            case 404:
                throw APIError.notImplemented(request.url?.path ?? "")
            case 409:
                throw APIError.conflict(Self.message(from: data) ?? "Действие недоступно")
            case 400, 422:
                throw APIError.badRequest(Self.message(from: data) ?? "Некорректный запрос")
            default:
                throw APIError.server(http.statusCode, Self.message(from: data) ?? "")
            }
        } catch let error as APIError {
            throw error
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw APIError.offline
            case .timedOut:
                throw APIError.timedOut
            case .cancelled:
                throw APIError.cancelled
            default:
                throw APIError.server(urlError.code.rawValue, urlError.localizedDescription)
            }
        } catch is CancellationError {
            throw APIError.cancelled
        }
    }

    private func syncTime(from response: HTTPURLResponse) {
        guard
            let raw = response.value(forHTTPHeaderField: "Date"),
            let serverDate = Self.httpDateFormatter.date(from: raw)
        else { return }

        serverTimeOffset = serverDate.timeIntervalSince(Date())
        didSyncTime = true
    }

    private static let httpDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    private static func message(from data: Data) -> String? {
        guard let api = try? JSONDecoder().decode(APIErrorResponse.self, from: data) else {
            return nil
        }
        return api.error ?? api.message ?? api.msg
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    // MARK: - 1.4.1 Создание заявки

    func createOrder(
        token: String,
        symbol: String,
        quantity: Double
    ) async throws -> BrokerOrder {
        // side/order_type обязательны для задеплоенной версии, новая их игнорирует
        guard let request = makeRequest(
            "POST", "/orders",
            token: token,
            body: [
                "symbol": symbol,
                "side": "BUY",
                "order_type": "MARKET",
                "quantity": String(format: "%g", quantity)
            ]
        ) else { throw APIError.badRequest("Некорректный адрес") }

        let data = try await perform(request)
        return try decode(BrokerOrder.self, from: data)
    }

    // MARK: - 1.4.2 Текущий курс конвертации

    /// Эндпоинта нет: бэкенд держит курс константой `CRYPTO_RATES_USD`.
    func fetchConversionRate(token: String) async throws -> CryptoRate {
        await CryptoRate.fetch()
    }

    // MARK: - 1.4.3 Список заявок и детали

    /// Заявки текущего пользователя
    func fetchOrders(
        token: String,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> OrderPage {
        guard let request = makeRequest(
            "GET", "/orders",
            token: token,
            query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
        ) else { throw APIError.badRequest("Некорректный адрес") }

        let data = try await perform(request)
        return try decode(OrderPage.self, from: data)
    }

    /// Заявки, назначенные брокеру. Фильтр по статусу — на стороне сервера.
    func fetchBrokerOrders(
        token: String,
        status: BrokerOrderStatus? = nil,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> OrderPage {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        if let status {
            query.append(URLQueryItem(name: "status", value: status.rawValue))
        }

        guard let request = makeRequest(
            "GET", "/broker/orders", token: token, query: query
        ) else { throw APIError.badRequest("Некорректный адрес") }

        let data = try await perform(request)
        return try decode(OrderPage.self, from: data)
    }

    func fetchOrder(token: String, orderId: String) async throws -> BrokerOrder {
        guard let request = makeRequest("GET", "/orders/\(orderId)", token: token) else {
            throw APIError.badRequest("Некорректный адрес")
        }
        let data = try await perform(request)
        return try decode(BrokerOrder.self, from: data)
    }

    func fetchBrokerOrder(token: String, orderId: String) async throws -> BrokerOrder {
        guard let request = makeRequest("GET", "/broker/orders/\(orderId)", token: token) else {
            throw APIError.badRequest("Некорректный адрес")
        }
        let data = try await perform(request)
        return try decode(BrokerOrder.self, from: data)
    }

    func fetchBrokerInventory(token: String) async throws -> [BrokerInventoryItem] {
        guard let request = makeRequest("GET", "/broker/inventory", token: token) else {
            throw APIError.badRequest("Некорректный адрес")
        }
        let data = try await perform(request)

        if let wrapped = try? JSONDecoder().decode([String: [BrokerInventoryItem]].self, from: data),
           let items = wrapped["items"] {
            return items
        }
        return try decode([BrokerInventoryItem].self, from: data)
    }

    // MARK: - 1.4.4 Бронирование пула

    /// Бронирование пула брокером. Если заявку уже взял другой брокер или
    /// не хватает бумаг, сервер отвечает 409 — это `APIError.conflict`.
    func acceptOrder(
        token: String,
        orderId: String,
        walletAddress: String? = nil
    ) async throws -> BrokerOrder {
        var body: [String: Any] = [:]
        if let walletAddress, !walletAddress.isEmpty {
            body["wallet_address"] = walletAddress
        }

        guard let request = makeRequest(
            "POST", "/broker/orders/\(orderId)/accept",
            token: token,
            body: body.isEmpty ? nil : body
        ) else { throw APIError.badRequest("Некорректный адрес") }

        let data = try await perform(request)
        return try decode(BrokerOrder.self, from: data)
    }

    func rejectOrder(
        token: String,
        orderId: String,
        reason: String
    ) async throws -> BrokerOrder {
        let trimmed = reason.trimmed
        guard !trimmed.isEmpty, trimmed.count <= 255 else {
            throw APIError.badRequest("Причина отказа — от 1 до 255 символов")
        }

        guard let request = makeRequest(
            "POST", "/broker/orders/\(orderId)/reject",
            token: token,
            body: ["rejection_reason": trimmed]
        ) else { throw APIError.badRequest("Некорректный адрес") }

        let data = try await perform(request)
        return try decode(BrokerOrder.self, from: data)
    }

    // MARK: - 1.4.5 Форма на оплату

    /// Создание формы оплаты. Эндпоинта нет (`POST /api/orders/{id}/payment`
    /// на сервере — заглушка `pass`, модель `PaymentInvoice` не определена),
    /// поэтому при 404 форма собирается локально.
    func createPaymentInvoice(
        token: String,
        orderId: String,
        amount: Double,
        walletAddress: String? = nil
    ) async throws -> PaymentInvoice {
        var body: [String: Any] = ["amount": String(format: "%g", amount)]
        if let walletAddress, !walletAddress.isEmpty {
            body["wallet_address"] = walletAddress
        }

        guard let request = makeRequest(
            "POST", "/orders/\(orderId)/payment", token: token, body: body
        ) else { throw APIError.badRequest("Некорректный адрес") }

        do {
            let data = try await perform(request)
            let invoice = try decode(PaymentInvoice.self, from: data)
            stubbedInvoices.removeValue(forKey: orderId)
            return invoice
        } catch APIError.notImplemented {
            let invoice = makeStubInvoice(orderId: orderId, amount: amount, walletAddress: walletAddress)
            stubbedInvoices[orderId] = invoice
            return invoice
        }
    }

    /// Получение уже созданной формы
    func fetchPaymentInvoice(token: String, orderId: String) async throws -> PaymentInvoice {
        guard let request = makeRequest("GET", "/orders/\(orderId)/payment", token: token) else {
            throw APIError.badRequest("Некорректный адрес")
        }

        do {
            let data = try await perform(request)
            return try decode(PaymentInvoice.self, from: data)
        } catch APIError.notImplemented {
            if let cached = stubbedInvoices[orderId] { return cached }
            throw APIError.notImplemented("/orders/\(orderId)/payment")
        }
    }

    private func makeStubInvoice(
        orderId: String,
        amount: Double,
        walletAddress: String?
    ) -> PaymentInvoice {
        PaymentInvoice(
            orderId: orderId,
            asset: "USDT",
            network: "TRON",
            // Тестовый адрес: контрольная сумма верна (иначе кошелёк его отвергнет),
            // но приватного ключа к нему не существует. Раньше здесь стоял адрес
            // контракта USDT-TRC20 — реальный перевод на него сжёг бы средства.
            walletAddress: walletAddress ?? Self.demoWalletAddress,
            amount: amount,
            expiresAt: serverNow.addingTimeInterval(PaymentInvoice.defaultTTL)
        )
    }

    /// Адрес-заглушка для формы оплаты, пока платёжного эндпоинта нет.
    /// Никому не принадлежит: тело собрано из хеша строки-маркера.
    static let demoWalletAddress = "TRmaNnnLE153MUHzfbu9KntmpQH4Xbjt1d"

    /// Есть ли у заявки локальная (не серверная) форма оплаты
    func isInvoiceStubbed(orderId: String) -> Bool {
        stubbedInvoices[orderId] != nil
    }

    // MARK: - 1.4.6 Чек-сумма транзакции

    /// Отправка хеша транзакции. Эндпоинта нет — при 404 сохраняем локально,
    /// чтобы экран подтверждения оставался проходимым.
    func submitTransactionHash(
        token: String,
        orderId: String,
        txHash: String
    ) async throws -> BrokerOrder? {
        guard TransactionHash.isValid(txHash) else {
            throw APIError.badRequest(TransactionHash.validationHint)
        }

        guard let request = makeRequest(
            "POST", "/orders/\(orderId)/payment/confirm",
            token: token,
            body: ["transaction_id": txHash]
        ) else { throw APIError.badRequest("Некорректный адрес") }

        do {
            let data = try await perform(request)
            return try? decode(BrokerOrder.self, from: data)
        } catch APIError.notImplemented {
            stubbedTxIds[orderId] = txHash
            return nil
        }
    }

    func submittedTransactionHash(orderId: String) -> String? {
        stubbedTxIds[orderId]
    }

    // MARK: - 1.4.7 Статус заявки

    /// Один цикл опроса. Возвращает заявку либо бросает ошибку —
    /// решение о продолжении принимает вызывающая сторона.
    func pollOrderStatus(
        token: String,
        orderId: String,
        asBroker: Bool = false
    ) async throws -> BrokerOrder {
        asBroker
        ? try await fetchBrokerOrder(token: token, orderId: orderId)
        : try await fetchOrder(token: token, orderId: orderId)
    }
}

// MARK: - Чек-сумма транзакции

enum TransactionHash {
    /// TRON: 64 шестнадцатеричных символа
    static let requiredLength = 64

    static func normalize(_ raw: String) -> String {
        var value = raw.trimmed
        if value.hasPrefix("0x") || value.hasPrefix("0X") {
            value.removeFirst(2)
        }
        return value.lowercased()
    }

    static func isValid(_ raw: String) -> Bool {
        let value = normalize(raw)
        guard value.count == requiredLength else { return false }
        return value.allSatisfy { $0.isHexDigit }
    }

    static func validationError(_ raw: String) -> String? {
        let value = normalize(raw)
        if value.isEmpty { return nil }
        if !value.allSatisfy({ $0.isHexDigit }) {
            return "Хеш содержит недопустимые символы"
        }
        if value.count < requiredLength {
            return "Не хватает \(requiredLength - value.count) символов"
        }
        if value.count > requiredLength {
            return "Лишних символов: \(value.count - requiredLength)"
        }
        return nil
    }

    static let validationHint = "Хеш транзакции — 64 символа в шестнадцатеричном виде"
}
