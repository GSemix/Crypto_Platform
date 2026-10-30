//
//  TradesView.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 18.11.2025.
//

import SwiftUI

struct TradesView: View {
    @EnvironmentObject var session: UserSession

    var body: some View {
        Group {
            if session.isAuthenticated {
                TradesContentView()
            } else {
                AuthPlaceholderView()
            }
        }
        .navigationTitle("Сделки")
    }
}

struct TradesContentView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {

                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionHeader("Покупка у брокера")

                    DataGroup {
                        NavigationRow(title: "Новая заявка", subtitle: "Покупка акций с оплатой в HZN") {
                            NewPurchaseView()
                        }
                        HairlineDivider()
                        NavigationRow(title: "Мои заявки", subtitle: "Активные и завершённые заявки") {
                            MyPurchasesView()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionHeader("История")

                    DataGroup {
                        NavigationRow(title: "Ордера", subtitle: "Рыночные ордера") {
                            OrdersView()
                        }
                        HairlineDivider()
                        NavigationRow(title: "Сделки", subtitle: "Исполненные операции") {
                            TransactionsView()
                        }
                        HairlineDivider()
                        NavigationRow(title: "Доходность", subtitle: "Нереализованный PnL") {
                            UnrealizedPnlView()
                        }
                    }
                }
            }
            .padding(Spacing.m)
        }
    }
}

/// Строка-переход: заголовок, пояснение и шеврон
/// «Загрузить ещё» под постраничным списком
struct LoadMoreButton: View {
    let isLoading: Bool
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                if isLoading { ProgressView() }
                Text("Загрузить ещё")
            }
        }
        .buttonStyle(.secondaryOutline)
        .disabled(isLoading)
    }
}

struct NavigationRow<Destination: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(Palette.primaryText)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
            .padding(.vertical, Spacing.s + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
