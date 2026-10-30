//
//  PurchaseStore.swift
//  Crypto_Platform
//
//  Покупка у брокера: котировка, заявка, оплата, отмена, «Мои заявки».

import SwiftUI
import Combine

@MainActor
final class PurchaseStore: ObservableObject {

    private let api: APIClient
    let clock = ServerClock()

    /// Заявки трейдера, свежие сверху
    @Published private(set) var requests: [PurchaseRequest] = []
    @Published private(set) var isLoadingList = false
    @Published var listError: String?

    /// Ссылка возврата из кошелька, которую нужно открыть после входа
    @Published var pendingReturn: PurchaseReturnLinks.Link?

    /// Валюты оплаты из /crypto-currencies
    @Published private(set) var cryptoCurrencies: [CryptoCurrency] = []

    init(api: APIClient) {
        self.api = api
    }

    var active: [PurchaseRequest] { requests.filter { $0.status?.isTerminal != true } }
    var finished: [PurchaseRequest] { requests.filter { $0.status?.isTerminal == true } }

    func reset() {
        requests = []
        listError = nil
        pendingReturn = nil
    }

    // MARK: Контракт

    /// Валюта оплаты по умолчанию, пока список не загружен
    static let defaultCryptoCurrency = "HZN"

    func loadCryptoCurrencies() async {
        guard cryptoCurrencies.isEmpty else { return }
        if let list = try? await api.get("crypto-currencies", as: CryptoCurrencyList.self) {
            cryptoCurrencies = list.items
        }
    }

    func quote(symbol: String, quantity: Decimal, cryptoCurrency: String) async throws -> PurchaseQuote {
        let quote = try await api.get("quotes", query: [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "quantity", value: quantity.plainString),
            URLQueryItem(name: "crypto_currency", value: cryptoCurrency)
        ], as: PurchaseQuote.self)
        clock.sync(serverTime: quote.server_time)
        AppAnalytics.log("purchase_quote_received", ["symbol": symbol, "amount_usd": quote.amount_usd.plainString])
        return quote
    }

    /// Количество уходит ровно той строкой, что вернула котировка:
    /// сервер сверяет его с quote_id, и трейдер платит ту сумму, которую видел
    func create(from quote: PurchaseQuote) async throws -> PurchaseRequest {
        let envelope = try await api.post("purchase-requests", body: [
            "symbol": quote.symbol,
            "quantity": quote.quantity,
            "quote_id": quote.quote_id,
            "crypto_currency": quote.crypto_currency
        ], as: PurchaseRequestEnvelope.self)
        apply(envelope)
        AppAnalytics.log("purchase_request_created", ["symbol": quote.symbol, "request_id": String(envelope.request.id)])
        return envelope.request
    }

    func request(id: Int) async throws -> PurchaseRequest {
        let envelope = try await api.get("purchase-requests/\(id)", as: PurchaseRequestEnvelope.self)
        apply(envelope)
        return envelope.request
    }

    /// Хеш уходит на сервер только по нажатию «Подтвердить оплату»;
    /// повтор того же хеша по той же заявке сервер принимает
    func submitProof(id: Int, txHash: String) async throws -> PurchaseRequest {
        let envelope = try await api.post("purchase-requests/\(id)/payment-proof",
                                          body: ["tx_hash": TransactionHash.normalize(txHash)],
                                          as: PurchaseRequestEnvelope.self)
        apply(envelope)
        AppAnalytics.log("purchase_payment_proof_sent", ["request_id": String(id)])
        return envelope.request
    }

    func cancel(id: Int) async throws -> PurchaseRequest {
        let envelope = try await api.post("purchase-requests/\(id)/cancel", body: [String: String](), as: PurchaseRequestEnvelope.self)
        apply(envelope)
        AppAnalytics.log("purchase_request_cancelled", ["request_id": String(id)])
        return envelope.request
    }

    func loadList(limit: Int = 50) async {
        isLoadingList = requests.isEmpty
        defer { isLoadingList = false }
        do {
            let page = try await api.get("purchase-requests", query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: "0")
            ], as: PurchaseRequestPage.self)
            clock.sync(serverTime: page.server_time)
            requests = page.items
            listError = nil
        } catch {
            listError = PurchaseErrorText.message(for: error)
        }
    }

    private func apply(_ envelope: PurchaseRequestEnvelope) {
        clock.sync(serverTime: envelope.server_time)
        let request = envelope.request
        if let index = requests.firstIndex(where: { $0.id == request.id }) {
            let wasTerminal = requests[index].status?.isTerminal == true
            requests[index] = request
            logFinishedIfNeeded(request, wasTerminal: wasTerminal)
        } else {
            requests.insert(request, at: 0)
            logFinishedIfNeeded(request, wasTerminal: false)
        }
    }

    /// purchase_request_finished — один раз на заявку, сколько бы её ни опрашивали
    private var finishedLogged: Set<Int> = []
    private func logFinishedIfNeeded(_ request: PurchaseRequest, wasTerminal: Bool) {
        guard request.status?.isTerminal == true, !wasTerminal, !finishedLogged.contains(request.id) else { return }
        finishedLogged.insert(request.id)
        AppAnalytics.log("purchase_request_finished", ["request_id": String(request.id), "status": request.statusValue])
    }

    // MARK: Опрос

    /// Опрос заявки, пока открыт экран: раз в 3 с, при ошибках интервал
    /// удваивается до 30 с. На терминальном статусе опрос заканчивается.
    func poll(id: Int, onUpdate: @escaping (PurchaseRequest) -> Void) async {
        await Poller.run(interval: 3) {
            let request = try await self.request(id: id)
            onUpdate(request)
            return request.status?.isTerminal != true
        }
    }

    /// Опрос списка «Мои заявки»: раз в 5 с
    func pollList() async {
        await Poller.run(interval: 5) {
            await self.loadList()
            return true
        }
    }
}

enum Poller {
    static let maxInterval: TimeInterval = 30

    /// `step` возвращает false, когда опрашивать больше не нужно.
    /// Цикл живёт в `.task` экрана и отменяется вместе с ним.
    static func run(interval: TimeInterval, _ step: @escaping () async throws -> Bool) async {
        var delay = interval
        while !Task.isCancelled {
            do {
                guard try await step() else { return }
                delay = interval
            } catch is CancellationError {
                return
            } catch {
                delay = min(delay * 2, maxInterval)
            }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}
