import SwiftUI

private let amber = Color(red: 0.95, green: 0.64, blue: 0.23)
private let signalRed = Color(red: 0.90, green: 0.33, blue: 0.24)
private let lightYellow = Color(red: 1.0, green: 0.91, blue: 0.58)

// Dial scale: 88.0–92.0 MHz, with the station at 89.9.
private let dialLow = 88.0
private let dialHigh = 92.0
private let stationFrequency = 89.9
private let dialInset: CGFloat = 14

private func dialX(_ frequency: Double, width: CGFloat) -> CGFloat {
    let usable = width - dialInset * 2
    return dialInset + CGFloat((frequency - dialLow) / (dialHigh - dialLow)) * usable
}

struct ContentView: View {
    @StateObject private var radio = RadioPlayer()

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.10).ignoresSafeArea()
            VStack(spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    Text("KCRW").font(.system(size: 40, weight: .bold))
                    Spacer()
                    Text("89.9 FM · LOS ANGELES")
                        .font(.caption.monospaced())
                        .foregroundStyle(amber)
                }
                Dial(live: radio.status == "Live")
                HStack(spacing: 12) {
                    ForEach(Channel.allCases) { channel in
                        ChannelButton(channel: channel, radio: radio)
                    }
                }
                Fader(value: $radio.volume)
                Text(radio.current == nil ? radio.status : " ")
                    .font(.caption.monospaced())
                    .foregroundStyle(signalRed)
            }
            .padding(24)
            .frame(maxWidth: 520)
        }
        .frame(minWidth: 420, minHeight: 440)
        .preferredColorScheme(.dark)
    }
}

struct ChannelButton: View {
    let channel: Channel
    @ObservedObject var radio: RadioPlayer

    var body: some View {
        let on = radio.current == channel
        Button { radio.toggle(channel) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(channel.title).font(.headline)
                Text(on ? radio.status : " ").font(.caption.monospaced())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(on ? amber : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.3), lineWidth: 1))
            .foregroundStyle(on ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}

struct Dial: View {
    let live: Bool

    private let labels: [(text: String, frequency: Double)] = [
        ("88", 88), ("89", 89), ("89.9", 89.9), ("91", 91), ("92", 92)
    ]

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ForEach(labels, id: \.text) { label in
                    Text(label.text)
                        .font(.caption2.monospaced())
                        .foregroundStyle(label.frequency == stationFrequency
                                         ? amber
                                         : (live ? lightYellow : Color.gray))
                        .shadow(color: lightYellow.opacity(live && label.frequency != stationFrequency ? 0.6 : 0),
                                radius: 4)
                        .position(x: dialX(label.frequency, width: geo.size.width),
                                  y: geo.size.height / 2)
                }
            }
            .frame(height: 14)

            ZStack {
                Ticks(color: .gray)
                Ticks(color: lightYellow)
                    .shadow(color: lightYellow.opacity(0.7), radius: 3)
                    .opacity(live ? 1 : 0)
                GeometryReader { geo in
                    Rectangle()
                        .fill(signalRed)
                        .frame(width: 2, height: geo.size.height)
                        .shadow(color: signalRed, radius: live ? 6 : 0)
                        .opacity(live ? 1 : 0.35)
                        .animation(.easeInOut(duration: 0.4), value: live)
                        .position(x: dialX(stationFrequency, width: geo.size.width),
                                  y: geo.size.height / 2)
                }
            }
            .frame(height: 44)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { rail }
        .overlay(alignment: .bottom) { rail }
        .animation(.easeInOut(duration: 0.4), value: live)
    }

    /// The horizontal lines above and below the dial.
    private var rail: some View {
        Rectangle()
            .fill(live ? lightYellow : Color.white.opacity(0.12))
            .frame(height: 1)
            .shadow(color: lightYellow.opacity(live ? 0.7 : 0), radius: 3)
    }
}

/// Horizontal channel fader in the style of a DJ mixer: recessed slot, scale marks, ridged cap.
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
                            let length: CGFloat = i % 5 == 0 ? 9 : 5
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: length))
                            path.move(to: CGPoint(x: x, y: size.height))
                            path.addLine(to: CGPoint(x: x, y: size.height - length))
                            // Ticks at or below the fader position are lit; the rest are off (gray).
                            let lit = Double(i) / Double(divisions) <= value + 0.0001
                            context.stroke(path, with: .color(lit ? lightYellow : Color.gray), lineWidth: 1)
                        }
                    }

                    // Recessed slot.
                    Capsule()
                        .fill(Color.black)
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        .frame(width: travel, height: 6)
                        .position(x: width / 2, y: midY)

                    // Lit portion of the slot, from the left end to the cap.
                    Capsule()
                        .fill(lightYellow.opacity(0.55))
                        .frame(width: max(travel * CGFloat(value), 0), height: 2)
                        .position(x: capWidth / 2 + travel * CGFloat(value) / 2, y: midY)

                    // Cap: dark body, vertical ridges, bright center line.
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.12)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.2), lineWidth: 1))
                        .overlay {
                            HStack(spacing: 3) {
                                ForEach(0..<7, id: \.self) { i in
                                    Rectangle()
                                        .fill(i == 3 ? lightYellow : Color.white.opacity(0.18))
                                        .frame(width: i == 3 ? 2 : 1)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
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
            .frame(height: 48)
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

struct Ticks: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            // One tick per 0.1 MHz; taller at every 0.5 and 1.0 MHz.
            for index in 0...40 {
                let frequency = dialLow + Double(index) * 0.1
                let x = dialX(frequency, width: size.width)
                let height: CGFloat = index % 10 == 0 ? 24 : (index % 5 == 0 ? 16 : 9)
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x, y: size.height - height))
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
        }
    }
}
