//
//  OrderTerminalView.swift
//  Crypto_Platform
//
//  Терминальные состояния заявки.

import SwiftUI

enum OrderTerminalKind: Equatable {
    case success
    case cancelled(reason: String?)
    case expired
    case submitted(hash: String)

    var title: String {
        switch self {
        case .success:   return String(localized: "Успешно выполнена")
        case .cancelled: return String(localized: "Отменена")
        case .expired:   return String(localized: "Истёк таймер")
        case .submitted: return String(localized: "Оплата отправлена")
        }
    }

    var message: String {
        switch self {
        case .success:
            return String(localized: "Бумаги зачислены на ваш счёт")
        case .cancelled(let reason):
            return reason?.isEmpty == false
                ? reason!
                : String(localized: "Заявка отменена, средства не списаны")
        case .expired:
            return String(localized: "Время на оплату вышло. Бронь снята, бумаги вернулись в пул брокера — оформите заявку заново")
        case .submitted:
            return String(localized: "Брокер проверяет перевод. Статус обновится, когда транзакция подтвердится в сети")
        }
    }

    var systemImage: String {
        switch self {
        case .success:   return "checkmark.seal.fill"
        case .cancelled: return "xmark.octagon.fill"
        case .expired:   return "clock.badge.exclamationmark.fill"
        case .submitted: return "paperplane.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .success:   return .green
        case .cancelled: return .red
        case .expired:   return .orange
        case .submitted: return .blue
        }
    }
}

struct OrderTerminalView: View {
    let kind: OrderTerminalKind
    let order: BrokerOrder

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(kind.tint.opacity(0.15))
                    .frame(width: 110, height: 110)

                Image(systemName: kind.systemImage)
                    .font(.system(size: 46))
                    .foregroundStyle(kind.tint)
            }
            .padding(.top, 32)

            VStack(spacing: 8) {
                Text(kind.title)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(kind.message)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            summary

            if case .submitted(let hash) = kind, !hash.isEmpty {
                hashRow(hash)
            }
        }
    }

    private var summary: some View {
        VStack(spacing: 0) {
            row("Актив", order.symbol)
            Divider().padding(.leading)
            row("Количество", String(localized: "\(formatQuantity(order.quantity)) шт."))

            if order.totalAmountUsd > 0 {
                Divider().padding(.leading)
                row("Сумма", formatCurrency(order.totalAmountUsd))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(Palette.surface)
        )
    }

    private func hashRow(_ hash: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Хеш транзакции")
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)

            Text(hash)
                .font(.system(.caption2, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control)
                        .fill(Palette.surface)
                )
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding()
    }
}
