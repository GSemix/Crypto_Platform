//
//  UnrealizedPnlView.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 13.01.2026.
//

import SwiftUI

struct UnrealizedPnlView: View {
    @EnvironmentObject var session: UserSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if let error = session.errorMessage {
                    NoticeView(kind: .error, title: "Ошибка", message: error)
                }

                if session.isUnrealizedPnlLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xl)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("Нереализованный PnL").label()
                        Text(formatCurrency(session.totalUnrealizedPnl))
                            .numeric(34)
                            .foregroundStyle(Palette.value(session.totalUnrealizedPnl))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: Spacing.l)

                    if session.positions.isEmpty {
                        EmptyStateView(
                            title: "Позиций нет",
                            message: String(localized: "Здесь появятся купленные бумаги")
                        )
                        .frame(height: 160)
                    } else {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            SectionHeader("Позиции")

                            DataGroup {
                                ForEach(Array(session.positions.enumerated()), id: \.element.symbol) { index, position in
                                    if index > 0 { HairlineDivider() }
                                    PnLPositionRow(position: position)
                                }
                            }
                        }
                    }
                }
            }
            .padding(Spacing.m)
        }
        .navigationTitle("Доходность")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.fetchUnrealizedPnL() }
        .onDisappear { session.errorMessage = nil }
    }
}

struct PnLPositionRow: View {
    let position: UnrealizedPnlPosition

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text(position.symbol)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if let pnl = position.unrealized_pnl {
                    Text(formatCurrency(pnl))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Palette.value(pnl))
                } else {
                    Text("—")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryText)
                }
            }

            HStack(spacing: Spacing.l) {
                metric("Средняя", position.average_price)
                metric("Текущая", position.latest_price)
                metric("Кол-во", position.total_quantity, isPrice: false)
            }
        }
        .padding(.vertical, Spacing.s + 2)
    }

    private func metric(_ title: String, _ value: Double?, isPrice: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Palette.secondaryText)

            Text(display(value, isPrice: isPrice))
                .font(.caption)
                .monospacedDigit()
        }
    }

    private func display(_ value: Double?, isPrice: Bool) -> String {
        guard let value else { return "—" }
        return isPrice ? formatPrice(value) : String(format: "%.4f", value)
    }
}
