import Foundation
import Observation

/// Подписки на подкасты — хранятся локально в `UserDefaults` (для скорости MVP;
/// при необходимости переедут в SwiftData/бэкенд).
@MainActor
@Observable
final class SubscriptionsService {
    private(set) var subscribedIds: Set<Int> = []

    private static let key = "libolibo.subscribedPodcastIds"

    init() {
        if let raw = UserDefaults.standard.array(forKey: Self.key) as? [Int] {
            subscribedIds = Set(raw)
        }
    }

    func isSubscribed(_ podcast: Podcast) -> Bool {
        subscribedIds.contains(podcast.id)
    }

    func toggle(_ podcast: Podcast) {
        if subscribedIds.contains(podcast.id) {
            subscribedIds.remove(podcast.id)
        } else {
            subscribedIds.insert(podcast.id)
        }
        save()
    }

    private func save() {
        UserDefaults.standard.set(Array(subscribedIds), forKey: Self.key)
    }
}
