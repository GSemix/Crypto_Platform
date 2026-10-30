//
//  MyPurchasesView.swift
//  Crypto_Platform
//
//  «Мои заявки»: активные отдельно от завершённых, свежие сверху,
//  у каждой ожидающей оплаты — свой отсчёт до дедлайна.

import SwiftUI

struct MyPurchasesView: View {
    @EnvironmentObject var purchases: PurchaseStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                NavigationLink {
                    NewPurchaseView()
                } label: {
                    Text("Создать новую заявку")
                }
                .buttonStyle(.primary)

                if purchases.isLoadingList {
                    ForEach(0..<3, id: \.self) { _ in
                        PurchaseRowPlaceholder()
                    }
                } else if let error = purchases.listError, purchases.requests.isEmpty {
                    NoticeView(kind: .error, title: "Не удалось загрузить заявки", message: error,
                               action: ("Повторить", { Task { await purchases.loadList() } }))
                } else if purchases.requests.isEmpty {
                    EmptyStateView(title: "Заявок пока нет", message: String(localized: "Создайте заявку, чтобы купить акции у брокера за HZN"))
                        .frame(minHeight: 200)
                } else {
                    section("Активные", purchases.active)
                    section("Завершённые", purchases.finished)
                }
            }
            .padding(Spacing.m)
        }
        .refreshable { await purchases.loadList() }
        .navigationTitle("Мои заявки")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await purchases.pollList()
        }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, _ items: [PurchaseRequest]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title)
                DataGroup {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, request in
                        if index > 0 { HairlineDivider() }
                        NavigationLink {
                            PurchaseRequestView(requestId: request.id)
                        } label: {
                            PurchaseRow(request: request, clock: purchases.clock)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct PurchaseRow: View {
    let request: PurchaseRequest
    let clock: ServerClock

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("\(request.symbol) · \(formatQuantity(request.quantity)) шт.")
                    .font(.subheadline.weight(.medium))
                StatusDot(text: LocalizedStringKey(request.status?.title ?? request.statusValue),
                          color: request.status?.color ?? Palette.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(formatHZN(request.crypto_amount))
                    .font(.subheadline)
                    .monospacedDigit()
                if request.status == .awaitingPayment, let deadline = request.payment?.payment_deadline {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let left = clock.remaining(until: deadline)
                        Text(left > 0 ? String(localized: "Осталось \(PaymentTimer.format(left))") : String(localized: "Время вышло"))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(PaymentTimer.isUrgent(left) ? Palette.negative : Palette.secondaryText)
                    }
                }
            }
        }
        .padding(.vertical, Spacing.s + 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Скелетон строки, пока список загружается
struct PurchaseRowPlaceholder: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("NVR · 1 шт.").font(.subheadline)
                Text("Ожидает брокера").font(.caption)
            }
            Spacer()
            Text("0.000 HZN").font(.subheadline)
        }
        .redacted(reason: .placeholder)
        .card()
        .accessibilityHidden(true)
    }
}
