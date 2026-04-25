import Foundation

/// Тонкий клиент бэкенда «Либо-Либо». Знает базовый URL, JSON-декодинг и форму
/// DTO под фазу 2.0. Преобразует DTO в доменные модели `Podcast` / `Episode`.
///
/// Контракт описан в `docs/specs/api/openapi.yaml`. Поле `audio_url` для
/// премиум-эпизодов без entitlement приходит `null` — поэтому `Episode.audioUrl`
/// тоже опциональный, а UI рисует тизер «доступно по подписке».
@MainActor
final class APIClient {
    static let shared = APIClient()

    /// Прод-домен Railway. Поменяется, когда поднимем кастомный домен.
    private static let defaultBaseURL = URL(string: "https://libolibo-production.up.railway.app/v1")!

    let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private var profileIdProvider: @MainActor () -> UUID? = { nil }

    init(baseURL: URL = APIClient.defaultBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601WithFractionalSeconds
        self.decoder = d
    }

    /// Должен быть вызван в composition root (LiboLiboApp) после создания
    /// `AdaptyService`. Без provider'а заголовок `X-Adapty-Profile-Id` не
    /// шлётся, и бэкенд видит анонимного зрителя.
    func attachProfileIdProvider(_ provider: @escaping @MainActor () -> UUID?) {
        self.profileIdProvider = provider
    }

    // MARK: - Endpoints

    func fetchPodcasts() async throws -> [Podcast] {
        let response: PodcastsResponse = try await get(path: "/podcasts")
        return response.items.map { $0.asPodcast }
    }

    /// Глобальная лента эпизодов всех подкастов, отсортированная по `pubDate desc`.
    func fetchFeed(cursor: String? = nil, limit: Int = 200) async throws -> (episodes: [Episode], nextCursor: String?) {
        let page: EpisodePage = try await get(
            path: "/feed",
            query: queryItems(cursor: cursor, limit: limit)
        )
        return (page.items.map { $0.asEpisode }, page.nextCursor)
    }

    /// Эпизоды одного подкаста с пагинацией по `pubDate desc`.
    func fetchEpisodes(podcastId: Int, cursor: String? = nil, limit: Int = 200) async throws -> (episodes: [Episode], nextCursor: String?) {
        let page: EpisodePage = try await get(
            path: "/podcasts/\(podcastId)/episodes",
            query: queryItems(cursor: cursor, limit: limit)
        )
        return (page.items.map { $0.asEpisode }, page.nextCursor)
    }

    /// Дёргает Adapty Server API на бэке, обновляет локальный кэш `entitlements`
    /// и возвращает свежее состояние. Идемпотентно: сервер защищён rate-limit'ом
    /// 1 запрос/5 секунд на профиль.
    func refreshEntitlement() async throws -> EntitlementDTO {
        try await post(path: "/me/entitlement/refresh")
    }

    /// Возвращает закэшированное на бэке значение без обращения к Adapty.
    /// Если записи нет — `is_premium: false`. Полезно для дебага.
    func fetchEntitlement() async throws -> EntitlementDTO {
        try await get(path: "/me/entitlement")
    }

    // MARK: - Internals

    private func queryItems(cursor: String?, limit: Int) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return items
    }

    private func get<T: Decodable>(path: String, query: [URLQueryItem] = []) async throws -> T {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        attachProfileHeader(to: &request)
        return try await execute(request)
    }

    private func post<T: Decodable>(path: String) async throws -> T {
        guard let url = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )?.url else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        attachProfileHeader(to: &request)
        return try await execute(request)
    }

    private func attachProfileHeader(to request: inout URLRequest) {
        if let profileId = profileIdProvider() {
            request.setValue(profileId.uuidString, forHTTPHeaderField: "X-Adapty-Profile-Id")
        }
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus(http.statusCode)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    enum APIError: Error {
        case invalidURL
        case transport
        case badStatus(Int)
        case decoding(Error)
    }
}

// MARK: - DTO

struct EntitlementDTO: Decodable, Sendable {
    let isPremium: Bool
    let expiresAt: Date?
    let checkedAt: Date?
}

private struct PodcastsResponse: Decodable {
    let items: [PodcastDTO]
}

private struct EpisodePage: Decodable {
    let items: [EpisodeDTO]
    let nextCursor: String?
}

private struct PodcastDTO: Decodable {
    let id: Int
    let name: String
    let artist: String
    let feedUrl: String
    let artworkUrl: String?
    let description: String?
    let genres: [String]
    let hasPremium: Bool
    let lastEpisodeDate: Date?

    var asPodcast: Podcast {
        Podcast(
            id: id,
            name: name,
            artist: artist,
            feedUrl: URL(string: feedUrl) ?? Self.placeholderURL,
            artworkUrl: artworkUrl.flatMap { URL(string: $0) },
            description: description,
            lastEpisodeDate: lastEpisodeDate
        )
    }

    private static let placeholderURL = URL(string: "https://libolibo.me")!
}

private struct EpisodeDTO: Decodable {
    let id: String
    let podcastId: Int
    let podcastName: String
    let podcastArtworkUrl: String?
    let title: String
    let summary: String
    let pubDate: Date
    let durationSec: Int?
    let audioUrl: String?
    let isPremium: Bool

    var asEpisode: Episode {
        Episode(
            id: id,
            podcastId: podcastId,
            podcastName: podcastName,
            podcastArtworkUrl: podcastArtworkUrl.flatMap { URL(string: $0) },
            title: title,
            summary: summary,
            pubDate: pubDate,
            duration: durationSec.map(TimeInterval.init),
            audioUrl: audioUrl.flatMap { URL(string: $0) },
            isPremium: isPremium
        )
    }
}

// MARK: - ISO8601 with fractional seconds

private extension JSONDecoder.DateDecodingStrategy {
    /// Бэкенд отдаёт даты вида `2026-04-25T13:12:00.000Z` (с миллисекундами) и
    /// `2026-04-25T13:12:00Z` (без). Стандартный `.iso8601` не парсит первый.
    static let iso8601WithFractionalSeconds: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let date = ISO8601DateFormatter.libo.full.date(from: raw)
            ?? ISO8601DateFormatter.libo.basic.date(from: raw) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unparseable date: \(raw)"
        )
    }
}

private extension ISO8601DateFormatter {
    enum libo {
        static let full: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        static let basic: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()
    }
}
