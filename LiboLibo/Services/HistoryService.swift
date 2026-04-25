import Foundation
import Observation

/// История прослушиваний — последние ≤ 100 запущенных эпизодов.
/// Хранится в `UserDefaults` как JSON; для MVP этого достаточно.
@MainActor
@Observable
final class HistoryService {
    struct Item: Codable, Hashable, Identifiable, Sendable {
        var id: String              // episode id
        var title: String
        var podcastId: Int
        var podcastName: String
        var podcastArtworkUrl: URL?
        var audioUrl: URL
        var lastPlayedAt: Date
    }

    private(set) var items: [Item] = []

    private static let key = "libolibo.playHistory"
    private static let maxItems = 100

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([Item].self, from: data) {
            items = decoded
        }
    }

    func record(_ episode: Episode) {
        let item = Item(
            id: episode.id,
            title: episode.title,
            podcastId: episode.podcastId,
            podcastName: episode.podcastName,
            podcastArtworkUrl: episode.podcastArtworkUrl,
            audioUrl: episode.audioUrl,
            lastPlayedAt: Date()
        )
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        if items.count > Self.maxItems {
            items = Array(items.prefix(Self.maxItems))
        }
        save()
    }

    /// Очищает всю историю прослушиваний.
    func clearAll() {
        items = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    /// Для обратной конвертации из истории в Episode — чтобы можно было снова запустить.
    func episode(for item: Item) -> Episode {
        Episode(
            id: item.id,
            podcastId: item.podcastId,
            podcastName: item.podcastName,
            podcastArtworkUrl: item.podcastArtworkUrl,
            title: item.title,
            summary: "",
            pubDate: item.lastPlayedAt,
            duration: nil,
            audioUrl: item.audioUrl
        )
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
