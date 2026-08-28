//
//  OrderAmountBlocks.swift
//  Crypto_Platform
//
//  Блоки итоговой суммы и конвертации в криптовалюту.

import SwiftUI

// MARK: - Итоговая сумма в USD

struct OrderTotalBlock: View {
    let quantity: Double
    let pricePerShare: Double
    let subtotal: Double
    let commissionRate: Double
    let commission: Double
    let total: Double
    /// Комиссия ориентировочная, пока заявка не создана
    var isCommissionEstimated: Bool = true

    var body: some View {
        VStack(spacing: 12) {
            amountRow(
                title: "\(formatQuantity(quantity)) × \(formatCurrency(pricePerShare))",
                value: subtotal
            )

            amountRow(
                title: "Комиссия \(formatPercent(commissionRate))",
                value: commission,
                isSecondary: true
            )

            Divider()

            HStack {
                Text("Итого")
                    .font(.headline)

                Spacer()

                Text(formatCurrency(total))
                    .font(.title3)
                    .fontWeight(.bold)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: total)
            }

            if isCommissionEstimated {
                Text("Комиссия предварительная — точную назначает брокер при создании заявки")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(Palette.surface)
        )
    }

    private func amountRow(
        title: LocalizedStringKey,
        value: Double,
        isSecondary: Bool = false
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(isSecondary ? .secondary : .primary)

            Spacer()

            Text(formatCurrency(value))
                .font(.subheadline)
                .foregroundStyle(isSecondary ? .secondary : .primary)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: value)
        }
    }
}

// MARK: - Конвертация в криптовалюту

struct CryptoConversionBlock: View {
    let totalUsd: Double
    let rate: CryptoRate?
    let isLoading: Bool
    let onRefresh: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Label("К оплате в криптовалюте", systemImage: "bitcoinsign.circle")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let rate {
                // Пересчитываем возраст курса каждую секунду
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    content(for: rate)
                }
            } else if isLoading {
                Text("Загружаем курс…")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            } else {
                HStack {
                    Text("Курс недоступен")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                    Spacer()
                    refreshButton
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(Palette.surface)
        )
    }

    @ViewBuilder
    private func content(for rate: CryptoRate) -> some View {
        let stale = rate.isStale

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(formatCrypto(rate.convert(usd: totalUsd)))
                    .font(.title3)
                    .fontWeight(.bold)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: totalUsd)

                Text(rate.asset)
                    .font(.headline)
                    .foregroundStyle(Palette.secondaryText)

                Spacer()

                Text(rate.network)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(6)
            }
            .opacity(stale ? 0.5 : 1)

            HStack(spacing: 6) {
                Image(systemName: stale ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .font(.caption2)
                    .foregroundStyle(stale ? .orange : .green)

                Text(
                    stale
                    ? "Курс устарел \(ageText(rate.age)) назад"
                    : "1 \(rate.asset) = \(formatCurrency(rate.usdPrice)) · актуален ещё \(rate.secondsUntilStale) с"
                )
                .font(.caption2)
                .foregroundStyle(Palette.secondaryText)

                Spacer()

                refreshButton
            }
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await onRefresh() }
        } label: {
            Label("Обновить", systemImage: "arrow.clockwise")
                .font(.caption2)
        }
        .buttonStyle(.borderless)
        .disabled(isLoading)
    }

    private func ageText(_ age: TimeInterval) -> String {
        let seconds = Int(age)
        if seconds < 60 { return "\(seconds) с" }
        return "\(seconds / 60) мин"
    }
}

// MARK: - Форматирование

func formatQuantity(_ value: Double) -> String {
    if value == value.rounded() && abs(value) < 1e15 {
        return String(format: "%.0f", value)
    }
    var s = String(format: "%.8f", value)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}

func formatCrypto(_ value: Double) -> String {
    String(format: "%.2f", value)
}

func formatPercent(_ rate: Double) -> String {
    String(format: "%.2f%%", rate * 100)
}
