//
//  Other.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 13.01.2026.
//

import SwiftUI

func formatCurrency(_ value: Double, currency: String = "USD") -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    formatter.maximumFractionDigits = 2

    return formatter.string(
        from: NSNumber(value: value)
    ) ?? "\(value)"
}

func formatPrice(_ value: Double) -> String {
    String(format: "%.2f", value)
}

struct StringOrInt: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            value = s
            return
        }
        if let i = try? c.decode(Int.self) {
            value = String(i)
            return
        }
        if let d = try? c.decode(Double.self) {
            value = String(d)
            return
        }
        throw DecodingError.typeMismatch(
            String.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Expected String/Int/Double")
        )
    }
}

struct NumberOrString: Decodable {
    let doubleValue: Double

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()

        if let d = try? c.decode(Double.self) {
            doubleValue = d
            return
        }
        if let i = try? c.decode(Int.self) {
            doubleValue = Double(i)
            return
        }
        if let s = try? c.decode(String.self),
           let d = Double(s) {
            doubleValue = d
            return
        }

        throw DecodingError.typeMismatch(
            Double.self,
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "Expected Double / Int / String number"
            )
        )
    }
}


struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.white.opacity(0.6),
                        Color.clear
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .rotationEffect(.degrees(30))
                .offset(x: phase * 300)
                .blendMode(.plusLighter)
                .blur(radius: 5)
            )
            .mask(content)
            .onAppear {
                withAnimation(
                    .linear(duration: 1.4)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

struct IdentityModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

extension View {
    @ViewBuilder
    func shimmer(active: Bool) -> some View {
        if active {
            self.modifier(ShimmerModifier())
        } else {
            self
        }
    }
}

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
