import SwiftUI

/// Дизайн-токены приложения Либо-Либо.
/// Шрифты — системные San Francisco через Dynamic Type. Никаких кастомных
/// шрифтов: следуем Apple HIG.
enum Theme {
    // MARK: - Цвета

    /// Брендовый красный со страницы libolibo.me — #FF3D3D.
    /// Используется ТОЛЬКО как:
    /// - `.tint` глобальной таб-навигации,
    /// - swipe-action «Скачать»,
    /// - индикатор активной подписки в SubscribeButton.
    /// Внутри контента (заголовки, подписи, кнопки play/pause) — не используется.
    static let red = Color(red: 1.0, green: 61.0/255.0, blue: 61.0/255.0)

    // MARK: - Типографика

    /// Hero-заголовок на детальном экране (имя подкаста в шапке).
    static let screenTitle = Font.title2.weight(.semibold)

    /// Заголовок строки в списке (имя подкаста, заголовок выпуска).
    static let itemTitle = Font.headline

    /// Подпись в строке (имя подкаста под обложкой выпуска, дата · длительность).
    static let itemMeta = Font.caption

    // MARK: - Корнер-радиусы

    /// Маленький — для thumb-обложек 40–60pt.
    static let radiusSmall: CGFloat = 8

    /// Средний — для строк списка и карточек 80–110pt.
    static let radiusMedium: CGFloat = 12

    /// Большой — для hero-обложек 140pt+ и плеера.
    static let radiusLarge: CGFloat = 16
}

extension Color {
    /// `Color.liboRed` — брендовый красный.
    static let liboRed = Theme.red
}

extension ShapeStyle where Self == Color {
    /// Сахар для `.foregroundStyle(.liboRed)`, `.tint(.liboRed)`.
    static var liboRed: Color { Theme.red }
}
