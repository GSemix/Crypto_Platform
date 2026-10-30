//
//  DesignSystem.swift
//  Crypto_Platform
//
//  Минималистичная система оформления.
//
//  Правила, из которых всё выведено:
//  — поверхности задаются волосяной рамкой, а не заливкой и тенями;
//  — цвет несёт смысл: зелёный и красный только для прибыли и убытка,
//    акцент только для действия, всё остальное — оттенки серого;
//  — цифры моноширинные, чтобы не прыгали при обновлении;
//  — четыре размера отступа вместо произвольных чисел.

import SwiftUI

// MARK: - Токены

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 40
}

enum Radius {
    static let control: CGFloat = 10
    static let card: CGFloat = 14
}

enum Palette {
    /// Фон экрана
    static let background = Color(.systemBackground)
    /// Поверхность карточки — почти неотличима от фона, форму держит рамка
    static let surface = Color(.secondarySystemBackground).opacity(0.5)
    /// Волосяная линия: и рамки, и разделители
    static let hairline = Color(.separator)

    static let primaryText = Color.primary
    static let secondaryText = Color.secondary

    static let accent = Color.accentColor
    static let positive = Color(red: 0.13, green: 0.62, blue: 0.35)
    static let negative = Color(red: 0.78, green: 0.20, blue: 0.20)

    /// Цвет числа по знаку
    static func value(_ number: Double) -> Color {
        number > 0 ? positive : (number < 0 ? negative : primaryText)
    }
}

// MARK: - Типографика

extension Text {
    /// Крупное число: баланс, сумма, цена
    func numeric(_ size: CGFloat = 32) -> Text {
        self.font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
    }

    /// Подпись над значением
    func label() -> some View {
        self.font(.footnote)
            .foregroundStyle(Palette.secondaryText)
    }

    /// Заголовок раздела
    func sectionTitle() -> some View {
        self.font(.caption)
            .fontWeight(.medium)
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(Palette.secondaryText)
    }
}

// MARK: - Поверхности

struct CardModifier: ViewModifier {
    var padding: CGFloat = Spacing.m

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Radius.card)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .stroke(Palette.hairline, lineWidth: 0.5)
            )
    }
}

extension View {
    func card(padding: CGFloat = Spacing.m) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

// MARK: - Компоненты

/// Заголовок раздела с необязательным действием справа
struct SectionHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(title).sectionTitle()
            Spacer()
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title: title) { EmptyView() }
    }
}

/// Строка «подпись — значение». Основной кирпич всех сводок.
struct DataRow: View {
    let label: LocalizedStringKey
    let value: String
    var valueColor: Color = Palette.primaryText
    var isMonospaced = false
    var isStrong = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // На крупных размерах шрифта подпись и значение встают друг под другом
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    labelText
                    valueText.multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                    labelText
                    Spacer(minLength: Spacing.s)
                    valueText.multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, Spacing.s + 2)
    }

    private var labelText: some View {
        Text(label)
            .font(.subheadline)
            .foregroundStyle(Palette.secondaryText)
    }

    /// Адреса и хеши (моноширинные) показываются целиком: их сверяют глазами
    private var valueText: some View {
        Text(value)
            .font(isMonospaced ? .system(.footnote, design: .monospaced) : .subheadline)
            .fontWeight(isStrong ? .semibold : .regular)
            .monospacedDigit()
            .foregroundStyle(valueColor)
            .lineLimit(isMonospaced ? nil : 2)
            .truncationMode(.middle)
    }
}

/// Список строк с волосяными разделителями между ними
struct DataGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .stroke(Palette.hairline, lineWidth: 0.5)
        )
    }
}

struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 0.5)
    }
}

/// Статус — точка и текст, без крупных цветных плашек
struct StatusDot: View {
    let text: LocalizedStringKey
    let color: Color

    var body: some View {
        HStack(spacing: Spacing.xs + 2) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
        }
    }
}

// MARK: - Кнопки

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(isEnabled ? Palette.accent : Palette.hairline)
            )
            .foregroundStyle(isEnabled ? Color.white : Palette.secondaryText)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Radius.control)
                    .stroke(Palette.hairline, lineWidth: 0.5)
            )
            .foregroundStyle(Palette.primaryText)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondaryOutline: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Сообщения

struct NoticeView: View {
    enum Kind {
        case info, warning, error

        var color: Color {
            switch self {
            case .info:    return Palette.secondaryText
            case .warning: return .orange
            case .error:   return Palette.negative
            }
        }

        var systemImage: String {
            switch self {
            case .info:    return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error:   return "exclamationmark.octagon"
            }
        }
    }

    let kind: Kind
    let title: LocalizedStringKey
    var message: String?
    var action: (title: LocalizedStringKey, handler: () -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s + 2) {
            Image(systemName: kind.systemImage)
                .font(.footnote)
                .foregroundStyle(kind.color)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.footnote)
                    .fontWeight(.medium)

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }

                if let action {
                    Button(action.title, action: action.handler)
                        .font(.caption.weight(.medium))
                        .padding(.top, Spacing.xs)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Radius.control)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control)
                .stroke(kind.color.opacity(0.35), lineWidth: 0.5)
        )
    }
}

/// Пустое состояние без картинок-заглушек
struct EmptyStateView: View {
    let title: LocalizedStringKey
    var message: String?

    var body: some View {
        VStack(spacing: Spacing.s) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Palette.primaryText)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }
}
