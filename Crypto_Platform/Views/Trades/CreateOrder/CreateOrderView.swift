//
//  CreateOrderView.swift
//  Crypto_Platform
//
//  Шаг 1 — выбор тикера и количества.

import SwiftUI

struct CreateOrderView: View {
    @EnvironmentObject var session: UserSession
    @EnvironmentObject var assetsStore: AssetsStore
    @StateObject private var flow = OrderFlowStore()

    /// Предвыбранный актив (когда заходим с карточки), иначе выбираем в списке
    let preselected: Asset?

    @State private var showConfirmation = false
    @FocusState private var quantityFocused: Bool

    init(preselected: Asset? = nil) {
        self.preselected = preselected
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                tickerSection

                if flow.pricePerShare > 0 {
                    quantitySection

                    OrderTotalBlock(
                        quantity: flow.quantity,
                        pricePerShare: flow.pricePerShare,
                        subtotal: flow.subtotalUsd,
                        commissionRate: OrderFlowStore.estimatedCommissionRate,
                        commission: flow.commissionUsd,
                        total: flow.totalUsd
                    )

                    CryptoConversionBlock(
                        totalUsd: flow.totalUsd,
                        rate: flow.rate,
                        isLoading: flow.isRateLoading,
                        onRefresh: { await flow.refreshRate() }
                    )

                    continueButton
                } else if flow.symbol.isEmpty {
                    Text("Выберите тикер, чтобы продолжить")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .padding(.top, 8)
                } else {
                    priceUnavailable
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Новая заявка")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showConfirmation) {
            OrderConfirmationView(flow: flow)
        }
        .task {
            if let preselected {
                flow.prepare(
                    symbol: preselected.symbol,
                    name: preselected.name,
                    price: preselected.price
                )
                if !preselected.hasPrice {
                    await assetsStore.loadPrice(for: preselected.symbol)
                    if let updated = assetsStore.assets.first(where: { $0.symbol == preselected.symbol }) {
                        flow.pricePerShare = updated.price
                    }
                }
            }
            await flow.refreshRate()
        }
    }

    // MARK: Тикер

    private var tickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Актив")
                .font(.headline)

            if preselected != nil {
                selectedTickerCard
            } else {
                Menu {
                    ForEach(assetsStore.assets) { asset in
                        Button {
                            Task { await select(asset) }
                        } label: {
                            Text("\(asset.symbol) · \(asset.name)")
                        }
                    }
                } label: {
                    HStack {
                        if flow.symbol.isEmpty {
                            Text("Выбрать тикер")
                                .foregroundStyle(Palette.secondaryText)
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(flow.symbol)
                                    .fontWeight(.semibold)
                                Text(flow.assetName)
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondaryText)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: Radius.card)
                            .fill(Palette.surface)
                    )
                }
                .foregroundStyle(.primary)
            }
        }
    }

    private var selectedTickerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(flow.symbol)
                    .font(.headline)
                Text(flow.assetName)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }

            Spacer()

            if flow.pricePerShare > 0 {
                Text(formatCurrency(flow.pricePerShare))
                    .font(.headline)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(Palette.surface)
        )
    }

    private func select(_ asset: Asset) async {
        flow.prepare(symbol: asset.symbol, name: asset.name, price: asset.price)

        if !asset.hasPrice {
            await assetsStore.loadPrice(for: asset.symbol)
            if let updated = assetsStore.assets.first(where: { $0.symbol == asset.symbol }) {
                flow.pricePerShare = updated.price
            }
        }
    }

    // MARK: Количество

    private var quantitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Количество")
                .font(.headline)

            HStack {
                TextField("0", text: $flow.quantityText)
                    .keyboardType(.decimalPad)
                    .font(.title2)
                    .focused($quantityFocused)

                if !flow.quantityText.isEmpty {
                    Button {
                        flow.quantityText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .buttonStyle(.borderless)
                }

                Text("шт.")
                    .foregroundStyle(Palette.secondaryText)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: Radius.card)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .stroke(
                        flow.validation.errorText == nil ? Color.clear : Color.red,
                        lineWidth: 1
                    )
            )

            if let error = flow.validation.errorText {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Palette.negative)
                    .transition(.opacity)
            }

            // Быстрый ввод
            HStack(spacing: 8) {
                ForEach([1, 5, 10, 25], id: \.self) { amount in
                    Button {
                        flow.quantityText = String(amount)
                    } label: {
                        Text("\(amount)")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: flow.validation)
    }

    private var priceUnavailable: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("Не удалось получить цену \(flow.symbol)")
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
            Button("Повторить") {
                Task {
                    await assetsStore.loadPrice(for: flow.symbol)
                    if let updated = assetsStore.assets.first(where: { $0.symbol == flow.symbol }) {
                        flow.pricePerShare = updated.price
                    }
                }
            }
            .font(.caption)
        }
        .padding(.top, 24)
    }

    private var continueButton: some View {
        Button {
            quantityFocused = false
            showConfirmation = true
        } label: {
            Text("Продолжить")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.primary)
        .disabled(!flow.canSubmit)
    }
}
