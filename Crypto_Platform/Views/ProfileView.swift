//
//  ProfileView.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 18.11.2025.
//

import SwiftUI

struct ProfileView: View {
    @AppStorage("app_language") private var appLanguage = "system"
    @AppStorage("app_theme") private var appThemeRaw = AppTheme.system.rawValue
    @EnvironmentObject var session: UserSession

    private var languageTitle: String {
        switch appLanguage {
        case "ru": return "Русский"
        case "en": return "English"
        default:   return "Системный"
        }
    }

    private var themeTitle: String {
        AppTheme(rawValue: appThemeRaw)?.title ?? "Системная"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {

                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionHeader("Аккаунт")

                    DataGroup {
                        if session.isAuthenticated {
                            NavigationRow(
                                title: "Мой аккаунт",
                                subtitle: session.email.isEmpty ? nil : LocalizedStringKey(session.email)
                            ) {
                                AccountView()
                            }
                            HairlineDivider()
                            NavigationRow(title: "Уведомления") {
                                NotificationsView()
                            }
                        } else {
                            NavigationRow(title: "Вход / Регистрация") {
                                AuthView()
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionHeader("Настройки")

                    DataGroup {
                        Menu {
                            Button("Системный") { appLanguage = "system" }
                            Button("Русский") { appLanguage = "ru" }
                            Button("English") { appLanguage = "en" }
                        } label: {
                            DataRow(label: "Язык приложения", value: languageTitle)
                        }
                        .buttonStyle(.plain)

                        HairlineDivider()

                        Menu {
                            ForEach(AppTheme.allCases) { theme in
                                Button(theme.title) { appThemeRaw = theme.rawValue }
                            }
                        } label: {
                            DataRow(label: "Тема приложения", value: themeTitle)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if session.isAuthenticated {
                    Button("Выйти", role: .destructive) {
                        Task { await session.logout() }
                    }
                    .buttonStyle(.secondaryOutline)
                }
            }
            .padding(Spacing.m)
        }
        .navigationTitle("Профиль")
    }
}
