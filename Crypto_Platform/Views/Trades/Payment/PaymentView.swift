//
//  PaymentView.swift
//  Crypto_Platform
//
//  Окно оплаты после того, как брокер забронировал заявку.

import SwiftUI
import CoreImage.CIFilterBuiltins

struct PaymentView: View {
    @EnvironmentObject var session: UserSession
    @Environment(\.scenePhase) private var scenePhase

    let order: BrokerOrder
    let amountUsd: Double
    let rate: CryptoRate?
    /// Сообщить владельцу флоу, что оплата отправлена
    var onPaid: (() -> Void)?

    @StateObject private var store: PaymentStore
    @State private var showWalletFallback = false
    @FocusState private var hashFocused: Bool

    init(
        order: BrokerOrder,
        amountUsd: Double,
        rate: CryptoRate?,
        api: OrdersAPI,
        onPaid: (() -> Void)? = nil
    ) {
        self.order = order
        self.amountUsd = amountUsd
        self.rate = rate
        self.onPaid = onPaid
        _store = StateObject(wrappedValue: PaymentStore(api: api))
    }

    private var cryptoAmount: Double {
        store.invoice?.amount ?? rate?.convert(usd: amountUsd) ?? amountUsd
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch store.phase {
                case .loading:
                    ProgressView("Готовим форму оплаты…")
                        .padding(.top, 60)

                case .expired:
                    OrderTerminalView(kind: .expired, order: order)

                case .submitted:
                    OrderTerminalView(
                        kind: .submitted(hash: store.txHashInput),
                        order: order
                    )

                case .failed(let message):
                    failureBlock(message)

                case .awaitingPayment, .submitting:
                    timerBlock
                    paymentDetailsBlock
                    walletButton
                    hashInputBlock

                    if store.isStubbed {
                        stubNotice
                    }
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Оплата")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadInvoice(token: session.accessToken, order: order, amount: cryptoAmount)
        }
        .onChange(of: scenePhase) { _, phase in
            // После сворачивания часы могли уйти вперёд — пересверяем срок
            if phase == .active { store.refreshAfterForeground() }
        }
    }

    // MARK: Таймер

    private var timerBlock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(spacing: 10) {
                Text("Оплатите в течение")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)

                Text(store.remainingText)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(store.isRunningOut ? .red : .primary)
                    .contentTransition(.numericText(countsDown: true))

                ProgressView(value: store.elapsedFraction)
                    .tint(store.isRunningOut ? .red : .accentColor)

                if store.isRunningOut {
                    Text("Время заканчивается — после истечения заявка отменится")
                        .font(.caption2)
                        .foregroundStyle(Palette.negative)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: Radius.card)
                    .fill(Palette.surface)
            )
        }
    }

    // MARK: Данные платежа

    @ViewBuilder
    private var paymentDetailsBlock: some View {
        if let invoice = store.invoice {
            VStack(spacing: 16) {

                VStack(spacing: 4) {
                    Text("К переводу")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(formatCrypto(invoice.amount))
                            .font(.title)
                            .fontWeight(.bold)
                        Text(invoice.asset)
                            .font(.headline)
                            .foregroundStyle(Palette.secondaryText)
                    }

                    Text("сеть \(invoice.network)")
                        .font(.caption2)
                        .foregroundStyle(Palette.secondaryText)
                }

                qrCode(for: paymentURI(invoice))

                copyRow(
                    title: "Адрес кошелька",
                    value: invoice.walletAddress,
                    field: "address"
                )

                copyRow(
                    title: "Сумма",
                    value: formatCrypto(invoice.amount),
                    field: "amount"
                )

                Text("Переводите строго в сети \(invoice.network). Перевод в другой сети приведёт к потере средств.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: Radius.card)
                    .fill(Palette.surface)
            )
        }
    }

    private func copyRow(title: String, value: String, field: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)

            HStack {
                Text(value)
                    .font(.system(.footnote, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)

                Spacer()

                Button {
                    store.copy(value, field: field)
                } label: {
                    Image(systemName: store.copiedField == field ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(store.copiedField == field ? .green : .accentColor)
                }
                .buttonStyle(.borderless)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(Palette.surface)
            )
        }
    }

    // MARK: QR

    private func qrCode(for text: String) -> some View {
        Group {
            if let image = Self.makeQR(from: text) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 190, height: 190)
                    .padding(10)
                    .background(Color.white)
                    .cornerRadius(12)
            } else {
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 190, height: 190)
                    .overlay(Text("QR недоступен").font(.caption))
            }
        }
    }

    private static func makeQR(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// URI платежа — его же кодируем в QR и передаём кошельку
    private func paymentURI(_ invoice: PaymentInvoice) -> String {
        "tron:\(invoice.walletAddress)?amount=\(formatCrypto(invoice.amount))&token=\(invoice.asset)"
    }

    // MARK: Переход в кошелёк

    @ViewBuilder
    private var walletButton: some View {
        if let invoice = store.invoice {
            VStack(spacing: 8) {
                Button {
                    openWallet(invoice: invoice)
                } label: {
                    Label("Открыть в криптокошельке", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)

                if showWalletFallback {
                    VStack(spacing: 6) {
                        Text("Кошелёк не установлен")
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryText)

                        Text("Скопируйте адрес и сумму — или установите приложение, поддерживающее \(invoice.network)")
                            .font(.caption2)
                            .foregroundStyle(Palette.secondaryText)
                            .multilineTextAlignment(.center)

                        Button("Скопировать адрес") {
                            store.copy(invoice.walletAddress, field: "address")
                        }
                        .font(.caption)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control)
                            .fill(Color.orange.opacity(0.1))
                    )
                }
            }
        }
    }

    /// Пробуем схемы по очереди. `open` не требует LSApplicationQueriesSchemes —
    /// в отличие от canOpenURL, поэтому проверяем результатом колбэка.
    private func openWallet(invoice: PaymentInvoice) {
        // Свой кошелёк первым: он получает и заявку, и адрес возврата,
        // поэтому чек-сумма вернётся в приложение автоматически.
        let own = "hoazinwallet://pay"
            + "?address=\(invoice.walletAddress)"
            + "&amount=\(formatCrypto(invoice.amount))"
            + "&asset=\(invoice.asset)"
            + "&network=\(invoice.network)"
            + "&order_id=\(order.id)"
            + "&callback=hoazinplatform"

        let candidates = [
            own,
            "tronlink://send?to=\(invoice.walletAddress)&amount=\(formatCrypto(invoice.amount))&token=\(invoice.asset)",
            "trust://send?address=\(invoice.walletAddress)&amount=\(formatCrypto(invoice.amount))",
            paymentURI(invoice)
        ].compactMap { URL(string: $0) }

        openFirstAvailable(candidates)
    }

    private func openFirstAvailable(_ urls: [URL]) {
        guard let url = urls.first else {
            showWalletFallback = true
            return
        }

        UIApplication.shared.open(url, options: [:]) { success in
            if !success {
                openFirstAvailable(Array(urls.dropFirst()))
            }
        }
    }

    // MARK: Чек-сумма

    private var hashInputBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Хеш транзакции")
                .font(.headline)

            Text("После перевода вставьте хеш — брокер сверит платёж")
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)

            HStack {
                TextField("64 символа", text: $store.txHashInput)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($hashFocused)

                if !store.txHashInput.isEmpty {
                    Button {
                        store.txHashInput = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .buttonStyle(.borderless)
                }

                Button {
                    if let clip = UIPasteboard.general.string {
                        store.txHashInput = clip
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control)
                    .stroke(store.txHashError == nil ? Color.clear : Color.red, lineWidth: 1)
            )

            if let error = store.txHashError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Palette.negative)
            } else if !store.txHashInput.isEmpty {
                Label("Формат верный", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(Palette.positive)
            }

            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Palette.negative)
            }

            Button {
                hashFocused = false
                Task {
                    await store.submitHash(token: session.accessToken, orderId: order.id)
                    if store.phase == .submitted { onPaid?() }
                }
            } label: {
                HStack {
                    if store.phase == .submitting {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                    Text(store.phase == .submitting ? "Отправляем…" : "Подтвердить оплату")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .disabled(!store.canSubmitHash || store.phase == .submitting)
        }
        .animation(.easeOut(duration: 0.15), value: store.txHashError)
    }

    // MARK: Прочее

    private func failureBlock(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Не удалось получить форму оплаты")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)

            Button("Повторить") {
                Task {
                    await store.loadInvoice(
                        token: session.accessToken,
                        order: order,
                        amount: cryptoAmount
                    )
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 60)
    }

    private var stubNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.negative)

            VStack(alignment: .leading, spacing: 4) {
                Text("Тестовый режим — не переводите сюда деньги")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.negative)

                Text("Платёжная часть API не реализована, форма собрана локально. Адрес ничей: приватного ключа к нему не существует, реальный перевод будет потерян безвозвратно.")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Radius.control)
                .fill(Color.red.opacity(0.12))
        )
    }
}
