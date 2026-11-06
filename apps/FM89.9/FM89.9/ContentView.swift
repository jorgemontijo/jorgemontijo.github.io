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

    // Two-line tagline beside the title; one step smaller on phones to leave room for the title.
    #if os(iOS)
    static let tagline = Font.caption2.monospaced()
    #else
    static let tagline = Font.caption.monospaced()
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
                Text("COMMUNITY RADIO • LOS ANGELES")
                    .font(M.tagline)
                    .foregroundStyle(amber)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        #if !os(tvOS)
            HStack(spacing: 12) {
                AirPlayButton(player: radio.player)
                DonateButton()
            }
                .frame(maxWidth: M.maxWidth, alignment: .trailing)
                .padding(8)
            Dial(live: radio.status == "Live")
        #if os(macOS)
            Fader(value: $radio.volume)
        #endif
            HStack(spacing: 12 * M.s) {
                ForEach(Channel.allCases) { channel in
                    ChannelButton(channel: channel, radio: radio)
                }
            }
            #endif
            Text(radio.current == nil ? radio.status : " ")
                .font(.caption.monospaced())
                .foregroundStyle(signalRed)
        }
        .padding(24 * M.s)
        .frame(maxWidth: M.maxWidth)
    }
}

#if !os(tvOS)
private let donateRed = Color(red: 0.95, green: 0.22, blue: 0.20)
private let donateURL = URL(string: "https://join.kcrw.com")!

/// Compact version of the channel-button look, shared by the AirPlay and Donate buttons.
private struct ActionLabel: View {
    let title: String
    var symbol: String? = nil
    let tint: Color
    var fill: Color = Color.white.opacity(0.06)
    var stroke: Color = Color.white.opacity(0.3)

    var body: some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(fill, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(stroke, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Red-tinted so it reads as the one call to action without competing with the amber channel buttons.
struct DonateButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { openURL(donateURL) } label: {
            ActionLabel(title: "❤️ Donate", tint: donateRed,
                        fill: donateRed.opacity(0.14), stroke: donateRed.opacity(0.7))
        }
        .buttonStyle(RadioButtonStyle())
        .focusEffectDisabled()
    }
}

/// Opens the system AirPlay output list. The label is ours; the system picker sits on top of it,
/// stretched over the whole button with its own icon made transparent, so the tap lands on the picker.
struct AirPlayButton: View {
    let player: AVPlayer

    var body: some View {
        ActionLabel(title: "AirPlay", symbol: "airplayaudio", tint: .white)
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
            ChannelLabel(title: channel.title, on: on, status: on ? radio.status : " ")
        }
        .buttonStyle(RadioButtonStyle())
        #if !os(tvOS)
        .focusEffectDisabled()
        #endif
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

#if os(macOS)
/// Horizontal channel fader in the style of a DJ mixer: recessed slot, scale marks, ridged cap.
/// macOS only; iOS and tvOS use the hardware volume controls.
struct Fader: View {
    @Binding var value: Double

    private let capWidth: CGFloat = 30
    private let capHeight: CGFloat = 40
    private let divisions = 20

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("VOLUME").font(.caption2.monospaced())
                Spacer()
                Text("\(Int((value * 100).rounded()))%").font(.caption2.monospaced())
            }
            .foregroundStyle(lightYellow)

            GeometryReader { geo in
                let width = geo.size.width
                let midY = geo.size.height / 2
                let travel = width - capWidth
                let capX = capWidth / 2 + CGFloat(value) * travel

                ZStack {
                    // Scale marks above and below the slot.
                    Canvas { context, size in
                        for i in 0...divisions {
                            let x = capWidth / 2 + CGFloat(i) / CGFloat(divisions) * travel
                            let length: CGFloat = (i % 5 == 0 ? 9 : 5) * M.s
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: length))
                            path.move(to: CGPoint(x: x, y: size.height))
                            path.addLine(to: CGPoint(x: x, y: size.height - length))
                            // Ticks at or below the fader position are lit; the rest are off (gray).
                            let lit = Double(i) / Double(divisions) <= value + 0.0001
                            context.stroke(path, with: .color(lit ? lightYellow : Color.gray), lineWidth: M.line)
                        }
                    }

                    // Recessed slot.
                    Capsule()
                        .fill(Color.black)
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: M.line))
                        .frame(width: travel, height: 6 * M.s)
                        .position(x: width / 2, y: midY)

                    // Lit portion of the slot, from the left end to the cap.
                    Capsule()
                        .fill(lightYellow.opacity(0.55))
                        .frame(width: max(travel * CGFloat(value), 0), height: 2 * M.s)
                        .position(x: capWidth / 2 + travel * CGFloat(value) / 2, y: midY)

                    // Cap: dark body, vertical ridges, bright center line.
                    RoundedRectangle(cornerRadius: 3 * M.s)
                        .fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.12)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 3 * M.s).stroke(Color.white.opacity(0.2), lineWidth: M.line))
                        .overlay {
                            HStack(spacing: 3 * M.s) {
                                ForEach(0..<7, id: \.self) { i in
                                    Rectangle()
                                        .fill(i == 3 ? lightYellow : Color.white.opacity(0.18))
                                        .frame(width: i == 3 ? 2 * M.s : M.line)
                                }
                            }
                            .padding(.vertical, 6 * M.s)
                        }
                        .shadow(color: .black.opacity(0.6), radius: 3 * M.s, y: 2 * M.s)
                        .frame(width: capWidth, height: capHeight)
                        .position(x: capX, y: midY)
                }
                .frame(width: width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { drag in
                        let fraction = (drag.location.x - capWidth / 2) / travel
                        value = min(max(Double(fraction), 0), 1)
                    }
                )
            }
            .frame(height: 48 * M.s)
        }
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 0.05, 1)
            case .decrement: value = max(value - 0.05, 0)
            @unknown default: break
            }
        }
    }
}
#endif

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
