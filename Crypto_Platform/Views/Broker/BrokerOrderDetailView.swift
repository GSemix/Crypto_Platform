//
//  BrokerOrderDetailView.swift
//  Crypto_Platform
//
//  Детали заявки и действия брокера: бронирование пула, отказ,
//  формирование формы на оплату.

import SwiftUI

struct BrokerOrderDetailView: View {
    @EnvironmentObject var session: UserSession
    @EnvironmentObject var api: OrdersAPI
    @ObservedObject var store: BrokerDashboardStore
    @Environment(\.dismiss) private var dismiss

    @State private var order: BrokerOrder
    @State private var isWorking = false
    @State private var conflictMessage: String?
    @State private var errorMessage: String?

    @State private var showRejectSheet = false
    @State private var rejectReason = ""

    @State private var showPaymentForm = false
    @State private var walletAddress = ""
    @State private var createdInvoice: PaymentInvoice?

    init(order: BrokerOrder, store: BrokerDashboardStore) {
        _order = State(initialValue: order)
        self.store = store
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusHeader
                detailsCard

                if let conflictMessage {
                    banner(conflictMessage, color: .orange, icon: "person.2.slash")
                }

                if let errorMessage {
                    banner(errorMessage, color: .red, icon: "exclamationmark.octagon")
                }

                if let invoice = createdInvoice {
                    invoiceCard(invoice)
                }

                actions
            }
            .padding()
        }
        .navigationTitle("Заявка")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRejectSheet) { rejectSheet }
        .sheet(isPresented: $showPaymentForm) { paymentFormSheet }
    }

    // MARK: Шапка

    private var statusHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: order.status.systemImage)
                .font(.system(size: 36))
                .foregroundStyle(order.status.color)

            Text(order.status.title)
                .font(.title3)
                .fontWeight(.bold)

            Text(order.status.detail)
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)

            if let reason = order.statusReason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(Palette.negative)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(order.status.color.opacity(0.1))
        )
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            row("Заявка", order.id)
            Divider().padding(.leading)
            row("Актив", order.symbol)
            Divider().padding(.leading)
            row("Количество", String(localized: "\(formatQuantity(order.quantity)) шт."))

            if order.executionPrice > 0 {
                Divider().padding(.leading)
                row("Цена", formatCurrency(order.executionPrice))
            }
            if order.commissionAmountUsd > 0 {
                Divider().padding(.leading)
                row("Комиссия \(formatPercent(order.commissionRate))", formatCurrency(order.commissionAmountUsd))
            }
            if order.totalAmountUsd > 0 {
                Divider().padding(.leading)
                row("К оплате", formatCurrency(order.totalAmountUsd), isBold: true)
            }
            if let created = order.createdAt {
                Divider().padding(.leading)
                row("Создана", created)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(Palette.surface)
        )
    }

    // MARK: Действия

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            switch order.status {
            case .awaitingBroker:
                Button {
                    Task { await book() }
                } label: {
                    HStack {
                        if isWorking { ProgressView().controlSize(.small).tint(.white) }
                        Text(isWorking ? "Бронируем…" : "Забронировать пул")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .disabled(isWorking)

                Button(role: .destructive) {
                    showRejectSheet = true
                } label: {
                    Text("Отклонить")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondaryOutline)
                .disabled(isWorking)

            case .paymentPending:
                Button {
                    showPaymentForm = true
                } label: {
                    Label("Сформировать форму на оплату", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)

            case .paid, .rejected:
                Text("Заявка закрыта — действия недоступны")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }

    /// Бронирование пула. Конкурентный случай приходит с сервера как 409:
    /// заявку уже взял другой брокер или не хватило бумаг в пуле.
    private func book() async {
        isWorking = true
        conflictMessage = nil
        errorMessage = nil
        defer { isWorking = false }

        let result = await store.bookPool(token: session.accessToken, orderId: order.id)

        switch result {
        case .booked(let updated):
            order = updated
        case .conflict(let message):
            conflictMessage = message
        case .failed(let message):
            errorMessage = message
        }
    }

    // MARK: Отказ

    private var rejectSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Причина отказа")) {
                    TextField("Например: нет бумаг в пуле", text: $rejectReason, axis: .vertical)
                        .lineLimit(3...6)

                    Text("\(rejectReason.trimmed.count) из 255")
                        .font(.caption2)
                        .foregroundStyle(rejectReason.trimmed.count > 255 ? .red : .secondary)
                }
            }
            .navigationTitle("Отклонить заявку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { showRejectSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Отклонить") {
                        Task { await reject() }
                    }
                    .disabled(rejectReason.trimmed.isEmpty || rejectReason.trimmed.count > 255)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func reject() async {
        isWorking = true
        defer { isWorking = false }

        let result = await store.reject(
            token: session.accessToken,
            orderId: order.id,
            reason: rejectReason
        )

        showRejectSheet = false

        switch result {
        case .booked(let updated):
            order = updated
            rejectReason = ""
        case .conflict(let message):
            conflictMessage = message
        case .failed(let message):
            errorMessage = message
        }
    }

    // MARK: Форма на оплату

    private var paymentFormSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Адрес кошелька для приёма")) {
                    TextField("Оставьте пустым — возьмётся основной", text: $walletAddress)
                        .font(.system(.footnote, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    LabeledContent("Сумма", value: formatCurrency(order.totalAmountUsd))
                    LabeledContent("Срок оплаты", value: "15 минут")
                }

                Section {
                    Button {
                        Task { await createInvoice() }
                    } label: {
                        HStack {
                            if isWorking { ProgressView().controlSize(.small) }
                            Text("Сформировать")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isWorking)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Palette.negative)
                    }
                }
            }
            .navigationTitle("Форма на оплату")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { showPaymentForm = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func createInvoice() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let invoice = try await api.createPaymentInvoice(
                token: session.accessToken,
                orderId: order.id,
                amount: order.totalAmountUsd,
                walletAddress: walletAddress.trimmed.isEmpty ? nil : walletAddress.trimmed
            )
            createdInvoice = invoice
            showPaymentForm = false
        } catch let error as APIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func invoiceCard(_ invoice: PaymentInvoice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Форма на оплату создана", systemImage: "doc.badge.checkmark")
                .font(.subheadline)
                .foregroundStyle(Palette.positive)

            row("Адрес", invoice.walletAddress)
            row("Сумма", "\(formatCrypto(invoice.amount)) \(invoice.asset)")
            row("Действительна до", invoice.expiresAt.formatted(date: .omitted, time: .standard))

            if api.isInvoiceStubbed(orderId: invoice.orderId) {
                Text("Собрана локально — платёжного эндпоинта на сервере пока нет")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(Color.green.opacity(0.1))
        )
    }

    // MARK: Мелочи

    private func row(_ title: LocalizedStringKey, _ value: String, isBold: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(isBold ? .bold : .medium)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func banner(_ text: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Radius.control)
                .fill(color.opacity(0.1))
        )
    }
}
