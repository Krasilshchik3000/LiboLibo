# Шаг 4 — Голос-комментарии к эпизодам

**Статус:** план, реализация в следующих сессиях.
**Зависит от:** фаза 2.3 (Adapty premium) — фича доступна только пользователям с активным entitlement; птица-имя привязывается к `adapty_profile_id`.
**Связанная сессия:** [`2026-04-25-26-voice-comments-design.md`](../sessions/2026-04-25-26-voice-comments-design.md).

## Задача

Дать слушателю возможность во время воспроизведения эпизода нажать кнопку микрофона на lock screen (Live Activity) и оставить **голосовой комментарий с тайм-кодом**. Подкаст в момент записи плавно уходит на паузу, после окончания речи плавно возвращается. Комментарий отправляется на бэкенд, в фоне расшифровывается через `SFSpeechRecognizer` (on-device), показывается всем слушателям эпизода в виде ленты с тайм-кодами и маркерами на скрабере. Текст комментария можно прочитать, аудио — прослушать.

Запись доступна только премиум-юзерам. Чтение — всем (включая free-юзеров): это конверсионный крючок.

## Решения

| Вопрос | Решение |
|---|---|
| Идентичность пользователя | `adapty_profile_id` (тот же, что в `entitlements`). Логина нет. |
| Имя пользователя в комментариях | Случайная русская птица, детерминированная хэшем `adapty_profile_id` (например, "Сорока"). Pool ≈1000+ птиц. На коллизию — суффикс `-2`, `-3`, … |
| Кто пишет / кто читает | Пишут только премиум; читают все. |
| Точка входа | Live Activity на lock screen (App Intent кнопка-микрофон) + дублирующая кнопка в `PlayerView`. |
| Жизненный цикл записи | Гибрид (single-shot + grace window). Тап микрофона → подкаст плавно пауза → пользователь говорит → тишина 1.5 с → подкаст плавно возвращается, **запись держится ещё 3 с в "soft cutoff"** — если пользователь снова заговорил, подкаст снова паузится и запись продолжается одним треком. По истечении grace без речи — финализируется. |
| Расшифровка | `SFSpeechRecognizer`, locale `ru-RU`, `requiresOnDeviceRecognition = true` (с фолбэком на серверное распознавание Apple, если on-device для устройства недоступен). |
| Хранилище аудио на бэке | Railway Volume mount, путь `/data/comments/<uuid>.m4a`. ENV `COMMENTS_AUDIO_DIR`. |
| Лимиты записи | Макс длительность 60 с, макс размер файла 2 МБ. Валидируется и на iOS, и на сервере. |
| Модерация | На этой фазе — нет. Только владелец может удалить свой комментарий. |
| Маркеры тайм-кодов на скрабере | Точечные маркеры в `PlayerView` (mini- и full-screen), tap = seek + play comment. |

## UX-сценарий

1. Юзер слушает эпизод. На lock screen — Live Activity «Сейчас играет: <название>», в правой части — круглая кнопка микрофона.
2. Тап по микрофону → Live Activity переходит в состояние "armed" (микрофон заполнен цветом, иконка пульсирует), запускается `RecordCommentIntent`.
3. Пользователь начинает говорить. RMS-метеринг улавливает речь → подкаст плавно за 0.4 с уходит в паузу, рамка Live Activity мигает «● REC» и растёт длительность записи.
4. Пользователь замолк. Через 1.5 с тишины подкаст плавно возвращается за 0.4 с. Live Activity показывает "soft cutoff: 3, 2, 1…".
5. Если за эти 3 с пользователь снова заговорил — обратно в шаг 3. Если нет — запись финализируется: на iOS запускается локальная расшифровка (`SFSpeechRecognizer`), параллельно файл аплоадится на бэк. Live Activity показывает «Отправляю...».
6. Когда и аплоад, и расшифровка завершились — POST с `audio_path` (от ответа upload) + `transcript` + `timecode_sec`. Live Activity показывает «Готово ✓» 1.5 с и возвращается в обычное состояние.
7. Кто-либо открывает `EpisodeDetailView` → видит секцию «Реплики слушателей» с комментарием: птица-аватар (моноцвет от хэша имени), тайм-код, текст транскрипта, кнопка ▷ для прослушивания.
8. На скрабере в `PlayerView` — точка-маркер на позиции тайм-кода. Тап по маркеру → seek + проигрывание комментария (подкаст пауза → comment audio → возврат к подкасту в той же точке).

## Идентичность: птицы

**Где живёт.** Бэкенд, `api/src/birdNames.ts` — массив `BIRDS: string[]` из ≈1000+ русских названий птиц (включая мировых, не только российских). Источник для составления списка — публичные русскоязычные орнитологические справочники; список фиксируется в коде.

**Алгоритм выбора имени:**
1. На `POST /v1/episodes/:id/comments` бэк проверяет, есть ли запись в `users` для данного `adapty_profile_id`.
2. Если нет — создаём:
   - `idx = sha256(adapty_profile_id) mod len(BIRDS)`
   - кандидат = `BIRDS[idx]`
   - пытаемся `INSERT users(...) VALUES (..., display_name = candidate)`. На UNIQUE-конфликт — `candidate-2`, `candidate-3`, … до победы.
3. Имя стабильно навсегда для этого `adapty_profile_id` (даже если юзер потерял подписку и купил снова — `profile_id` от Adapty переживает переустановку через App Store receipt, см. фазу 2.3).

**Никаких аватаров-картинок.** Аватар = круг, залитый детерминированным цветом (HSL от хэша имени), внутри — первая буква имени.

## Бэкенд

### Схема (Prisma)

```prisma
model User {
  adaptyProfileId String   @id @map("adapty_profile_id")
  displayName     String   @unique @map("display_name")
  createdAt       DateTime @default(now()) @map("created_at")

  comments Comment[]

  @@map("users")
}

model Comment {
  id                    String   @id @default(uuid()) @db.Uuid
  episodeId             String   @map("episode_id")
  episode               Episode  @relation(fields: [episodeId], references: [id], onDelete: Cascade)
  authorAdaptyProfileId String   @map("author_adapty_profile_id")
  author                User     @relation(fields: [authorAdaptyProfileId], references: [adaptyProfileId], onDelete: Cascade)
  audioPath             String   @map("audio_path")
  audioDurationSec      Int      @map("audio_duration_sec")
  transcript            String
  timecodeSec           Int      @map("timecode_sec")
  createdAt             DateTime @default(now()) @map("created_at")

  @@index([episodeId, timecodeSec])
  @@map("comments")
}
```

В существующей модели `Episode` нужно добавить обратную связь: `comments Comment[]`.

### Эндпоинты

```
GET /v1/episodes/:episodeId/comments
  auth: не требуется
  → 200 {
      items: [{
        id, author: {birdName}, transcript,
        timecodeSec, durationSec, audioUrl, createdAt
      }]
    }
  порядок: ASC по timecode_sec, при равенстве — ASC по created_at
  без пагинации на v1 (если эпизод соберёт >200 комментариев — в следующей фазе)

POST /v1/episodes/:episodeId/comments
  headers: X-Adapty-Profile-Id (обязателен)
  Content-Type: multipart/form-data
  body: audio (file, m4a/AAC), transcript (string), timecodeSec (int), durationSec (int)
  middleware: resolveViewer + requirePremium (новый)
  валидация:
    - durationSec ≤ 60
    - file size ≤ 2 МБ
    - audio mime ∈ {audio/mp4, audio/aac, audio/x-m4a}
    - transcript длина ≤ 4000 символов
    - timecodeSec ≥ 0
  ленивое создание users-записи, выбор bird name
  сохранение файла на Volume + insert
  → 201 {id, author: {birdName}, transcript, timecodeSec, durationSec, audioUrl, createdAt}
  ошибки:
    402 {error: "premium_required"}
    413 {error: "payload_too_large"}
    400 {error: "invalid_audio" | "invalid_duration" | ...}

DELETE /v1/comments/:id
  headers: X-Adapty-Profile-Id
  требует: comment.author_adapty_profile_id == X-Adapty-Profile-Id
  удаляет файл с Volume + строку из БД
  → 204
  ошибки: 404, 403

GET /v1/comments/:id/audio
  auth: не требуется
  стриминг файла с диска, Content-Type: audio/mp4
  Cache-Control: public, max-age=31536000, immutable
  ETag: <id> (комментарии immutable, файл по id никогда не меняется)
```

### Хранилище

Railway Volume mount по пути `/data` (создаётся в Railway UI у API-сервиса). Файлы — `/data/comments/<uuid>.m4a`. Перед записью — `mkdir -p` на `/data/comments`.

В `.env.example` и Railway Variables — `COMMENTS_AUDIO_DIR=/data/comments`.

Лимит мультипарта — `multer` с `limits: { fileSize: 2 * 1024 * 1024 }`.

### Middleware `requirePremium`

Новый middleware в `api/src/middleware/`. Использует уже существующий `resolveViewer` (он добавляет `req.viewer = { adaptyProfileId, isPremium }`). Если `!req.viewer?.isPremium` — отдаёт 402 `{error: "premium_required"}`.

## iOS — сервисы и state machine

### Новый сервис `VoiceCommentRecorder`

`@MainActor @Observable`. Composition root — `LiboLiboApp.swift`. Зависимости (через init): `PlayerService`, `APIClient`, `AdaptyService`.

```swift
enum RecordingState {
    case idle
    case armed                  // тап mic, ждём первую речь
    case recording              // активная фаза, подкаст на паузе
    case softCutoff(remaining: TimeInterval) // 3 с grace
    case finalizing             // upload + transcribe
    case done(commentId: String)
    case failed(Error)
}

@Observable @MainActor
final class VoiceCommentRecorder {
    private(set) var state: RecordingState = .idle
    private(set) var elapsed: TimeInterval = 0          // суммарная активная длительность
    private(set) var currentLevel: Float = 0            // dBFS, для UI-индикатора

    func toggle() async         // главная точка входа из App Intent / UI
    func cancel() async         // user отказался (закрыл sheet)
}
```

**Конечный автомат:**

```
idle ──tap──> armed
armed ──speech detected──> recording (PlayerService.fadePause())
recording ──silence ≥ 1.5s──> softCutoff(3.0) (PlayerService.fadeResume())
softCutoff ──speech detected──> recording (fadePause again, добавляем к тому же файлу)
softCutoff ──timer expires──> finalizing
finalizing ──upload + transcribe ok──> done
finalizing ──error──> failed
recording ──tap (manual stop)──> finalizing  // ручной стоп тоже работает
recording ──elapsed > 60s──> finalizing      // hard cap
```

### VAD (детектор речи)

Через `AVAudioRecorder` с `isMeteringEnabled = true`. Каждые 80 мс читаем `averagePower(forChannel: 0)`:

- **speech_threshold** = `-40` dBFS
- **silence_threshold** = `-50` dBFS (гистерезис)
- **min_speech_duration** = `150 мс` (отсекаем щелчки)
- **silence_to_softcutoff** = `1.5 с`
- **softcutoff_grace** = `3.0 с`

Числа закладываются как `static let` константы — настраиваются по живым тестам.

### Ducking подкаста

В `PlayerService` добавляем:

```swift
func fadePause(duration: TimeInterval = 0.4) async    // плавно volume → 0, потом pause
func fadeResume(duration: TimeInterval = 0.4) async   // resume + плавно volume → previous
```

Реализация — `Task` с шагами по 50 мс, изменяющий `player.volume` (поле `volume` уже есть в `PlayerService`, см. `PlayerService.swift:33`). После fade-out — `player.pause()`. На fadeResume — `player.play()` + ramp обратно.

### Аудио-сессия

Сейчас сессия `.playback` (см. `PlayerService.configureAudioSession`). При переходе в recording режим:

1. Деактивировать сессию.
2. Установить `.playAndRecord`, mode `.spokenAudio`, options `[.allowBluetooth, .defaultToSpeaker, .duckOthers]`.
3. Активировать.

После финализации — обратно в `.playback`. Логику инкапсулируем в новый утилитарный класс `AudioSessionCoordinator`.

### Транскрипция

`SFSpeechRecognizer` с `locale: Locale(identifier: "ru-RU")`, `SFSpeechURLRecognitionRequest(url: <m4a file>)`, `requiresOnDeviceRecognition = true` если `recognizer.supportsOnDeviceRecognition` — иначе fallback на серверный recogn (Apple, бесплатно). Запускается параллельно с upload — оба ждутся через `async let`.

Если транскрипция упала или вернула пустую строку — отправляем POST с `transcript = ""`. UI на сервере покажет «(без расшифровки)» и кнопку повтора в локальном состоянии.

### `CommentsRepository`

```swift
@Observable @MainActor
final class CommentsRepository {
    private(set) var byEpisodeId: [String: [EpisodeComment]] = [:]

    func loadComments(for episodeId: String) async
    func postComment(episodeId: String, audioFileURL: URL, transcript: String, timecodeSec: Int, durationSec: Int) async throws -> EpisodeComment
    func deleteComment(_ comment: EpisodeComment) async throws
}
```

Кэш в памяти; на старте `EpisodeDetailView` — `loadComments`. Без локального оффлайн-кэша на v1.

## iOS — Live Activity и App Intent

### Новый widget extension target `LiboLiboLiveActivity`

Содержит:

- `LiboLiboPlaybackAttributes: ActivityAttributes` — статические поля (`episodeTitle`, `podcastName`, `episodeId`, `artworkUrlString`).
- `LiboLiboPlaybackAttributes.ContentState` — динамика (`isPlaying`, `recordingState: RecordingState`, `recordingElapsed`, `currentTimecodeSec`, `softCutoffRemaining`).
- `LiboLiboLiveActivity: Widget` — три представления:
  - **Lock screen / banner** — обложка слева, заголовок и подкаст по центру, **кнопка микрофона справа** (с App Intent `RecordCommentIntent`). В состоянии `recording` — кнопка пульсирует красным, под ней «●  REC 0:14». В `softCutoff` — «жду продолжения 3…»
  - **Dynamic Island compact** — справа лого подкаста, слева мик-иконка (статичная). При записи — пульсирующая красная точка.
  - **Dynamic Island expanded** — расширенная версия lock-screen-варианта.

### `RecordCommentIntent: AppIntent`

```swift
struct RecordCommentIntent: AppIntent {
    static var title: LocalizedStringResource = "Записать комментарий"
    static var openAppWhenRun = false   // важно — не открываем приложение

    func perform() async throws -> some IntentResult {
        await VoiceCommentRecorder.shared.toggle()
        return .result()
    }
}
```

App Intent, привязанный к кнопке в Live Activity (iOS 17+), исполняется системой **в процессе основного приложения** — даже если приложение в background или suspended, система оживляет его в фоновом режиме на время выполнения интента. Поэтому `VoiceCommentRecorder.shared` живёт в основном таргете и доступен из intent'а напрямую. App Group нужен только для shared `UserDefaults` (например, статус premium из `AdaptyService` для рендера UI Live Activity, который выполняется уже в процессе widget extension).

### Жизненный цикл активности

- `PlayerService.play(...)` после успешного запуска — стартует `Activity.request(...)` (через новый `LiveActivityService`).
- `PlayerService.pause()` / окончание эпизода / `replaceCurrentItem` — обновляет `ContentState` (или ends activity при stop).
- Таймер обновления `ContentState` — раз в секунду на изменение `currentTimecodeSec`, и реактивно при смене `RecordingState`.

## iOS — UI в приложении

### Изменения в `PlayerView`

- В нижнем ряду controls — **кнопка микрофона** рядом со скоростью / таймером сна. Видна только если `adaptyService.isPremium == true`. Тап = `voiceCommentRecorder.toggle()`.
- При `state ∈ {recording, softCutoff}` — поверх playback bar появляется тонкая красная полоска и текст «● REC 0:14» / «жду 3 с».
- На скрабере — точечные маркеры на позициях тайм-кодов комментариев (берутся из `commentsRepository.byEpisodeId[currentEpisode.id]`). Тап по маркеру → seek + воспроизведение комментария.

### Изменения в `EpisodeDetailView`

Новый раздел внизу под `description`:

```
┌─ Реплики слушателей (12) ─────────────┐
│ [○] Сорока       12:34   ▷           │
│     "А вот тут он ошибся..."          │
│                                        │
│ [○] Дятел-2      18:02   ▷           │
│     "Согласен, добавлю что..."        │
└────────────────────────────────────────┘
```

- Аватар: круг с детерминированным цветом + первая буква имени.
- Тайм-код кликабелен — открывает плеер на этой позиции и проигрывает комментарий.
- Кнопка ▷ — играет только аудио, без перехода в плеер.
- Если комментарий — твой, в правом краю появляется кнопка «···» с действием «Удалить».
- Сортировка ASC по `timecode_sec`.
- Если комментариев нет — секция не рисуется (никакой пустой плашки).

### Воспроизведение комментария

Через новый метод `PlayerService.playComment(_ comment: EpisodeComment)`:

1. Запоминаем `currentEpisode`, `currentTime`, `isPlaying`.
2. `fadePause()`.
3. Создаём отдельный `AVPlayer` для comment audio (или временно `replaceCurrentItem`, если простой путь подходит).
4. По окончании — обратно к подкасту в той же позиции, `fadeResume()`.

(Реализация выберется в имплементации — но контракт API стабилен.)

### Запись внутри приложения

Для пользователей, которые жмут микрофон на in-app кнопке (а не на lock screen), нужно показать **bottom sheet** с:

- Большой пульсирующий микрофон-индикатор (RMS-уровень в реальном времени).
- Текущий тайм-код и длительность записи.
- Кнопка «Стоп» (ручной cutoff).
- Кнопка «Отменить» (`recorder.cancel()`).

После финализации шит автоматически закрывается, в `EpisodeDetailView` появляется новый комментарий.

## Permissions

В `Info.plist` (а точнее в Build Settings, поскольку Info.plist в проекте генерируется):

- `NSMicrophoneUsageDescription` = "Чтобы записать ваш голос-комментарий к эпизоду."
- `NSSpeechRecognitionUsageDescription` = "Чтобы расшифровать ваш голос-комментарий в текст."

Запрос разрешений — лениво, при первом тапе по mic-кнопке (in-app или Live Activity). Если отказ — показываем алерт с кнопкой «Открыть настройки».

В `Capabilities` основного таргета:

- App Groups (для общего state между app target и widget extension).
- Background Modes: уже включён `audio` — этого достаточно для продолжения записи когда приложение в background.

Live Activity не требует отдельного capability, но в `Info.plist` нужен `NSSupportsLiveActivities = YES`.

## Edge cases

| Кейс | Поведение |
|---|---|
| Звонок во время записи | `AVAudioSession` interruption → `recorder.cancel()`. Запись отбрасывается, подкаст ставится на паузу системой (как обычно). |
| AirPods отключились во время записи | Перенаправляется на встроенный микрофон iPhone, запись продолжается. |
| Юзер заблокировал устройство во время записи | Запись продолжается (фоновая аудиосессия). Live Activity показывает прогресс. |
| Пропала сеть на момент upload | До 3 ретраев с экспоненциальным бэкоффом. Если все провалились — комментарий держим в `Documents/pending_comments/<uuid>/` (audio + json metadata) и пытаемся переотправить при следующем cold start. |
| Юзер свернул приложение во время финализации | Upload идёт через `URLSession` с `backgroundSessionConfiguration` (продолжается после suspend). Транскрипция — внутри `UIApplication.beginBackgroundTask(...)` блока (≈30 с гарантированного фонового времени, обычно хватает на ≤60 с записи). Если транскрипция не успела — `transcript = ""`, можно перезапустить позже. |
| Премиум истёк прямо во время записи | Recording завершается локально, попытка POST даст 402 → комментарий сохраняется в pending и выкладывается снова при возобновлении подписки (`refreshEntitlement` success → проверяем pending). |
| Юзер удалил приложение и поставил снова | `adapty_profile_id` восстанавливается через App Store receipt → у юзера то же имя птицы. Локальные pending-комментарии теряются. |
| Эпизод удалён, а комментарии есть | Cascade delete — `Comment.episode` с `onDelete: Cascade`. Файлы тоже надо удалить — чистится воркером (фоновый job, отдельная сессия). На v1 — не удаляем файлы, оставляем мусор; ставим issue. |
| Пустой transcript (распознавание не справилось) | POST с `transcript = ""`. UI показывает «(без расшифровки)» вместо текста. |
| Очень длинный transcript | Обрезается на iOS до 4000 символов перед отправкой; сервер тоже валидирует. |
| Симулятор без поддержки on-device recognition | Fallback на server-side (Apple) — работает в симуляторе с интернетом. |

## Безопасность

- Никаких секретов в публичном репо: `COMMENTS_AUDIO_DIR` — это путь, не секрет; ключей не добавляется.
- `requirePremium` middleware гейтит запись — без активного entitlement POST вернёт 402.
- Аудиофайлы публично читаемы — это **дизайн-решение** (комментарии публичные). Если в будущем нужно ограничить чтение премиумом — добавляется resolveViewer на `GET /v1/comments/:id/audio`.
- Rate-limit на `POST /v1/episodes/:id/comments`: не более 10 комментариев в минуту с одного `adapty_profile_id` (через `express-rate-limit`).
- Валидация audio mime на сервере — кастомный middleware смотрит первые байты файла на m4a magic-numbers (не доверяя `Content-Type` от клиента).
- Размер ответа `GET /v1/episodes/:id/comments` ограничивается лимитом строк (1000 — больше пока невозможно по rate-limit'у).

## Шаги имплементации

Делятся на бэк и iOS, бэк сначала.

### Бэкенд

1. Добавить модели `User`, `Comment` в `prisma/schema.prisma`. Связь `Episode.comments`. `prisma migrate dev`, `prisma generate`.
2. Создать `api/src/birdNames.ts` с pool ≈1000+ русских названий птиц. Утилита `pickBirdName(profileId): { name, suffixUsed }`.
3. Middleware `requirePremium.ts`. Тесты на 402.
4. Volume-helper: `audioStorage.ts` — `saveCommentAudio(buffer): Promise<{path, size}>`, `deleteCommentAudio(path): Promise<void>`, `streamCommentAudio(path, res)`. `mkdir -p` при инициализации.
5. Эндпоинт `GET /v1/episodes/:id/comments` + тесты (vitest, supertest).
6. Эндпоинт `POST /v1/episodes/:id/comments` (multer), валидация, ленивое создание `User`, `INSERT comment`, ответ. Тесты на: 402, 413, валидный happy path, дубль для того же `profile_id` (проверяет, что bird name стабилен).
7. Эндпоинт `DELETE /v1/comments/:id`. Тесты на 403/404/204.
8. Эндпоинт `GET /v1/comments/:id/audio`. Стрим, ETag, кэш-хедеры.
9. Rate-limit на POST (10/мин/profile_id).
10. В Railway UI добавить Volume mount на `/data` к API-сервису. Задеплоить.
11. Проверить продовый эндпоинт через curl с реальным премиум-`X-Adapty-Profile-Id`.
12. Обновить `docs/specs/api/openapi.yaml`.

### iOS

13. Добавить таргет `LiboLiboLiveActivity` (Widget Extension). Настроить App Group.
14. `LiboLiboPlaybackAttributes` (общая модель в App Group).
15. `LiveActivityService` — старт/обновление/остановка активности, привязка к `PlayerService`.
16. Расширить `PlayerService`: `fadePause()`, `fadeResume()`, `playComment(_)`, `seekToCommentTimecode(_)`. Тесты вручную.
17. `AudioSessionCoordinator` — переключение `.playback ↔ .playAndRecord`.
18. `VoiceCommentRecorder` — state machine, AVAudioRecorder, RMS-метеринг, VAD, хендлеры interruption.
19. Модель `EpisodeComment` + декодер из API. Расширение `APIClient`: `getEpisodeComments(_)`, `postEpisodeComment(_)`, `deleteComment(_)`. Поддержка multipart в APIClient.
20. `CommentsRepository` (Observable, кэш в памяти).
21. Транскрипция: утилитарный класс `LocalSpeechTranscriber` поверх `SFSpeechRecognizer`. Permissions handling.
22. `RecordCommentIntent: AppIntent`.
23. UI Live Activity (lock screen + DI compact + DI expanded).
24. UI: `EpisodeDetailView` секция комментариев — `CommentRow`, аватар-плейсхолдер, мини-плеер.
25. UI: маркеры в `PlayerView` на скрабере.
26. UI: in-app мик-кнопка в `PlayerView` + bottom sheet recording overlay.
27. Pending queue для офлайн-постов: `PendingCommentsService` + retry на cold start.
28. `Info.plist`: `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `NSSupportsLiveActivities = YES`.
29. Сборка, sandbox-тестер с активной премиум-подпиской, ручной end-to-end: запись с lock screen → upload → транскрипция → видно в `EpisodeDetailView` + маркер на скрабере + воспроизведение.
30. Build, install in simulator, commit, push (по ритуалу `CLAUDE.md`).
