//
//  PurchaseModels.swift
//  Crypto_Platform
//
//  Покупка акций у брокера с оплатой в HZN — модели контракта
//  /quotes и /purchase-requests.

import SwiftUI

// MARK: - Статусы

enum PurchaseStatus: String, CaseIterable {
    case pendingBroker = "PENDING_BROKER"
    case poolReserved = "POOL_RESERVED"
    case awaitingPayment = "AWAITING_PAYMENT"
    case paymentSubmitted = "PAYMENT_SUBMITTED"
    case filled = "FILLED"
    case rejectedByBroker = "REJECTED_BY_BROKER"
    case expired = "EXPIRED"
    case paymentFailed = "PAYMENT_FAILED"
    case cancelled = "CANCELLED"

    static let terminal: Set<PurchaseStatus> = [.filled, .rejectedByBroker, .expired, .paymentFailed, .cancelled]
    /// Отмена разрешена, пока не отправлен хеш
    static let cancellable: Set<PurchaseStatus> = [.pendingBroker, .poolReserved, .awaitingPayment]

    var isTerminal: Bool { Self.terminal.contains(self) }
    var canCancel: Bool { Self.cancellable.contains(self) }

    var title: String {
        switch self {
        case .pendingBroker:    return String(localized: "Ожидает брокера")
        case .poolReserved:     return String(localized: "Брокер взял в работу")
        case .awaitingPayment:  return String(localized: "Ожидает оплаты")
        case .paymentSubmitted: return String(localized: "Оплата на проверке")
        case .filled:           return String(localized: "Успешно выполнена")
        case .rejectedByBroker: return String(localized: "Отклонена брокером")
        case .expired:          return String(localized: "Истёк таймер")
        case .paymentFailed:    return String(localized: "Оплата не подтверждена")
        case .cancelled:        return String(localized: "Отменена")
        }
    }

    var detail: String {
        switch self {
        case .pendingBroker:    return String(localized: "Заявка отправлена брокеру")
        case .poolReserved:     return String(localized: "Брокер забронировал бумаги и готовит форму оплаты")
        case .awaitingPayment:  return String(localized: "Оплатите заявку до истечения таймера")
        case .paymentSubmitted: return String(localized: "Брокер проверяет перевод")
        case .filled:           return String(localized: "Бумаги зачислены на ваш счёт")
        case .rejectedByBroker: return String(localized: "Брокер отказал в заявке")
        case .expired:          return String(localized: "Время на оплату вышло, бронь снята")
        case .paymentFailed:    return String(localized: "Брокер не подтвердил перевод")
        case .cancelled:        return String(localized: "Заявка отменена, средства не списаны")
        }
    }

    var color: Color {
        switch self {
        case .pendingBroker, .poolReserved: return .orange
        case .awaitingPayment, .paymentSubmitted: return Palette.accent
        case .filled: return Palette.positive
        case .rejectedByBroker, .expired, .paymentFailed, .cancelled: return Palette.negative
        }
    }

    var systemImage: String {
        switch self {
        case .pendingBroker:    return "clock"
        case .poolReserved:     return "checkmark.shield"
        case .awaitingPayment:  return "creditcard"
        case .paymentSubmitted: return "hourglass"
        case .filled:           return "checkmark.seal.fill"
        case .rejectedByBroker: return "xmark.octagon"
        case .expired:          return "clock.badge.exclamationmark"
        case .paymentFailed:    return "exclamationmark.triangle"
        case .cancelled:        return "xmark.circle"
        }
    }
}

// MARK: - Валюты оплаты

struct CryptoCurrency: Decodable, Identifiable, Equatable {
    let code: String
    let name: String
    let network: String
    let decimals: Int
    let min_amount: Decimal

    var id: String { code }

    enum CodingKeys: String, CodingKey { case code, name, network, decimals, min_amount }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        name = (try? c.decode(String.self, forKey: .name)) ?? code
        network = (try? c.decode(String.self, forKey: .network)) ?? code
        decimals = (try? c.decode(Int.self, forKey: .decimals)) ?? 3
        min_amount = c.decimal(.min_amount)
    }
}

struct CryptoCurrencyList: Decodable {
    let items: [CryptoCurrency]
}

// MARK: - Котировка

struct PurchaseQuote: Decodable, Equatable {
    let quote_id: String
    let symbol: String
    /// Ровно та строка, что вернул сервер: она же уходит при создании заявки
    let quantity: String
    let price_usd: Decimal
    let amount_usd: Decimal
    let crypto_currency: String
    let crypto_amount: Decimal
    let rate_usd_per_crypto: Decimal
    let expires_at: Date
    let server_time: Date

    enum CodingKeys: String, CodingKey {
        case quote_id, symbol, quantity, price_usd, amount_usd, crypto_currency
        case crypto_amount, rate_usd_per_crypto, expires_at, server_time
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quote_id = try c.decode(String.self, forKey: .quote_id)
        symbol = try c.decode(String.self, forKey: .symbol)
        quantity = try c.decode(String.self, forKey: .quantity)
        price_usd = c.decimal(.price_usd)
        amount_usd = c.decimal(.amount_usd)
        crypto_currency = try c.decode(String.self, forKey: .crypto_currency)
        crypto_amount = c.decimal(.crypto_amount)
        rate_usd_per_crypto = c.decimal(.rate_usd_per_crypto)
        expires_at = try ServerTime.decode(c, .expires_at)
        server_time = try ServerTime.decode(c, .server_time)
    }
}

// MARK: - Заявка

struct PaymentForm: Decodable, Equatable {
    let crypto_currency: String
    let network: String
    let crypto_amount: Decimal
    /// Строкой, как прислал сервер: в ссылку сумма идёт ровно с тремя знаками
    let crypto_amount_text: String
    let wallet_address: String
    let memo: String?
    let payment_deadline: Date

    enum CodingKeys: String, CodingKey {
        case crypto_currency, network, crypto_amount, wallet_address, memo, payment_deadline
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        crypto_currency = try c.decode(String.self, forKey: .crypto_currency)
        network = (try? c.decode(String.self, forKey: .network)) ?? "HZN"
        crypto_amount_text = (try? c.decode(String.self, forKey: .crypto_amount)) ?? ""
        crypto_amount = c.decimal(.crypto_amount)
        wallet_address = try c.decode(String.self, forKey: .wallet_address)
        memo = try? c.decodeIfPresent(String.self, forKey: .memo)
        payment_deadline = try ServerTime.decode(c, .payment_deadline)
    }
}

struct PurchaseRequest: Decodable, Identifiable, Equatable {
    let id: Int
    let symbol: String
    let quantity: Decimal
    let price_usd: Decimal
    let amount_usd: Decimal
    let crypto_currency: String
    let crypto_amount: Decimal
    /// Статус строкой: незнакомый статус не роняет разбор и показывается как есть
    let statusValue: String
    let payment: PaymentForm?
    let tx_hash: String?
    let reason: String?
    let created_at: Date?
    let updated_at: Date?

    var status: PurchaseStatus? { PurchaseStatus(rawValue: statusValue) }

    enum CodingKeys: String, CodingKey {
        case id, symbol, quantity, price_usd, amount_usd, crypto_currency, crypto_amount
        case status, payment, tx_hash, reason, created_at, updated_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        symbol = try c.decode(String.self, forKey: .symbol)
        quantity = c.decimal(.quantity)
        price_usd = c.decimal(.price_usd)
        amount_usd = c.decimal(.amount_usd)
        crypto_currency = (try? c.decode(String.self, forKey: .crypto_currency)) ?? "HZN"
        crypto_amount = c.decimal(.crypto_amount)
        statusValue = try c.decode(String.self, forKey: .status)
        payment = try? c.decodeIfPresent(PaymentForm.self, forKey: .payment)
        tx_hash = try? c.decodeIfPresent(String.self, forKey: .tx_hash)
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
        created_at = try? ServerTime.decode(c, .created_at)
        updated_at = try? ServerTime.decode(c, .updated_at)
    }
}

/// Ответ на одну заявку: `{"request": {...}, "server_time": "..."}`
struct PurchaseRequestEnvelope: Decodable {
    let request: PurchaseRequest
    let server_time: Date

    enum CodingKeys: String, CodingKey { case request, server_time }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        request = try c.decode(PurchaseRequest.self, forKey: .request)
        server_time = try ServerTime.decode(c, .server_time)
    }
}

struct PurchaseRequestPage: Decodable {
    let items: [PurchaseRequest]
    let total: Int
    let server_time: Date

    enum CodingKeys: String, CodingKey { case items, total, server_time }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decode([PurchaseRequest].self, forKey: .items)) ?? []
        total = (try? c.decode(Int.self, forKey: .total)) ?? items.count
        server_time = try ServerTime.decode(c, .server_time)
    }
}

// MARK: - Ошибки

/// Тексты ошибок покупки по кодам сервера
enum PurchaseErrorText {
    static func message(for error: Error) -> String {
        guard let api = error as? APIError else { return error.localizedDescription }
        if api.isNetwork { return String(localized: "Нет связи с сервером") }
        if [500, 502, 503, 504].contains(api.status) { return String(localized: "Сервис временно недоступен, попробуйте позже") }
        switch api.code {
        case "QUOTE_EXPIRED", "QUOTE_NOT_FOUND":
            return String(localized: "Курс устарел — пересчитайте сумму и подтвердите заново")
        case "INVALID_QUANTITY":          return String(localized: "Неверное количество: больше нуля, не более 4 знаков после запятой")
        case "SYMBOL_NOT_FOUND":          return String(localized: "Такой акции нет в каталоге")
        case "MARKET_PRICE_UNAVAILABLE":  return String(localized: "Цена акции сейчас недоступна, попробуйте позже")
        case "TX_HASH_INVALID":           return String(localized: "Нужно 64 hex-символа")
        case "TX_HASH_ALREADY_USED":      return String(localized: "Этот хеш уже привязан к другой заявке")
        case "PAYMENT_WINDOW_EXPIRED":    return String(localized: "Время на оплату вышло. Заявка будет закрыта — создайте новую")
        case "INVALID_STATUS_TRANSITION": return String(localized: "Статус заявки изменился — обновите экран")
        case "NOT_FOUND":                 return String(localized: "Заявка не найдена")
        case "FORBIDDEN":                 return String(localized: "Покупка у брокера доступна только трейдерам")
        case "UNAUTHENTICATED":           return String(localized: "Войдите в аккаунт заново")
        default:                          return api.errorDescription ?? api.code
        }
    }
}

// MARK: - Время сервера

enum ServerTime {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Python `isoformat()` пишет до шести знаков долей секунды — обрезаем до миллисекунд
    static func parse(_ value: String) -> Date? {
        let trimmed = value.replacingOccurrences(
            of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression
        )
        return fractional.date(from: trimmed) ?? plain.date(from: trimmed)
    }

    static func decode<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) throws -> Date {
        let raw = try c.decode(String.self, forKey: key)
        guard let date = parse(raw) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Bad ISO 8601: \(raw)")
        }
        return date
    }
}

/// Смещение серверных часов: таймеры считаются от времени сервера,
/// а не от часов телефона, поэтому перевод часов их не сдвигает.
nonisolated final class ServerClock: @unchecked Sendable {
    private(set) var offset: TimeInterval = 0

    func sync(serverTime: Date) {
        offset = serverTime.timeIntervalSince(Date())
    }

    var now: Date { Date().addingTimeInterval(offset) }

    func remaining(until deadline: Date) -> TimeInterval {
        max(0, deadline.timeIntervalSince(now))
    }
}

/// Таймер оплаты и котировки: остаток по часам сервера, формат мм:сс,
/// последние две минуты — срочно
enum PaymentTimer {
    /// Окно оплаты сервера — 15 минут
    static let window: TimeInterval = 15 * 60
    static let urgentBelow: TimeInterval = 120

    static func remaining(until deadline: Date, clock: ServerClock) -> TimeInterval {
        clock.remaining(until: deadline)
    }

    /// Доля оставшегося окна для кругового индикатора, 0…1
    static func progress(_ remaining: TimeInterval, window: TimeInterval = window) -> Double {
        guard window > 0 else { return 0 }
        return min(1, max(0, remaining / window))
    }

    static func isUrgent(_ remaining: TimeInterval) -> Bool { remaining <= urgentBelow }

    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
