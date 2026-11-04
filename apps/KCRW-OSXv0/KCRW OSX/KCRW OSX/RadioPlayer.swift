import AVFoundation
import Combine
import MediaPlayer

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
    /// 0...1, defaults to full volume. Applies to whichever stream is playing.
    @Published var volume: Double = 1.0 {
        didSet { player.volume = Float(volume) }
    }

    private let player = AVPlayer()
    private var itemObservers = Set<AnyCancellable>()    // cleared on every stop()
    private var playerObservers = Set<AnyCancellable>()  // lives for the player's lifetime
    private var task: Task<Void, Never>?

    init() {
        #if os(iOS) || os(tvOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
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
        commands.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.stop() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.current != nil else { return .commandFailed }
            DispatchQueue.main.async { self.stop() }
            return .success
        }
    }

    func toggle(_ channel: Channel) {
        current == channel ? stop() : play(channel)
    }

    func stop() {
        task?.cancel()
        itemObservers.removeAll()
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = nil
        status = ""
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
    }

    private func play(_ channel: Channel) {
        stop()
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
