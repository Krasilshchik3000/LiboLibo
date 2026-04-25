# 2026-04-25-28 — App Store Connect: метаданные и страница поддержки

## Контекст

Готовим первый сабмит «Либо-Либо» в App Store. В App Store Connect горят красные ошибки на странице iOS App Version 1.0:

- нет скриншота для 6.5" iPhone displays;
- не отвечен age rating;
- не заполнен Contact Information;
- пусто Copyright;
- админ должен заполнить App Privacy;
- по русской локализации пусто: Description, Keywords, Support URL.

Пользователь попросил подготовить максимум — тексты, support URL, скриншоты — чтобы ему оставались только клики в ASC.

## Что обсудили

- **Студия не Ильи Красильщика.** В первой версии текстов я ошибочно поставил его как автора студии — поправил на нейтральное «студия Либо-Либо».
- **Контакты для App Review** — Самата Галимова: `Samat Galimov`, `+371 25429427`, `s@samat.me`.
- **Support URL.** Постоянного лендинга нет, лучшее решение — добавить страницу `/support` рядом с уже существующими `/terms` и `/privacy` на бэкенде.

## Что сделали

- [`api/src/routes/legal.ts`](../../api/src/routes/legal.ts) — добавлен `GET /support`. На странице: e-mail (`s@samat.me`), ссылка на GitHub Issues, что приложить к письму, инструкция по управлению подпиской через App Store, ссылки на Terms и Privacy. Стили общие (`baseStyles`), как у остальных legal-страниц. Email Самата вынесен в отдельную константу `SUPPORT_EMAIL`, чтобы не путать с `CONTACT_EMAIL` (Ильи) в Terms/Privacy.
- `npx tsc --noEmit src/routes/legal.ts` — чисто. (Глобальный `tsc --noEmit` падает на pre-existing missing modules — не связано.)

После пуша Railway задеплоит автоматически. URL: <https://libolibo-production.up.railway.app/support>.

## Заготовки текстов для ASC (отправлены пользователю в чат, не в репо)

- **Description (RU)** — 8 пунктов про возможности, упоминание Либо-Либо+ для эксклюзивных выпусков.
- **Keywords (RU, 96 симв.)** — `подкасты,либолибо,красильщик,что случилось,так вышло,аудио,плеер,радио,новости,журналистика`.
- **Copyright** — `2026 Либо-Либо` (или официальное юрлицо студии, если есть).
- **Age Rating** — рекомендован 17+ при честном ответе про мат: Profanity = Frequent/Intense, остальные категории — None / Infrequent. Made for Kids: No.
- **Contact Information** — Samat Galimov, +371 25429427, s@samat.me.
- **App Privacy** — минимальный набор: Device ID + Purchase History + Crash Data + Performance Data; Tracking = No.
- **Support URL** — `https://libolibo-production.up.railway.app/support` (после деплоя этой сессии).
- **Marketing URL (опц.)** — `https://github.com/Krasilshchik3000/LiboLibo`.

## Открытые вопросы / TODO

- **Скриншоты 6.5" iPhone displays** (1284×2778). Снять в симуляторе iPhone 11 Pro Max / iPhone 14 Plus: фид, экран подкаста, плеер, профиль, paywall. Положить в `docs/screenshots/appstore/`. Договорились — делаю в следующей сессии после того, как соберём приложение в симуляторе.
- **Юрлицо студии** для поля Copyright в ASC. Сейчас заглушка `2026 Либо-Либо`.
- **Постоянный домен.** `/terms`, `/privacy`, `/support` сейчас живут на `libolibo-production.up.railway.app` — надо переехать на постоянный домен до релиза, оставить 301-редиректы.
