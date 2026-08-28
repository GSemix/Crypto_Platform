//
//  RegisterView.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 04.01.2026.
//

import SwiftUI

struct RegisterView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var repeatPassword = ""

    @EnvironmentObject var session: UserSession
    @Environment(\.dismiss) private var dismiss

    private var passwordsMismatch: Bool {
        !repeatPassword.isEmpty && password != repeatPassword
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let error = session.errorMessage {
                NoticeView(kind: .error, title: "Не удалось зарегистрироваться", message: error)
            }

            DataGroup {
                FormField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                HairlineDivider()
                SecureFormField("Пароль", text: $password)
                HairlineDivider()
                SecureFormField("Повторите пароль", text: $repeatPassword)
            }

            if passwordsMismatch {
                Text("Пароли не совпадают")
                    .font(.caption)
                    .foregroundStyle(Palette.negative)
            }

            Button("Зарегистрироваться") {
                Task {
                    await session.registerUser(email: email, password: password)
                    if session.isAuthenticated { dismiss() }
                }
            }
            .buttonStyle(.primary)
            .disabled(email.isEmpty || password.isEmpty || password != repeatPassword)
        }
        .padding(Spacing.m)
    }
}
