import SwiftUI
import UIKit
import Observation

/// Извлекает и кеширует «характерный» цвет обложки подкаста.
/// Алгоритм: уменьшаем картинку до 24×24, среди пикселей со средней яркостью
/// выбираем самый насыщенный. Если картинка целиком серая — берём средний цвет.
/// Результат — `TintColor` (RGB 0…1) — кешируется в памяти и в UserDefaults
/// по `podcastId`, поэтому повторно не пересчитывается.
@MainActor
@Observable
final class PodcastColorService {
    private static let storageKey = "podcastTintColors.v1"

    private(set) var tints: [Int: TintColor] = [:]
    private var inFlight: Set<Int> = []

    init() {
        load()
    }

    func tint(for podcastId: Int) -> TintColor? {
        tints[podcastId]
    }

    /// Запрашивает вычисление цвета, если он ещё не известен и не считается.
    func ensureTint(for podcastId: Int, artworkUrl: URL?) {
        guard tints[podcastId] == nil,
              !inFlight.contains(podcastId),
              let url = artworkUrl else { return }
        inFlight.insert(podcastId)
        Task { [weak self] in
            let computed = await Self.extract(from: url)
            await MainActor.run {
                guard let self else { return }
                self.inFlight.remove(podcastId)
                if let computed {
                    self.tints[podcastId] = computed
                    self.persist()
                }
            }
        }
    }

    private func persist() {
        let payload: [String: [String: Double]] = Dictionary(
            uniqueKeysWithValues: tints.map { (String($0.key), ["r": $0.value.r, "g": $0.value.g, "b": $0.value.b]) }
        )
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let any = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Double]]
        else { return }
        for (key, value) in any {
            if let id = Int(key),
               let r = value["r"], let g = value["g"], let b = value["b"] {
                tints[id] = TintColor(r: r, g: g, b: b)
            }
        }
    }

    nonisolated private static func extract(from url: URL) async -> TintColor? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data),
              let cg = image.cgImage else { return nil }
        return dominantColor(of: cg)
    }

    nonisolated private static func dominantColor(of cg: CGImage) -> TintColor? {
        let size = 24
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: size, height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))

        var bestSat = -1.0
        var best: TintColor?
        var avgR = 0.0, avgG = 0.0, avgB = 0.0, count = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255.0
            let g = Double(pixels[i + 1]) / 255.0
            let b = Double(pixels[i + 2]) / 255.0
            avgR += r; avgG += g; avgB += b; count += 1
            let lum = 0.299 * r + 0.587 * g + 0.114 * b
            // отсекаем почти-белое и почти-чёрное — они «съедают» итог.
            guard lum > 0.12 && lum < 0.92 else { continue }
            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let sat = maxC == 0 ? 0 : (maxC - minC) / maxC
            if sat > bestSat {
                bestSat = sat
                best = TintColor(r: r, g: g, b: b)
            }
        }
        if let best, bestSat > 0.25 { return best }
        guard count > 0 else { return nil }
        return TintColor(r: avgR / count, g: avgG / count, b: avgB / count)
    }
}

/// RGB-цвет обложки в диапазоне 0…1 + помощники для подбора контрастного шрифта.
struct TintColor: Sendable, Hashable {
    let r: Double
    let g: Double
    let b: Double

    var color: Color { Color(red: r, green: g, blue: b) }

    var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }

    /// true — фон светлый, текст должен быть тёмным.
    var prefersDarkText: Bool { luminance > 0.6 }

    var primaryText: Color {
        prefersDarkText ? Color.black.opacity(0.88) : Color.white
    }

    var secondaryText: Color {
        prefersDarkText ? Color.black.opacity(0.6) : Color.white.opacity(0.72)
    }

    var preferredColorScheme: ColorScheme {
        prefersDarkText ? .light : .dark
    }

    /// Слегка затемнённая версия — для нижней части градиентного фона.
    var darker: Color {
        Color(red: r * 0.78, green: g * 0.78, blue: b * 0.78)
    }
}
