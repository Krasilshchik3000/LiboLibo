import Foundation
import AVFoundation
import MediaPlayer
import Observation

/// Состояние воспроизведения и контролы.
/// Один экземпляр на всё приложение, инъектируется в SwiftUI environment.
@MainActor
@Observable
final class PlayerService {
    private(set) var currentEpisode: Episode?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    /// Все эпизоды текущего подкаста, отсортированные от старых к новым.
    /// Используется для навигации по выпускам (вперёд/назад) и отображения очереди.
    private(set) var feedContext: [Episode] = []

    var rate: Float = 1.0 {
        didSet {
            if isPlaying {
                player.rate = rate
            }
            updateNowPlayingInfo()
        }
    }

    /// Громкость воспроизведения внутри приложения (0…1). Применяется поверх
    /// системной громкости — это даёт видимый рабочий регулятор и в симуляторе.
    var volume: Float = 1.0 {
        didSet { player.volume = volume }
    }

    /// Колбэк, который вызывается при старте нового эпизода.
    /// Используется HistoryService, чтобы записать факт прослушивания.
    var onPlay: ((Episode) -> Void)?

    /// Резолвер локального URL для оффлайн-воспроизведения.
    /// Если выпуск скачан — DownloadService возвращает локальный URL и плеер играет с диска.
    var localUrlResolver: ((Episode) -> URL?)?

    static let speedOptions: [Float] = [1.0, 1.25, 1.5, 2.0, 0.8]

    // MARK: - Sleep timer

    enum SleepTimer: CaseIterable, Hashable {
        case off, fifteen, thirty, fortyfive, untilEnd

        var minutes: Int? {
            switch self {
            case .off:       return nil
            case .fifteen:   return 15
            case .thirty:    return 30
            case .fortyfive: return 45
            case .untilEnd:  return nil
            }
        }

        /// Короткая метка для pill-кнопки.
        var pillLabel: String {
            switch self {
            case .off:       return "Сон"
            case .fifteen:   return "15м"
            case .thirty:    return "30м"
            case .fortyfive: return "45м"
            case .untilEnd:  return "Эп."
            }
        }

        /// Полная метка для меню.
        var menuLabel: String {
            switch self {
            case .off:       return "Выключено"
            case .fifteen:   return "15 минут"
            case .thirty:    return "30 минут"
            case .fortyfive: return "45 минут"
            case .untilEnd:  return "До конца выпуска"
            }
        }

        var isActive: Bool { self != .off }
    }

    private(set) var sleepTimer: SleepTimer = .off
    private var sleepTimerTask: Task<Void, Never>?

    private let player = AVPlayer()
    private var timeObserver: Any?

    init() {
        configureAudioSession()
        setupTimeObserver()
        setupRemoteCommands()
        setupEndOfItemObserver()
    }

    // MARK: - Public API

    /// Запускает эпизод. Если передан context — обновляет ленту эпизодов подкаста.
    /// context должен быть отсортирован от старых к новым.
    func play(_ episode: Episode, context: [Episode] = []) {
        if !context.isEmpty {
            feedContext = context
        }
        if currentEpisode?.id == episode.id {
            resume()
            return
        }
        // Премиум-эпизод без активного entitlement: бэкенд отдал `audio_url: null`,
        // играть нечего. Тихо выходим — UI должен сам блокировать «Слушать».
        guard let remoteUrl = episode.audioUrl else { return }

        currentEpisode = episode
        currentTime = 0
        duration = 0
        let url = localUrlResolver?(episode) ?? remoteUrl
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.play()
        player.rate = rate
        isPlaying = true
        updateNowPlayingInfo()
        onPlay?(episode)
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func skip(by seconds: TimeInterval) {
        seek(to: max(0, currentTime + seconds))
    }

    /// Вставляет выпуск сразу после текущего в очередь. Если выпуск уже есть в
    /// очереди — перемещает его на позицию «следующий».
    func playNext(_ episode: Episode) {
        if episode.id != currentEpisode?.id {
            feedContext.removeAll { $0.id == episode.id }
        }
        guard let current = currentEpisode,
              let idx = feedContext.firstIndex(where: { $0.id == current.id }) else {
            feedContext.insert(episode, at: 0)
            return
        }
        feedContext.insert(episode, at: idx + 1)
    }

    /// Удаляет выпуск из очереди. Текущий эпизод удалить нельзя.
    func removeFromQueue(_ episode: Episode) {
        guard episode.id != currentEpisode?.id else { return }
        feedContext.removeAll { $0.id == episode.id }
    }

    /// Переставляет выпуски в секции «Далее» (индексы относительно неё).
    func moveInQueue(fromOffsets: IndexSet, toOffset: Int) {
        guard let current = currentEpisode,
              let idx = feedContext.firstIndex(where: { $0.id == current.id }),
              idx + 1 < feedContext.count else { return }
        var after = Array(feedContext[(idx + 1)...])
        after.move(fromOffsets: fromOffsets, toOffset: toOffset)
        feedContext = Array(feedContext[...idx]) + after
    }

    /// Заменяет секцию «Далее» целиком. Используется при drag-to-reorder.
    func setQueueAfter(_ episodes: [Episode]) {
        guard let current = currentEpisode,
              let idx = feedContext.firstIndex(where: { $0.id == current.id }) else { return }
        feedContext = Array(feedContext[...idx]) + episodes
    }

    func seek(to time: TimeInterval) {
        let cm = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cm)
        currentTime = time
        updateNowPlayingInfo()
    }

    /// Тапом по кнопке скорости — циклически переключаем 1× → 1.25× → 1.5× → 2× → 0.8× → 1×.
    func cycleSpeed() {
        let all = Self.speedOptions
        let idx = all.firstIndex(of: rate) ?? 0
        rate = all[(idx + 1) % all.count]
    }

    /// Цикличное переключение таймера сна (оставлено для совместимости).
    func cycleSleepTimer() {
        let all = SleepTimer.allCases
        let idx = all.firstIndex(of: sleepTimer) ?? 0
        setSleepTimer(all[(idx + 1) % all.count])
    }

    func setSleepTimer(_ option: SleepTimer) {
        sleepTimer = option
        sleepTimerTask?.cancel()
        guard let mins = option.minutes else { return }

        sleepTimerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(mins) * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.pause()
                self?.sleepTimer = .off
            }
        }
    }

    // MARK: - Private

    private func resume() {
        player.play()
        player.rate = rate
        isPlaying = true
        updateNowPlayingInfo()
    }

    private func pause() {
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    private func setupEndOfItemObserver() {
        NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.playNextInContext()
            }
        }
    }

    private func playNextInContext() {
        if sleepTimer == .untilEnd {
            isPlaying = false
            sleepTimer = .off
            return
        }
        guard let current = currentEpisode,
              let idx = feedContext.firstIndex(where: { $0.id == current.id }),
              idx + 1 < feedContext.count else {
            isPlaying = false
            return
        }
        play(feedContext[idx + 1])
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = CMTimeGetSeconds(time)
                if let item = self.player.currentItem {
                    let d = CMTimeGetSeconds(item.duration)
                    if d.isFinite, d > 0 {
                        self.duration = d
                    }
                }
                self.updateNowPlayingInfo()
            }
        }
    }

    private func setupRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()

        cc.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        cc.skipForwardCommand.preferredIntervals = [10]
        cc.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: 10) }
            return .success
        }
        cc.skipBackwardCommand.preferredIntervals = [10]
        cc.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: -10) }
            return .success
        }
        cc.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNextInContext() }
            return .success
        }
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let episode = currentEpisode else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            MPMediaItemPropertyArtist: episode.podcastName,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
        ]
        if duration > 0, duration.isFinite {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

extension PlayerService {
    /// Простой форматтер вида «12:34» / «1:23:45».
    static func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func formatRate(_ rate: Float) -> String {
        if rate == 1.0 { return "1×" }
        if rate.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rate))×"
        }
        return String(format: "%.2g×", rate)
    }
}
