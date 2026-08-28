//
//  OrderWaitingView.swift
//  Crypto_Platform
//
//  Шаг 3 — ожидание решения брокера. Опрашивает GET /api/orders/{id}.

import SwiftUI

struct OrderWaitingView: View {
    @EnvironmentObject var session: UserSession
    @EnvironmentObject var api: OrdersAPI
    @ObservedObject var flow: OrderFlowStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let order = flow.createdOrder {
                    statusIcon(for: order.status)

                    VStack(spacing: 8) {
                        Text(order.status.title)
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(order.status.detail)
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryText)
                            .multilineTextAlignment(.center)

                        if let reason = order.statusReason, !reason.isEmpty {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(order.status == .rejected ? .red : .secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                    }

                    orderCard(order)

                    if flow.isPolling {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Проверяем статус… (запрос \(flow.pollAttempts))")
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryText)
                        }
                    }

                    if flow.isStubbed {
                        stubNotice
                    }

                    actions
                } else {
                    ProgressView("Отправляем заявку…")
                        .padding(.top, 80)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Заявка")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(flow.isPolling)
        .onDisappear {
            flow.stopPolling()
        }
    }

    // MARK: Компоненты

    private func statusIcon(for status: BrokerOrderStatus) -> some View {
        ZStack {
            Circle()
                .fill(status.color.opacity(0.15))
                .frame(width: 96, height: 96)

            Image(systemName: status.systemImage)
                .font(.system(size: 40))
                .foregroundStyle(status.color)
        }
        .animation(.spring(duration: 0.4), value: status)
    }

    /// Задеплоенная версия не заполняет цену, пока ордер не исполнен,
    /// и не считает суммы — тогда показываем то, что посчитали при оформлении.
    private func resolvedPrice(_ order: BrokerOrder) -> Double {
        order.executionPrice > 0 ? order.executionPrice : flow.pricePerShare
    }

    private func resolvedTotal(_ order: BrokerOrder) -> Double {
        order.totalAmountUsd > 0 ? order.totalAmountUsd : flow.totalUsd
    }

    private func orderCard(_ order: BrokerOrder) -> some View {
        let price = resolvedPrice(order)
        let total = resolvedTotal(order)

        return VStack(spacing: 0) {
            row("Заявка", value: shortId(order.id))
            Divider().padding(.leading)
            row("Актив", value: order.symbol)
            Divider().padding(.leading)
            row("Количество", value: String(localized: "\(formatQuantity(order.quantity)) шт."))
            Divider().padding(.leading)
            row(
                order.executionPrice > 0 ? "Цена исполнения" : "Цена (ожидаемая)",
                value: price > 0 ? formatCurrency(price) : "—"
            )
            Divider().padding(.leading)

            if order.commissionAmountUsd > 0 {
                row("Комиссия \(formatPercent(order.commissionRate))", value: formatCurrency(order.commissionAmountUsd))
                Divider().padding(.leading)
            }

            row("К оплате", value: total > 0 ? formatCurrency(total) : "—", isBold: true)

            if let rate = flow.rate, total > 0 {
                Divider().padding(.leading)
                row("В криптовалюте", value: "\(formatCrypto(rate.convert(usd: total))) \(rate.asset)")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(Palette.surface)
        )
    }

    private func row(_ title: LocalizedStringKey, value: String, isBold: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(isBold ? .bold : .medium)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var stubNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "theatermasks.fill")
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 4) {
                Text("Демонстрационный сценарий")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if let reason = flow.stubReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }

                Text("Статусы меняются локально, сервер в этом не участвует.")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Radius.control)
                .fill(Color.purple.opacity(0.12))
        )
        .padding(.horizontal)
    }

    @ViewBuilder
    private var actions: some View {
        if let order = flow.createdOrder {
            VStack(spacing: 12) {
                // Брокер забронировал бумаги — открывается окно оплаты с таймером
                if order.status == .paymentPending {
                    NavigationLink {
                        PaymentView(
                            order: order,
                            amountUsd: resolvedTotal(order),
                            rate: flow.rate,
                            api: api,
                            onPaid: { flow.markStubPaid() }
                        )
                    } label: {
                        Label("Перейти к оплате", systemImage: "creditcard")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: Radius.control)
                                    .fill(Color.accentColor)
                            )
                            .foregroundStyle(.white)
                    }
                }

                if order.status.isTerminal || !flow.isPolling {
                    Button {
                        flow.reset()
                        dismiss()
                    } label: {
                        Text("Готово")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primary)
                }

                if !order.status.isTerminal {
                    Button {
                        if flow.isPolling {
                            flow.stopPolling()
                        } else {
                            flow.startPolling(accessToken: session.accessToken)
                        }
                    } label: {
                        Text(flow.isPolling ? "Остановить проверку" : "Проверить снова")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.secondaryOutline)
                }
            }
        }
    }

    private func shortId(_ id: String) -> String {
        id.count > 12 ? "\(id.prefix(8))…" : id
    }
}
