import SwiftUI

/// Бегущая строка с фазной анимацией: пауза в начале → линейный проезд до
/// конца → пауза в конце → плавный возврат к началу → повтор. Если текст
/// помещается в контейнер — рендерится статично, без анимации и без
/// дублирования контента (поэтому ничего не «мигает» при смене состояний).
///
/// Принимает готовый `Text`, чтобы вызывающий мог задать шрифт / вес / цвет
/// в одном месте и не было дублирующих параметров.
struct MarqueeText: View {
    let content: Text
    /// Скорость прокрутки в точках в секунду (для линейного проезда).
    var velocity: CGFloat = 30
    /// Сколько висим в начале перед стартом.
    var startHold: Double = 1.5
    /// Сколько висим в конце перед обратным ходом.
    var endHold: Double = 5.0
    /// Длительность плавного возврата к началу.
    var returnDuration: Double = 0.6

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        // Невидимая копия в одну строку фиксирует высоту блока. Внешняя ширина
        // приходит от контейнера через `.frame(maxWidth: .infinity)` сверху.
        content
            .lineLimit(1)
            .opacity(0)
            .overlay(
                GeometryReader { geo in
                    content
                        .fixedSize(horizontal: true, vertical: false)
                        .background(measureTextWidth)
                        .offset(x: offset)
                        .frame(
                            width: geo.size.width,
                            height: geo.size.height,
                            alignment: .leading
                        )
                        .clipped()
                        .onAppear { containerWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in containerWidth = w }
                }
            )
            .task(id: cycleKey) {
                await runCycle()
            }
    }

    /// Меняется при изменении текста или ширин — это перезапускает `.task`
    /// и саму анимационную петлю с новыми параметрами.
    private var cycleKey: String { "\(textWidth)/\(containerWidth)" }

    private var measureTextWidth: some View {
        GeometryReader { textGeo in
            Color.clear
                .onAppear { textWidth = textGeo.size.width }
                .onChange(of: textGeo.size.width) { _, w in textWidth = w }
        }
    }

    @MainActor
    private func runCycle() async {
        offset = 0
        let scroll = textWidth - containerWidth
        guard scroll > 1 else { return }
        let scrollDuration = max(0.5, Double(scroll) / Double(velocity))
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(startHold))
            if Task.isCancelled { return }
            withAnimation(.linear(duration: scrollDuration)) { offset = -scroll }
            try? await Task.sleep(for: .seconds(scrollDuration))
            if Task.isCancelled { return }
            try? await Task.sleep(for: .seconds(endHold))
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: returnDuration)) { offset = 0 }
            try? await Task.sleep(for: .seconds(returnDuration))
            if Task.isCancelled { return }
        }
    }
}
