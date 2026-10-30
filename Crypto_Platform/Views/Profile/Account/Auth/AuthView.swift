//
//  AuthView.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 04.01.2026.
//

import SwiftUI

enum AuthMode {
    case login
    case register
}

struct AuthView: View {
    @State private var mode: AuthMode = .login
    @EnvironmentObject var session: UserSession

    var body: some View {
        VStack(spacing: Spacing.l) {
            HStack(spacing: 0) {
                modeTab("Вход", .login)
                modeTab("Регистрация", .register)
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control)
                    .stroke(Palette.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, Spacing.m)

            if mode == .login {
                LoginView()
            } else {
                RegisterView()
            }

            Spacer()
        }
        .padding(.top, Spacing.m)
        .navigationTitle("Авторизация")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: mode) { _, _ in
            session.errorMessage = nil
        }
    }

    private func modeTab(_ title: String, _ value: AuthMode) -> some View {
        let isSelected = mode == value

        return Text(title)
            .font(.subheadline)
            .fontWeight(isSelected ? .semibold : .regular)
            .foregroundStyle(isSelected ? Palette.primaryText : Palette.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: Radius.control - 4)
                    .fill(isSelected ? Palette.background : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture { mode = value }
            .animation(.easeOut(duration: 0.15), value: mode)
    }
}
