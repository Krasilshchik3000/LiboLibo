import SwiftUI

/// SwiftUI-обёртка над AdaptyUI paywall'ом.
///
/// **Текущее состояние:** SPM-зависимости Adapty / AdaptyUI ещё не
/// подключены, поэтому здесь — placeholder-View с описанием подписки и
/// кнопкой «Закрыть». UX-flow можно тестировать уже сейчас: тап на премиум →
/// `EpisodeDetailView` → кнопка → sheet с этим View.
///
/// **TODO (после SPM Adapty + AdaptyUI):** заменить тело на
/// `UIViewControllerRepresentable` над `AdaptyPaywallController`:
/// ```swift
/// let paywall = try await Adapty.getPaywall(placementId: placementId, locale: "ru")
/// let config = try await AdaptyUI.getViewConfiguration(forPaywall: paywall)
/// let controller = AdaptyPaywallController(
///     paywall: paywall,
///     viewConfiguration: config,
///     delegate: ...
/// )
/// ```
/// Колбэки делегата:
/// - `.didFinishPurchase` → `onPurchase()` (далее AdaptyService.refreshEntitlement)
/// - `.didFinishRestore` → если premium активен — `onPurchase()`, иначе `onClose()`
/// - `.didCancel` → `onClose()`
struct AdaptyPaywallView: View {
    let placementId: String
    var onPurchase: () -> Void = {}
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.liboRed)
            Text("Премиум-подписка")
                .font(.title2.bold())
            Text("Бонусные и эксклюзивные выпуски «Либо-Либо».")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Text("Подключение Adapty SDK — следующий шаг.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                onClose()
            } label: {
                Text("Закрыть")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.liboRed)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
