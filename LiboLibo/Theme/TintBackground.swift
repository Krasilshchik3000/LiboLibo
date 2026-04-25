import SwiftUI

/// Фон экрана, окрашенный «характерным» цветом подкаста.
/// Если цвет ещё не вычислен — возвращает системный фон, чтобы не было пустого
/// чёрного экрана. Лёгкий вертикальный градиент к более тёмной версии цвета
/// добавляет глубину, как на album-pages в Apple Music.
struct TintBackground: View {
    let tint: TintColor?

    var body: some View {
        Group {
            if let tint {
                LinearGradient(
                    colors: [tint.background, tint.backgroundDeep],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                Color(.systemBackground)
            }
        }
        .ignoresSafeArea()
    }
}
