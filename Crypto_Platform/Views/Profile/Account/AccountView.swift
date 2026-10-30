//
//  AccountView.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 06.01.2026.
//

import SwiftUI

struct AccountView: View {
    @EnvironmentObject var session: UserSession

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
                            switch session.kycState {
                            case .approved:
                                DataRow(label: "KYC", value: String(localized: "Одобрено"), valueColor: Palette.positive)
                            case .pending:
                                DataRow(label: "KYC", value: String(localized: "На проверке"))
                            case .rejected(let reason):
                                resubmitRows(status: String(localized: "Отклонено"), reason: reason)
                            case .reupload(let reason):
                                resubmitRows(status: String(localized: "Нужна повторная отправка"), reason: reason)
                            case .notSubmitted:
                                NavigationRow(title: "Пройти KYC") { KYCView() }
                            case nil:
                                ProgressView().frame(maxWidth: .infinity).padding(.vertical, Spacing.s)
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
                await session.fetchKYC()
            }
        }
        .onDisappear {
            session.errorMessage = nil
        }
    }

    /// После отказа анкету можно отправить снова
    @ViewBuilder
    private func resubmitRows(status: String, reason: String?) -> some View {
        DataRow(label: "KYC", value: status, valueColor: Palette.negative)
        if let reason, !reason.isEmpty {
            HairlineDivider()
            DataRow(label: "Причина", value: reason)
        }
        HairlineDivider()
        NavigationRow(title: "Отправить анкету снова") { KYCView() }
    }
}
