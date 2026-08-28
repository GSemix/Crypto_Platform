//
//  BrokerDashboardView.swift
//  Crypto_Platform
//
//  Дашборд брокера: заявки, требующие обработки.

import SwiftUI

struct BrokerDashboardView: View {
    @EnvironmentObject var session: UserSession
    @EnvironmentObject var api: OrdersAPI
    @StateObject private var store: BrokerDashboardStore

    @State private var toast: String?

    init(api: OrdersAPI) {
        _store = StateObject(wrappedValue: BrokerDashboardStore(api: api))
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar

            if store.unavailable {
                unavailableState
            } else if let error = store.errorMessage, store.orders.isEmpty {
                errorState(error)
            } else if store.isLoading && store.orders.isEmpty {
                ProgressView("Загружаем заявки…")
                    .frame(maxHeight: .infinity)
            } else if store.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Заявки брокера")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let updated = store.lastUpdated {
                    Text(updated, format: .dateTime.hour().minute().second())
                        .font(.caption2)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.caption)
                    .padding()
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast)
        .task {
            await store.load(token: session.accessToken)
            store.startAutoRefresh(token: session.accessToken)
        }
        .onDisappear {
            store.stopAutoRefresh()
        }
        .onChange(of: store.filter) { _, _ in
            Task { await store.load(token: session.accessToken) }
        }
    }

    // MARK: Фильтры

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BrokerFilter.allCases) { item in
                    Button {
                        store.filter = item
                    } label: {
                        Text(item.title)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                store.filter == item
                                ? Color.accentColor.opacity(0.2)
                                : Color.gray.opacity(0.15)
                            )
                            .foregroundStyle(store.filter == item ? Color.accentColor : .secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    // MARK: Список

    private var list: some View {
        List {
            if store.total > store.orders.count {
                Text("Показано \(store.orders.count) из \(store.total)")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryText)
                    .listRowSeparator(.hidden)
            }

            ForEach(store.orders) { order in
                NavigationLink {
                    BrokerOrderDetailView(order: order, store: store)
                } label: {
                    BrokerOrderRow(
                        order: order,
                        isTaken: store.takenByOthers.contains(order.id)
                    )
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await store.refresh(token: session.accessToken)
        }
    }

    // MARK: Пустые состояния

    private var emptyState: some View {
        ContentUnavailableView(
            "Заявок нет",
            systemImage: "tray",
            description: Text("В фильтре «\(store.filter.title)» пока пусто. Потяните вниз, чтобы обновить.")
        )
        .frame(maxHeight: .infinity)
    }

    private var unavailableState: some View {
        ContentUnavailableView {
            Label("Раздел недоступен", systemImage: "wrench.and.screwdriver")
        } description: {
            Text("Брокерская часть API (`/api/broker/*`) ещё не задеплоена на сервере. Экран заработает без изменений в приложении, как только её выкатят.")
        }
        .frame(maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Не удалось загрузить", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Повторить") {
                Task { await store.load(token: session.accessToken) }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Карточка в списке

struct BrokerOrderRow: View {
    let order: BrokerOrder
    var isTaken: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(order.symbol)
                    .font(.headline)

                Spacer()

                Label(order.status.title, systemImage: order.status.systemImage)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(order.status.color.opacity(0.15))
                    .foregroundStyle(order.status.color)
                    .clipShape(Capsule())
            }

            HStack {
                Text("\(formatQuantity(order.quantity)) шт.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)

                Spacer()

                if order.totalAmountUsd > 0 {
                    Text(formatCurrency(order.totalAmountUsd))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }

            if let created = order.createdAt {
                Text(created)
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryText)
            }

            if isTaken {
                Label("Заявку уже взял другой брокер", systemImage: "person.2.slash")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .opacity(isTaken ? 0.5 : 1)
    }
}
