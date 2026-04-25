# Сессия 18 — красный текст в фиде и тинтованный фон у экранов подкаста / выпуска / плеера

**Дата:** 2026-04-25
**Участники:** Илья, Claude (Opus 4.7)
**Контекст:** до этой сессии брендовый красный `Theme.liboRed` (#FF3D3D) использовался только как акцент кнопок, пилюль, прогресса, свайпов. На плеере фон был размытой обложкой с чёрной плёнкой; экраны подкаста и выпуска — на стандартном системном фоне.

## Задача

1. Применить красный к **тексту** интерфейса — но ограниченно: только название подкаста в карточках фида.
2. Для каждого подкаста вычислить и сохранить «характерный» фоновый цвет на основе обложки. Использовать его как фон на трёх экранах: плеер, выпуск, подкаст. Цвет шрифта адаптировать.

Илья выбрал минимальный вариант красного — только в `EpisodeRow` (вкладка «Фид»).

## Что сделали

### Сервис цвета

[PodcastColorService.swift](../../LiboLibo/Services/PodcastColorService.swift) — новый `@Observable` сервис, инжектится через `.environment` из `LiboLiboApp`:

- Извлекает «характерный» цвет: уменьшает обложку до 24×24 в RGBA, среди пикселей с яркостью в диапазоне 0.12…0.92 выбирает самый насыщенный (saturation > 0.25). Иначе — средний цвет. Это даёт более «живой» оттенок, чем CIAreaAverage, и при этом устойчиво к чёрно-белым/выцветшим обложкам.
- Кеширует результат в памяти (`tints: [Int: TintColor]`) и в `UserDefaults` под ключом `podcastTintColors.v1`. Повторно для одного `podcastId` не считает.
- `TintColor` хранит `r/g/b` в 0…1 и помогает с контрастным шрифтом: `primaryText`, `secondaryText`, `preferredColorScheme`, `darker` (для нижней точки градиента).

Прогрев цветов запускается в `LiboLiboApp.onAppear` сразу для всех подкастов из бандла, плюс `task` на `PodcastsView` — чтобы за пару секунд после холодного запуска тинт уже был.

### Фон

[TintBackground.swift](../../LiboLibo/Theme/TintBackground.swift) — общий фон для трёх экранов: вертикальный градиент от `tint.color` сверху к `tint.darker` снизу, либо `Color(.systemBackground)`, если цвет ещё не вычислен.

Применили на:

- [PlayerView.swift](../../LiboLibo/Features/Player/PlayerView.swift) — заменили `BlurredBackdrop` на `TintBackground`. Цвета шрифта, прогресса, контролов и пилюль теперь берутся из `tint.primaryText` / `secondaryText`, плюс `preferredColorScheme` подкручивается под яркость фона. Активная пилюля по-прежнему красная — это намеренный единственный «красный» акцент на плеере.
- [PodcastDetailView.swift](../../LiboLibo/Features/Podcasts/PodcastDetailView.swift) — `List` с `.scrollContentBackground(.hidden)`, секции с `listRowBackground(.clear)`, шапка получает явные `primary/secondary` из тинта, остальной контент адаптируется через `.preferredColorScheme(tint?.preferredColorScheme)`.
- [EpisodeDetailView.swift](../../LiboLibo/Features/Episodes/EpisodeDetailView.swift) — `ScrollView` с `TintBackground` и `preferredColorScheme`.

### Красный текст

[EpisodeRow.swift](../../LiboLibo/Features/Feed/EpisodeRow.swift) — `episode.podcastName` теперь `.foregroundStyle(.liboRed)` вместо `.secondary`. Это единственная точка, где красный применяется как цвет интерфейсного текста.

## Проверка

- [x] `xcodebuild ... build` — `** BUILD SUCCEEDED **`.
- [x] `simctl install` + `simctl launch me.libolibo.app` — приложение запущено, в «Фиде» названия подкастов корректно красные.

## Открытые вопросы

— Как воспринимаются красные названия подкастов на тинтованном фоне (когда тинт сам красноватый — например, `Никакого правильно`)? Если глаз будет «слипаться» — можно либо в тинтованных списках выводить имя другим цветом, либо приглушать тинт.
— Вкус градиента (`tint → darker × 0.78`): возможно, на каких-то обложках стоит сделать переход мягче.

## Следующий шаг

— Илья посмотрит UI вживую (Подкаст / Выпуск / Плеер). Если что-то режет глаз — точечная итерация. Дальше — продолжаем шаг 2 (бэкенд).
