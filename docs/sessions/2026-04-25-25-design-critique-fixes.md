# 2026-04-25 — Сессия 25. Design critique + правки по 5 пунктам

## Контекст

Илья запустил `/design:design-critique` с аргументом «изучи весь наш апп —
все экраны». Я прошёлся по всем основным вьюхам (Feed, Podcasts,
PodcastDetail, Player, MiniPlayer, Profile, Search) и скриншотам шагов
1.x–1.11 в `docs/screenshots/`, выдал структурированный разбор: usability,
visual hierarchy, consistency, accessibility, что работает.

Ключевые проблемы:
1. `Color.liboRed` (`#FF3D3D`) использовался как цвет caption-а имени шоу
   на белом — контраст ~3.7:1, ниже WCAG AA для мелкого текста.
2. Инвертированный паттерн «тап по строке = играть, кнопка (i) = детали»
   не имел видимой подсказки.
3. Состояние «Подписан» на `PodcastDetailView` отрисовывалось через
   `.tint(.secondary)` — выглядело как **disabled**, а не как активное.
4. Пустое состояние «Подписки» в Профиле — серый текст без CTA, теряет
   момент конверсии в подписку.
5. `UtilityRow` плеера смешивал две визуальные системы: pill-кнопки для
   speed/sleep и голые иконки для notes/queue/download.

Илья: «Правь все, но пуш только с моего разрешения».

## Что сделали

### #1 EpisodeListItem — контраст + play-overlay
[`LiboLibo/Features/Feed/FeedView.swift`](../../LiboLibo/Features/Feed/FeedView.swift)

После rebase на свежий `origin/main` оказалось, что `EpisodeRow.swift`
там удалён, а его контент инлайнен в `FeedView.swift` как
`EpisodeListItem` (PR #16 «Queue management»). Перенёс правки в
актуальное место:

- Имя подкаста: `.foregroundStyle(.liboRed)` → `.foregroundStyle(.secondary)`.
  Брендовый красный остаётся за интерактивами (выбранный таб, чекмарк
  подписки, play в мини-плеере, акцент прогресса).
- Поверх артворка — `play.circle.fill` (28pt, palette: white-on-black65%,
  shadow). Только для `episode.isPlayable`. Премиум-эпизоды без
  entitlement по-прежнему показывают `lock.fill` в метастроке.

### #3 PodcastDetailView — `SubscribeCTA`
[`LiboLibo/Features/Podcasts/PodcastDetailView.swift`](../../LiboLibo/Features/Podcasts/PodcastDetailView.swift)

Заменили `.borderedProminent` + `.tint(.secondary)` на собственный
компонент `SubscribeCTA`:
- Не подписан: фон = `accent` (per-podcast tint или `.liboRed`), текст
  — `accentForeground` (обычно `.white`). Это CTA-состояние.
- Подписан: фон = `accent.opacity(0.15)`, обводка `accent.opacity(0.3)`,
  текст и иконка `checkmark` в цвете `accent`. Читается как «у меня уже
  это есть», а не «недоступно».

### #4 ProfileView — CTA «Открыть подкасты»
[`LiboLibo/Features/Profile/ProfileView.swift`](../../LiboLibo/Features/Profile/ProfileView.swift)
+ [`LiboLibo/App/RootView.swift`](../../LiboLibo/App/RootView.swift)

- В `ProfileView` добавлен опциональный колбэк `onOpenPodcasts: (() -> Void)?`.
- Пустое состояние секции «Подписки» теперь — переписанный текст +
  красная кнопка «Открыть подкасты» (44pt, `Color.liboRed`).
- `RootView` на iOS 26 и legacy одинаково передаёт
  `onOpenPodcasts: { selectedTab = .podcasts }`.

### #5 PlayerView — pill только при недефолтном состоянии
[`LiboLibo/Features/Player/PlayerView.swift`](../../LiboLibo/Features/Player/PlayerView.swift)

- `PillButton` теперь рендерится двумя ветками: при `isHighlighted=true`
  — pill с тинтом подкаста + текущим значением (1.5×, 15м); при
  `isHighlighted=false` — голая иконка 44×44 (визуально совпадает с
  notes/queue/download рядом).
- Call-site передаёт пустой `text` в дефолтном состоянии:
  - speed: text = `formatRate(rate)` только при `rate != 1.0`,
  - sleep: text = `sleepTimer.label` только при `sleepTimer.isActive`.

## Ритуал завершения

- `xcodebuild ... build` → **BUILD SUCCEEDED** (на iPhone 17 / iOS 26.4 SDK).
- `xcrun simctl install booted` + launch — приложение запустилось,
  визуально подтверждены: серый caption имени шоу и play-overlay в фиде,
  premium-эпизод без overlay (с lock).
- Коммит сделан, **пуш отложен по просьбе Ильи** (другие сессии
  параллельно мерджатся в main, не хочется конфликтов).

## Открытые вопросы

- `MarqueeText` в `MiniPlayerView` пока не уважает
  `accessibilityReduceMotion` — отдельная задача.
- В `PodcastsView` `SubscribeButton` (28×28) и `progressBar` (drag-area
  18pt) меньше HIG-минимума 44pt — пометил для отдельной а11y-итерации,
  но не трогал в этой сессии.

## Что дальше

Проверить интерактивно:
- На `PodcastDetailView` подписаться/отписаться — кнопка должна менять
  фон с заполненного на тинт-15% с обводкой.
- В Профиле, если нет подписок — должна появиться красная кнопка
  «Открыть подкасты», тап на неё переключает таб.
- В плеере: при rate=1× и sleep off — иконки. Тап на 🐎 → «1.5×» в pill
  с тинтом подкаста. Аналогично sleep.

Если визуально OK — push.
