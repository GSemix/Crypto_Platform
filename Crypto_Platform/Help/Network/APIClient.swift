//
//  APIClient.swift
//  Crypto_Platform
//
//  Единая точка запросов к API платформы.
//
//  Access-токен живёт только в памяти. Refresh-токен — HttpOnly-cookie
//  сервера в ephemeral-сессии, поэтому на диск не попадает ни то, ни другое:
//  после выгрузки процесса нужен новый вход.

import Foundation

struct APIError: LocalizedError, Equatable {
    let status: Int
    /// Код из `{"error": "<CODE>"}` либо текст ошибки сервера
    let code: String

    static let network = APIError(status: 0, code: "NETWORK")
    static let unauthorized = APIError(status: 401, code: "UNAUTHENTICATED")

    var isNetwork: Bool { status == 0 }

    var errorDescription: String? {
        if isNetwork { return String(localized: "Нет связи с сервером") }
        if status == 401 { return String(localized: "Войдите в аккаунт заново") }
        return code
    }
}

@MainActor
final class APIClient {

    static let baseURL = URL(string: "https://hse-server.tw1.ru/api/")!

    /// Сессию сбросил сервер (refresh не прошёл) — экраны должны показать вход
    var onSessionExpired: (() -> Void)?

    private(set) var accessToken: String?
    private let session: URLSession
    /// Cookie живут только в памяти этой сессии
    private let cookies: HTTPCookieStorage?
    /// Один refresh на все параллельные 401
    private var refreshTask: Task<Bool, Never>?

    /// `configuration` подменяется в тестах (свой URLProtocol вместо сервера)
    init(configuration: URLSessionConfiguration = .ephemeral) {
        let config = configuration
        config.timeoutIntervalForRequest = 30
        config.httpCookieAcceptPolicy = .always
        cookies = config.httpCookieStorage
        session = URLSession(configuration: config)
    }

    /// Закрывает соединения сессии; клиент приложения живёт весь процесс, это нужно тестам
    func close() { session.invalidateAndCancel() }

    var isAuthenticated: Bool { accessToken != nil }

    var hasSession: Bool { accessToken != nil }

    func setAccessToken(_ token: String?) {
        accessToken = token
    }

    func clearSession() {
        accessToken = nil
        cookies?.removeCookies(since: .distantPast)
    }

    // MARK: Запросы

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        try decode(type, from: try await send("GET", path, query: query))
    }

    func post<T: Decodable>(_ path: String, body: Any? = nil, as type: T.Type = T.self) async throws -> T {
        try decode(type, from: try await send("POST", path, body: body))
    }

    func put<T: Decodable>(_ path: String, body: Any? = nil, as type: T.Type = T.self) async throws -> T {
        try decode(type, from: try await send("PUT", path, body: body))
    }

    func delete<T: Decodable>(_ path: String, body: Any? = nil, as type: T.Type = T.self) async throws -> T {
        try decode(type, from: try await send("DELETE", path, body: body))
    }

    /// Запрос без разбора тела ответа
    @discardableResult
    func send(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Any? = nil) async throws -> Data {
        var attempt = 0
        while true {
            do {
                return try await sendOnce(method, path, query: query, body: body, allowRefresh: true)
            } catch let error as APIError {
                // Повтор только для чтения: повтор POST после обрыва мог бы создать второй ордер
                guard RetryPolicy.shouldRetry(method: method, error: error, attempt: attempt) else { throw error }
                attempt += 1
                try? await Task.sleep(nanoseconds: RetryPolicy.delayNanos(attempt: attempt))
            }
        }
    }

    private func sendOnce(_ method: String, _ path: String, query: [URLQueryItem], body: Any?, allowRefresh: Bool) async throws -> Data {
        let request = try makeRequest(method, path, query: query, body: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.network
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401, allowRefresh, !Self.usesRefreshCookie(path), accessToken != nil {
            if await refresh() {
                return try await sendOnce(method, path, query: query, body: body, allowRefresh: false)
            }
            throw APIError.unauthorized
        }

        guard (200...299).contains(status) else {
            throw APIError(status: status, code: Self.errorCode(from: data) ?? "HTTP_\(status)")
        }
        return data
    }

    private func makeRequest(_ method: String, _ path: String, query: [URLQueryItem], body: Any?) throws -> URLRequest {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // jwt/refresh и auth/logout аутентифицируются refresh-cookie. С заголовком
        // Authorization сервер берёт токен из него и отвечает 422.
        if !Self.usesRefreshCookie(path), let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if method != "GET", let csrf = csrfToken {
            request.setValue(csrf, forHTTPHeaderField: "X-CSRF-TOKEN")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private static func usesRefreshCookie(_ path: String) -> Bool {
        path == "jwt/refresh" || path == "auth/logout"
    }

    private var csrfToken: String? {
        cookies?.cookies?
            .first { $0.name == "csrf_refresh_token" }?.value
    }

    // MARK: Refresh

    /// Параллельные запросы, получившие 401, ждут один и тот же refresh,
    /// поэтому ротация refresh-токена не устраивает гонку.
    private func refresh() async -> Bool {
        if let refreshTask { return await refreshTask.value }

        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            do {
                let data = try await self.sendOnce("PUT", "jwt/refresh", query: [], body: nil, allowRefresh: false)
                let token = try JSONDecoder().decode(AccessTokenResponse.self, from: data).access_token
                self.accessToken = token
                return true
            } catch {
                return false
            }
        }
        refreshTask = task
        let ok = await task.value
        refreshTask = nil

        if !ok {
            clearSession()
            onSessionExpired?()
        }
        return ok
    }

    // MARK: Разбор

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError(status: 200, code: "DECODING")
        }
    }

    /// Сервер кладёт ошибку под `error`, `message` или `msg` — по-разному в разных blueprint'ах
    static func errorCode(from data: Data) -> String? {
        guard let body = try? JSONDecoder().decode(APIErrorResponse.self, from: data) else { return nil }
        return body.error ?? body.message ?? body.msg
    }
}

struct AccessTokenResponse: Decodable {
    let access_token: String
}

struct EmptyResponse: Decodable {}

struct APIErrorResponse: Decodable {
    let error: String?
    let message: String?
    let msg: String?
}

/// Повторяется только GET и только при сбое сети или 502/503/504:
/// не больше двух раз, пауза 500 мс × номер попытки.
enum RetryPolicy {
    static let maxRetries = 2

    static func shouldRetry(method: String, error: APIError, attempt: Int) -> Bool {
        guard method == "GET", attempt < maxRetries else { return false }
        return error.isNetwork || [502, 503, 504].contains(error.status)
    }

    static func delayNanos(attempt: Int) -> UInt64 {
        UInt64(attempt) * 500_000_000
    }
}
