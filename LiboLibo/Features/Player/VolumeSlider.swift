import SwiftUI

/// Apple-style регулятор громкости — тот же визуальный язык, что и progress-bar:
/// тонкий трек, без видимого thumb-а, утолщается при скрабинге.
/// Управляет `PlayerService.volume` (AVPlayer.volume) — видим и работает в любом
/// окружении, включая симулятор. Динамики устройства подчиняются всё равно.
struct VolumeSlider: View {
    @Environment(PlayerService.self) private var player
    @State private var draggedFraction: Double?
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))

            GeometryReader { geo in
                let width = geo.size.width
                let progress = max(0, min(1, currentFraction))
                let trackHeight: CGFloat = isDragging ? 6 : 3

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(height: trackHeight)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: width * progress, height: trackHeight)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let f = max(0, min(1, value.location.x / width))
                            draggedFraction = f
                            player.volume = Float(f)
                        }
                        .onEnded { _ in
                            draggedFraction = nil
                            isDragging = false
                        }
                )
                .animation(.easeInOut(duration: 0.15), value: isDragging)
            }
            .frame(height: 18)

            Image(systemName: "speaker.wave.3.fill")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var currentFraction: Double {
        if let dv = draggedFraction { return dv }
        return Double(player.volume)
    }
}
