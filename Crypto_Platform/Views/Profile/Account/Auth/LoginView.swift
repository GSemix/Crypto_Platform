//
//  LoginView.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 04.01.2026.
//

import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""

    @EnvironmentObject var session: UserSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let error = session.errorMessage {
                NoticeView(kind: .error, title: "Не удалось войти", message: error)
            }

            DataGroup {
                FormField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                HairlineDivider()
                SecureFormField("Пароль", text: $password)
            }

            Button("Войти") {
                Task {
                    await session.loginUser(email: email, password: password)
                    if session.isAuthenticated { dismiss() }
                }
            }
            .buttonStyle(.primary)
            .disabled(email.isEmpty || password.isEmpty)
        }
        .padding(Spacing.m)
    }
}

/// Пароль в стиле DataGroup
struct SecureFormField: View {
    let title: LocalizedStringKey
    @Binding var text: String

    init(_ title: LocalizedStringKey, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)

            Spacer(minLength: Spacing.m)

            SecureField("", text: $text)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, Spacing.s + 2)
    }
}
