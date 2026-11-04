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

    private let player = AVPlayer()
    private var observers = Set<AnyCancellable>()
    private var task: Task<Void, Never>?

    init() {
        #if os(iOS) || os(tvOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        #endif
        let commands = MPRemoteCommandCenter.shared()
        commands.pauseCommand.addTarget { [weak self] _ in
            self?.stop()
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.current != nil else { return .commandFailed }
            self.stop()
            return .success
        }
    }

    func toggle(_ channel: Channel) {
        current == channel ? stop() : play(channel)
    }

    func stop() {
        task?.cancel()
        observers.removeAll()
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = nil
        status = ""
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func play(_ channel: Channel) {
        stop()
        current = channel
        status = "Connecting"
        #if os(iOS) || os(tvOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "KCRW \(channel.title)",
            MPNowPlayingInfoPropertyIsLiveStream: true
        ]
        task = Task {
            let url = await resolve(channel)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                let fallback: URL? = (url == channel.fallbackURL) ? nil : channel.fallbackURL
                self.start(url, fallback: fallback, channel: channel)
            }
        }
    }

    /// Reads the first File1= entry of the .pls; falls back to the known direct stream.
    private func resolve(_ channel: Channel) async -> URL {
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
        observers.removeAll()
        let item = AVPlayerItem(url: url)
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] itemStatus in
                guard let self, self.current == channel else { return }
                switch itemStatus {
                case .readyToPlay:
                    self.status = "Live"
                case .failed:
                    if let fallback {
                        self.start(fallback, fallback: nil, channel: channel)
                    } else {
                        self.stop()
                        self.status = "Could not play \(channel.title)"
                    }
                default:
                    break
                }
            }
            .store(in: &observers)
        player.replaceCurrentItem(with: item)
        player.play()
    }
}
