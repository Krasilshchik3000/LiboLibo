import Foundation

/// Константы Adapty.
///
/// `publicSDKKey` — Public SDK Key из Adapty Dashboard. По документации Adapty,
/// этот ключ предназначен для использования в клиентском коде и считается
/// публичным (не secret). Хранится в репозитории. Серверный Secret API Key —
/// в Railway Variables, в репо его быть не должно (см. `SECURITY.md`).
enum AdaptyConfig {
    static let publicSDKKey = "public_live_rj0kCiWl.y24PVWRN42JhQlvSHcea"
}
