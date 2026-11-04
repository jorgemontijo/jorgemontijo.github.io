import AVFoundation
import Combine
import MediaPlayer
#if canImport(UIKit)
import UIKit
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

@MainActor
final class RadioPlayer: ObservableObject {
    @Published var current: Channel?
    @Published var status = ""

    private let player = AVPlayer()
    private var sessionObservers = Set<AnyCancellable>()  // lives for the object's lifetime
    private var itemObservers = Set<AnyCancellable>()     // per AVPlayerItem
    private var task: Task<Void, Never>?
    private var isConfigured = false

    init() {}  // intentionally empty

    // MARK: - One-time setup (runs on first play, not during view construction)

    private func configureOnce() {
        guard !isConfigured else { return }
        isConfigured = true

        #if os(iOS) || os(tvOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback)

        NotificationCenter.default
            .publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                MainActor.assumeIsolated { self?.handleInterruption(note) }
            }
            .store(in: &sessionObservers)
        #endif

        let commands = MPRemoteCommandCenter.shared()
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
    }

    // MARK: - Interruptions

    #if os(iOS) || os(tvOS)
    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw),
              let channel = current else { return }

        switch type {
        case .began:
            status = "Interrupted"
        case .ended:
            let optRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if AVAudioSession.InterruptionOptions(rawValue: optRaw).contains(.shouldResume) {
                Task { await play(channel) }
            } else {
                stop() // system says don't resume; don't leave stale "playing" state
            }
        @unknown default:
            break
        }
    }
    #endif

    // MARK: - Public controls

    func toggle(_ channel: Channel) async {
        if current == channel {
            stop()
        } else {
            await play(channel)
        }
    }

    func stop() {
        task?.cancel()
        itemObservers.removeAll()
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = nil
        status = ""
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Playback

    private func play(_ channel: Channel) async {
        configureOnce()
        stop()
        current = channel
        status = "Connecting"

        #if os(iOS) || os(tvOS)
        if #available(iOS 27.0, *) {
            do {
                _ = try await AVAudioSession.sharedInstance().activate(options: [])
            } catch {
                print("Audio session activation failed: \(error)")
            }
        } else {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("Audio session activation failed: \(error)")
            }
        }
        // User may have toggled to another channel or stopped while activating.
        guard current == channel else { return }
        #endif

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: "KCRW \(channel.title)",
            MPMediaItemPropertyArtist: "KCRW 89.9 FM",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0
        ]
        #if canImport(UIKit)
        // Lock screen / Control Center artwork: image named "art" in Assets.xcassets.
        if let image = UIImage(named: "art") {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        #endif
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        task = Task {
            let url = await resolve(channel)
            guard !Task.isCancelled else { return }
            let fallback: URL? = (url == channel.fallbackURL) ? nil : channel.fallbackURL
            self.start(url, fallback: fallback, channel: channel)
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
        itemObservers.removeAll()
        let item = AVPlayerItem(url: url)
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] itemStatus in
                MainActor.assumeIsolated {
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
            }
            .store(in: &itemObservers)
        player.replaceCurrentItem(with: item)
        player.play()
    }
}
