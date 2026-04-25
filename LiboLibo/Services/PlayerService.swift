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

    var rate: Float = 1.0 {
        didSet {
            if isPlaying {
                player.rate = rate
            }
            updateNowPlayingInfo()
        }
    }

    /// Колбэк, который вызывается при старте нового эпизода.
    /// Используется HistoryService, чтобы записать факт прослушивания.
    var onPlay: ((Episode) -> Void)?

    static let speedOptions: [Float] = [0.8, 1.0, 1.25, 1.5, 2.0]

    private let player = AVPlayer()
    private var timeObserver: Any?

    init() {
        configureAudioSession()
        setupTimeObserver()
        setupRemoteCommands()
    }

    // MARK: - Public API

    func play(_ episode: Episode) {
        if currentEpisode?.id == episode.id {
            resume()
            return
        }
        currentEpisode = episode
        currentTime = 0
        duration = 0
        let item = AVPlayerItem(url: episode.audioUrl)
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

    func seek(to time: TimeInterval) {
        let cm = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cm)
        currentTime = time
        updateNowPlayingInfo()
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
