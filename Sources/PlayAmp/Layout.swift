import SwiftUI
#if canImport(PlayAmpCore)
import PlayAmpCore
#endif

/// Everything a layout can show or do. It doesn't depend on Model, so the command-line
/// preview renderer can fill it with sample values.
struct LayoutState {
    var values: [String: Double]          // bindings, each 0…1
    var text: [String: String]            // {placeholder} values
    var playing: Bool
    var stopped: Bool
    var position: Double
    var positionDate: Date
    var live: LiveState                   // for the embedded cassette element
    var spectrum: () -> [Float]
    var setValue: (String, Double) -> Void   // slider bindings, 0…1
    var perform: (String) -> Void            // button actions
    var preview = false                      // rendering to an image: skip AppKit-only pieces

    /// A stopped, non-interactive state for thumbnails.
    @MainActor static let still = LayoutState(
        values: ["stopped": 1, "volume": 0.7, "balance": 0.5], text: ["time": "00:42", "title": "PlayAmp", "song": "PlayAmp", "status": "STOP", "format": "MP3"],
        playing: false, stopped: true, position: 0, positionDate: .distantPast, live: LiveState(), spectrum: { [] },
        setValue: { _, _ in }, perform: { _ in }, preview: true)
}

/// Draws a skin's declarative player layout. Only elements that move every frame (spinning
/// groups, level-driven needles) get their own animation clock; everything else redraws only
/// when playback state changes, which keeps CPU use low.
struct LayoutCanvas: View {
    let layout: SkinLayout
    let state: LayoutState
    @State private var meter = LevelMeter()
    @Environment(\.palette) private var palette

    var body: some View {
        let renderer = LayoutRenderer(palette: palette, state: state, values: state.values, playTime: state.position, meter: meter)
        ZStack(alignment: .topLeading) {
            ForEach(Array(layout.elements.enumerated()), id: \.offset) { _, element in renderer.view(element) }
        }.frame(width: layout.width, height: layout.height, alignment: .topLeading)
    }
    /// True if an element (or a child) spins or follows the level meter, so it needs a frame clock.
    static func animates(_ elements: [LayoutElement]) -> Bool { elements.contains(where: { animates($0) }) }
    static func animates(_ e: LayoutElement) -> Bool {
        if e.spin != nil { return true }
        for value in [e.rotation, e.opacity, e.radius] { if case .bound(let bind, _, _, _) = value, bind == "level" { return true } }
        if e.visible?.hasSuffix("level") == true { return true }
        return animates(e.children ?? [])
    }
}

/// Smoothed overall loudness for VU-style needles: rises fast, falls back gently.
final class LevelMeter {
    private var level = 0.0, last: TimeInterval?
    func step(_ bars: [Float], at now: TimeInterval) -> Double {
        if now == last { return level }   // several animated elements share one reading per frame
        let dt = min(0.1, max(0, now - (last ?? now))); last = now
        // Loudness from the strongest bands, so typical music swings the needle through its range.
        let loudest = bars.sorted(by: >).prefix(8)
        let target = loudest.isEmpty ? 0 : min(1, max(0, (Double(loudest.reduce(0, +)) / Double(loudest.count) - 0.22) / 0.55))
        level = target > level ? level + (target - level) * 0.6 : max(target, level - 1.4 * dt)
        return level
    }
}

@MainActor struct LayoutRenderer {
    let palette: Palette
    let state: LayoutState
    let values: [String: Double]
    let playTime: Double
    let meter: LevelMeter
    var animating = false   // already inside an element's animation clock

    func view(_ e: LayoutElement) -> AnyView {
        if !animating, LayoutCanvas.animates(e) {
            // Moving parts get their own 30 fps clock, which runs only while playing.
            let base = self
            return AnyView(TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !state.playing)) { context in
                base.at(context.date).view(e)
            })
        }
        guard let f = e.frame, f.count == 4, f[2] > 0, f[3] > 0 else { return AnyView(EmptyView()) }
        if let condition = e.visible, !isOn(condition) { return AnyView(EmptyView()) }
        let size = CGSize(width: f[2], height: f[3])
        var content = AnyView(body(e, size).frame(width: size.width, height: size.height, alignment: .topLeading))
        if e.type == "group" {
            let pivot = e.pivot.flatMap { $0.count == 2 ? UnitPoint(x: $0[0] / f[2], y: $0[1] / f[3]) : nil } ?? .center
            let spin = e.spin.map { $0.resolve(values, stopped: state.stopped) * 6 * playTime } ?? 0   // rpm → degrees
            let angle = (e.rotation?.resolve(values, stopped: state.stopped) ?? 0) + spin
            content = AnyView(content.rotationEffect(.degrees(angle), anchor: pivot))
        }
        let opacity = e.opacity?.resolve(values, stopped: state.stopped) ?? 1
        if let help = e.help, !state.preview { content = AnyView(content.help(help)) }   // tooltips can't be captured in previews
        return AnyView(content.opacity(opacity).offset(x: f[0], y: f[1]))
    }

    @ViewBuilder private func body(_ e: LayoutElement, _ size: CGSize) -> some View {
        let corner = CGFloat(e.corner ?? 0)
        switch e.type {
        case "rect":
            RoundedRectangle(cornerRadius: corner).fill(style(e.fill, .clear))
                .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(style(e.stroke, .clear), lineWidth: e.stroke == nil ? 0 : CGFloat(e.strokeWidth ?? 1)))
                .frame(width: size.width, height: size.height)
        case "ellipse":
            let r = e.radius.map { CGFloat($0.resolve(values, stopped: state.stopped)) }
            Ellipse().fill(style(e.fill, .clear))
                .overlay(Ellipse().strokeBorder(style(e.stroke, .clear), lineWidth: e.stroke == nil ? 0 : CGFloat(e.strokeWidth ?? 1)))
                .frame(width: r.map { $0 * 2 } ?? size.width, height: r.map { $0 * 2 } ?? size.height)
                .frame(width: size.width, height: size.height)
        case "image":
            if let image = image(e.file, mode: e.mode) {
                image.view.frame(width: size.width, height: size.height).clipShape(RoundedRectangle(cornerRadius: corner))
            }
        case "text":
            let text = fill(e.text ?? "")
            let font = palette.font(spec: e.font, CGFloat(e.fontSize ?? 9), weight(e.weight))
            if e.scroll == true {
                MarqueeText(text: text, font: font, fontSize: CGFloat(e.fontSize ?? 9), style: style(e.color, AnyShapeStyle(palette.display)), running: state.playing)
                    .frame(width: size.width, height: size.height)
            } else {
                Text(text).font(font).foregroundStyle(style(e.color, AnyShapeStyle(palette.display))).lineLimit(1).minimumScaleFactor(0.5)
                    .frame(width: size.width, height: size.height, alignment: alignment(e.align))
            }
        case "spectrum":
            let gap = CGFloat(e.gap ?? 1)
            SpectrumBars(source: state.spectrum, active: state.playing, barWidth: max(1, (size.width - gap * CGFloat(Spectrum.bands - 1)) / CGFloat(Spectrum.bands)),
                         height: size.height, gap: gap, showPeaks: e.peaks ?? true,
                         colors: e.fill.map { $0.stops.map { palette[$0] } }, peakColor: e.peakColor.map { palette[$0.stops.first ?? "displayHighlight"] })
        case "button":
            Button { state.perform(e.action ?? "") } label: {
                Text(fill(e.label ?? "")).font(palette.font(spec: e.font, CGFloat(e.fontSize ?? 8), weight(e.weight ?? "bold")))
                    .foregroundStyle(style(e.color, AnyShapeStyle(palette.buttonText))).lineLimit(1).minimumScaleFactor(0.5)
                    .frame(width: size.width, height: size.height)
            }.buttonStyle(LayoutButtonStyle(look: e.style ?? (e.image == nil ? "retro" : "image"), image: image(e.image, mode: nil),
                                            pressedImage: image(e.pressedImage, mode: nil), corner: e.corner.map { CGFloat($0) } ?? palette.buttonCorner))
            .accessibilityLabel(e.help ?? e.action ?? "button")
        case "slider":
            LayoutSlider(element: e, value: values[e.bind == "position" ? "progress" : e.bind ?? ""] ?? 0,
                         knobImage: image(e.knobImage, mode: nil), track: style(e.track, AnyShapeStyle(palette.displayBackground)),
                         fill: style(e.fill, AnyShapeStyle(palette.sliderFill)), knob: style(e.knob, AnyShapeStyle(palette.knob))) { state.setValue(e.bind ?? "", $0) }
        case "group":
            let renderer = self
            let children = ZStack(alignment: .topLeading) {
                ForEach(Array((e.children ?? []).enumerated()), id: \.offset) { _, child in renderer.view(child) }
            }.frame(width: size.width, height: size.height, alignment: .topLeading)
            if e.clip == true { children.clipShape(RoundedRectangle(cornerRadius: corner)) } else { children }
        case "dragArea":
            DragHandle().frame(width: size.width, height: size.height)
        case "cassette":
            CassetteView(title: state.text["title"] ?? "", format: state.text["format"] ?? "", live: state.live)
                .scaleEffect(x: size.width / CassetteView.size.width, y: size.height / CassetteView.size.height, anchor: .topLeading)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
        default:
            EmptyView()
        }
    }

    /// The same renderer at a given frame time: smooth play time and a fresh level reading.
    func at(_ date: Date) -> LayoutRenderer {
        var values = state.values
        values["level"] = state.playing ? meter.step(state.spectrum(), at: date.timeIntervalSinceReferenceDate) : 0
        let time = state.position + (state.playing ? min(0.25, max(0, date.timeIntervalSince(state.positionDate))) : 0)
        return LayoutRenderer(palette: palette, state: state, values: values, playTime: time, meter: meter, animating: true)
    }

    // MARK: Helpers
    func isOn(_ condition: String) -> Bool {
        condition.hasPrefix("!") ? (values[String(condition.dropFirst())] ?? 0) <= 0.5 : (values[condition] ?? 0) > 0.5
    }
    /// Replaces {placeholders} with live values.
    func fill(_ template: String) -> String {
        guard template.contains("{") else { return template }
        var result = "", name: String?
        for ch in template {
            if ch == "{" { name = "" } else if ch == "}", let key = name { result += state.text[key] ?? ""; name = nil }
            else if name != nil { name!.append(ch) } else { result.append(ch) }
        }
        return result
    }
    func image(_ file: String?, mode: String?) -> SkinImage? {
        guard let file else { return nil }
        if file.hasPrefix("@") { return palette.image(String(file.dropFirst())) }
        return SkinImage.load(file, mode: mode ?? "stretch")
    }
    func style(_ paint: Paint?, _ fallback: AnyShapeStyle) -> AnyShapeStyle {
        switch paint {
        case nil: return fallback
        case .color(let token): return AnyShapeStyle(palette[token])
        case .linear(let stops, let angle):
            let radians = angle * .pi / 180, dx = cos(radians) / 2, dy = sin(radians) / 2
            return AnyShapeStyle(LinearGradient(colors: stops.map { palette[$0] }, startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy), endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)))
        case .radial(let stops):
            return AnyShapeStyle(EllipticalGradient(colors: stops.map { palette[$0] }))
        }
    }
    func style(_ paint: Paint?, _ fallback: Color) -> AnyShapeStyle { style(paint, AnyShapeStyle(fallback)) }
    func weight(_ name: String?) -> Font.Weight {
        switch name {
        case "ultraLight": .ultraLight; case "thin": .thin; case "light": .light; case "medium": .medium
        case "semibold": .semibold; case "bold": .bold; case "heavy": .heavy; case "black": .black
        default: .regular
        }
    }
    func alignment(_ name: String?) -> Alignment {
        switch name { case "center": .center; case "right": .trailing; default: .leading }
    }
}

/// Buttons in layouts: the skin's retro look, an image, plain text, or an invisible hit area.
struct LayoutButtonStyle: ButtonStyle {
    let look: String
    let image: SkinImage?
    let pressedImage: SkinImage?
    let corner: CGFloat
    func makeBody(configuration: Configuration) -> some View { Look(configuration: configuration, style: self) }
    private struct Look: View {
        let configuration: ButtonStyleConfiguration
        let style: LayoutButtonStyle
        @Environment(\.palette) private var palette
        var body: some View {
            let pressed = configuration.isPressed
            switch style.look {
            case "none":
                Color.clear.contentShape(Rectangle()).overlay(configuration.label.opacity(0))
            case "plain":
                configuration.label.opacity(pressed ? 0.6 : 1).contentShape(Rectangle())
            case "image":
                ZStack {
                    (pressed ? style.pressedImage ?? style.image : style.image)?.view
                    configuration.label
                }.brightness(pressed && style.pressedImage == nil ? -0.15 : 0).contentShape(Rectangle())
            default:
                configuration.label
                    .background(palette.surface(pressed ? "buttonPressed" : "button", palette.button(pressed: pressed)))
                    .clipShape(RoundedRectangle(cornerRadius: style.corner))
                    .overlay(RoundedRectangle(cornerRadius: style.corner).stroke(Color.black, lineWidth: 0.7))
            }
        }
    }
}

/// A slider for volume, balance or position, horizontal or vertical.
struct LayoutSlider: View {
    let element: LayoutElement
    let value: Double
    let knobImage: SkinImage?
    let track: AnyShapeStyle
    let fill: AnyShapeStyle
    let knob: AnyShapeStyle
    let set: (Double) -> Void
    var body: some View {
        GeometryReader { proxy in
            let vertical = element.vertical == true
            let length = vertical ? proxy.size.height : proxy.size.width
            let thickness = vertical ? proxy.size.width : proxy.size.height
            let knobSize = element.knobSize.flatMap { $0.count == 2 ? CGSize(width: $0[0], height: $0[1]) : nil }
                ?? (vertical ? CGSize(width: min(thickness, 10), height: 8) : CGSize(width: 9, height: min(thickness, 8)))
            let travel = max(1, length - (vertical ? knobSize.height : knobSize.width))
            let along = travel * CGFloat(min(1, max(0, value)))
            let corner = CGFloat(element.corner ?? 1)
            ZStack(alignment: vertical ? .bottom : .leading) {
                RoundedRectangle(cornerRadius: corner).fill(track)
                    .frame(width: vertical ? max(2, thickness * 0.4) : length, height: vertical ? length : max(2, thickness * 0.4))
                RoundedRectangle(cornerRadius: corner).fill(fill)
                    .frame(width: vertical ? max(1, thickness * 0.2) : along + 2, height: vertical ? along + 2 : max(1, thickness * 0.2))
                Group {
                    if let knobImage { knobImage.view } else { RoundedRectangle(cornerRadius: 1).fill(knob).overlay(RoundedRectangle(cornerRadius: 1).stroke(.black, lineWidth: 0.5)) }
                }.frame(width: knobSize.width, height: knobSize.height).offset(x: vertical ? 0 : along, y: vertical ? -along : 0)
            }.frame(width: proxy.size.width, height: proxy.size.height, alignment: vertical ? .bottom : .leading)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let point = vertical ? proxy.size.height - drag.location.y - knobSize.height / 2 : drag.location.x - knobSize.width / 2
                set(Double(min(1, max(0, point / travel))))
            })
        }
        .accessibilityElement().accessibilityLabel(element.help ?? element.bind ?? "slider").accessibilityValue("\(Int(value * 100))%")
        .accessibilityAdjustableAction { direction in set(min(1, max(0, value + (direction == .increment ? 0.05 : -0.05)))) }
    }
}

/// Single-line text that scrolls when it doesn't fit (only while playing).
struct MarqueeText: View {
    let text: String
    let font: Font
    let fontSize: CGFloat
    let style: AnyShapeStyle
    let running: Bool
    var body: some View {
        GeometryReader { proxy in
            let travel = max(0, CGFloat(text.count) * fontSize * 0.62 - proxy.size.width)
            TimelineView(.animation(minimumInterval: 0.05, paused: travel == 0 || !running)) { context in
                let speed = fontSize * 1.8
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: max(1, Double(travel / speed + 4)))
                Text(text).font(font).foregroundStyle(style).fixedSize()
                    .offset(x: running ? -min(travel, max(0, CGFloat(phase - 2) * speed)) : 0)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            }
        }.clipped()
    }
}
