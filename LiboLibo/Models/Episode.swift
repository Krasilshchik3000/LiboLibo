import Foundation

struct Episode: Identifiable, Hashable, Sendable {
    let id: String
    let podcastId: Int
    let podcastName: String
    let podcastArtworkUrl: URL?
    let title: String
    let summary: String
    let pubDate: Date
    let duration: TimeInterval?
    /// `nil` означает «премиум-эпизод без активного entitlement» — клиент
    /// показывает тизер вместо кнопок воспроизведения и скачивания. Для
    /// публичных эпизодов всегда заполнено.
    let audioUrl: URL?
    let isPremium: Bool

    init(
        id: String,
        podcastId: Int,
        podcastName: String,
        podcastArtworkUrl: URL?,
        title: String,
        summary: String,
        pubDate: Date,
        duration: TimeInterval?,
        audioUrl: URL?,
        isPremium: Bool = false
    ) {
        self.id = id
        self.podcastId = podcastId
        self.podcastName = podcastName
        self.podcastArtworkUrl = podcastArtworkUrl
        self.title = title
        self.summary = summary
        self.pubDate = pubDate
        self.duration = duration
        self.audioUrl = audioUrl
        self.isPremium = isPremium
    }

    /// Удобство для UI: если `audioUrl` есть — эпизод можно слушать и качать.
    var isPlayable: Bool { audioUrl != nil }
}
