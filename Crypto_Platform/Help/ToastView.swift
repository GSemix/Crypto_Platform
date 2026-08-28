//
//  ToastView.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 13.01.2026.
//

import SwiftUI
import Combine

enum ToastType: Equatable {
    case success
    case error
}

struct ToastData: Identifiable, Equatable {
    let id = UUID()
    let type: ToastType
    let message: String
}

struct ToastView: View {
    let data: ToastData

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: data.type == .success
                  ? "checkmark.circle.fill"
                  : "xmark.octagon.fill"
            )
            .foregroundColor(.white)

            Text(data.message)
                .foregroundColor(.white)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(data.type == .success ? Color.green : Color.red)
        )
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct ToastModifier: ViewModifier {
    @Binding var toast: ToastData?

    func body(content: Content) -> some View {
        ZStack {
            content

            if let toast {
                VStack {
                    ToastView(data: toast)
                        .padding(.top, 12)
                    Spacer()
                }
            }
        }
        .animation(.easeInOut, value: toast)
    }
}

@MainActor
final class ToastManager: ObservableObject {
    @Published var toast: ToastData?

    func showSuccess(_ message: String) {
        show(.success, message)
    }

    func showError(_ message: String) {
        show(.error, message)
    }

    private func show(_ type: ToastType, _ message: String) {
        toast = ToastData(type: type, message: message)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.toast = nil
        }
    }
}

extension View {
    func toast(_ toast: Binding<ToastData?>) -> some View {
        self.modifier(ToastModifier(toast: toast))
    }
}
