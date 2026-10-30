//
//  OrdersPanelView.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 13.01.2026.
//

import SwiftUI

enum OrderSide: String {
    case buy = "BUY"
    case sell = "SELL"
}

struct OrderPanelView: View {
    @EnvironmentObject var session: UserSession
    @EnvironmentObject var toastManager: ToastManager

    let symbol: String
    let currentPrice: Double

    @State private var side: OrderSide = .buy
    @State private var quantityText: String = ""
    @State private var isSubmitting = false
    @State private var errorText: String?

    var quantity: Decimal {
        Decimal(string: quantityText.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    /// Оценка по последней цене графика; точную цену исполнения назначит сервер
    var estimatedValue: Double {
        quantity.doubleValue * currentPrice
    }

    var body: some View {
        VStack(spacing: 16) {

            // ===== BUY / SELL SWITCH =====
            Picker("", selection: $side) {
                Text("Купить").tag(OrderSide.buy)
                Text("Продать").tag(OrderSide.sell)
            }
            .pickerStyle(.segmented)

            // ===== QUANTITY INPUT =====
            VStack(alignment: .leading, spacing: 6) {
                Text("Количество")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)

                TextField("0", text: $quantityText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }

            // ===== ESTIMATION =====
            HStack {
                Text("Ориентировочная сумма")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)

                Spacer()

                Text(formatPrice(estimatedValue))
                    .fontWeight(.semibold)
            }

            // ===== ERROR =====
            if let errorText {
                Text(errorText)
                    .foregroundStyle(Palette.negative)
                    .font(.caption)
            }

            // ===== ACTION BUTTON =====
            Button {
                hideKeyboard()
                submit()
            } label: {
                HStack {
                    if isSubmitting {
                        ProgressView()
                    }
                    Text(side == .buy ? "Купить" : "Продать")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(side == .buy ? .green : .red)
            .disabled(isSubmitting || quantity <= 0)

        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(Palette.surface)
        )
    }

    // MARK: - Submit

    private func submit() {
        Task {
            let success = await session.createOrder(
                symbol: symbol,
                side: side.rawValue,
                quantity: quantity
            )

            if success {
                toastManager.showSuccess(
                    session.lastOrderMessage ?? String(localized: "Заказ создан")
                )
            } else {
                toastManager.showError(
                    session.lastOrderMessage ?? String(localized: "Не удалось создать заказ")
                )
            }
        }
    }

}
