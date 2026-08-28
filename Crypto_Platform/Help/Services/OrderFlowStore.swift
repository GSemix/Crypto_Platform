//
//  OrderFlowStore.swift
//  Crypto_Platform
//
//  Флоу создания заявки: выбор тикера и количества → подтверждение →
//  ожидание решения брокера.
//
//  Целевой API — версия из Hoazin-backend-api (POST /api/orders со статусами
//  AWAITING_BROKER / PAYMENT_PENDING / PAID / REJECTED). На сервере она пока
//  не выкачена, поэтому при 404 стор переключается на локальную заглушку,
//  чтобы экраны оставались проходимыми. См. `isStubbed`.

import SwiftUI
import Combine

// MARK: - Статусы заявки

enum BrokerOrderStatus: String, Codable, CaseIterable {
    case awaitingBroker = "AWAITING_BROKER"
    case paymentPending = "PAYMENT_PENDING"
    case paid           = "PAID"
    case rejected       = "REJECTED"

    var title: String {
        switch self {
        case .awaitingBroker: return String(localized: "Новая")
        case .paymentPending: return String(localized: "Забронирована")
        case .paid:           return String(localized: "Оплачена")
        case .rejected:       return String(localized: "Отклонена")
        }
    }

    var detail: String {
        switch self {
        case .awaitingBroker: return String(localized: "Заявка отправлена брокеру и ждёт решения")
        case .paymentPending: return String(localized: "Брокер забронировал бумаги, ожидается оплата")
        case .paid:           return String(localized: "Оплата прошла, сделка исполнена")
        case .rejected:       return String(localized: "Брокер отклонил заявку")
        }
    }

    var systemImage: String {
        switch self {
        case .awaitingBroker: return "clock"
        case .paymentPending: return "checkmark.shield"
        case .paid:           return "checkmark.seal.fill"
        case .rejected:       return "xmark.octagon"
        }
    }

    var color: Color {
        switch self {
        case .awaitingBroker: return .orange
        case .paymentPending: return .blue
        case .paid:           return .green
        case .rejected:       return .red
        }
    }

    /// Дальше статус уже не изменится — опрос можно останавливать
    var isTerminal: Bool {
        self == .paid || self == .rejected
    }

    /// Задеплоенная версия API оперирует другим набором статусов —
    /// приводим его к брокерскому, чтобы экраны не зависели от версии.
    static func from(apiValue raw: String) -> BrokerOrderStatus {
        let cleaned = (raw.components(separatedBy: ".").last ?? raw).uppercased()

        if let direct = BrokerOrderStatus(rawValue: cleaned) {
            return direct
        }

        switch cleaned {
        case "OPEN", "NEW", "PENDING":       return .awaitingBroker
        case "RESERVED", "PARTIALLY_FILLED": return .paymentPending
        case "FILLED", "EXECUTED", "CLOSED": return .paid
        case "CANCELLED", "CANCELED":        return .rejected
        default:                             return .awaitingBroker
        }
    }
}

// MARK: - Заявка

struct BrokerOrder: Decodable, Identifiable {
    let id: String              // order_id — UUID-строка
    let brokerId: Int?
    let symbol: String
    let quantity: Double
    let executionPrice: Double
    let subtotalUsd: Double
    let commissionRate: Double
    let commissionAmountUsd: Double
    let totalAmountUsd: Double
    let status: BrokerOrderStatus
    let statusReason: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "order_id"
        case fallbackId = "id"
        case brokerId = "broker_id"
        case symbol, quantity, status
        case executionPrice = "execution_price"
        case subtotalUsd = "subtotal_usd"
        case commissionRate = "commission_rate"
        case commissionAmountUsd = "commission_amount_usd"
        case totalAmountUsd = "total_amount_usd"
        case statusReason = "status_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Новая версия отдаёт order_id (UUID), задеплоенная — id (int)
        id = (try? c.decode(StringOrInt.self, forKey: .id))?.value
            ?? (try? c.decode(StringOrInt.self, forKey: .fallbackId))?.value
            ?? UUID().uuidString
        brokerId = try? c.decodeIfPresent(Int.self, forKey: .brokerId)
        symbol = (try? c.decode(String.self, forKey: .symbol)) ?? ""

        quantity = (try? c.decode(NumberOrString.self, forKey: .quantity))?.doubleValue ?? 0
        executionPrice = (try? c.decode(NumberOrString.self, forKey: .executionPrice))?.doubleValue ?? 0
        subtotalUsd = (try? c.decode(NumberOrString.self, forKey: .subtotalUsd))?.doubleValue ?? 0
        commissionRate = (try? c.decode(NumberOrString.self, forKey: .commissionRate))?.doubleValue ?? 0
        commissionAmountUsd = (try? c.decode(NumberOrString.self, forKey: .commissionAmountUsd))?.doubleValue ?? 0

        // Задеплоенная версия сумм не считает — восстанавливаем из количества и цены
        let decodedTotal = (try? c.decode(NumberOrString.self, forKey: .totalAmountUsd))?.doubleValue
        totalAmountUsd = decodedTotal
            ?? (subtotalUsd > 0 ? subtotalUsd + commissionAmountUsd : quantity * executionPrice)

        let rawStatus = (try? c.decode(String.self, forKey: .status)) ?? ""
        status = BrokerOrderStatus.from(apiValue: rawStatus)

        statusReason = try? c.decodeIfPresent(String.self, forKey: .statusReason)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    /// Для локальной заглушки
    init(
        id: String,
        brokerId: Int?,
        symbol: String,
        quantity: Double,
        executionPrice: Double,
        commissionRate: Double,
        status: BrokerOrderStatus,
        statusReason: String? = nil
    ) {
        self.id = id
        self.brokerId = brokerId
        self.symbol = symbol
        self.quantity = quantity
        self.executionPrice = executionPrice
        self.subtotalUsd = quantity * executionPrice
        self.commissionRate = commissionRate
        self.commissionAmountUsd = quantity * executionPrice * commissionRate
        self.totalAmountUsd = quantity * executionPrice * (1 + commissionRate)
        self.status = status
        self.statusReason = statusReason
        self.createdAt = ISO8601DateFormatter().string(from: Date())
        self.updatedAt = nil
    }
}

// MARK: - Курс криптовалюты

/// Курс оплаты. Бэкенд держит его константой (`CRYPTO_RATES_USD = {"USDT": "1"}`)
/// и эндпоинта для отдачи курса пока нет, поэтому значение зашито здесь же.
/// Структура готова к подмене на живой источник: достаточно переписать `fetch()`,
/// логика обновления и устаревания в UI уже опирается на `fetchedAt`.
struct CryptoRate: Equatable {
    let asset: String
    let network: String
    let usdPrice: Double
    let fetchedAt: Date

    /// Сколько курс считается свежим
    static let timeToLive: TimeInterval = 60

    var age: TimeInterval {
        Date().timeIntervalSince(fetchedAt)
    }

    var isStale: Bool {
        age > Self.timeToLive
    }

    /// Осталось секунд до устаревания
    var secondsUntilStale: Int {
        max(0, Int(Self.timeToLive - age.rounded()))
    }

    func convert(usd: Double) -> Double {
        usdPrice == 0 ? 0 : usd / usdPrice
    }

    static func fetch() async -> CryptoRate {
        // Заглушка: USDT привязан к доллару 1:1
        CryptoRate(
            asset: "USDT",
            network: "TRON",
            usdPrice: 1.0,
            fetchedAt: Date()
        )
    }
}

// MARK: - Ошибки ввода

enum QuantityValidation: Equatable {
    case empty
    case notANumber
    case notPositive
    case tooManyDecimals
    case tooLarge
    case valid(Double)

    var errorText: String? {
        switch self {
        case .empty:            return nil          // пустое поле — не ошибка, просто нечего считать
        case .notANumber:       return "Введите число"
        case .notPositive:      return "Количество должно быть больше нуля"
        case .tooManyDecimals:  return "Не более 8 знаков после запятой"
        case .tooLarge:         return "Слишком большое количество"
        case .valid:            return nil
        }
    }

    var value: Double? {
        if case let .valid(v) = self { return v }
        return nil
    }

    var isValid: Bool { value != nil }
}

// MARK: - Стор флоу

@MainActor
final class OrderFlowStore: ObservableObject {

    /// Комиссия до создания заявки неизвестна: на сервере она берётся из
    /// брокера, а эндпоинта, который её отдаёт, нет. Показываем ориентир и
    /// заменяем фактическим значением из ответа.
    static let estimatedCommissionRate: Double = 0.003

    @Published var symbol: String = ""
    @Published var assetName: String = ""
    @Published var pricePerShare: Double = 0

    @Published var quantityText: String = ""
    @Published var rate: CryptoRate?
    @Published var isRateLoading = false

    @Published var isSubmitting = false
    @Published var createdOrder: BrokerOrder?
    @Published var errorMessage: String?

    @Published private(set) var isPolling = false
    @Published private(set) var pollAttempts = 0
    /// true — флоу идёт на локальном сценарии, а не на ответах сервера
    @Published private(set) var isStubbed = false
    /// Почему пришлось перейти на демонстрацию — показывается на экране
    @Published private(set) var stubReason: String?

    private let api: OrdersAPI
    private var pollTask: Task<Void, Never>?
    private var stubStatusAdvanceAt: Date?

    /// Значение по умолчанию создаётся внутри init: OrdersAPI изолирован
    /// главным актором, а выражения умолчаний вычисляются вне его контекста.
    init(api: OrdersAPI? = nil) {
        self.api = api ?? OrdersAPI()
    }

    // MARK: Расчёты

    var validation: QuantityValidation {
        let raw = quantityText
            .replacingOccurrences(of: ",", with: ".")
            .trimmed

        if raw.isEmpty { return .empty }

        guard let value = Double(raw), value.isFinite else { return .notANumber }
        if value <= 0 { return .notPositive }
        if value > 1_000_000 { return .tooLarge }

        if let dot = raw.firstIndex(of: "."),
           raw.distance(from: raw.index(after: dot), to: raw.endIndex) > 8 {
            return .tooManyDecimals
        }

        return .valid(value)
    }

    var quantity: Double { validation.value ?? 0 }

    var subtotalUsd: Double { quantity * pricePerShare }

    var commissionUsd: Double { subtotalUsd * Self.estimatedCommissionRate }

    var totalUsd: Double { subtotalUsd + commissionUsd }

    var cryptoAmount: Double? {
        guard let rate else { return nil }
        return rate.convert(usd: totalUsd)
    }

    var canSubmit: Bool {
        validation.isValid && pricePerShare > 0 && !isSubmitting
    }

    // MARK: Подготовка

    func prepare(symbol: String, name: String, price: Double) {
        self.symbol = symbol
        self.assetName = name
        self.pricePerShare = price
        self.quantityText = ""
        self.createdOrder = nil
        self.errorMessage = nil
        self.isStubbed = false
    }

    func refreshRate() async {
        isRateLoading = true
        defer { isRateLoading = false }
        rate = await CryptoRate.fetch()
    }

    // MARK: Создание заявки

    func submit(accessToken: String) async {
        guard let value = validation.value else { return }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            createdOrder = try await api.createOrder(
                token: accessToken,
                symbol: symbol,
                quantity: value
            )
            isStubbed = false
            stubReason = nil
        } catch let error as APIError {
            // Часть отказов из клиента не починить: нет эндпоинта, нет денег
            // на счету платформы. Чтобы флоу можно было пройти целиком,
            // продолжаем на локальном сценарии — но говорим об этом прямо.
            if let reason = Self.demoReason(for: error) {
                isStubbed = true
                stubReason = reason
                createdOrder = makeStubOrder(quantity: value)
                stubStatusAdvanceAt = Date().addingTimeInterval(6)
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// nil — ошибку нужно показать пользователю, а не подменять демонстрацией
    private static func demoReason(for error: APIError) -> String? {
        switch error {
        case .notImplemented:
            return "Эндпоинта создания заявки нет на сервере"
        case .conflict(let message), .badRequest(let message):
            return "Сервер отклонил заявку: \(message)"
        case .server(let code, let message):
            return "Сервер ответил ошибкой \(code)\(message.isEmpty ? "" : ": \(message)")"
        case .unauthorized, .offline, .timedOut, .decoding, .cancelled:
            // Это чинится пользователем — вход, сеть, повтор
            return nil
        }
    }

    private func makeStubOrder(quantity: Double) -> BrokerOrder {
        BrokerOrder(
            id: UUID().uuidString,
            brokerId: 1,
            symbol: symbol,
            quantity: quantity,
            executionPrice: pricePerShare,
            commissionRate: Self.estimatedCommissionRate,
            status: .awaitingBroker
        )
    }

    // MARK: Опрос статуса

    func startPolling(accessToken: String) {
        guard let order = createdOrder, !order.status.isTerminal else { return }

        pollTask?.cancel()
        isPolling = true
        pollAttempts = 0

        pollTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                // первые опросы чаще, дальше реже — не долбим сервер
                let delay: UInt64 = await self.pollAttempts < 5 ? 3 : 10
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)

                if Task.isCancelled { return }

                let finished = await self.pollOnce(accessToken: accessToken)
                if finished { break }
            }

            await MainActor.run { self.isPolling = false }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
    }

    /// Возвращает true, когда статус стал финальным
    private func pollOnce(accessToken: String) async -> Bool {
        guard let order = createdOrder else { return true }
        pollAttempts += 1

        if isStubbed {
            return advanceStub()
        }

        do {
            let updated = try await api.pollOrderStatus(
                token: accessToken,
                orderId: order.id
            )
            createdOrder = updated
            return updated.status.isTerminal

        } catch APIError.notImplemented {
            isStubbed = true
            return false

        } catch APIError.unauthorized {
            // Токен протух — дальнейший опрос бессмысленен
            errorMessage = APIError.unauthorized.localizedDescription
            return true

        } catch APIError.cancelled {
            return true

        } catch {
            // Сеть моргнула — не роняем экран, попробуем на следующем цикле
            return false
        }
    }

    /// Заглушка: через несколько секунд брокер «бронирует» заявку
    private func advanceStub() -> Bool {
        guard
            let order = createdOrder,
            let advanceAt = stubStatusAdvanceAt,
            Date() >= advanceAt
        else { return false }

        createdOrder = BrokerOrder(
            id: order.id,
            brokerId: order.brokerId,
            symbol: order.symbol,
            quantity: order.quantity,
            executionPrice: order.executionPrice,
            commissionRate: order.commissionRate,
            status: .paymentPending
        )
        stubStatusAdvanceAt = nil
        return true
    }

    /// Демонстрация: после отправки чек-суммы заявка становится оплаченной
    func markStubPaid() {
        guard isStubbed, let order = createdOrder else { return }

        createdOrder = BrokerOrder(
            id: order.id,
            brokerId: order.brokerId,
            symbol: order.symbol,
            quantity: order.quantity,
            executionPrice: order.executionPrice,
            commissionRate: order.commissionRate,
            status: .paid
        )
        stopPolling()
    }

    func reset() {
        stopPolling()
        createdOrder = nil
        errorMessage = nil
        quantityText = ""
        isStubbed = false
        stubReason = nil
        stubStatusAdvanceAt = nil
    }

}
