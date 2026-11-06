import AVFoundation
import Combine
import MediaPlayer
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

enum Channel: String, CaseIterable, Identifiable {
    case onAir, e24

    var id: String { rawValue }
    var title: String { self == .onAir ? "On Air" : "Eclectic 24" }

    /// Playlist file KCRW publishes; points at the current live stream.
    var plsURL: URL {
        URL(string: self == .onAir
            ? "https://media.kcrw.com/pls/kcrwsimulcast.pls"
            : "https://media.kcrw.com/pls/kcrwmusic.pls")!
    }

    /// Direct stream known to work. Used if the playlist can't be read or its stream fails.
    var fallbackURL: URL {
        URL(string: self == .onAir
            ? "https://streams.kcrw.com/kcrw_aac"
            : "https://streams.kcrw.com/e24_aac")!
    }
}

final class RadioPlayer: ObservableObject {
    @Published var current: Channel?
    @Published var status = ""
    /// 0...1 app gain on the stream, defaults to full. Only the macOS fader changes it.
    @Published var volume: Double = 1.0 {
        didSet { player.volume = Float(volume) }
    }

    /// Exposed so the macOS AirPlay picker can route this player's output.
    let player = AVPlayer()
    private let artwork = RadioPlayer.makeArtwork()
    private var itemObservers = Set<AnyCancellable>()    // cleared on every stop()
    private var playerObservers = Set<AnyCancellable>()  // lives for the player's lifetime
    private var task: Task<Void, Never>?
    private var lastChannel: Channel?         // what a lock-screen / remote Play resumes
    private var interruptedChannel: Channel?  // what to resume after a call / Siri interruption

    init() {
        #if os(iOS) || os(tvOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback)

        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.handleInterruption(note) }
            .store(in: &playerObservers)

        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.handleRouteChange(note) }
            .store(in: &playerObservers)
        #endif

        // Status follows the player, so stalls and recoveries are reflected.
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self, self.current != nil else { return }
                switch state {
                case .playing: self.status = "Live"
                case .waitingToPlayAtSpecifiedRate: self.status = "Buffering"
                default: break
                }
            }
            .store(in: &playerObservers)

        // Remote command handlers may run off the main thread; hop before touching state.
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.togglePlayPauseCommand.isEnabled = true

        commands.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.pauseKeepingNowPlaying() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.current != nil { self.pauseKeepingNowPlaying() } else { self.resume() }
            }
            return .success
        }
    }

    func toggle(_ channel: Channel) {
        current == channel ? stop() : play(channel)
    }

    /// Stops playback. With `keepNowPlaying`, the Now Playing item stays (rate 0, paused) so the
    /// lock screen / remote can resume; otherwise it is cleared.
    func stop(keepNowPlaying: Bool = false) {
        task?.cancel()
        itemObservers.removeAll()
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = nil
        status = ""
        let center = MPNowPlayingInfoCenter.default()
        if keepNowPlaying, var info = center.nowPlayingInfo {
            info[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
            center.nowPlayingInfo = info
            center.playbackState = .paused
        } else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
        }
    }

    private func pauseKeepingNowPlaying() {
        guard current != nil else { return }
        stop(keepNowPlaying: true)
    }

    private func resume() {
        play(lastChannel ?? .onAir)
    }

    #if os(iOS) || os(tvOS)
    /// Phone call, Siri, another app taking the session. Live streams reconnect rather than resume.
    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            interruptedChannel = current
            pauseKeepingNowPlaying()
        case .ended:
            let optionRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionRaw).contains(.shouldResume)
            if shouldResume, let channel = interruptedChannel { play(channel) }
            interruptedChannel = nil
        @unknown default:
            break
        }
    }

    /// Headphones unplugged / AirPlay speaker gone: pause instead of blasting the built-in speaker.
    private func handleRouteChange(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
              reason == .oldDeviceUnavailable else { return }
        pauseKeepingNowPlaying()
    }
    #endif

    private func play(_ channel: Channel) {
        stop()
        lastChannel = channel
        current = channel
        status = "Connecting"
        #if os(iOS) || os(tvOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        let center = MPNowPlayingInfoCenter.default()
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: "KCRW \(channel.title)",
            MPMediaItemPropertyArtist: "KCRW 89.9 FM",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0
        ]
        center.nowPlayingInfo = info
        center.playbackState = .playing

        task = Task { [weak self] in
            let url = await Self.resolve(channel)
            await MainActor.run {
                // Checked after the hop, so a stale task can't start a stream.
                guard let self, !Task.isCancelled else { return }
                let fallback: URL? = (url == channel.fallbackURL) ? nil : channel.fallbackURL
                self.start(url, fallback: fallback, channel: channel)
            }
        }
    }

    /// Artwork for Control Center, the lock screen and the macOS Now Playing menu.
    /// Loads the "NowPlayingArt" image from the asset catalog; nil (no artwork) if it's missing.
    /// `nonisolated` matters: the system calls the image handler on a background queue, and a
    /// main-actor-isolated closure there crashes in projects that default to main-actor isolation.
    nonisolated private static func makeArtwork() -> MPMediaItemArtwork? {
        #if canImport(UIKit)
        guard let image = UIImage(named: "NowPlayingArt") else { return nil }
        #else
        guard let image = NSImage(named: "NowPlayingArt") else { return nil }
        #endif
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    /// Reads the first File1= entry of the .pls; falls back to the known direct stream.
    private static func resolve(_ channel: Channel) async -> URL {
        do {
            let (data, _) = try await URLSession.shared.data(from: channel.plsURL)
            let text = String(decoding: data, as: UTF8.self)
            for line in text.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.lowercased().hasPrefix("file1="),
                   let url = URL(string: String(trimmed.dropFirst(6))),
                   url.scheme == "https" {
                    return url
                }
            }
        } catch {}
        return channel.fallbackURL
    }

    private func start(_ url: URL, fallback: URL?, channel: Channel) {
        guard current == channel else { return }
        itemObservers.removeAll()
        let item = AVPlayerItem(url: url)
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] itemStatus in
                guard let self, self.current == channel else { return }
                if itemStatus == .failed {
                    if let fallback {
                        self.start(fallback, fallback: nil, channel: channel)
                    } else {
                        self.stop()
                        self.status = "Could not play \(channel.title)"
                    }
                }
            }
            .store(in: &itemObservers)
        player.replaceCurrentItem(with: item)
        player.play()
    }
}
