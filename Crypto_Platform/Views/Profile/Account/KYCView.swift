//
//  KYCView.swift
//  Crypto_Platform
//
//  Created by Семен Безгин on 04.01.2026.
//
//  Верификация — POST /api/kyc (JSON, без загрузки файла)

import SwiftUI

enum KYCDocumentType: String, CaseIterable, Identifiable {
    case passport
    case national_id
    case residence_permit
    case driver_license

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passport:         return String(localized: "Паспорт")
        case .national_id:      return String(localized: "Внутренний ID")
        case .residence_permit: return String(localized: "Вид на жительство")
        case .driver_license:   return String(localized: "Водительское удостоверение")
        }
    }
}

struct KYCView: View {
    @EnvironmentObject var session: UserSession
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var secondName = ""
    @State private var citizenship = ""
    @State private var countryOfResidence = ""
    @State private var documentType: KYCDocumentType = .passport
    @State private var documentNumber = ""
    @State private var dateOfIssue = Date()
    @State private var expirationDate = Date()
    @State private var isSubmitting = false

    private static let apiDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Сервер требует: выдача не в будущем, истечение позже выдачи и не в прошлом
    private var validationError: String? {
        if firstName.trimmed.isEmpty || secondName.trimmed.isEmpty
            || citizenship.trimmed.isEmpty || countryOfResidence.trimmed.isEmpty
            || documentNumber.trimmed.isEmpty {
            return "Заполните все поля"
        }
        if firstName.count > 50 || secondName.count > 50
            || citizenship.count > 50 || countryOfResidence.count > 50 {
            return "Максимум 50 символов в поле"
        }
        if documentNumber.count > 100 {
            return "Номер документа — максимум 100 символов"
        }
        let today = Calendar.current.startOfDay(for: Date())
        if Calendar.current.startOfDay(for: dateOfIssue) > today {
            return "Дата выдачи не может быть в будущем"
        }
        if expirationDate <= dateOfIssue {
            return "Дата истечения должна быть позже даты выдачи"
        }
        if Calendar.current.startOfDay(for: expirationDate) < today {
            return "Документ просрочен"
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {

                switch session.kycState {
                case .rejected(let reason):
                    NoticeView(kind: .error, title: "Анкета отклонена", message: reason)
                case .reupload(let reason):
                    NoticeView(kind: .warning, title: "Нужно отправить анкету снова", message: reason)
                default:
                    EmptyView()
                }

                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionHeader("Личные данные")

                    DataGroup {
                        FormField("Имя", text: $firstName, contentType: .givenName)
                        HairlineDivider()
                        FormField("Фамилия", text: $secondName, contentType: .familyName)
                        HairlineDivider()
                        FormField("Гражданство", text: $citizenship)
                        HairlineDivider()
                        FormField("Страна проживания", text: $countryOfResidence)
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionHeader("Документ")

                    DataGroup {
                        Menu {
                            ForEach(KYCDocumentType.allCases) { type in
                                Button(type.title) { documentType = type }
                            }
                        } label: {
                            DataRow(label: "Тип", value: documentType.title)
                        }
                        .buttonStyle(.plain)

                        HairlineDivider()
                        FormField("Номер документа", text: $documentNumber)
                        HairlineDivider()

                        DatePicker(
                            "Дата выдачи",
                            selection: $dateOfIssue,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .font(.subheadline)
                        .padding(.vertical, Spacing.s + 2)

                        HairlineDivider()

                        DatePicker(
                            "Действителен до",
                            selection: $expirationDate,
                            displayedComponents: .date
                        )
                        .font(.subheadline)
                        .padding(.vertical, Spacing.s + 2)
                    }
                }

                if let error = session.errorMessage {
                    NoticeView(kind: .error, title: "Ошибка", message: error)
                }

                VStack(alignment: .leading, spacing: Spacing.s) {
                    Button {
                        hideKeyboard()
                        submit()
                    } label: {
                        HStack {
                            if isSubmitting { ProgressView().tint(.white) }
                            Text("Отправить на проверку")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(isSubmitting || validationError != nil)

                    if let validationError {
                        Text(validationError)
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
            }
            .padding(Spacing.m)
        }
        // После отправки сервер переводит анкету на проверку — экран закрываем
        .onChange(of: session.kycState) { _, state in
            if state == .pending || state == .approved { dismiss() }
        }
        .onDisappear {
            session.errorMessage = nil
        }
        .navigationTitle("Безопасность")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() {
        isSubmitting = true

        Task {
            _ = await session.submitKYC(KYCRequest(
                first_name: firstName.trimmed,
                second_name: secondName.trimmed,
                citizenship: citizenship.trimmed,
                country_of_residence: countryOfResidence.trimmed,
                document_type: documentType.rawValue,
                document_number: documentNumber.trimmed,
                date_of_issue: Self.apiDateFormatter.string(from: dateOfIssue),
                expiration_date: Self.apiDateFormatter.string(from: expirationDate)
            ))

            isSubmitting = false
        }
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Поле ввода в стиле DataGroup — подпись слева, значение справа, без рамки
struct FormField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var contentType: UITextContentType?

    init(_ title: LocalizedStringKey, text: Binding<String>, contentType: UITextContentType? = nil) {
        self.title = title
        self._text = text
        self.contentType = contentType
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)

            Spacer(minLength: Spacing.m)

            TextField("", text: $text)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
                .textContentType(contentType)
        }
        .padding(.vertical, Spacing.s + 2)
    }
}
