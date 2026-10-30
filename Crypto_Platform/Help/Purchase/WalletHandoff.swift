//
//  WalletHandoff.swift
//  Crypto_Platform
//
//  Ссылки между платформой и кошельком. Формат общий с Android и вебом:
//  запрос на оплату — hoazinwallet://send или https://…/wallet/send,
//  ссылка возврата — hoazinplatform://purchases/<id> или https://…/purchases/<id>.

import Foundation
import UIKit

enum WalletHandoff {

    static let webOrigin = "https://hse-server.tw1.ru"
    static let walletScheme = "hoazinwallet"
    static let platformScheme = "hoazinplatform"

    /// Запрос на оплату в приложение-кошелёк
    static func walletLink(for request: PurchaseRequest) -> URL? {
        guard let form = request.payment else { return nil }
        return build(
            base: "\(walletScheme)://send",
            form: form,
            requestId: request.id,
            returnURL: "\(platformScheme)://purchases/\(request.id)"
        )
    }

    /// Тот же запрос для веб-кошелька — если приложения-кошелька на телефоне нет
    static func webWalletLink(for request: PurchaseRequest) -> URL? {
        guard let form = request.payment else { return nil }
        return build(
            base: "\(webOrigin)/wallet/send",
            form: form,
            requestId: request.id,
            returnURL: "\(webOrigin)/purchases/\(request.id)"
        )
    }

    /// Платёжная ссылка для QR: без request_id и return_url
    static func qrLink(for form: PaymentForm) -> URL? {
        build(base: "\(webOrigin)/wallet/send", form: form, requestId: nil, returnURL: nil)
    }

    private static func build(base: String, form: PaymentForm, requestId: Int?, returnURL: String?) -> URL? {
        // Сумма — ровно с тремя знаками; если у суммы их больше, ссылку не строим:
        // округлять сумму платежа нельзя
        guard let amount = amountText(form) else { return nil }

        var pairs: [(String, String)] = [("to", form.wallet_address), ("amount", amount), ("asset", "HZN")]
        if let requestId { pairs.append(("request_id", String(requestId))) }
        if let memo = form.memo, !memo.isEmpty { pairs.append(("memo", memo)) }
        if let returnURL { pairs.append(("return_url", returnURL)) }

        let query = pairs.map { "\($0.0)=\(encode($0.1))" }.joined(separator: "&")
        return URL(string: "\(base)?\(query)")
    }

    static func amountText(_ form: PaymentForm) -> String? {
        let text = form.crypto_amount_text
        if text.range(of: #"^\d+\.\d{3}$"#, options: .regularExpression) != nil { return text }
        guard form.crypto_amount.scale <= 3, form.crypto_amount > 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 3
        formatter.maximumFractionDigits = 3
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: form.crypto_amount))
    }

    /// RFC 3986: кодируется всё, кроме unreserved; пробел — %20, не «+»
    static func encode(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}

/// Ссылка возврата из кошелька: принимается целиком или отбрасывается целиком
enum PurchaseReturnLinks {

    struct Link: Equatable {
        let requestId: Int
        /// nil — пользователь вернулся без оплаты
        let txHash: String?
    }

    static func parse(_ url: URL) -> Link? {
        guard url.absoluteString.count <= 2048, url.fragment == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        let segments: [String]
        switch components.scheme?.lowercased() {
        case WalletHandoff.platformScheme:
            // hoazinplatform://purchases/<id>
            guard components.host == "purchases" else { return nil }
            segments = components.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init).dropFirst().map { $0 }
        case "https":
            // https://hse-server.tw1.ru/purchases/<id>
            guard components.host == "hse-server.tw1.ru", components.port == nil else { return nil }
            let parts = components.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, parts[0].isEmpty, parts[1] == "purchases" else { return nil }
            segments = [parts[2]]
        default:
            return nil
        }

        guard segments.count == 1, let rawId = segments.first,
              rawId.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil,
              let id = Int(rawId) else { return nil }

        // Повтор ключа — отказ: иначе можно проверить первый, а использовать второй
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            if values[item.name] != nil { return nil }
            values[item.name] = item.value ?? ""
        }

        if let paid = values["paid"], paid != "1" { return nil }

        guard let tx = values["tx_hash"] else { return Link(requestId: id, txHash: nil) }
        guard values["paid"] == "1", TransactionHash.isValid(tx) else { return nil }
        return Link(requestId: id, txHash: tx.lowercased())
    }
}

/// Хеш транзакции HZN: 64 hex, без префикса 0x
enum TransactionHash {
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isValid(_ raw: String) -> Bool {
        normalize(raw).range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
    }
}

/// Порядок открытия ссылки: https как Universal Link (сразу в приложении), затем
/// собственная схема приложения, затем та же https-ссылка в браузере
enum LinkOpener {
    struct Step {
        let url: URL
        /// Открыть, только если ссылку примет приложение (Universal Link)
        let appOnly: Bool
    }

    static func steps(web: URL?, scheme: URL?) -> [Step] {
        [web.map { Step(url: $0, appOnly: true) }, scheme.map { Step(url: $0, appOnly: false) },
         web.map { Step(url: $0, appOnly: false) }].compactMap { $0 }
    }

    /// `completion` получает номер сработавшего шага или nil
    @MainActor
    static func open(_ steps: [Step], index: Int = 0, completion: @escaping (Int?) -> Void = { _ in }) {
        guard index < steps.count else { return completion(nil) }
        let step = steps[index]
        UIApplication.shared.open(step.url, options: step.appOnly ? [.universalLinksOnly: true] : [:]) { opened in
            if opened { completion(index) } else { open(steps, index: index + 1, completion: completion) }
        }
    }
}
