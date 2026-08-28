//
//  AccountView.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 06.01.2026.
//

import SwiftUI

struct AccountView: View {
    @EnvironmentObject var session: UserSession
    @EnvironmentObject var api: OrdersAPI

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if let error = session.errorMessage {
                    NoticeView(kind: .error, title: "Ошибка", message: error)
                }

                if session.userId == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xl)
                } else {
                    if session.role.lowercased() == "broker" {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            SectionHeader("Брокер")

                            DataGroup {
                                NavigationRow(
                                    title: "Заявки на обработку",
                                    subtitle: "Бронирование, отказ, форма на оплату"
                                ) {
                                    BrokerDashboardView(api: api)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader("Информация")

                        DataGroup {
                            DataRow(label: "ID", value: session.userId.map(String.init) ?? "—")
                            HairlineDivider()
                            DataRow(label: "Роль", value: session.role.isEmpty ? "—" : session.role)
                            HairlineDivider()
                            DataRow(label: "Email", value: session.email.isEmpty ? "—" : session.email)
                            HairlineDivider()
                            DataRow(label: "Дата регистрации", value: session.createdAt ?? "—")
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader("Верификация")

                        DataGroup {
                            if session.kycCompleted {
                                DataRow(label: "KYC", value: String(localized: "Пройден"), valueColor: Palette.positive)
                            } else if session.kycUploaded {
                                DataRow(label: "KYC", value: String(localized: "На проверке"))
                            } else {
                                NavigationRow(title: "Пройти KYC") {
                                    KYCView()
                                }
                            }
                        }
                    }
                }
            }
            .padding(Spacing.m)
        }
        .navigationTitle("Аккаунт")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if session.isAuthenticated {
                await session.fetchUser()
            }
        }
        .onDisappear {
            session.errorMessage = nil
        }
    }
}
