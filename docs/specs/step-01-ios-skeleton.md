# Spec: Шаг 1 — iOS-приложение

**Базовое ТЗ:** [docs/sessions/2026-04-25-kickoff.md](../sessions/2026-04-25-kickoff.md). Поправки: [docs/sessions/2026-04-25-02-corrections.md](../sessions/2026-04-25-02-corrections.md).
**Owner:** Илья (направляет), Claude (кодит).

## Цель шага 1

«Сырой работающий MVP» (директива Егора) — приложение запускается, показывает реальные подкасты Либо-Либо, играет выпуски, помнит подписки и историю.

## Фазы (сжатый план)

| Фаза | Что делаем | Статус |
|---|---|---|
| **1.0** | Каркас: пустое приложение с тремя вкладками | ✅ [session 03](../sessions/2026-04-25-03-step-1.0.md) |
| **1.1** | **Браузить:** Фид + Подкасты с реальным RSS — список выпусков всех 44 подкастов, сетка обложек, экран подкаста | ✅ [session 04](../sessions/2026-04-25-04-step-1.1.md) |
| **1.2** | **Слушать:** AVPlayer, mini-player + полноэкранный, ±10 / play/pause / скорость, background audio + lock screen controls | ✅ [session 05](../sessions/2026-04-25-05-step-1.2.md) |
| **1.3** | **Сохранять и шлифовать:** подписки (UserDefaults), профиль с подписками / свежим / историей, тёмная тема и dynamic type из коробки | ✅ [session 06](../sessions/2026-04-25-06-step-1.3.md) |
| **1.4** | **UX-фиксы и поиск:** mini-player на iOS 26 `tabViewBottomAccessory` + `tabBarMinimizeBehavior(.onScrollDown)`, выравнивание сетки подкастов (`reservesSpace`), таб «Поиск» с объектным результатом (Подкасты / Выпуски) | ✅ [session 07](../sessions/2026-04-25-07-step-1.4.md) |
| **1.5** | **Полировка по гайдам iOS:** Tab API + `Tab(role: .search)` (нативный «search в правом углу» + collapse-tabs паттерн), фикс «облачка плеера, когда ничего не играет» (accessory выключается, когда нет episode), полная программная UI-регрессия через cliclick | ✅ [session 08](../sessions/2026-04-25-08-step-1.5.md) |

**Шаг 1 закрыт.** Дальше — шаг 2 (бэкенд Самата, push-уведомления, оффлайн).

## Стартовые параметры

- **Стек:** Swift, SwiftUI, AVFoundation, SwiftData, URLSession, XMLParser.
- **Минимальный iOS:** 18.0.
- **Bundle ID:** `me.libolibo.app`.
- **Display name:** «Либо-Либо».
- **Источник данных:** [`docs/specs/podcasts-feeds.json`](podcasts-feeds.json) — 44 фида студии libo/libo. Копия лежит в бандле приложения.
- **Шрифт:** временно — системный San Francisco. Финальный выбор (Gerbera vs OFL-альтернативы) обсуждается, см. [сессию 02](../sessions/2026-04-25-02-corrections.md).
- **Сборка:** через Xcode напрямую. `LiboLibo.xcodeproj` в репо. `LiboLibo/` — synchronized root group: новые файлы в этой папке подхватываются Xcode автоматически без правок проекта.

## Структура репозитория

```
LiboLibo/
├── LiboLibo.xcodeproj/           # Xcode-проект (synchronized folders)
├── LiboLibo/                     # Все исходники здесь
│   ├── App/
│   ├── Features/
│   │   ├── Feed/
│   │   ├── Podcasts/
│   │   └── Profile/
│   ├── Models/                   # появятся на 1.1
│   ├── Services/                 # появятся на 1.1
│   └── Resources/
│       └── Assets.xcassets
├── docs/                         # документация и логи сессий
└── README.md
```

## Билд и запуск

```bash
git clone https://github.com/Krasilshchik3000/LiboLibo.git
cd LiboLibo
open LiboLibo.xcodeproj      # → Cmd+R
```

## DoD шага 1 целиком

После 1.3 приложение делает следующее без бэкенда:
- Открываешь — видишь ленту реальных выпусков всех 44 подкастов студии.
- Тапаешь — играет. Сворачиваешь — продолжает играть. На lock screen — контролы.
- На «Подкастах» можешь подписаться. На «Моё» видны подписки и история.
- Тёмная тема и dynamic type работают.

После этого шаг 2 — бэкенд Самата, push-уведомления, оффлайн, авторизация и т.д.
