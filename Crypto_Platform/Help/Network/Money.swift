//
//  Money.swift
//  Crypto_Platform
//
//  Денежные значения — Decimal, без двоичной плавающей точки.
//  Сервер присылает суммы строками (бывает и «0E-8»), реже числами.

import SwiftUI

/// Decimal из строки или числа JSON
struct DecimalValue: Decodable {
    let value: Decimal

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self), let d = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) {
            value = d
        } else if let d = try? c.decode(Decimal.self) {
            value = d
        } else {
            throw DecodingError.typeMismatch(Decimal.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected decimal string or number"))
        }
    }
}

extension KeyedDecodingContainer {
    func decimal(_ key: Key) -> Decimal {
        (try? decode(DecimalValue.self, forKey: key))?.value ?? 0
    }

    func decimalIfPresent(_ key: Key) -> Decimal? {
        (try? decodeIfPresent(DecimalValue.self, forKey: key))?.value
    }
}

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }

    /// Строка для отправки на сервер: точка, без группировки и экспоненты
    var plainString: String {
        NSDecimalNumber(decimal: self).description(withLocale: Locale(identifier: "en_US_POSIX"))
    }

    func rounded(_ scale: Int, _ mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, mode)
        return result
    }

    /// Знаков после запятой
    var scale: Int {
        let s = plainString
        guard let dot = s.firstIndex(of: ".") else { return 0 }
        return s.distance(from: s.index(after: dot), to: s.endIndex)
    }
}

// MARK: - Форматирование

func formatCurrency(_ value: Decimal, currency: String = "USD") -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSDecimalNumber(decimal: value)) ?? value.plainString
}

func formatPrice(_ value: Decimal) -> String {
    fixed(value, digits: 2)
}

/// Количество бумаг: до 4 знаков, без лишних нулей
func formatQuantity(_ value: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 4
    return formatter.string(from: NSDecimalNumber(decimal: value)) ?? value.plainString
}

/// HZN всегда с тремя знаками, как в контракте
func formatHZN(_ value: Decimal) -> String {
    fixed(value, digits: 3) + " HZN"
}

private func fixed(_ value: Decimal, digits: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = digits
    formatter.maximumFractionDigits = digits
    return formatter.string(from: NSDecimalNumber(decimal: value)) ?? value.plainString
}

extension Palette {
    static func value(_ number: Decimal) -> Color {
        number > 0 ? positive : (number < 0 ? negative : primaryText)
    }
}
