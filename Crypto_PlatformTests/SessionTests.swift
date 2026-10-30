//
//  SessionTests.swift
//  Crypto_PlatformTests
//
//  Сетевой слой и сессия платформы на подменённых ответах сервера:
//  один refresh на одновременные 401, заголовки, CSRF, повторы, ошибки, выход.

import XCTest
@testable import Crypto_Platform

/// Подменяет сервер: отвечает по пути и записывает запросы
final class StubServer: URLProtocol {
    struct Reply { let status: Int; let body: String; var headers: [String: String] = [:] }
    nonisolated(unsafe) static var handler: ((URLRequest) -> Reply)?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    private static let lock = NSLock()

    static func reset(_ handler: @escaping (URLRequest) -> Reply) {
        lock.lock(); requests = []; self.handler = handler; lock.unlock()
    }
    static func recorded() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests.append(request); let handler = Self.handler; Self.lock.unlock()
        let reply = handler?(request) ?? Reply(status: 500, body: "{}")
        if reply.status == -1 {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil,
                                       headerFields: reply.headers.merging(["Content-Type": "application/json"]) { a, _ in a })!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class SessionTests: XCTestCase {
    private func makeClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubServer.self]
        return APIClient(configuration: config)
    }

    private func path(_ r: URLRequest) -> String { r.url!.path.replacingOccurrences(of: "/api/", with: "") }

    func testConcurrent401sShareOneRefreshAndRetryWithNewToken() async throws {
        StubServer.reset { r in
            if r.url!.path.hasSuffix("jwt/refresh") { return .init(status: 200, body: #"{"access_token":"new"}"#) }
            let auth = r.value(forHTTPHeaderField: "Authorization")
            return auth == "Bearer new" ? .init(status: 200, body: "{}") : .init(status: 401, body: #"{"msg":"expired"}"#)
        }
        let api = makeClient()
        api.setAccessToken("old")
        async let a: EmptyResponse = api.get("users/me")
        async let b: EmptyResponse = api.get("portfolio/balance")
        async let c: EmptyResponse = api.get("orders")
        _ = try await (a, b, c)
        let refreshes = StubServer.recorded().filter { path($0) == "jwt/refresh" }
        XCTAssertEqual(refreshes.count, 1)
        XCTAssertEqual(refreshes.first?.httpMethod, "PUT")
        XCTAssertEqual(api.accessToken, "new")
    }

    func testRefreshAndLogoutGoWithoutAuthorization() async throws {
        StubServer.reset { _ in .init(status: 200, body: #"{"message":"ok"}"#) }
        let api = makeClient()
        api.setAccessToken("token")
        try await api.send("DELETE", "auth/logout")
        _ = try await api.get("users/me", as: EmptyResponse.self)
        let requests = StubServer.recorded()
        XCTAssertNil(requests.first { path($0) == "auth/logout" }?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(requests.first { path($0) == "users/me" }?.value(forHTTPHeaderField: "Authorization"), "Bearer token")
    }

    func testCsrfHeaderOnWritesFromRefreshCookie() async throws {
        StubServer.reset { r in
            if r.url!.path.hasSuffix("auth/login") {
                return .init(status: 200, body: #"{"access_token":"t"}"#,
                             headers: ["Set-Cookie": "csrf_refresh_token=CSRF123; Path=/"])
            }
            return .init(status: 200, body: "{}")
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubServer.self]
        let api = APIClient(configuration: config)
        let auth: AccessTokenResponse = try await api.post("auth/login", body: ["email": "a", "password": "b"])
        api.setAccessToken(auth.access_token)
        // Подменённый сервер не проходит обработку cookie URLSession — кладём их, как она
        let url = URL(string: "https://hse-server.tw1.ru/api/auth/login")!
        config.httpCookieStorage?.setCookies(HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": "csrf_refresh_token=CSRF123; Path=/"], for: url),
                                             for: url, mainDocumentURL: nil)
        _ = try await api.post("orders", body: ["symbol": "X"], as: EmptyResponse.self)
        _ = try await api.get("orders", as: EmptyResponse.self)
        let requests = StubServer.recorded()
        XCTAssertEqual(requests.first { path($0) == "orders" && $0.httpMethod == "POST" }?.value(forHTTPHeaderField: "X-CSRF-TOKEN"), "CSRF123")
        XCTAssertNil(requests.first { path($0) == "orders" && $0.httpMethod == "GET" }?.value(forHTTPHeaderField: "X-CSRF-TOKEN"))
    }

    func testFailedRefreshClearsSessionAndNotifies() async {
        StubServer.reset { _ in .init(status: 401, body: #"{"msg":"expired"}"#) }
        let api = makeClient()
        api.setAccessToken("old")
        var expired = false
        api.onSessionExpired = { expired = true }
        do { _ = try await api.get("users/me", as: EmptyResponse.self); XCTFail() } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
        XCTAssertTrue(expired)
        XCTAssertFalse(api.hasSession)
    }

    func testOnlyGetIsRetriedOnGatewayErrors() async {
        StubServer.reset { _ in .init(status: 503, body: "{}") }
        let api = makeClient()
        _ = try? await api.get("assets", as: EmptyResponse.self)
        XCTAssertEqual(StubServer.recorded().count, 3, "GET: попытка и два повтора")
        StubServer.reset { _ in .init(status: 503, body: "{}") }
        _ = try? await api.post("orders", body: ["x": 1], as: EmptyResponse.self)
        XCTAssertEqual(StubServer.recorded().count, 1, "POST не повторяется")
        StubServer.reset { _ in .init(status: 400, body: "{}") }
        _ = try? await api.get("assets", as: EmptyResponse.self)
        XCTAssertEqual(StubServer.recorded().count, 1, "400 не повторяется")
    }

    func testErrorCodeFromErrorMessageOrMsg() async {
        for (body, code) in [(#"{"error":"QUOTE_EXPIRED"}"#, "QUOTE_EXPIRED"), (#"{"message":"bad"}"#, "bad"), (#"{"msg":"nope"}"#, "nope")] {
            StubServer.reset { _ in .init(status: 409, body: body) }
            do { _ = try await makeClient().get("quotes", as: EmptyResponse.self); XCTFail() } catch {
                XCTAssertEqual((error as? APIError)?.code, code)
            }
        }
        StubServer.reset { _ in .init(status: -1, body: "") }
        do { _ = try await makeClient().post("orders", as: EmptyResponse.self); XCTFail() } catch {
            XCTAssertEqual(error as? APIError, .network)
        }
    }

    func testPaymentTimer() {
        XCTAssertEqual(PaymentTimer.format(899.2), "15:00")
        XCTAssertEqual(PaymentTimer.format(61), "01:01")
        XCTAssertEqual(PaymentTimer.format(-5), "00:00")
        XCTAssertTrue(PaymentTimer.isUrgent(120))
        XCTAssertFalse(PaymentTimer.isUrgent(121))
        XCTAssertEqual(PaymentTimer.progress(450), 0.5, accuracy: 0.001)
        let clock = ServerClock()
        clock.sync(serverTime: Date().addingTimeInterval(3600))
        let deadline = clock.now.addingTimeInterval(300)
        XCTAssertEqual(PaymentTimer.remaining(until: deadline, clock: clock), 300, accuracy: 1, "остаток — по часам сервера, не телефона")
    }
}
