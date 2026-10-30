//
//  NotificationsView.swift
//  Crypto_Platform
//
//  Лента уведомлений: свежие сверху, нажатие отмечает прочитанным.

import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject var notifications: NotificationsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if notifications.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, Spacing.xl)
                } else if let error = notifications.error, notifications.items.isEmpty {
                    NoticeView(kind: .error, title: "Не удалось загрузить уведомления", message: error,
                               action: ("Повторить", { Task { await notifications.load() } }))
                } else if notifications.items.isEmpty {
                    EmptyStateView(title: "Уведомлений пока нет",
                                   message: String(localized: "Здесь появятся события по ордерам и заявкам"))
                        .frame(minHeight: 200)
                } else {
                    DataGroup {
                        ForEach(Array(notifications.items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { HairlineDivider() }
                            Button {
                                Task { await notifications.markRead(item) }
                            } label: {
                                NotificationRow(item: item)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if item.id == notifications.items.last?.id {
                                    Task { await notifications.loadMore() }
                                }
                            }
                        }
                    }

                    if notifications.isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }

                DataGroup {
                    NavigationRow(title: "Настройки уведомлений") {
                        NotificationSettingsView()
                    }
                }
            }
            .padding(Spacing.m)
        }
        .refreshable { await notifications.load() }
        .navigationTitle("Уведомления")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if notifications.unreadCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Прочитать все")) {
                        Task { await notifications.markAllRead() }
                    }
                }
            }
        }
        .task { await notifications.load() }
    }
}

struct NotificationRow: View {
    let item: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Circle()
                .fill(item.is_read ? Color.clear : Palette.accent)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(item.title.isEmpty ? NotificationEvent.title(item.type) : item.title)
                    .font(.subheadline.weight(item.is_read ? .regular : .semibold))
                    .foregroundStyle(Palette.primaryText)
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let date = item.created_at {
                    Text(date, format: .dateTime.day().month().hour().minute())
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.s + 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.is_read ? Text("") : Text("Отметить прочитанным"))
    }
}

/// Колокольчик со счётчиком непрочитанных для главной
struct NotificationsBell: View {
    @EnvironmentObject var notifications: NotificationsStore

    var body: some View {
        NavigationLink {
            NotificationsView()
        } label: {
            Image(systemName: "bell")
                .overlay(alignment: .topTrailing) {
                    if notifications.unreadCount > 0 {
                        Text(notifications.unreadCount > 99 ? "99+" : "\(notifications.unreadCount)")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Palette.negative, in: Capsule())
                            .offset(x: 9, y: -8)
                    }
                }
        }
        .accessibilityLabel(Text("Уведомления"))
        .accessibilityValue(Text(notifications.unreadCount > 0 ? "Непрочитанных: \(notifications.unreadCount)" : ""))
    }
}

// MARK: - Настройки

struct NotificationSettingsView: View {
    @EnvironmentObject var notifications: NotificationsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if notifications.isLoadingSettings {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, Spacing.xl)
                } else {
                    if let error = notifications.settingsError {
                        NoticeView(kind: .error, title: LocalizedStringKey(error))
                    }

                    ForEach(NotificationEvent.all, id: \.self) { type in
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            SectionHeader(LocalizedStringKey(NotificationEvent.title(type)))
                            DataGroup {
                                ForEach(Array(NotificationChannel.allCases.enumerated()), id: \.element) { index, channel in
                                    if index > 0 { HairlineDivider() }
                                    Toggle(isOn: binding(type, channel)) {
                                        Text(channel.title).font(.subheadline)
                                    }
                                    .tint(Palette.accent)
                                    .padding(.vertical, Spacing.xs)
                                }
                            }
                        }
                    }
                }
            }
            .padding(Spacing.m)
        }
        .navigationTitle("Настройки уведомлений")
        .navigationBarTitleDisplayMode(.inline)
        .task { await notifications.loadSettings() }
    }

    private func binding(_ type: String, _ channel: NotificationChannel) -> Binding<Bool> {
        Binding(
            get: { notifications.isEnabled(type, channel) },
            set: { value in Task { await notifications.set(type, channel, enabled: value) } }
        )
    }
}
