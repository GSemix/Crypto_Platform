//
//  PlatformTests.swift
//  Crypto_PlatformTests
//
//  Ссылки в кошелёк и обратно, количество бумаг, время сервера и разбор
//  ответов API. Образцы ответов — в формате развёрнутого сервера.

import XCTest
@testable import Crypto_Platform

private let broker = "2b63467f2df2fd7a1aa568c22cc9d7c46f90b5c0cff301cead"
private let sampleHash = String(repeating: "ab", count: 32)

/// Заявка в ответе сервера: `{"request": {...}, "server_time": "..."}`
private func envelope(status: String = "AWAITING_PAYMENT", amount: String = "5969.930", memo: String = "PR-42") -> Data {
    let payment = status == "AWAITING_PAYMENT" ? """
    {"crypto_currency":"HZN","network":"HZN","crypto_amount":"\(amount)","wallet_address":"\(broker)","memo":"\(memo)","payment_deadline":"2026-10-29T18:35:51.340608+03:00"}
    """ : "null"
    return Data("""
    {"request":{"amount_usd":"5969.93","broker_email":null,"created_at":"2026-10-29T15:20:51.340608Z","crypto_amount":"\(amount)","crypto_currency":"HZN","id":42,"payment":\(payment),"price_usd":"1672.02488599","quantity":"0.0001","rate_usd_per_crypto":"1.00000000","reason":null,"status":"\(status)","symbol":"FCNCA","tx_hash":null,"updated_at":"2026-10-29T18:20:51.614565+03:00","user_email":"trader@example.com","user_id":1},"server_time":"2026-10-29T15:20:51.621244Z"}
    """.utf8)
}

@MainActor
final class WalletHandoffTests: XCTestCase {
    private func request(_ data: Data = envelope()) throws -> PurchaseRequest {
        try JSONDecoder().decode(PurchaseRequestEnvelope.self, from: data).request
    }

    func testWalletAndWebLinks() throws {
        let r = try request()
        XCTAssertEqual(WalletHandoff.walletLink(for: r)?.absoluteString,
                       "hoazinwallet://send?to=\(broker)&amount=5969.930&asset=HZN&request_id=42&memo=PR-42&return_url=hoazinplatform%3A%2F%2Fpurchases%2F42")
        XCTAssertEqual(WalletHandoff.webWalletLink(for: r)?.absoluteString,
                       "https://hse-server.tw1.ru/wallet/send?to=\(broker)&amount=5969.930&asset=HZN&request_id=42&memo=PR-42&return_url=https%3A%2F%2Fhse-server.tw1.ru%2Fpurchases%2F42")
        XCTAssertEqual(WalletHandoff.qrLink(for: r.payment!)?.absoluteString,
                       "https://hse-server.tw1.ru/wallet/send?to=\(broker)&amount=5969.930&asset=HZN&memo=PR-42")
    }

    func testMemoIsEncodedRfc3986() throws {
        let link = WalletHandoff.walletLink(for: try request(envelope(memo: "Заказ 1+2")))!.absoluteString
        XCTAssertTrue(link.contains("memo=%D0%97%D0%B0%D0%BA%D0%B0%D0%B7%201%2B2"), link)
    }

    /// Больше трёх знаков у суммы — ссылку не строим: округлять сумму платежа нельзя
    func testNoLinkForFineAmount() throws {
        XCTAssertNil(WalletHandoff.walletLink(for: try request(envelope(amount: "1.0005"))))
        XCTAssertNil(WalletHandoff.walletLink(for: try request(envelope(status: "PENDING_BROKER"))))
    }

    func testReturnLinks() {
        let ok = URL(string: "hoazinplatform://purchases/42?tx_hash=\(sampleHash)&paid=1")!
        XCTAssertEqual(PurchaseReturnLinks.parse(ok), PurchaseReturnLinks.Link(requestId: 42, txHash: sampleHash))
        XCTAssertEqual(PurchaseReturnLinks.parse(URL(string: "https://hse-server.tw1.ru/purchases/42?tx_hash=\(sampleHash.uppercased())&paid=1")!)?.txHash, sampleHash)
        XCTAssertEqual(PurchaseReturnLinks.parse(URL(string: "hoazinplatform://purchases/42")!), PurchaseReturnLinks.Link(requestId: 42, txHash: nil))
        for bad in ["hoazinplatform://purchases/42?tx_hash=abc&paid=1",
                    "hoazinplatform://purchases/42?tx_hash=\(sampleHash)&paid=0",
                    "hoazinplatform://purchases/42?tx_hash=\(sampleHash)&tx_hash=\(sampleHash)&paid=1",
                    "hoazinplatform://purchases/42/extra",
                    "hoazinplatform://purchases/42#frag",
                    "hoazinplatform://evil/42",
                    "https://evil.example/purchases/42",
                    "otherapp://purchases/42"] {
            XCTAssertNil(PurchaseReturnLinks.parse(URL(string: bad)!), bad)
        }
    }

    func testTransactionHash() {
        XCTAssertTrue(TransactionHash.isValid(" \(sampleHash.uppercased()) "))
        XCTAssertFalse(TransactionHash.isValid(String(sampleHash.dropLast())))
        XCTAssertFalse(TransactionHash.isValid(String(repeating: "g", count: 64)))
    }
}

@MainActor
final class PurchaseModelTests: XCTestCase {
    func testQuantity() {
        XCTAssertEqual(PurchaseQuantity.check(""), .empty)
        XCTAssertEqual(PurchaseQuantity.check("0,0001"), .valid(Decimal(string: "0.0001")!))
        for bad in ["0", "0.00001", "1e3", "-1", "abc", ".5"] { XCTAssertEqual(PurchaseQuantity.check(bad), .invalid, bad) }
    }

    func testServerTime() {
        XCTAssertNotNil(ServerTime.parse("2026-10-29T15:19:29.692808Z"))
        XCTAssertEqual(ServerTime.parse("2026-10-29T18:20:51.340608+03:00"), ServerTime.parse("2026-10-29T15:20:51.340Z"))
    }

    func testDecodeRequestAndPage() throws {
        let r = try JSONDecoder().decode(PurchaseRequestEnvelope.self, from: envelope()).request
        XCTAssertEqual(r.status, .awaitingPayment)
        XCTAssertEqual(r.payment?.crypto_amount_text, "5969.930")
        XCTAssertEqual(r.quantity, Decimal(string: "0.0001"))
        let unknown = try JSONDecoder().decode(PurchaseRequestEnvelope.self, from: envelope(status: "SOMETHING_NEW")).request
        XCTAssertNil(unknown.status)
        XCTAssertEqual(unknown.statusValue, "SOMETHING_NEW")
        let page = Data(#"{"items":[],"limit":50,"offset":0,"server_time":"2026-10-29T15:19:29.692808Z","total":0}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(PurchaseRequestPage.self, from: page).total, 0)
    }

    func testDecodeQuote() throws {
        let quote = Data(#"{"amount_usd":"0.17","crypto_amount":"0.170","crypto_currency":"HZN","expires_at":"2026-10-29T18:22:35.391001+03:00","network":"HZN","price_usd":"1672.02488599","quantity":"0.0001","quote_id":"q_1","rate_source":"internal","rate_usd_per_crypto":"1.00000000","server_time":"2026-10-29T15:20:35.398886Z","symbol":"FCNCA"}"#.utf8)
        let q = try JSONDecoder().decode(PurchaseQuote.self, from: quote)
        XCTAssertEqual(q.quantity, "0.0001")
        XCTAssertEqual(q.crypto_amount, Decimal(string: "0.17"))
        XCTAssertEqual(q.expires_at.timeIntervalSince(q.server_time), 120, accuracy: 0.1)
    }

    func testDecodeBalanceWithExponentZero() throws {
        let data = Data(#"{"available_balance":"386219.24307719","reserved_balance":"0E-8","total_balance":"386219.24307719"}"#.utf8)
        let balance = try JSONDecoder().decode(PortfolioBalanceResponse.self, from: data)
        XCTAssertEqual(balance.reserved_balance, 0)
        XCTAssertEqual(balance.total_balance, Decimal(string: "386219.24307719"))
    }

    func testErrorTexts() {
        XCTAssertEqual(PurchaseErrorText.message(for: APIError(status: 409, code: "QUOTE_EXPIRED")),
                       "Курс устарел — пересчитайте сумму и подтвердите заново")
        XCTAssertEqual(PurchaseErrorText.message(for: APIError(status: 0, code: "NETWORK")), "Нет связи с сервером")
        XCTAssertEqual(PurchaseErrorText.message(for: APIError(status: 503, code: "X")), "Сервис временно недоступен, попробуйте позже")
    }

    func testNotificationsDecode() throws {
        let page = Data(#"{"items":[{"body":"Лимитная заявка отменена","created_at":"2026-10-27T15:29:09.513971+03:00","data":{},"id":39,"is_read":false,"read_at":null,"title":"Отменена","type":"ORDER_CANCELLED"}],"limit":20,"offset":0,"total":16}"#.utf8)
        let decoded = try JSONDecoder().decode(NotificationPage.self, from: page)
        XCTAssertEqual(decoded.items.first?.id, 39)
        XCTAssertEqual(decoded.total, 16)
        XCTAssertTrue(decoded.items.first?.markedRead().is_read ?? false)
    }
}
