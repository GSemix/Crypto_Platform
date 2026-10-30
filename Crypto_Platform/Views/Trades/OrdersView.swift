//
//  OrdersView.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 13.01.2026.
//

import SwiftUI

struct OrdersView: View {
    @EnvironmentObject var session: UserSession

    var body: some View {
        Group {
            if session.isOrdersLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = session.errorMessage, session.orders.isEmpty {
                VStack {
                    NoticeView(
                        kind: .error,
                        title: "Не удалось загрузить",
                        message: error,
                        action: ("Повторить", { Task { await session.fetchOrders() } })
                    )
                    Spacer()
                }
                .padding(Spacing.m)
            } else if session.orders.isEmpty {
                EmptyStateView(
                    title: "Ордеров нет",
                    message: String(localized: "Оформите заявку, чтобы она появилась здесь")
                )
            } else {
                ScrollView {
                    VStack(spacing: Spacing.m) {
                    DataGroup {
                        ForEach(Array(session.orders.enumerated()), id: \.element.id) { index, order in
                            if index > 0 { HairlineDivider() }

                            NavigationLink {
                                OrderDetailsView(orderId: order.id)
                            } label: {
                                OrderRow(order: order)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if order.status == "OPEN" {
                                    Button(role: .destructive) {
                                        Task { _ = await session.cancelOrder(orderId: order.id) }
                                    } label: {
                                        Label("Отменить", systemImage: "xmark")
                                    }
                                }
                            }
                        }
                    }

                    if session.canLoadMoreOrders {
                        LoadMoreButton(isLoading: session.isOrdersLoadingMore) {
                            await session.loadMoreOrders()
                        }
                    }
                    }
                    .padding(Spacing.m)
                }
                .refreshable { await session.fetchOrders() }
            }
        }
        .navigationTitle("Ордера")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.fetchOrders() }
        .onDisappear { session.errorMessage = nil }
    }
}

/// Цвет статуса ордера задеплоенного API
func orderStatusColor(_ status: String) -> Color {
    switch status.uppercased() {
    case "FILLED":               return Palette.positive
    case "CANCELLED", "REJECTED": return Palette.negative
    default:                     return .orange
    }
}

/// Перевод сырого статуса ордера с сервера в отображаемый текст
func orderStatusLabel(_ status: String) -> LocalizedStringKey {
    switch status.uppercased() {
    case "OPEN":      return "Открыт"
    case "FILLED":    return "Исполнен"
    case "CANCELLED": return "Отменён"
    case "REJECTED":  return "Отклонён"
    default:          return LocalizedStringKey(status)
    }
}

struct OrderRow: View {
    let order: OrderItem

    var body: some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.s) {
                    Text(order.symbol)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(order.side.uppercased() == "BUY" ? "покупка" : "продажа")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }

                StatusDot(text: orderStatusLabel(order.status), color: orderStatusColor(order.status))
            }

            Spacer(minLength: Spacing.s)

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatPrice(order.quantity))
                    .font(.subheadline)
                    .monospacedDigit()

                if let price = order.execution_price ?? order.limit_price {
                    Text(formatPrice(price))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryText)
                }
            }
        }
        .padding(.vertical, Spacing.s + 2)
        .contentShape(Rectangle())
    }
}

struct OrderDetailsView: View {
    @EnvironmentObject var session: UserSession
    let orderId: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if let error = session.errorMessage {
                    NoticeView(kind: .error, title: "Ошибка", message: error)
                }

                if session.isOrdersDetailsLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xl)
                } else if let order = session.selectedOrder {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text(order.symbol).label()
                        Text(formatPrice(order.quantity) + " шт.")
                            .numeric(30)
                        StatusDot(text: orderStatusLabel(order.status), color: orderStatusColor(order.status))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: Spacing.l)

                    DataGroup {
                        DataRow(label: "Операция", value: order.side.uppercased() == "BUY" ? "Покупка" : "Продажа")
                        HairlineDivider()
                        DataRow(label: "Тип", value: order.order_type)
                        HairlineDivider()
                        DataRow(label: "Лимитная цена", value: order.limit_price.map(formatPrice) ?? "—")
                        HairlineDivider()
                        DataRow(label: "Цена исполнения", value: order.execution_price.map(formatPrice) ?? "—")
                        HairlineDivider()
                        DataRow(label: "Создан", value: order.created_at ?? "—")
                        HairlineDivider()
                        DataRow(label: "Обновлён", value: order.updated_at ?? "—")
                    }

                    // API отменяет только ордера в статусе OPEN
                    if order.status == "OPEN" {
                        Button("Отменить ордер", role: .destructive) {
                            Task {
                                if await session.cancelOrder(orderId: orderId) {
                                    await session.fetchOrderDetails(orderId: orderId)
                                }
                            }
                        }
                        .buttonStyle(.secondaryOutline)
                    }
                }
            }
            .padding(Spacing.m)
        }
        .navigationTitle("Ордер № \(orderId)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.fetchOrderDetails(orderId: orderId) }
        .onDisappear { session.errorMessage = nil }
    }
}
