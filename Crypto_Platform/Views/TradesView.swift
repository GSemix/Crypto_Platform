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

                NavigationLink {
                    CreateOrderView()
                } label: {
                    Text("Оформить заявку")
                }
                .buttonStyle(.primary)

                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionHeader("История")

                    DataGroup {
                        NavigationRow(title: "Ордера", subtitle: "Оформленные заявки") {
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
