//
//  OrderConfirmationView.swift
//  Crypto_Platform
//
//  Шаг 2 — сводка и подтверждение заявки.

import SwiftUI

struct OrderConfirmationView: View {
    @EnvironmentObject var session: UserSession
    @ObservedObject var flow: OrderFlowStore

    @State private var goToWaiting = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                summaryCard

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

                if let error = flow.errorMessage {
                    errorBanner(error)
                }

                if isRateStale {
                    staleWarning
                }

                submitButton

                Text("Заявка уйдёт брокеру на подтверждение. Списание произойдёт только после того, как брокер её забронирует.")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("Подтверждение")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goToWaiting) {
            OrderWaitingView(flow: flow)
        }
        .onDisappear {
            flow.errorMessage = nil
        }
    }

    private var isRateStale: Bool {
        flow.rate?.isStale ?? false
    }

    // MARK: Сводка

    private var summaryCard: some View {
        VStack(spacing: 0) {
            summaryRow("Актив", value: flow.symbol, caption: flow.assetName)
            Divider().padding(.leading)
            summaryRow("Операция", value: "Покупка")
            Divider().padding(.leading)
            summaryRow("Тип", value: "По рыночной цене")
            Divider().padding(.leading)
            summaryRow("Количество", value: "\(formatQuantity(flow.quantity)) шт.")
            Divider().padding(.leading)
            summaryRow("Цена за штуку", value: formatCurrency(flow.pricePerShare))
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(Palette.surface)
        )
    }

    private func summaryRow(
        _ title: String,
        value: String,
        caption: String? = nil
    ) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(Palette.secondaryText)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .fontWeight(.medium)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
        }
        .padding()
    }

    // MARK: Состояния

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(Palette.negative)
            Text(text)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Radius.control)
                .fill(Color.red.opacity(0.1))
        )
    }

    private var staleWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.orange)
            Text("Курс устарел — обновите его перед отправкой")
                .font(.caption)
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Radius.control)
                .fill(Color.orange.opacity(0.1))
        )
    }

    private var submitButton: some View {
        Button {
            Task {
                await flow.submit(accessToken: session.accessToken)

                if flow.createdOrder != nil {
                    flow.startPolling(accessToken: session.accessToken)
                    goToWaiting = true
                }
            }
        } label: {
            HStack {
                if flow.isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(flow.isSubmitting ? "Отправляем…" : "Отправить заявку")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.primary)
        .disabled(flow.isSubmitting || isRateStale || !flow.canSubmit)
    }
}
