# 2026-04-25-26 — iOS-сторона премиум-подписки: каркас (scaffold)

## Контекст

Сразу за сессией 25 (план в [`step-2.3-premium-adapty-ios.md`](../specs/step-2.3-premium-adapty-ios.md)). Пользователь разрешил делать сразу всё, что можно без подключения SPM-зависимости Adapty (это шаг через Xcode UI, не CLI). Подключение SDK + продукт + placement в Adapty Dashboard — следующая сессия.

## Что сделали

Полный каркас iOS-стороны фазы 2.3, готовый собираться и запускаться без `import Adapty`. После добавления SPM-зависимости останется заполнить тела двух методов в `AdaptyService` (TODO-блоки внутри файла) и заменить тело `AdaptyPaywallView` на `UIViewControllerRepresentable` обёртку над `AdaptyPaywallController`.

### Новые файлы

- [`LiboLibo/Services/AdaptyService.swift`](../../LiboLibo/Services/AdaptyService.swift) — `@Observable @MainActor` сервис. Состояние: `profileId`, `isPremium`, `expiresAt`, `lastRefreshAt`, `isActivated`. Методы: `activate()`, `refreshEntitlement()`, `restorePurchases()`, `markWelcomePaywallShown()`. Кэш в `UserDefaults` (переживает запуски). Тело `activate` и `restorePurchases` — заглушки с TODO-комментариями для SDK-вызовов; `refreshEntitlement` уже реально дёргает бэкенд через `APIClient`.
- [`LiboLibo/Features/Subscription/AdaptyPaywallView.swift`](../../LiboLibo/Features/Subscription/AdaptyPaywallView.swift) — placeholder paywall (SwiftUI View с описанием подписки и кнопкой «Закрыть»). После SPM — заменяется на обёртку над `AdaptyPaywallController` (см. TODO внутри файла).

### Изменённые файлы

- [`LiboLibo/Services/APIClient.swift`](../../LiboLibo/Services/APIClient.swift) — добавил `attachProfileIdProvider(_:)`, заголовок `X-Adapty-Profile-Id` для всех запросов, методы `refreshEntitlement()` и `fetchEntitlement()`, `EntitlementDTO`. Refactor: `get`/`post` через `URLRequest` (вместо `session.data(from:)`), общий `execute` с декодингом.
- [`LiboLibo/App/LiboLiboApp.swift`](../../LiboLibo/App/LiboLiboApp.swift) — composition root для `AdaptyService`, wiring `APIClient.attachProfileIdProvider`, cold-start `activate()` + `refreshEntitlement()`, перезагрузка ленты при изменении `isPremium`, welcome-paywall sheet с проверкой `shouldShowWelcomePaywall`.
- [`LiboLibo/Features/Episodes/EpisodeDetailView.swift`](../../LiboLibo/Features/Episodes/EpisodeDetailView.swift) — для непроигрываемого эпизода вместо плашки «Доступно по подписке» теперь кнопка `borderedProminent` «Слушать с премиумом», открывающая `.sheet` с `AdaptyPaywallView(placementId: "episode-trigger")`. После успеха — `refreshEntitlement` + `loadAllEpisodes`.
- [`LiboLibo/Features/Profile/ProfileView.swift`](../../LiboLibo/Features/Profile/ProfileView.swift) — новая секция «Премиум» сверху списка. Если `isPremium == true` — статус и срок + ссылка «Управлять подпиской» (deep link App Store). Если нет — заголовок, кнопки «Оформить» и «Восстановить покупки». Restore показывает три варианта alert (восстановили / нет покупок / ошибка).

### Поведение прямо сейчас (без SPM)

- `AdaptyService.activate()` — no-op. `profileId == nil`, бэк видит анонимного зрителя, премиум-эпизоды с замочком (как до этой фазы).
- Кнопка «Слушать с премиумом» в `EpisodeDetailView` — открывает sheet с placeholder paywall'ом.
- В `ProfileView` секция «Премиум» в режиме «не подписан» — кнопки «Оформить» (открывает placeholder) и «Восстановить покупки» (всегда возвращает «Покупок не найдено»).
- Welcome-paywall — НЕ появляется на cold start (`isActivated == false`).
- Никаких регрессий в существующем UX.

### Что заполняется после SPM-add Adapty + AdaptyUI

1. В `AdaptyService.activate()` — `Adapty.activate(with: AdaptyConfiguration.builder(withAPIKey: ADAPTY_PUBLIC_SDK_KEY).build())`, `Adapty.getProfile()`, выставить `profileId` и `isActivated = true`.
2. В `AdaptyService.restorePurchases()` — `Adapty.restorePurchases()` + последующий `refreshEntitlement` + классификация результата.
3. В `AdaptyPaywallView` — `UIViewControllerRepresentable` над `AdaptyPaywallController` (с `Adapty.getPaywall(placementId:)` + `AdaptyUI.getViewConfiguration(forPaywall:)`).
4. xcconfig + `Info.plist` — `ADAPTY_PUBLIC_SDK_KEY` через переменную (xcconfig в `.gitignore`).

## Сборка / симулятор

- `xcodebuild ... build` → `** BUILD SUCCEEDED **`.
- Установка в booted-симулятор `iPhone 17` + launch → запустилось.

## Что НЕ делали

- SPM-зависимость Adapty — это шаг через Xcode UI (`File → Add Package Dependencies`), не CLI.
- xcconfig для `ADAPTY_PUBLIC_SDK_KEY` — добавится вместе с SPM (бессмысленно без SDK, который её читает).
- `paywall placement` в Adapty Dashboard, продукт в App Store Connect, sandbox-тестер — UI-настройки в дашбордах, не код.

## Следующий шаг

iOS-сессия 27 — подключить SDK:
1. Открыть Xcode → File → Add Package Dependencies → `https://github.com/adaptyteam/AdaptySDK-iOS` → выбрать продукты `Adapty` + `AdaptyUI`.
2. Создать `LiboLibo/Resources/Config.xcconfig` (в `.gitignore`) с `ADAPTY_PUBLIC_SDK_KEY = <ключ из subs.env>`. Подключить xcconfig к Debug/Release в Xcode Project Settings. В `Info.plist` добавить ключ `ADAPTY_PUBLIC_SDK_KEY` → `$(ADAPTY_PUBLIC_SDK_KEY)`.
3. Заполнить TODO в `AdaptyService.activate()` и `restorePurchases()`.
4. Заполнить TODO в `AdaptyPaywallView` — обёртка над `AdaptyPaywallController`.
5. В Adapty Dashboard — создать paywall и placement (например `welcome` + `episode-trigger` + `profile-cta`, или один общий). Привязать продукт.
6. Sandbox-проверка по шагу 9 спеки.
