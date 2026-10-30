//
//  NewPurchaseView.swift
//  Crypto_Platform
//
//  Новая заявка на покупку у брокера: актив, валюта оплаты, количество, итог.

import SwiftUI

/// Количество бумаг: больше нуля, не больше 4 знаков после запятой (шаг сервера 0.0001)
enum PurchaseQuantity {
    enum Check: Equatable {
        case empty, invalid, valid(Decimal)
    }

    static func check(_ text: String) -> Check {
        let raw = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if raw.isEmpty { return .empty }
        guard raw.range(of: #"^\d+(\.\d{1,4})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")),
              value > 0 else { return .invalid }
        return .valid(value)
    }
}

struct NewPurchaseView: View {
    @EnvironmentObject var purchases: PurchaseStore
    @EnvironmentObject var assetsStore: AssetsStore

    /// Тикер приходит с карточки актива; из «Сделок» пользователь выбирает его сам
    @State private var symbol: String
    @State private var cryptoCurrency = PurchaseStore.defaultCryptoCurrency
    @State private var quantityText = ""
    @State private var quote: PurchaseQuote?
    @State private var isQuoting = false
    @State private var isCreating = false
    @State private var errorText: String?
    @State private var createdId: Int?
    @FocusState private var quantityFocused: Bool

    init(symbol: String? = nil) {
        _symbol = State(initialValue: symbol ?? "")
    }

    private var quantityCheck: PurchaseQuantity.Check { PurchaseQuantity.check(quantityText) }

    private var isQuantityValid: Bool {
        if case .valid = quantityCheck { return true }
        return false
    }

    private var assetName: String {
        assetsStore.assets.first { $0.symbol == symbol }?.name ?? ""
    }

    private var isQuoteLive: Bool {
        guard let quote else { return false }
        return purchases.clock.remaining(until: quote.expires_at) > 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                assetSection
                currencySection
                quantitySection

                if let quote {
                    totalSection(quote)
                } else if isQuoting {
                    ProgressView().frame(maxWidth: .infinity)
                }

                if let errorText {
                    NoticeView(kind: .error, title: LocalizedStringKey(errorText))
                }

                if errorText != nil, quote == nil, !symbol.isEmpty, isQuantityValid {
                    refreshRateButton
                }

                confirmButton
            }
            .padding(Spacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Новая заявка")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $createdId) { id in
            PurchaseRequestView(requestId: id)
        }
        .onChange(of: quantityText) { _, _ in quote = nil; errorText = nil }
        .onChange(of: symbol) { _, _ in quote = nil; errorText = nil }
        .onChange(of: cryptoCurrency) { _, _ in quote = nil; errorText = nil }
        // Итог считается сам, когда актив и количество заданы;
        // пауза — чтобы не дёргать сервер на каждую введённую цифру
        .task(id: "\(symbol)|\(quantityText)|\(cryptoCurrency)") {
            guard !symbol.isEmpty, isQuantityValid else { return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await requestQuote()
        }
        .task {
            await assetsStore.loadAssets()
            await purchases.loadCryptoCurrencies()
        }
    }

    // MARK: Актив, валюта, количество

    private var assetSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader("Актив")

            Menu {
                ForEach(assetsStore.assets) { asset in
                    Button("\(asset.symbol) · \(asset.name)") { symbol = asset.symbol }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(symbol.isEmpty ? String(localized: "Выберите акцию") : symbol)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(symbol.isEmpty ? Palette.secondaryText : Palette.primaryText)
                        if !assetName.isEmpty {
                            Text(assetName).font(.caption).foregroundStyle(Palette.secondaryText)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
                .card()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Актив"))
        }
    }

    private var selectedCurrency: CryptoCurrency? {
        purchases.cryptoCurrencies.first { $0.code == cryptoCurrency }
    }

    private var currencySection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader("Валюта оплаты")

            Menu {
                ForEach(purchases.cryptoCurrencies) { currency in
                    Button("\(currency.code) · сеть \(currency.network)") { cryptoCurrency = currency.code }
                }
            } label: {
                HStack {
                    Text("\(cryptoCurrency), сеть \(selectedCurrency?.network ?? cryptoCurrency)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.primaryText)
                    Spacer()
                    if purchases.cryptoCurrencies.count > 1 {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
                .card()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Валюта оплаты"))
        }
    }

    private var quantitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader("Количество")

            HStack {
                TextField("0", text: $quantityText)
                    .keyboardType(.decimalPad)
                    .font(.title3.monospacedDigit())
                    .focused($quantityFocused)
                    .accessibilityLabel(Text("Количество"))
                Text("шт.").foregroundStyle(Palette.secondaryText)
            }
            .card()

            if quantityCheck == .invalid {
                Text("Больше нуля, не более 4 знаков после запятой")
                    .font(.caption)
                    .foregroundStyle(Palette.negative)
            }
        }
    }

    // MARK: Итог

    private func totalSection(_ quote: PurchaseQuote) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader("Итог")

            DataGroup {
                DataRow(label: "Цена за акцию", value: formatCurrency(quote.price_usd))
                HairlineDivider()
                DataRow(label: "Сумма в USD", value: formatCurrency(quote.amount_usd))
                HairlineDivider()
                DataRow(label: "Курс", value: "1 \(quote.crypto_currency) = \(formatCurrency(quote.rate_usd_per_crypto))")
                HairlineDivider()
                DataRow(label: "К оплате", value: formatHZN(quote.crypto_amount), isStrong: true)
            }

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let left = purchases.clock.remaining(until: quote.expires_at)
                HStack {
                    Text(left > 0
                         ? String(localized: "Курс обновится через \(PaymentTimer.format(left))")
                         : String(localized: "Курс устарел"))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(left > 10 ? Palette.secondaryText : Color.orange)
                    Spacer()
                    if left <= 0 {
                        Button(String(localized: "Обновить курс")) { Task { await requestQuote() } }
                            .font(.caption.weight(.medium))
                            .disabled(isQuoting)
                    }
                }
                // Котировка перезапрашивается сама, когда её срок доходит до нуля
                .task(id: left <= 0) {
                    if left <= 0, !isQuoting { await requestQuote() }
                }
            }
        }
    }

    private var refreshRateButton: some View {
        Button(String(localized: "Обновить курс")) { Task { await requestQuote() } }
            .buttonStyle(.secondaryOutline)
            .disabled(isQuoting)
    }

    private var confirmButton: some View {
        Button {
            quantityFocused = false
            Task { await createRequest() }
        } label: {
            HStack {
                if isCreating { ProgressView().tint(.white) }
                Text("Подтвердить заявку")
            }
        }
        .buttonStyle(.primary)
        .disabled(!isQuoteLive || isQuoting || isCreating)
    }

    // MARK: Действия

    private func requestQuote() async {
        guard case let .valid(quantity) = quantityCheck, !symbol.isEmpty else { return }
        isQuoting = true
        defer { isQuoting = false }
        do {
            quote = try await purchases.quote(symbol: symbol, quantity: quantity, cryptoCurrency: cryptoCurrency)
            errorText = nil
        } catch is CancellationError {
            // Пользователь изменил ввод — итог пересчитает новый цикл
        } catch {
            quote = nil
            errorText = PurchaseErrorText.message(for: error)
            AppAnalytics.log("purchase_error", ["step": "quote", "code": (error as? APIError)?.code ?? "UNKNOWN"])
        }
    }

    private func createRequest() async {
        guard let quote else { return }
        isCreating = true
        errorText = nil
        defer { isCreating = false }
        do {
            let request = try await purchases.create(from: quote)
            createdId = request.id
        } catch let error as APIError where ["QUOTE_EXPIRED", "QUOTE_NOT_FOUND"].contains(error.code) {
            // Курс устарел: пересчитываем итог, пользователь подтверждает заново
            await requestQuote()
            errorText = PurchaseErrorText.message(for: error)
        } catch {
            errorText = PurchaseErrorText.message(for: error)
            AppAnalytics.log("purchase_error", ["step": "create", "code": (error as? APIError)?.code ?? "UNKNOWN"])
        }
    }
}
