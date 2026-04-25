# Либо-Либо

Нативное мобильное приложение для подкастов студии «Либо-Либо». Разрабатывается публично, в режиме vibe-coding с Claude.

## Документация

Все обсуждения, спецификации и логи рабочих сессий лежат в [`docs/`](docs/).

Текущая отправная точка — [docs/sessions/2026-04-25-kickoff.md](docs/sessions/2026-04-25-kickoff.md): что мы поняли на стартовом стриме и ТЗ на первый шаг.

## Команда

- **Илья Красильщик** — продукт и iOS UI
- **Самат Галимов** — backend, админка, оплаты
- Сообщество — комментарии и предложения через Issues и Pull Request

## Технологический стек (планируемый)

- **iOS:** Swift, SwiftUI, AVFoundation
- **Android:** Kotlin (после стабилизации iOS, перенос с помощью AI)
- **Backend:** Node.js (стек развёртывания на стороне Самата)
- **Источник контента:** RSS-фиды подкастов Либо-Либо

## Билд и запуск (iOS)

Требования: macOS, Xcode 16+.

```bash
git clone https://github.com/Krasilshchik3000/LiboLibo.git
cd LiboLibo
open LiboLibo.xcodeproj   # → Xcode → Cmd+R
```

Проект использует synchronized folders — новые исходники в `LiboLibo/` подхватываются Xcode автоматически.

Без UI:

```bash
xcodebuild -scheme LiboLibo -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Текущий план разработки и фазы — в [docs/specs/step-01-ios-skeleton.md](docs/specs/step-01-ios-skeleton.md).
