//
//  BalanceView.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 13.01.2026.
//

import SwiftUI

struct BalanceView: View {
    @EnvironmentObject var session: UserSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if let error = session.errorMessage {
                    NoticeView(
                        kind: .error,
                        title: "Не удалось загрузить баланс",
                        message: error,
                        action: ("Повторить", { Task { await session.fetchBalance() } })
                    )
                }

                if session.isBalanceLoading && session.totalBalance == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xl)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("Всего").label()
                        Text(formatCurrency(session.totalBalance ?? 0, currency: session.currency))
                            .numeric(36)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: Spacing.l)

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader("Распределение")

                        DataGroup {
                            DataRow(
                                label: "Доступно",
                                value: formatCurrency(session.availableBalance, currency: session.currency)
                            )
                            HairlineDivider()
                            DataRow(
                                label: "Зарезервировано",
                                value: formatCurrency(session.reservedBalance, currency: session.currency)
                            )
                        }
                    }
                }
            }
            .padding(Spacing.m)
        }
        .navigationTitle("Баланс")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.fetchBalance() }
        .onDisappear { session.errorMessage = nil }
    }
}
