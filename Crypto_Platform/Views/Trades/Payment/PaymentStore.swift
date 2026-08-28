//
//  PaymentStore.swift
//  Crypto_Platform
//
//  Состояние окна оплаты: форма, таймер на 15 минут и отправка чек-суммы.

import SwiftUI
import Combine

enum PaymentPhase: Equatable {
    case loading
    case awaitingPayment
    case submitting
    case submitted
    case expired
    case failed(String)

    var isTerminal: Bool {
        switch self {
        case .submitted, .expired: return true
        default: return false
        }
    }
}

@MainActor
final class PaymentStore: ObservableObject {

    @Published private(set) var invoice: PaymentInvoice?
    @Published private(set) var phase: PaymentPhase = .loading
    @Published private(set) var isStubbed = false

    @Published var txHashInput = ""
    @Published var errorMessage: String?
    @Published var copiedField: String?

    private let api: OrdersAPI
    private var expiryTask: Task<Void, Never>?

    init(api: OrdersAPI) {
        self.api = api
    }

    deinit {
        expiryTask?.cancel()
    }

    // MARK: Таймер

    /// Срок считаем по часам сервера: если на телефоне сбиты часы,
    /// таймер всё равно покажет верный остаток.
    var remaining: TimeInterval {
        guard let invoice else { return 0 }
        return max(0, invoice.expiresAt.timeIntervalSince(api.serverNow))
    }

    var isExpired: Bool {
        invoice != nil && remaining <= 0
    }

    var remainingText: String {
        let total = Int(remaining.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// Доля прошедшего времени — для индикатора
    var elapsedFraction: Double {
        guard let invoice else { return 0 }
        let total = invoice.expiresAt.timeIntervalSince(invoice.createdAt)
        guard total > 0 else { return 1 }
        return min(1, max(0, 1 - remaining / total))
    }

    var isRunningOut: Bool {
        remaining > 0 && remaining <= 120
    }

    // MARK: Загрузка формы

    func loadInvoice(token: String, order: BrokerOrder, amount: Double) async {
        phase = .loading
        errorMessage = nil

        do {
            // Если форма уже создана — забираем её, иначе создаём
            let existing = try? await api.fetchPaymentInvoice(token: token, orderId: order.id)
            let result: PaymentInvoice

            if let existing {
                result = existing
            } else {
                result = try await api.createPaymentInvoice(
                    token: token,
                    orderId: order.id,
                    amount: amount
                )
            }

            invoice = result
            isStubbed = api.isInvoiceStubbed(orderId: order.id)

            if let submitted = api.submittedTransactionHash(orderId: order.id) {
                txHashInput = submitted
                phase = .submitted
                return
            }

            phase = remaining > 0 ? .awaitingPayment : .expired
            scheduleExpiry()

        } catch let error as APIError {
            phase = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        } catch {
            phase = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    /// Просыпается ровно к моменту истечения. Работает и после сворачивания:
    /// при возвращении в приложение состояние ещё раз сверяется в `refreshAfterForeground`.
    private func scheduleExpiry() {
        expiryTask?.cancel()

        let seconds = remaining
        guard seconds > 0 else {
            phase = .expired
            return
        }

        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }

            await MainActor.run {
                if self.phase == .awaitingPayment, self.remaining <= 0 {
                    self.phase = .expired
                }
            }
        }
    }

    /// Вызывать при возврате приложения из фона
    func refreshAfterForeground() {
        guard invoice != nil else { return }

        if remaining <= 0 {
            expiryTask?.cancel()
            if phase == .awaitingPayment { phase = .expired }
        } else if phase == .awaitingPayment {
            scheduleExpiry()
        }
    }

    // MARK: Чек-сумма

    var txHashError: String? {
        TransactionHash.validationError(txHashInput)
    }

    var canSubmitHash: Bool {
        TransactionHash.isValid(txHashInput)
            && phase == .awaitingPayment
            && !isExpired
    }

    func submitHash(token: String, orderId: String) async {
        guard canSubmitHash else { return }

        phase = .submitting
        errorMessage = nil

        do {
            _ = try await api.submitTransactionHash(
                token: token,
                orderId: orderId,
                txHash: TransactionHash.normalize(txHashInput)
            )
            phase = .submitted
        } catch let error as APIError {
            errorMessage = error.localizedDescription
            phase = .awaitingPayment
        } catch {
            errorMessage = error.localizedDescription
            phase = .awaitingPayment
        }
    }

    // MARK: Буфер обмена

    func copy(_ value: String, field: String) {
        UIPasteboard.general.string = value
        copiedField = field

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if copiedField == field { copiedField = nil }
        }
    }
}
