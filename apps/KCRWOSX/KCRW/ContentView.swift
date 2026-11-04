import SwiftUI

private let amber = Color(red: 0.95, green: 0.64, blue: 0.23)
private let signalRed = Color(red: 0.90, green: 0.33, blue: 0.24)

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
                Text(radio.current == nil ? radio.status : " ")
                    .font(.caption.monospaced())
                    .foregroundStyle(signalRed)
            }
            .padding(24)
            .frame(maxWidth: 520)
        }
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
            .foregroundStyle(on ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
    }
}

struct Dial: View {
    let live: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("88"); Spacer()
                Text("89"); Spacer()
                Text("89.9").foregroundStyle(amber); Spacer()
                Text("91"); Spacer()
                Text("92")
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.gray)

            ZStack {
                Canvas { context, size in
                    var x: CGFloat = 0
                    var index = 0
                    while x <= size.width {
                        let height: CGFloat = index % 5 == 0 ? 22 : 10
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: size.height))
                        path.addLine(to: CGPoint(x: x, y: size.height - height))
                        context.stroke(path, with: .color(.gray), lineWidth: 1)
                        x += 14
                        index += 1
                    }
                }
                Rectangle()
                    .fill(signalRed)
                    .frame(width: 2)
                    .shadow(color: signalRed, radius: live ? 6 : 0)
                    .opacity(live ? 1 : 0.35)
                    .animation(.easeInOut(duration: 0.4), value: live)
            }
            .frame(height: 44)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1) }
    }
}
