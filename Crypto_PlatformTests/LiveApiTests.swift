//
//  LiveApiTests.swift
//  Crypto_PlatformTests
//
//  Live-тест на рабочем сервере. Запускается только с переменными окружения
//  HOAZIN_LIVE_EMAIL и HOAZIN_LIVE_PASSWORD (в xcodebuild — с префиксом
//  TEST_RUNNER_); без них пропускается. Создаёт и сразу отменяет заявку,
//  деньги не двигает.

import XCTest
@testable import Crypto_Platform

@MainActor
final class LiveApiTests: XCTestCase {
    private var email = ""
    private var password = ""

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let e = env["HOAZIN_LIVE_EMAIL"], let p = env["HOAZIN_LIVE_PASSWORD"], !e.isEmpty, !p.isEmpty else {
            throw XCTSkip("HOAZIN_LIVE_EMAIL / HOAZIN_LIVE_PASSWORD не заданы")
        }
        email = e; password = p
    }

    private var clients: [APIClient] = []

    override func tearDown() async throws {
        clients.forEach { $0.close() }
        clients = []
    }

    private func login() async throws -> APIClient {
        let api = APIClient()
        clients.append(api)
        let auth: AccessTokenResponse = try await api.post("auth/login", body: ["email": email, "password": password])
        api.setAccessToken(auth.access_token)
        return api
    }

    func testLoginReadsAndLogout() async throws {
        let api = try await login()
        let me: UserProfileResponse = try await api.get("users/me")
        XCTAssertEqual(me.email, email)
        _ = try await api.get("portfolio/balance", as: PortfolioBalanceResponse.self)
        _ = try await api.get("portfolio/unrealized-pnl", as: UnrealizedPnlResponse.self)
        _ = try await api.get("orders", query: [URLQueryItem(name: "limit", value: "5")], as: Page<OrderItem>.self)
        _ = try await api.get("trades", query: [URLQueryItem(name: "limit", value: "5")], as: Page<TradeItem>.self)
        _ = try await api.get("notifications", as: NotificationPage.self)
        _ = try await api.get("notifications/settings", as: NotificationSettingsBody.self)
        try await api.send("DELETE", "auth/logout")
        api.clearSession()
    }

    /// Обновление токена по refresh-cookie с CSRF и без Authorization; новый токен работает
    func testRefreshRotatesAccessToken() async throws {
        let api = try await login()
        let before = api.accessToken
        let data = try await api.send("PUT", "jwt/refresh")
        let fresh = try JSONDecoder().decode(AccessTokenResponse.self, from: data).access_token
        XCTAssertNotEqual(fresh, before)
        api.setAccessToken(fresh)
        let me: UserProfileResponse = try await api.get("users/me")
        XCTAssertEqual(me.email, email)
        try await api.send("DELETE", "auth/logout")
        // После выхода refresh-токен отозван
        do { _ = try await api.send("PUT", "jwt/refresh"); XCTFail("refresh после выхода должен быть отклонён") } catch {}
    }

    /// Котировка, заявка, список, отмена — заявка отменяется сразу, до брокера
    func testPurchaseQuoteCreateCancel() async throws {
        let api = try await login()
        let store = PurchaseStore(api: api)
        let assets = try await api.get("assets", as: [Asset].self)
        let symbol = try XCTUnwrap(assets.first?.symbol)
        let quote = try await store.quote(symbol: symbol, quantity: Decimal(string: "0.0001")!, cryptoCurrency: "HZN")
        XCTAssertGreaterThan(quote.expires_at, quote.server_time)
        let created = try await store.create(from: quote)
        XCTAssertEqual(created.status, .pendingBroker)
        await store.loadList()
        XCTAssertTrue(store.requests.contains { $0.id == created.id })
        let cancelled = try await store.cancel(id: created.id)
        XCTAssertEqual(cancelled.status, .cancelled)
        try await api.send("DELETE", "auth/logout")
    }
}
