import Foundation
import Observation
import Adapty
import AdaptyUI

/// Источник правды о премиум-подписке на стороне iOS.
///
/// - идентификатор зрителя — `adapty_profile_id` (UUID), его выдаёт Adapty SDK
///   и сам кладёт в Keychain;
/// - решение «есть ли премиум» принимает бэкенд (`POST /v1/me/entitlement/refresh`),
///   мы только показываем закэшированное значение и инициируем refresh после
///   purchase / restore / cold start;
/// - локальный `isPremium` влияет только на UI; бэк независимо гейтит
///   `audio_url`, поэтому подмена локального флага не даёт доступа к контенту.
///
/// Ключ `ADAPTY_PUBLIC_SDK_KEY` пробрасывается в `Info.plist` через
/// User-Defined Build Setting (см. `LiboLibo.xcodeproj`). Если ключ пустой —
/// SDK не активируется, `profileId` остаётся `nil`, бэк видит анонимного
/// зрителя (поведение для существующих юзеров не меняется).
@MainActor
@Observable
final class AdaptyService {
    private(set) var profileId: UUID?
    private(set) var isPremium: Bool = false
    private(set) var expiresAt: Date?
    private(set) var lastRefreshAt: Date?
    /// `true`, когда Adapty SDK успешно поднялся и `profileId` известен.
    private(set) var isActivated: Bool = false

    private let api: APIClient
    private let defaults: UserDefaults

    init(api: APIClient = .shared, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        loadFromCache()
    }

    // MARK: - Lifecycle

    /// Поднимает Adapty SDK (если есть ключ), фиксирует `profileId`. Зовётся
    /// из `LiboLiboApp.task` (cold start). После — `refreshEntitlement`
    /// зовётся отдельно из composition root, чтобы вызывающий мог решить,
    /// нужно ли перезагружать ленту.
    func activate() async {
        let key = AdaptyConfig.publicSDKKey
        guard !key.isEmpty else { return }
        do {
            let configuration = AdaptyConfiguration
                .builder(withAPIKey: key)
                .build()
            try await Adapty.activate(with: configuration)
            try await AdaptyUI.activate()
            let profile = try await Adapty.getProfile()
            if let id = UUID(uuidString: profile.profileId) {
                self.profileId = id
                self.isActivated = true
                defaults.set(profile.profileId, forKey: Keys.profileId)
            }
        } catch {
            // SDK не поднялся — остаёмся в anon mode.
        }
    }

    /// Дёргает `POST /v1/me/entitlement/refresh`, обновляет локальное состояние
    /// и возвращает `true`, если значение `isPremium` изменилось (тогда
    /// вызывающий должен перегрузить ленту: `audio_url` зависит от viewer'а
    /// на бэке).
    @discardableResult
    func refreshEntitlement() async -> Bool {
        guard profileId != nil else { return false }
        do {
            let dto = try await api.refreshEntitlement()
            return applyEntitlement(dto)
        } catch {
            return false
        }
    }

    /// Restore через Adapty SDK + последующий refresh. Зовётся по тапу
    /// «Восстановить покупки» в `ProfileView`.
    func restorePurchases() async -> RestoreOutcome {
        guard isActivated else { return .nothingToRestore }
        do {
            _ = try await Adapty.restorePurchases()
            await refreshEntitlement()
            return isPremium ? .restored : .nothingToRestore
        } catch {
            return .failed(error)
        }
    }

    /// Помечает, что welcome-paywall был показан. Дальше 7 дней не показываем.
    func markWelcomePaywallShown() {
        defaults.set(Date(), forKey: Keys.welcomePaywallLastShownAt)
    }

    /// `true`, если на cold start стоит показать welcome-paywall: SDK
    /// активирован, премиума нет, последний показ был ≥ 7 дней назад (или
    /// его не было вовсе).
    var shouldShowWelcomePaywall: Bool {
        guard isActivated, !isPremium else { return false }
        guard let last = defaults.object(forKey: Keys.welcomePaywallLastShownAt) as? Date else {
            return true
        }
        return Date().timeIntervalSince(last) >= 7 * 24 * 3600
    }

    enum RestoreOutcome {
        case restored
        case nothingToRestore
        case failed(Error)
    }

    // MARK: - Cache

    private func loadFromCache() {
        if let raw = defaults.string(forKey: Keys.profileId), let id = UUID(uuidString: raw) {
            self.profileId = id
        }
        self.isPremium = defaults.bool(forKey: Keys.isPremium)
        self.expiresAt = defaults.object(forKey: Keys.expiresAt) as? Date
        self.lastRefreshAt = defaults.object(forKey: Keys.lastRefreshAt) as? Date
    }

    /// Применяет ответ бэка и пишет в кэш. Возвращает `true`, если `isPremium`
    /// изменился.
    private func applyEntitlement(_ dto: EntitlementDTO) -> Bool {
        let wasPremium = isPremium
        self.isPremium = dto.isPremium
        self.expiresAt = dto.expiresAt
        self.lastRefreshAt = dto.checkedAt ?? Date()

        defaults.set(isPremium, forKey: Keys.isPremium)
        if let expiresAt {
            defaults.set(expiresAt, forKey: Keys.expiresAt)
        } else {
            defaults.removeObject(forKey: Keys.expiresAt)
        }
        defaults.set(lastRefreshAt, forKey: Keys.lastRefreshAt)

        return isPremium != wasPremium
    }

    private enum Keys {
        static let profileId = "adapty.profileId"
        static let isPremium = "adapty.entitlement.isPremium"
        static let expiresAt = "adapty.entitlement.expiresAt"
        static let lastRefreshAt = "adapty.entitlement.lastRefreshAt"
        static let welcomePaywallLastShownAt = "adapty.welcomePaywall.lastShownAt"
    }
}
