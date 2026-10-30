//
//  HomeView.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 18.11.2025.
//

import SwiftUI

struct HomeView: View {
    @State private var selectedCategory = "Популярное"
    @EnvironmentObject var session: UserSession
    @EnvironmentObject var assetsStore: AssetsStore
    @EnvironmentObject var notifications: NotificationsStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if session.isAuthenticated {
                    NavigationLink {
                        BalanceView()
                    } label: {
                        BalanceBlock()
                    }
                    .buttonStyle(.plain)
                }

                CatalogOfflineNotice()

                VStack(alignment: .leading, spacing: Spacing.m) {
                    CollectionsTabs(selectedCategory: $selectedCategory)
                    CollectionsList(selectedCategory: selectedCategory)
                }
            }
            .padding(Spacing.m)
        }
        .navigationTitle("Главная")
        .toolbar {
            if session.isAuthenticated {
                ToolbarItem(placement: .topBarTrailing) { NotificationsBell() }
            }
        }
        // Счётчик непрочитанных обновляется, пока главная на экране
        .task(id: session.isAuthenticated && scenePhase == .active) {
            guard session.isAuthenticated, scenePhase == .active else { return }
            while !Task.isCancelled {
                await notifications.refreshUnreadCount()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }
}

// MARK: - Баланс

struct BalanceBlock: View {
    @EnvironmentObject var session: UserSession

    private var isLoading: Bool {
        session.isBalanceLoading && session.totalBalance == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Баланс").label()

            Text(formatCurrency(session.totalBalance ?? 0, currency: session.currency))
                .numeric(34)
                .redacted(reason: isLoading ? .placeholder : [])

            HStack(spacing: Spacing.xs) {
                Text(formatCurrency(session.totalUnrealizedPnl, currency: session.currency))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Palette.value(session.totalUnrealizedPnl))

                Text("Нереализованный PnL")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryText)
            }
            .redacted(reason: isLoading ? .placeholder : [])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Категории

struct CollectionsTabs: View {
    @Binding var selectedCategory: String

    let tabs = ["Популярное", "Технологии", "Банки", "ETF", "Крипта"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.l) {
                ForEach(tabs, id: \.self) { tab in
                    let isSelected = selectedCategory == tab

                    VStack(spacing: Spacing.s) {
                        Text(tab)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundStyle(isSelected ? Palette.primaryText : Palette.secondaryText)

                        Rectangle()
                            .fill(isSelected ? Palette.primaryText : .clear)
                            .frame(height: 1.5)
                    }
                    .fixedSize()
                    .onTapGesture { selectedCategory = tab }
                }
            }
            .padding(.horizontal, 1)
        }
        .animation(.easeOut(duration: 0.15), value: selectedCategory)
    }
}

// MARK: - Список активов

struct MarketRow: View {
    let ticker: String
    let name: String
    let price: Double
    let change: Double
    var hasPrice: Bool = true

    var body: some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ticker)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(name)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.s)

            VStack(alignment: .trailing, spacing: 2) {
                Text(hasPrice ? String(format: "%.2f $", price) : "—")
                    .font(.subheadline)
                    .monospacedDigit()

                if hasPrice {
                    Text("\(change >= 0 ? "+" : "")\(String(format: "%.2f%%", change))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.value(change))
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
        }
        .padding(.vertical, Spacing.s + 2)
        .contentShape(Rectangle())
    }
}

struct CollectionsList: View {
    let selectedCategory: String
    @EnvironmentObject var assetsStore: AssetsStore

    var filtered: [Asset] {
        assetsStore.assets.filter { $0.type == selectedCategory }
    }

    var body: some View {
        Group {
            if assetsStore.assets.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl)
            } else if filtered.isEmpty {
                EmptyStateView(
                    title: "В этой подборке пусто",
                    message: String(localized: "Категории пока не приходят с сервера")
                )
                .frame(height: 160)
            } else {
                DataGroup {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, stock in
                        if index > 0 { HairlineDivider() }

                        NavigationLink {
                            AssetDetailScreen(stock: stock)
                        } label: {
                            MarketRow(
                                ticker: stock.symbol,
                                name: stock.name,
                                price: stock.price,
                                change: stock.change,
                                hasPrice: stock.hasPrice
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Карточка актива: график и оформление заявки
struct AssetDetailScreen: View {
    let stock: Asset

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                AssetChartView(
                    name: stock.name,
                    symbol: stock.symbol,
                    displayTitle: stock.symbol + "/" + stock.currency
                )

                VStack(spacing: Spacing.s) {
                    NavigationLink {
                        NewPurchaseView(symbol: stock.symbol)
                    } label: {
                        Text("Оформить заявку")
                    }
                    .buttonStyle(.primary)

                    OrderPanelView(symbol: stock.symbol, currentPrice: stock.price)
                }
                .padding(.horizontal, Spacing.m)
            }
        }
    }
}
