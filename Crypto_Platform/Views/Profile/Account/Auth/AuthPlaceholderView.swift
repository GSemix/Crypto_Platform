//
//  AuthPlaceholderView.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 04.01.2026.
//

import SwiftUI

struct AuthPlaceholderView: View {
    var body: some View {
        VStack(spacing: Spacing.m) {
            Spacer()

            Text("Войдите, чтобы продолжить")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)

            NavigationLink {
                AuthView()
            } label: {
                Text("Вход / Регистрация")
            }
            .buttonStyle(.primary)
            .padding(.horizontal, Spacing.xl)

            Spacer()
        }
    }
}
