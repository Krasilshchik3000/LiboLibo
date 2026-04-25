import SwiftUI
import Adapty
import AdaptyUI

/// SwiftUI-обёртка над AdaptyUI paywall'ом. Загружает paywall и его
/// view-конфигурацию по `placementId` из Adapty Dashboard, рендерит
/// `AdaptyPaywallController`. Если placement не сконфигурирован в дашборде,
/// нет сети, или SDK не активирован — показывает fallback-плашку.
struct AdaptyPaywallView: View {
    let placementId: String
    var onPurchase: () -> Void = {}
    var onClose: () -> Void = {}

    @State private var configuration: AdaptyUI.PaywallConfiguration?
    @State private var loadError: Error?

    var body: some View {
        ZStack {
            if let configuration {
                PaywallControllerWrapper(
                    configuration: configuration,
                    onPurchase: onPurchase,
                    onClose: onClose
                )
                .ignoresSafeArea()
            } else if loadError != nil {
                fallback
            } else {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .task(id: placementId) {
            do {
                let paywall = try await Adapty.getPaywall(placementId: placementId, locale: "ru")
                let config = try await AdaptyUI.getPaywallConfiguration(forPaywall: paywall)
                self.configuration = config
            } catch {
                self.loadError = error
            }
        }
    }

    private var fallback: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.liboRed)
            Text("Премиум-подписка")
                .font(.title2.bold())
            Text("Сейчас покупка недоступна.\nПопробуй позже.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
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

private struct PaywallControllerWrapper: UIViewControllerRepresentable {
    let configuration: AdaptyUI.PaywallConfiguration
    let onPurchase: () -> Void
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        do {
            return try AdaptyUI.paywallController(
                with: configuration,
                delegate: context.coordinator
            )
        } catch {
            return UIViewController()
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPurchase: onPurchase, onClose: onClose)
    }

    final class Coordinator: NSObject, AdaptyPaywallControllerDelegate {
        private let onPurchase: () -> Void
        private let onClose: () -> Void

        init(onPurchase: @escaping () -> Void, onClose: @escaping () -> Void) {
            self.onPurchase = onPurchase
            self.onClose = onClose
        }

        // MARK: - Close action

        func paywallController(
            _ controller: AdaptyPaywallController,
            didPerform action: AdaptyUI.Action
        ) {
            switch action {
            case .close:
                onClose()
            case .openURL, .custom:
                break
            @unknown default:
                break
            }
        }

        // MARK: - Purchase

        func paywallController(
            _ controller: AdaptyPaywallController,
            didFinishPurchase product: AdaptyPaywallProduct,
            purchaseResult: AdaptyPurchaseResult
        ) {
            switch purchaseResult {
            case .success:
                onPurchase()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        }

        func paywallController(
            _ controller: AdaptyPaywallController,
            didFailPurchase product: AdaptyPaywallProduct,
            error: AdaptyError
        ) {
            // оставляем юзера на paywall'е, он сам решит — закрыть или попробовать ещё.
        }

        // MARK: - Restore

        func paywallController(
            _ controller: AdaptyPaywallController,
            didFinishRestoreWith profile: AdaptyProfile
        ) {
            // Если в профиле уже есть активный access level — считаем восстановлением.
            // refreshEntitlement в onPurchase всё равно перепроверит на сервере.
            onPurchase()
        }

        func paywallController(
            _ controller: AdaptyPaywallController,
            didFailRestoreWith error: AdaptyError
        ) {
            // молча — UI остаётся на paywall'е.
        }

        // MARK: - Required no-op

        func paywallController(
            _ controller: AdaptyPaywallController,
            didFailRenderingWith error: AdaptyUIError
        ) {
            onClose()
        }
    }
}
