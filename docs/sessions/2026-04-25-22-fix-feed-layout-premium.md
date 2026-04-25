# 2026-04-25-22 — Фикс лайаута фида для премиум-эпизодов

## Контекст

После мержа PR #6 (очередь, см. сессию 2026-04-25-21) и предшествующего рефактора `EpisodeListItem` (коммит `0c14493`) обнаружилось, что строка фида **для премиум-эпизодов** ломается: текст в `EpisodeRow` рвётся посимвольно в очень узкую колонку, рядом видны два `>` chevron'а.

## Диагноз

В `EpisodeListItem` после `0c14493` структура была:

```swift
HStack(spacing: 4) {
    if episode.isPlayable {
        Button(action: onPlay) { EpisodeRow(...) }
    } else {
        NavigationLink(value: episode) { EpisodeRow(...) }   // премиум
    }
    NavigationLink(value: episode) { Image("info.circle")... }  // всегда
}
```

Для обычных эпизодов: `Button + NavigationLink` — работает.
Для премиум-эпизодов: `NavigationLink + NavigationLink` — два соседних `NavigationLink` внутри `List` ломают распределение ширины: каждый берёт ~половину и рендерит свой системный disclosure-chevron, `EpisodeRow` получает узкую колонку. `.buttonStyle(.plain)` в iOS 26 в `List` это, видимо, не давит.

## Что сделали (вариант A)

Вернули `onShowDetail`-колбэк в `EpisodeListItem`, оба внутренних виджета — `Button`. Один `NavigationLink` в строке остаётся только косвенно, через `path.append(episode)` родительского `NavigationStack`.

### Файлы

- `LiboLibo/Features/Feed/FeedView.swift`:
  - `EpisodeListItem`: вернули `let onShowDetail: () -> Void`. Внутренний виджет — `Button(action: episode.isPlayable ? onPlay : onShowDetail) { EpisodeRow(...) }`. «i» — `Button(action: onShowDetail)`. Никаких `NavigationLink` внутри строки.
  - Вызов `EpisodeListItem` дополнен `onShowDetail: { path.append(episode) }`.

- `LiboLibo/Features/Profile/ProfileView.swift`: то же — три места (downloadedSection, recentSection, historySection).
- `LiboLibo/Features/Search/SearchView.swift`: то же.
- `LiboLibo/Features/Podcasts/PodcastDetailView.swift`:
  - У этого view нет собственного `NavigationStack`, локальный `path` был бы «висящим» (это и был исходный мотив рефактора `0c14493`). Решение: принимаем `@Binding var path: NavigationPath` от родителя. В `onShowDetail` — `path.append(episode)`, что пушит `EpisodeDetailView` в общий стек.
- `LiboLibo/Features/Podcasts/PodcastsView.swift`, `Profile/ProfileView.swift`, `Search/SearchView.swift`:
  - В `.navigationDestination(for: Podcast.self)` пробросили `path: $path` в `PodcastDetailView`.

`PodcastDetailView` сохранил свой `.navigationDestination(for: Episode.self)` — он регистрируется на родительском `NavigationStack` через propagation модификатора. Для `PodcastsView` (которая до сих пор Episode-destination не объявляла) это и есть единственный регистратор; пока `PodcastDetailView` на экране — пуш Episode работает.

### Сборка

`xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 17'` → `BUILD SUCCEEDED`.
Установлено и запущено в симуляторе.

## Открытые вопросы

- Хорошо бы визуально проверить и запушить скрин, что текст премиум-эпизода теперь верстается на полную ширину строки.
- Возможно, имеет смысл явно объявить `.navigationDestination(for: Episode.self)` в `PodcastsView` (а не полагаться на propagation из `PodcastDetailView`) — это более устойчиво, если когда-нибудь понадобится пушить Episode из самого `PodcastsView`.
