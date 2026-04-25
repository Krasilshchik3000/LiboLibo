# 2026-04-25-27 — Adapty SDK подключён в iOS-приложение

## Контекст

Сразу после сессии 26 (каркас фазы 2.3 iOS — заглушки `AdaptyService` + `AdaptyPaywallView` без SPM-зависимости). Пользователь подтвердил, что ключи Adapty есть, и попросил подключить SDK сейчас.

## Что сделали

1. **SPM-зависимость:** добавили `https://github.com/adaptyteam/AdaptySDK-iOS` (резолвится в `3.15.7`) с продуктами `Adapty` + `AdaptyUI`. Сделали через ruby `xcodeproj` gem ([`scripts/add_adapty_spm.rb`](../../scripts/add_adapty_spm.rb), идемпотентный) — устанавливать SPM через CLI Xcode не умеет, но `xcodeproj` правит `project.pbxproj` напрямую. Скрипт оставлен в репо для воспроизводимости.

2. **Build settings:** в `LiboLibo.xcodeproj`:
   - `ADAPTY_PUBLIC_SDK_KEY` — пустой (User-Defined). Пользователь вписывает ключ через Xcode → Project → Build Settings.
   - `INFOPLIST_KEY_ADAPTY_PUBLIC_SDK_KEY = $(ADAPTY_PUBLIC_SDK_KEY)` — пробрасывает в сгенерированный Info.plist (проект использует `GENERATE_INFOPLIST_FILE = YES`).

3. **`AdaptyService` — реальный код вместо TODO:**
   - `import Adapty`, `import AdaptyUI`.
   - `activate()` — читает ключ из `Bundle.main.object(forInfoDictionaryKey:)`, активирует `Adapty.activate(with: AdaptyConfiguration.builder...)`, активирует `AdaptyUI.activate()`, получает `Adapty.getProfile()`, выставляет `profileId` и `isActivated = true`. Если ключа нет или активация упала — остаёмся в anon mode (без crash'а).
   - `restorePurchases()` — `Adapty.restorePurchases()` + `refreshEntitlement()`. Возвращает `.restored` / `.nothingToRestore` / `.failed(Error)`.

4. **`AdaptyPaywallView` — реальная обёртка над `AdaptyPaywallController`:**
   - SwiftUI `View` с двумя состояниями: загрузка (`ProgressView`) и `PaywallControllerWrapper` (`UIViewControllerRepresentable`). Если `Adapty.getPaywall(...)` или `AdaptyUI.getPaywallConfiguration(...)` упали (placement не сконфигурирован, нет сети) — fallback-плашка «Сейчас покупка недоступна. Попробуй позже» с кнопкой «Закрыть».
   - `Coordinator: AdaptyPaywallControllerDelegate` обрабатывает: `.close` → `onClose`, `didFinishPurchase` → если `purchaseResult.success` → `onPurchase`, `didFinishRestoreWith profile` → `onPurchase` (затем рефреш на сервере подтвердит). Ошибки рендеринга → `onClose`.

5. **`xcodebuild build` → `** BUILD SUCCEEDED **`** (только pre-existing Swift 6 warning'и в `APIClient.shared` / `PodcastsRepository.shared` — не related).
6. **Установка + запуск в booted-симулятор `iPhone 17`** — без crash'ей. SDK не активируется (ключ пустой), `profileId == nil`, бэк видит anon viewer, поведение для существующих юзеров без изменений.

## Файлы

| Файл | Что |
|---|---|
| [`scripts/add_adapty_spm.rb`](../../scripts/add_adapty_spm.rb) | new: ruby-скрипт для добавления SPM-зависимости и build settings (идемпотентный) |
| [`LiboLibo.xcodeproj/project.pbxproj`](../../LiboLibo.xcodeproj/project.pbxproj) | modified: `XCRemoteSwiftPackageReference` для AdaptySDK-iOS, `package_product_dependencies` (Adapty + AdaptyUI), build settings `ADAPTY_PUBLIC_SDK_KEY` + `INFOPLIST_KEY_ADAPTY_PUBLIC_SDK_KEY` |
| `LiboLibo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | new: SPM lockfile (Adapty 3.15.7) |
| [`LiboLibo/Services/AdaptyService.swift`](../../LiboLibo/Services/AdaptyService.swift) | modified: реальный `Adapty.activate` + `AdaptyUI.activate` + `getProfile`, реальный `restorePurchases` |
| [`LiboLibo/Features/Subscription/AdaptyPaywallView.swift`](../../LiboLibo/Features/Subscription/AdaptyPaywallView.swift) | modified: `UIViewControllerRepresentable` обёртка над `AdaptyPaywallController`, fallback-плашка для случаев, когда paywall не загрузился |

## Что нужно от пользователя для конца фазы 2.3

1. **Открыть Xcode → Project (LiboLibo) → Build Settings → User-Defined → `ADAPTY_PUBLIC_SDK_KEY`**, вписать ключ из `subs.env`. Закоммитить — **только если это публичный SDK key** (Adapty это разрешает; если по ошибке вписать Secret API key — это критичная ошибка, см. SECURITY.md).
2. **В Adapty Dashboard:**
   - Создать paywall и привязать его к **одному** placement'у (или нескольким — `welcome`, `episode-trigger`, `profile-cta`). Сейчас в коде используются три ID, можно сделать один общий и поменять три места в Swift на одно имя.
   - Добавить продукт (Subscription Group → tier) — Adapty синхронизирует с App Store Connect.
3. **App Store Connect:**
   - Subscription Group + tier (например, месячная подписка).
   - Sandbox-тестер для отладки.
4. **Sandbox-проверка** (по шагу 9 спеки `step-2.3-premium-adapty-ios.md`):
   - Купить → бэк отдаёт `audio_url` → плеер играет.
   - Restore на свежей установке.
   - Истечение sandbox-подписки → бэк перестаёт отдавать `audio_url` после следующего refresh.

## Открытые вопросы

- Точное имя placement'а в Adapty Dashboard. Сейчас в коде три ID (`welcome`, `episode-trigger`, `profile-cta`). После того как пользователь создаст paywall — обновим эти строки.
- Текст и оффер на paywall'е — конфигурируется в Adapty Dashboard, не в коде.
