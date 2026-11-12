import SwiftUI
#if os(iOS) || os(macOS)
import AVKit
#endif

private let amber = Color(red: 0.95, green: 0.64, blue: 0.23)
private let signalRed = Color(red: 0.90, green: 0.33, blue: 0.24)
private let lightYellow = Color(red: 1.0, green: 0.91, blue: 0.58)

/// Per-platform sizing. tvOS is viewed from ~10 feet, so fixed sizes scale up.
private enum M {
    #if os(tvOS)
    static let s: CGFloat = 2.2        // general scale
    static let line: CGFloat = 1.5     // hairline width
    static let titleSize: CGFloat = 72
    static let maxWidth: CGFloat = 1100
    #else
    static let s: CGFloat = 1
    static let line: CGFloat = 1
    static let titleSize: CGFloat = 40
    static let maxWidth: CGFloat = 520
    #endif
}

// Dial scale: 88.0–92.0 MHz, with the station at 89.9.
private let dialLow = 88.0
private let dialHigh = 92.0
private let stationFrequency = 89.9
private let dialInset: CGFloat = 14 * M.s

private func dialX(_ frequency: Double, width: CGFloat) -> CGFloat {
    let usable = width - dialInset * 2
    return dialInset + CGFloat((frequency - dialLow) / (dialHigh - dialLow)) * usable
}

struct ContentView: View {
    @StateObject private var radio = RadioPlayer()

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.10).ignoresSafeArea()
            #if os(iOS)
            // Landscape phones are too short for the full stack; fall back to scrolling.
            ViewThatFits(in: .vertical) {
                panel
                ScrollView { panel }
            }
            #else
            panel
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 440)
        #endif
        #if os(iOS)
        .sensoryFeedback(.impact(weight: .light), trigger: radio.current)
        #endif
        .preferredColorScheme(.dark)
    }

    private var panel: some View {
        VStack(spacing: 24 * M.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("89.9 FM")
                    .font(.system(size: M.titleSize, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                #if !os(tvOS)
                AirPlayButton(player: radio.player)
                #endif
            }
            Dial(live: radio.status == .live)
                .accessibilityHidden(true)
            HStack(spacing: 12 * M.s) {
                ForEach(Channel.allCases) { channel in
                    ChannelButton(channel: channel, radio: radio)
                }
            }
            Text(radio.current == nil && radio.status != .idle ? radio.status.text : " ")
                .font(.caption.monospaced())
                .foregroundStyle(signalRed)
        }
        .padding(24 * M.s)
        .frame(maxWidth: M.maxWidth)
    }
}

#if !os(tvOS)

/// Opens the system AirPlay output list. The label is ours; the system picker sits on top of it,
/// stretched over the whole button with its own icon made transparent, so the tap lands on the picker.
struct AirPlayButton: View {
    let player: AVPlayer

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "airplayaudio")
            Text("AirPlay")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.3), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .overlay { RoutePicker(player: player) }
    }
}

private struct RoutePicker {
    let player: AVPlayer
}

#if os(iOS)
extension RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .clear
        view.activeTintColor = .clear
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
#elseif os(macOS)
extension RoutePicker: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.player = player
        view.isRoutePickerButtonBordered = false
        let states: [AVRoutePickerView.ButtonState] = [.normal, .normalHighlighted, .active, .activeHighlighted]
        for state in states { view.setRoutePickerButtonColor(.clear, for: state) }
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {}
}
#endif
#endif

/// No system press/focus effect; focus is drawn by `ChannelLabel` so it looks the same everywhere.
private struct RadioButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct ChannelButton: View {
    let channel: Channel
    @ObservedObject var radio: RadioPlayer

    var body: some View {
        let on = radio.current == channel
        Button { radio.toggle(channel) } label: {
            ChannelLabel(title: channel.title, on: on, status: on ? radio.status.text : " ")
        }
        .buttonStyle(RadioButtonStyle())
        #if !os(tvOS)
        .focusEffectDisabled()
        #endif
        .accessibilityLabel(channel.title)
        .accessibilityValue(on ? radio.status.text : "Off")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private struct ChannelLabel: View {
    let title: String
    let on: Bool
    let status: String
    @Environment(\.isFocused) private var focused

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * M.s) {
            Text(title).font(.headline)
            Text(status).font(.caption.monospaced())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16 * M.s)
        .background(on ? amber : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10 * M.s))
        .overlay(
            RoundedRectangle(cornerRadius: 10 * M.s)
                .stroke(focused ? lightYellow : Color.white.opacity(0.3),
                        lineWidth: focused ? 4 : M.line)
        )
        .foregroundStyle(on ? Color.black : Color.white)
        .scaleEffect(focused ? 1.06 : 1)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

struct Dial: View {
    let live: Bool

    private let labels: [(text: String, frequency: Double)] = [
        ("88", 88), ("89", 89), ("89.9", 89.9), ("91", 91), ("92", 92)
    ]

    var body: some View {
        VStack(spacing: 6 * M.s) {
            GeometryReader { geo in
                ForEach(labels, id: \.text) { label in
                    Text(label.text)
                        .font(.caption2.monospaced())
                        .foregroundStyle(label.frequency == stationFrequency
                                         ? amber
                                         : (live ? lightYellow : Color.gray))
                        .shadow(color: lightYellow.opacity(live && label.frequency != stationFrequency ? 0.6 : 0),
                                radius: 4 * M.s)
                        .position(x: dialX(label.frequency, width: geo.size.width),
                                  y: geo.size.height / 2)
                }
            }
            .frame(height: 14 * M.s)

            ZStack {
                Ticks(color: .gray)
                Ticks(color: lightYellow)
                    .shadow(color: lightYellow.opacity(0.7), radius: 3 * M.s)
                    .opacity(live ? 1 : 0)
                GeometryReader { geo in
                    Rectangle()
                        .fill(signalRed)
                        .frame(width: 2 * M.s, height: geo.size.height)
                        .shadow(color: signalRed, radius: live ? 6 * M.s : 0)
                        .opacity(live ? 1 : 0.35)
                        .animation(.easeInOut(duration: 0.4), value: live)
                        .position(x: dialX(stationFrequency, width: geo.size.width),
                                  y: geo.size.height / 2)
                }
            }
            .frame(height: 44 * M.s)
        }
        .padding(.vertical, 8 * M.s)
        .overlay(alignment: .top) { rail }
        .overlay(alignment: .bottom) { rail }
        .animation(.easeInOut(duration: 0.4), value: live)
    }

    /// The horizontal lines above and below the dial.
    private var rail: some View {
        Rectangle()
            .fill(live ? lightYellow : Color.white.opacity(0.12))
            .frame(height: M.line)
            .shadow(color: lightYellow.opacity(live ? 0.7 : 0), radius: 3 * M.s)
    }
}

struct Ticks: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            // One tick per 0.1 MHz; taller at every 0.5 and 1.0 MHz.
            for index in 0...40 {
                let frequency = dialLow + Double(index) * 0.1
                let x = dialX(frequency, width: size.width)
                let height: CGFloat = (index % 10 == 0 ? 24 : (index % 5 == 0 ? 16 : 9)) * M.s
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x, y: size.height - height))
                context.stroke(path, with: .color(color), lineWidth: M.line)
            }
        }
    }
}

#Preview {
    ContentView()
}
