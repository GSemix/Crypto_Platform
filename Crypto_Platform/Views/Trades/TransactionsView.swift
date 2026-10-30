//
//  TransactionsView.swift
//  Crypto_Platform
//
//  История сделок — GET /api/trades

import SwiftUI

struct TransactionsView: View {
    @EnvironmentObject var session: UserSession

    var body: some View {
        Group {
            if session.isTradesLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = session.errorMessage, session.trades.isEmpty {
                VStack {
                    NoticeView(
                        kind: .error,
                        title: "Не удалось загрузить",
                        message: error,
                        action: ("Повторить", { Task { await session.fetchTrades() } })
                    )
                    Spacer()
                }
                .padding(Spacing.m)
            } else if session.trades.isEmpty {
                EmptyStateView(
                    title: "Сделок пока нет",
                    message: String(localized: "Здесь появятся исполненные операции")
                )
            } else {
                ScrollView {
                    VStack(spacing: Spacing.m) {
                        DataGroup {
                            ForEach(Array(session.trades.enumerated()), id: \.element.id) { index, trade in
                                if index > 0 { HairlineDivider() }
                                TradeRow(trade: trade)
                            }
                        }

                        if session.canLoadMoreTrades {
                            LoadMoreButton(isLoading: session.isTradesLoadingMore) {
                                await session.loadMoreTrades()
                            }
                        }
                    }
                    .padding(Spacing.m)
                }
                .refreshable { await session.fetchTrades() }
            }
        }
        .navigationTitle("Сделки")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.fetchTrades() }
        .onDisappear { session.errorMessage = nil }
    }
}

struct TradeRow: View {
    let trade: TradeItem

    private var isBuy: Bool { trade.side.uppercased() == "BUY" }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs + 2) {
            HStack {
                Text(trade.symbol)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(isBuy ? "покупка" : "продажа")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)

                Spacer()

                Text(formatCurrency(trade.value))
                    .font(.subheadline)
                    .monospacedDigit()
            }

            HStack {
                Text("\(formatPrice(trade.quantity)) × \(formatPrice(trade.price))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryText)

                Spacer()

                if let executedAt = trade.executed_at {
                    Text(executedAt.prefix(16).replacingOccurrences(of: "T", with: " "))
                        .font(.caption2)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
        }
        .padding(.vertical, Spacing.s + 2)
    }
}

