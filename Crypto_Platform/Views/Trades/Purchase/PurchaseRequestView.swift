//
//  PurchaseRequestView.swift
//  Crypto_Platform
//
//  Заявка на покупку: статус, форма оплаты с таймером, переход в кошелёк,
//  подтверждение оплаты хешем, отмена.

import SwiftUI
import CoreImage.CIFilterBuiltins

struct PurchaseRequestView: View {
    @EnvironmentObject var purchases: PurchaseStore
    @Environment(\.scenePhase) private var scenePhase

    let requestId: Int
    /// Хеш из ссылки возврата: подставляется в поле, на сервер уходит по кнопке
    var returnedTxHash: String?

    @State private var request: PurchaseRequest?
    @State private var loadError: String?
    @State private var txHash = ""
    @State private var actionError: String?
    @State private var isSending = false
    @State private var isCancelling = false
    @State private var showCancelConfirm = false
    @State private var copiedField: String?
    @State private var proofSent = false
    @State private var showNewPurchase = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if let request {
                    statusHeader(request)

                    if returnedTxHash != nil, request.status == .awaitingPayment {
                        NoticeView(kind: .info, title: "Вернулись из кошелька — проверьте хеш и подтвердите оплату")
                    }

                    if let form = request.payment, request.status == .awaitingPayment {
                        paymentSection(request, form)
                        proofSection(request)
                    }

                    summary(request)

                    if proofSent, request.status == .paymentSubmitted {
                        NoticeView(kind: .info, title: "Оплата отправлена на проверку")
                    }

                    if let actionError {
                        NoticeView(kind: .error, title: LocalizedStringKey(actionError))
                    }

                    if request.status?.canCancel == true {
                        Button(String(localized: "Отменить заявку"), role: .destructive) { showCancelConfirm = true }
                            .buttonStyle(.secondaryOutline)
                            .disabled(isCancelling)
                    }

                    if request.status?.isTerminal == true, request.status != .filled {
                        Button(String(localized: "Создать новую заявку")) { showNewPurchase = true }
                            .buttonStyle(.primary)
                    }
                } else if let loadError {
                    NoticeView(kind: .error, title: "Не удалось загрузить заявку", message: loadError,
                               action: ("Повторить", { Task { await load() } }))
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, Spacing.xl)
                }
            }
            .padding(Spacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(String(localized: "Заявка №\(requestId)"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(String(localized: "Отменить заявку?"), isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button(String(localized: "Отменить заявку"), role: .destructive) { Task { await cancel() } }
            Button(String(localized: "Оставить"), role: .cancel) {}
        }
        .navigationDestination(isPresented: $showNewPurchase) {
            NewPurchaseView(symbol: request?.symbol)
        }
        .onAppear {
            if let returnedTxHash, txHash.isEmpty { txHash = returnedTxHash }
        }
        // Опрос живёт, пока экран открыт и приложение активно
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await purchases.poll(id: requestId) { updated in
                request = updated
                loadError = nil
            }
        }
        .task { if request == nil { await load() } }
    }

    // MARK: Статус

    private func statusHeader(_ request: PurchaseRequest) -> some View {
        let status = request.status
        return VStack(alignment: .leading, spacing: Spacing.s) {
            Label(status?.title ?? request.statusValue, systemImage: status?.systemImage ?? "questionmark.circle")
                .font(.headline)
                .foregroundStyle(status?.color ?? Palette.secondaryText)
            if let status {
                Text(status.detail).font(.subheadline).foregroundStyle(Palette.secondaryText)
            }
            if let reason = request.reason, !reason.isEmpty,
               [.rejectedByBroker, .paymentFailed].contains(status) {
                Text(reason).font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }

    // MARK: Форма оплаты

    private func paymentSection(_ request: PurchaseRequest, _ form: PaymentForm) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader("Реквизиты платежа")

            PaymentTimerView(deadline: form.payment_deadline, clock: purchases.clock)

            if purchases.clock.remaining(until: form.payment_deadline) <= 0 {
                NoticeView(kind: .error, title: "Время на оплату вышло. Заявка будет закрыта — создайте новую")
            }

            DataGroup {
                copyRow(label: "К оплате", value: formatHZN(form.crypto_amount),
                        copyValue: form.crypto_amount_text.isEmpty ? form.crypto_amount.plainString : form.crypto_amount_text,
                        key: "amount", isStrong: true)
                HairlineDivider()
                copyRow(label: "Адрес брокера", value: form.wallet_address, copyValue: form.wallet_address,
                        key: "address", isMonospaced: true)
                HairlineDivider()
                DataRow(label: "Сеть", value: form.network)
                if let memo = form.memo, !memo.isEmpty {
                    HairlineDivider()
                    DataRow(label: "Назначение", value: memo)
                }
            }

            if let qr = WalletHandoff.qrLink(for: form), let image = QRCode.image(qr.absoluteString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .padding(Spacing.s)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: Radius.control))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text("QR-код платёжной ссылки"))
            }

            Button {
                openWallet(request)
            } label: {
                Label(String(localized: "Оплатить в кошельке"), systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.primary)
            .disabled(WalletHandoff.walletLink(for: request) == nil)
        }
    }

    private func copyRow(label: LocalizedStringKey, value: String, copyValue: String, key: String,
                         isStrong: Bool = false, isMonospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            DataRow(label: label, value: value, isMonospaced: isMonospaced, isStrong: isStrong)
            Button {
                UIPasteboard.general.string = copyValue
                copiedField = key
            } label: {
                Label(copiedField == key ? String(localized: "Скопировано") : String(localized: "Копировать"),
                      systemImage: copiedField == key ? "checkmark" : "doc.on.doc")
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.bottom, Spacing.xs)
        }
    }

    /// Сначала приложение-кошелёк; если его нет — веб-кошелёк в браузере
    /// Кошелёк по Universal Link, затем по схеме `hoazinwallet`; если его нет — веб-кошелёк в браузере
    private func openWallet(_ request: PurchaseRequest) {
        let steps = LinkOpener.steps(web: WalletHandoff.webWalletLink(for: request), scheme: WalletHandoff.walletLink(for: request))
        LinkOpener.open(steps) { index in
            guard let index else { return }
            let target = steps[index].appOnly || index == 1 ? "app" : "web"
            AppAnalytics.log("purchase_wallet_opened", ["request_id": String(request.id), "target": target])
        }
    }

    // MARK: Подтверждение оплаты

    private func proofSection(_ request: PurchaseRequest) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader("Хеш транзакции")

            HStack {
                TextField(String(localized: "64 символа"), text: $txHash)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel(Text("Хеш транзакции"))
                Button(String(localized: "Вставить")) {
                    if let clip = UIPasteboard.general.string { txHash = clip }
                }
                .font(.footnote.weight(.medium))
            }
            .card()

            if !txHash.isEmpty {
                let valid = TransactionHash.isValid(txHash)
                Text(valid ? "Формат верный" : "Нужно 64 hex-символа")
                    .font(.caption)
                    .foregroundStyle(valid ? Palette.positive : Palette.negative)
            }

            Button {
                Task { await submitProof() }
            } label: {
                HStack {
                    if isSending { ProgressView().tint(.white) }
                    Text("Подтвердить оплату")
                }
            }
            .buttonStyle(.primary)
            .disabled(!TransactionHash.isValid(txHash) || isSending)
        }
    }

    // MARK: Сводка

    private func summary(_ request: PurchaseRequest) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader("Заявка")
            DataGroup {
                DataRow(label: "Акция", value: request.symbol)
                HairlineDivider()
                DataRow(label: "Количество", value: formatQuantity(request.quantity))
                HairlineDivider()
                DataRow(label: "Цена за штуку", value: formatCurrency(request.price_usd))
                HairlineDivider()
                DataRow(label: "Сумма", value: formatCurrency(request.amount_usd))
                HairlineDivider()
                DataRow(label: "В HZN", value: formatHZN(request.crypto_amount))
                if let hash = request.tx_hash {
                    HairlineDivider()
                    DataRow(label: "Хеш", value: hash, isMonospaced: true)
                }
            }
        }
    }

    // MARK: Действия

    private func load() async {
        do {
            request = try await purchases.request(id: requestId)
            loadError = nil
        } catch {
            loadError = PurchaseErrorText.message(for: error)
        }
    }

    private func submitProof() async {
        isSending = true
        actionError = nil
        defer { isSending = false }
        do {
            request = try await purchases.submitProof(id: requestId, txHash: txHash)
            proofSent = true
        } catch {
            actionError = PurchaseErrorText.message(for: error)
            AppAnalytics.log("purchase_error", ["step": "payment_proof", "code": (error as? APIError)?.code ?? "UNKNOWN"])
        }
    }

    private func cancel() async {
        isCancelling = true
        actionError = nil
        defer { isCancelling = false }
        do {
            request = try await purchases.cancel(id: requestId)
        } catch {
            actionError = PurchaseErrorText.message(for: error)
        }
    }
}

// MARK: - Таймер оплаты

/// Круговой отсчёт до дедлайна оплаты по часам сервера; последние две минуты — красный
struct PaymentTimerView: View {
    let deadline: Date
    let clock: ServerClock
    var window: TimeInterval = PaymentTimer.window

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let left = PaymentTimer.remaining(until: deadline, clock: clock)
            let urgent = PaymentTimer.isUrgent(left)
            HStack(spacing: Spacing.m) {
                ZStack {
                    Circle().stroke(Palette.hairline, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: PaymentTimer.progress(left, window: window))
                        .stroke(urgent ? Palette.negative : Palette.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: left)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Время на оплату").label()
                    Text(PaymentTimer.format(left))
                        .numeric(24)
                        .foregroundStyle(urgent ? Palette.negative : Palette.primaryText)
                }
                Spacer()
            }
            .card()
            .accessibilityElement(children: .combine)
        }
    }

}

enum QRCode {
    static func image(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
