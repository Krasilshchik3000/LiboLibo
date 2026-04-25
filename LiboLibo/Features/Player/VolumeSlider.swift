import SwiftUI
import MediaPlayer
import UIKit

/// Системная громкость устройства через `MPVolumeView`. Двигается синхронно
/// с железными кнопками и Control Center, как в Apple Music/Подкастах.
/// В симуляторе слайдер не активен — это ограничение iOS, не приложения.
struct VolumeSlider: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))

            SystemVolumeView()
                .frame(height: 24)

            Image(systemName: "speaker.wave.3.fill")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

private struct SystemVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: .zero)
        v.showsRouteButton = false
        v.tintColor = .white
        v.setVolumeThumbImage(UIImage(), for: .normal)
        v.setVolumeThumbImage(UIImage(), for: .highlighted)
        return v
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
