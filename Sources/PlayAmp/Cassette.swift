import SwiftUI
#if canImport(PlayAmpCore)
import PlayAmpCore
#endif

/// Player face for skins with `"face": "cassette"`: a tape deck well with a cassette whose
/// reels turn while playing, next to an amber tape counter and the usual controls.
struct CassetteFace: View {
    @ObservedObject var model: Model
    @ObservedObject var live: LiveState
    var windows: Windows
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                palette.surface("deck", palette["deck"]).clipShape(RoundedRectangle(cornerRadius: 4))
                CassetteView(title: model.current?.title ?? "Drop your music here", format: model.current?.url.pathExtension.uppercased() ?? "TYPE I",
                             live: live)
                // Smoked glass of the deck door.
                RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: [.white.opacity(0.10), .clear, .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)).allowsHitTesting(false)
                RoundedRectangle(cornerRadius: 4).strokeBorder(palette.border, lineWidth: 1)
            }.frame(width: 176, height: 112)
            VStack(spacing: 3) {
                Button { model.remaining.toggle() } label: {
                    Text((model.remaining ? "−" : "") + clock(model.remaining ? live.duration - live.position : live.position))
                        .font(palette.font("display", 17, .medium)).foregroundStyle(palette.display)
                        .frame(maxWidth: .infinity).padding(.vertical, 2).background(palette.surface("display", palette.displayBackground))
                        .overlay(Rectangle().strokeBorder(palette.border, lineWidth: 0.5))
                }.buttonStyle(.plain).accessibilityLabel("Toggle elapsed or remaining time")
                SpectrumBars(source: model.spectrumNow, active: live.playing, barWidth: 3, height: 14).frame(maxWidth: .infinity).padding(.vertical, 2).background(palette.surface("display", palette.displayBackground))
                HStack(spacing: 2) {
                    Circle().fill(live.playing ? palette["spectrumHigh"] : palette.displayDim).frame(width: 4, height: 4)
                    Text(live.playing ? "PLAY" : (live.position > 0 ? "PAUSE" : "STOP"))
                    Spacer(minLength: 0)
                    Text(model.current?.url.pathExtension.uppercased() ?? "—")
                }.font(palette.font("display", 7, .bold)).foregroundStyle(palette.display).padding(.horizontal, 3).padding(.vertical, 2).background(palette.surface("display", palette.displayBackground))
                Spacer(minLength: 0)
                Text("VOL · BAL").font(palette.font("ui", 6, .bold)).frame(maxWidth: .infinity, alignment: .leading)
                VolumeRow(model: model)
                PanelButtons(model: model, windows: windows)
            }.frame(width: 85, height: 112)
        }.frame(height: 112)
    }
}

struct CassetteView: View {
    var title: String
    var format: String
    @ObservedObject var live: LiveState
    @Environment(\.palette) private var palette
    static let size = CGSize(width: 168, height: 107)   // real cassette proportions, 100 × 64 mm

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Redraws ~30 times a second only while playing; frozen otherwise.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !live.playing)) { context in
                Canvas { g, _ in draw(g, time: tapeTime(at: context.date)) }
            }
            Text("A").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(palette["cassetteInk"]).offset(x: 13, y: 7)
            Text(title).font(palette.font("label", 10)).foregroundStyle(palette["cassetteInk"])
                .lineLimit(1).minimumScaleFactor(0.6).truncationMode(.tail)
                .frame(width: 122, alignment: .leading).offset(x: 28, y: 9)
            HStack {
                Text("C-60").font(.system(size: 6, weight: .bold, design: .rounded))
                Spacer()
                Text(format + " · NORMAL").font(.system(size: 5.5, weight: .semibold, design: .rounded))
            }.foregroundStyle(palette["cassetteInk"].opacity(0.75)).frame(width: 136).offset(x: 16, y: 63)
        }.frame(width: Self.size.width, height: Self.size.height).help(title).accessibilityElement().accessibilityLabel("Cassette: \(title)")
    }

    /// Playback position, smoothed between the model's ~12 Hz updates so the reels turn evenly.
    private func tapeTime(at date: Date) -> Double {
        live.position + (live.playing ? min(0.25, max(0, date.timeIntervalSince(live.positionDate))) : 0)
    }

    private func draw(_ g: GraphicsContext, time: Double) {
        let W = Self.size.width, H = Self.size.height
        let shell = palette["cassetteShell"], label = palette["cassetteLabel"], tape = palette["tape"], deck = palette["deck"]
        let ink = palette["cassetteInk"]

        // Shell with a lighter bevel line.
        let body = Path(roundedRect: CGRect(x: 0, y: 0, width: W, height: H), cornerRadius: 7)
        g.fill(body, with: .color(shell))
        g.stroke(Path(roundedRect: CGRect(x: 1, y: 1, width: W - 2, height: H - 2), cornerRadius: 6), with: .color(.white.opacity(0.18)), lineWidth: 1)

        // Label with two colored stripes running behind the window.
        let labelRect = CGRect(x: 8, y: 5, width: W - 16, height: 68)
        g.fill(Path(roundedRect: labelRect, cornerRadius: 4), with: .color(label))
        if let art = palette.image("cassetteLabel") {   // the skin's printed label artwork
            var printed = g
            printed.clip(to: Path(roundedRect: labelRect, cornerRadius: 4))
            printed.draw(Image(nsImage: art.image).resizable(), in: labelRect)
        } else if palette.labelStyle == "stripes" {
            g.fill(Path(CGRect(x: labelRect.minX, y: 28, width: labelRect.width, height: 7)), with: .color(palette["cassetteStripe1"]))
            g.fill(Path(CGRect(x: labelRect.minX, y: 35, width: labelRect.width, height: 7)), with: .color(palette["cassetteStripe2"]))
        }
        for y in [22.0, 60.0] {   // writing lines
            g.stroke(Path { $0.move(to: CGPoint(x: 26, y: y)); $0.addLine(to: CGPoint(x: labelRect.maxX - 6, y: y)) }, with: .color(ink.opacity(0.18)), lineWidth: 0.5)
        }

        // Window onto the reels: one wide window, or two round ones around the hubs ("twin").
        let window = CGRect(x: 32, y: 32, width: 104, height: 30)
        let windowPath = palette.cassetteWindow == "twin"
            ? Path { p in for x in [W / 2 - 30, W / 2 + 30] { p.addEllipse(in: CGRect(x: x - 15, y: window.midY - 15, width: 30, height: 30)) } }
            : Path(roundedRect: window, cornerRadius: 9)
        g.fill(windowPath, with: .color(deck.opacity(0.9)))
        var inside = g
        inside.clip(to: windowPath)
        let progress = live.duration > 0 ? min(1, max(0, time / live.duration)) : 0
        let hubR = 8.5, fullR = 22.0
        // Tape area is conserved: what leaves the left pack lands on the right one.
        let leftR = (hubR * hubR + (1 - progress) * (fullR * fullR - hubR * hubR)).squareRoot()
        let rightR = (hubR * hubR + progress * (fullR * fullR - hubR * hubR)).squareRoot()
        let left = CGPoint(x: W / 2 - 30, y: window.midY), right = CGPoint(x: W / 2 + 30, y: window.midY)
        for (center, radius) in [(left, leftR), (right, rightR)] {
            inside.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(tape))
            inside.stroke(Path(ellipseIn: CGRect(x: center.x - radius + 1.5, y: center.y - radius + 1.5, width: radius * 2 - 3, height: radius * 2 - 3)), with: .color(.white.opacity(0.06)), lineWidth: 1)
        }
        // Constant tape speed: the smaller pack spins faster.
        let speed = 16.0
        drawHub(g, at: left, angle: time * speed / leftR)
        drawHub(g, at: right, angle: time * speed / rightR)
        // Glass glare and rim.
        inside.fill(Path(CGRect(x: window.minX, y: window.minY, width: window.width, height: window.height * 0.45)), with: .linearGradient(Gradient(colors: [.white.opacity(0.16), .clear]), startPoint: CGPoint(x: 0, y: window.minY), endPoint: CGPoint(x: 0, y: window.midY)))
        g.stroke(windowPath, with: .color(.black.opacity(0.55)), lineWidth: 1)

        // Head opening at the bottom, with the exposed tape and its guide rollers.
        let opening = Path { p in
            p.move(to: CGPoint(x: 30, y: H)); p.addLine(to: CGPoint(x: 40, y: 79)); p.addLine(to: CGPoint(x: W - 40, y: 79)); p.addLine(to: CGPoint(x: W - 30, y: H)); p.closeSubpath()
        }
        g.fill(opening, with: .color(.white.opacity(0.07)))
        g.stroke(opening, with: .color(.black.opacity(0.4)), lineWidth: 0.8)
        for x in [52.0, W / 2 - 6, W / 2 + 6, W - 52] {
            g.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: 84, width: 5, height: 5)), with: .color(deck))
        }
        g.fill(Path(CGRect(x: 36, y: H - 4, width: W - 72, height: 2)), with: .color(tape))
        for x in [38.0, W - 38] {
            g.fill(Path(ellipseIn: CGRect(x: x - 3, y: H - 8, width: 6, height: 6)), with: .color(palette["reel"].opacity(0.85)))
        }

        // Screws.
        for point in [CGPoint(x: 5, y: 5), CGPoint(x: W - 5, y: 5), CGPoint(x: 5, y: H - 5), CGPoint(x: W - 5, y: H - 5), CGPoint(x: W / 2, y: 95)] {
            g.fill(Path(ellipseIn: CGRect(x: point.x - 2.3, y: point.y - 2.3, width: 4.6, height: 4.6)), with: .color(Color(white: 0.72)))
            g.stroke(Path { $0.move(to: CGPoint(x: point.x - 1.5, y: point.y)); $0.addLine(to: CGPoint(x: point.x + 1.5, y: point.y)) }, with: .color(.black.opacity(0.6)), lineWidth: 0.6)
        }
    }

    /// A reel hub: white ring, dark spindle hole, and six drive teeth that make rotation visible.
    private func drawHub(_ g: GraphicsContext, at center: CGPoint, angle: Double) {
        let reel = palette["reel"]
        var hub = g
        hub.translateBy(x: center.x, y: center.y)
        hub.rotate(by: .radians(angle))
        switch palette.reels {
        case "spokes":   // a wheel: rim, three thick spokes, small spindle
            g.stroke(Path(ellipseIn: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)), with: .color(reel), lineWidth: 2)
            for i in 0..<3 {
                var spoke = hub
                spoke.rotate(by: .degrees(Double(i) * 120))
                spoke.fill(Path(roundedRect: CGRect(x: -1.4, y: -8, width: 2.8, height: 8), cornerRadius: 1), with: .color(reel))
            }
            g.fill(Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)), with: .color(palette["deck"]))
            return
        case "solid":    // a plain disk with an off-centre marker
            g.fill(Path(ellipseIn: CGRect(x: center.x - 8.5, y: center.y - 8.5, width: 17, height: 17)), with: .color(reel))
            g.fill(Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)), with: .color(palette["deck"]))
            hub.fill(Path(ellipseIn: CGRect(x: -1.5, y: -7, width: 3, height: 3)), with: .color(palette["deck"].opacity(0.7)))
            return
        default: break
        }
        g.fill(Path(ellipseIn: CGRect(x: center.x - 8.5, y: center.y - 8.5, width: 17, height: 17)), with: .color(reel))
        g.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(palette["deck"]))
        var teeth = g
        teeth.translateBy(x: center.x, y: center.y)
        teeth.rotate(by: .radians(angle))
        for i in 0..<6 {
            var tooth = teeth
            tooth.rotate(by: .degrees(Double(i) * 60))
            tooth.fill(Path(CGRect(x: -1, y: -5, width: 2, height: 2.6)), with: .color(reel))
        }
        // Spokes on the ring so it reads as turning even at a glance.
        for i in 0..<3 {
            var spoke = teeth
            spoke.rotate(by: .degrees(Double(i) * 120 + 30))
            spoke.fill(Path(CGRect(x: -0.8, y: -8.5, width: 1.6, height: 3.2)), with: .color(.black.opacity(0.35)))
        }
    }
}
