import SwiftUI
import UniformTypeIdentifiers
#if canImport(MacAmpCore)
import MacAmpCore
#endif

/// Title-bar drag; Windows.drag moves the panel (and its attached panels) in screen coordinates.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) {
            (window as? PlayerWindow)?.titleDrag?(event)
        }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}
/// Drag area that is left out when rendering a preview image (AppKit views can't be captured).
struct DragHandle: View {
    @Environment(\.renderingPreview) private var preview
    var body: some View { if !preview { WindowDragArea() } }
}
private struct RenderingPreviewKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var renderingPreview: Bool {
        get { self[RenderingPreviewKey.self] }
        set { self[RenderingPreviewKey.self] = newValue }
    }
}
struct Chrome<Content: View>: View {
    var title: String
    var close: () -> Void
    /// Image slot for this window's background ("player", "playlist", …; falls back to "panel").
    var slot = "panel"
    /// Shows a grip in the bottom-right corner; the window handles the drag (see Windows.resize).
    var grip = false
    @ViewBuilder var content: Content
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                HStack(spacing: 4) {
                    Rectangle().fill(palette.border).frame(height: 1)
                    Text(title).font(palette.font("ui", 8, .bold)).fixedSize()
                    Rectangle().fill(palette.border).frame(height: 1)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(DragHandle().accessibilityLabel("Drag window"))
                Button("×", action: close).buttonStyle(RetroButton()).accessibilityLabel("Close \(title)")
            }.frame(height: 11)
            content
        }.padding(5)
        // Fill the whole window so nothing behind it shows through at the edges.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(palette.surface(slot, palette.panel))
        .clipShape(RoundedRectangle(cornerRadius: palette.windowCorner))
        .overlay(RoundedRectangle(cornerRadius: palette.windowCorner).strokeBorder(palette.border, lineWidth: 1))
        .overlay(alignment: .bottomTrailing) { if grip { ResizeGrip().padding(2) } }
        .foregroundStyle(palette.text)
    }
}
/// Three diagonal ridges, like the size grip of old desktop players.
struct ResizeGrip: View {
    @Environment(\.palette) private var palette
    var body: some View {
        Canvas { g, size in
            for i in 0..<3 {
                let inset = CGFloat(i) * 3 + 2
                var line = Path(); line.move(to: CGPoint(x: size.width - 1, y: inset)); line.addLine(to: CGPoint(x: inset, y: size.height - 1))
                g.stroke(line, with: .color(palette.panelAccent.opacity(0.9)), lineWidth: 1)
            }
        }.frame(width: 10, height: 10)
        .pointerStyle(.frameResize(position: .bottomTrailing, directions: [.inward, .outward]))
        .help("Drag up or down to resize")
        .accessibilityLabel("Resize")
    }
}
struct RetroButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Look(configuration: configuration) }
    private struct Look: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.palette) private var palette
        var body: some View {
            configuration.label.font(palette.font("ui", 8, .bold)).padding(.horizontal, 4).frame(minHeight: 12)
                .background(palette.surface(configuration.isPressed ? "buttonPressed" : "button", palette.button(pressed: configuration.isPressed)))
                .clipShape(RoundedRectangle(cornerRadius: palette.buttonCorner))
                .overlay(RoundedRectangle(cornerRadius: palette.buttonCorner).stroke(Color.black, lineWidth: 0.7)).foregroundStyle(palette.buttonText)
        }
    }
}

struct RetroSlider<Value: BinaryFloatingPoint>: View {
    @Binding var value: Value
    var range: ClosedRange<Value>
    @Environment(\.palette) private var palette
    var body: some View {
        GeometryReader { proxy in
            let fraction = Double((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let width = max(1, proxy.size.width - 9)
            ZStack(alignment: .leading) {
                Rectangle().fill(palette.displayBackground).frame(height: 4)
                Rectangle().fill(palette.sliderFill).frame(width: max(0, width * min(1,max(0,fraction)) + 4), height: 2)
                Rectangle().fill(palette.knob).frame(width: 9, height: 8).overlay(Rectangle().stroke(.black, lineWidth: 0.5)).offset(x: width * min(1,max(0,fraction)))
            }.frame(height: proxy.size.height).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                    value = range.lowerBound + Value(min(1,max(0,(event.location.x - 4.5) / width))) * (range.upperBound - range.lowerBound)
                })
        }.frame(height: 10)
        .accessibilityElement().accessibilityValue("\(Int(Double(value) * 100))")
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            value = min(range.upperBound,max(range.lowerBound,value + (direction == .increment ? step : -step)))
        }
    }
}

struct Ticker: View {
    var text: String
    var running = true
    @Environment(\.palette) private var palette
    var body: some View {
        GeometryReader { proxy in
            let travel = max(0, CGFloat(text.count) * 6 - proxy.size.width)
            // Only animate while playing and when the title is too long to fit.
            TimelineView(.animation(minimumInterval: 0.05, paused: travel == 0 || !running)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: max(1, Double(travel / 16 + 4)))
                Text(text).font(palette.font("display", 9)).fixedSize().offset(x: running ? -min(travel, max(0, phase - 2) * 16) : 0)
            }
        }.frame(height: 12).clipped().foregroundStyle(palette.display)
    }
}
func clock(_ value: Double) -> String { let n = Int(max(0, value)); return String(format: "%02d:%02d", n / 60, n % 60) }

struct PlayerView: View {
    @ObservedObject var model: Model
    @ObservedObject var live: LiveState
    var windows: Windows
    @Environment(\.palette) private var palette
    var body: some View {
        Group {
            if let layout = palette.layout {
                LayoutCanvas(layout: layout, state: layoutState)
            } else {
                builtInFace
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: receive)
        .alert("Mac-Amp", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) { Button("OK") { model.message = nil } } message: { Text(model.message ?? "") }
    }
    private var builtInFace: some View {
        Chrome(title: "Mac-Amp", close: { NSApp.hide(nil) }, slot: "player") {
            if palette.face == .cassette {
                CassetteFace(model: model, live: live, windows: windows)
            } else {
                classicDisplay
            }
            RetroSlider(value: Binding(get: { min(live.position, max(1, live.duration)) }, set: { model.seek($0) }), range: 0...max(1, live.duration)).controlSize(.mini).frame(height: 10).accessibilityLabel("Playback position")
            TransportRow(model: model)
        }.frame(width: 275, height: Windows.playerHeight(palette.face))
    }
    /// Live values and actions for layout skins.
    private var layoutState: LayoutState {
        let track = model.current
        let parts = track?.title.components(separatedBy: " — ") ?? []
        let index = model.session.tracks.firstIndex { $0.id == model.session.selected }
        let progress = live.duration > 0 ? min(1, live.position / live.duration) : 0
        let status = live.playing ? "PLAY" : (model.isLoaded ? "PAUSE" : "STOP")
        let repeatValue: Double = switch model.session.repeatMode { case .off: 0; case .all: 0.5; case .one: 1 }
        return LayoutState(
            values: ["progress": progress, "playing": live.playing ? 1 : 0, "paused": model.isLoaded && !live.playing ? 1 : 0,
                     "stopped": model.isLoaded ? 0 : 1, "volume": Double(model.session.volume), "balance": Double(model.session.balance + 1) / 2,
                     "shuffle": model.session.shuffle ? 1 : 0, "repeat": repeatValue, "remaining": model.remaining ? 1 : 0],
            text: ["time": (model.remaining ? "−" : "") + clock(model.remaining ? live.duration - live.position : live.position),
                   "elapsed": clock(live.position), "remaining": clock(live.duration - live.position), "duration": clock(live.duration),
                   "title": track?.title ?? "DROP YOUR MUSIC HERE", "artist": parts.count > 1 ? parts[0] : "",
                   "song": parts.count > 1 ? parts.dropFirst().joined(separator: " — ") : (track?.title ?? "Mac-Amp"),
                   "format": track?.url.pathExtension.uppercased() ?? "—", "status": status,
                   "track": index.map { "\($0 + 1)" } ?? "–", "count": "\(model.session.tracks.count)",
                   "shuffle": model.session.shuffle ? "SHUF ●" : "SHUF", "repeat": "R:\(model.session.repeatMode.rawValue.uppercased())",
                   "volume": "\(Int(model.session.volume * 100))%", "skin": palette.name.uppercased()],
            playing: live.playing, stopped: !model.isLoaded, position: live.position, positionDate: live.positionDate, live: live,
            spectrum: model.spectrumNow,
            setValue: { bind, value in
                switch bind {
                case "volume": model.session.volume = Float(value); model.changed()
                case "balance": model.session.balance = Float(value * 2 - 1); model.changed()
                case "position": model.seek(value * max(1, live.duration))
                default: break
                }
            },
            perform: { action in
                switch action {
                case "playPause": model.toggle()
                case "play": if !live.playing { model.toggle() }
                case "pause": model.pause()
                case "stop": model.stop()
                case "next": model.advance()
                case "previous": model.advance(backwards: true)
                case "add": model.choose()
                case "shuffle": model.toggleShuffle()
                case "repeat": model.cycleRepeat()
                case "equalizer": windows.toggle(.equalizer)
                case "playlist": windows.toggle(.playlist)
                case "skins": windows.toggle(.skins)
                case "find": (NSApp.delegate as? AppDelegate)?.find()
                case "toggleTime": model.remaining.toggle()
                case "hide": NSApp.hide(nil)
                case "minimize": windows.panels[.player]?.miniaturize(nil)
                default: break
                }
            }, preview: model.isPreview)
    }
    private var classicDisplay: some View {
        HStack(spacing: 5) {
            VStack(spacing: 1) {
                Button { model.remaining.toggle() } label: {
                    Text((model.remaining ? "−" : "") + clock(model.remaining ? live.duration - live.position : live.position)).font(palette.font("display", 23, .regular)).foregroundStyle(palette.display)
                }.buttonStyle(.plain).accessibilityLabel("Toggle elapsed or remaining time")
                SpectrumBars(source: model.spectrumNow, active: live.playing, barWidth: 4, height: 18)
            }.frame(width: 104).background(palette.surface("display", palette.displayBackground))
            VStack(spacing: 2) {
                Ticker(text: model.current?.title ?? "DROP YOUR MUSIC HERE • Mac-Amp", running: live.playing)
                HStack { Text(model.current?.url.pathExtension.uppercased() ?? "LOCAL AUDIO"); Spacer(); Text(live.playing ? "STEREO ▶" : "READY") }.font(palette.font("display", 7)).foregroundStyle(palette.display).padding(2).background(palette.surface("display", palette.displayBackground))
                VolumeRow(model: model)
                PanelButtons(model: model, windows: windows)
            }
        }.frame(height: 49)
    }
    func receive(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers { _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in model.add([url]) } } } }; return true
    }
}
/// Classic analyzer motion: bars jump up instantly and fall back at a steady rate;
/// peak markers hold briefly at the top, then drop with gravity.
final class SpectrumMotion {
    private(set) var levels = Array(repeating: Float(0), count: Spectrum.bands)
    private(set) var peaks = Array(repeating: Float(0), count: Spectrum.bands)
    private var peakVelocity = Array(repeating: Float(0), count: Spectrum.bands)
    private var peakHoldUntil = Array(repeating: 0.0, count: Spectrum.bands)
    private var last: TimeInterval?
    static let fallRate: Float = 2.2        // full height per second
    static let peakHold = 0.3               // seconds
    static let peakGravity: Float = 3.5     // height per second²
    var isIdle: Bool { !levels.contains { $0 > 0 } && !peaks.contains { $0 > 0 } }

    func step(to targets: [Float], at now: TimeInterval) {
        let dt = Float(min(0.1, max(0, now - (last ?? now)))); last = now
        for i in levels.indices {
            let target = i < targets.count ? targets[i] : 0
            levels[i] = target >= levels[i] ? target : max(target, levels[i] - Self.fallRate * dt)
            if levels[i] >= peaks[i] {
                peaks[i] = levels[i]; peakVelocity[i] = 0; peakHoldUntil[i] = now + Self.peakHold
            } else if now > peakHoldUntil[i] {
                peakVelocity[i] += Self.peakGravity * dt
                peaks[i] = max(levels[i], peaks[i] - peakVelocity[i] * dt)
            }
        }
    }
}
struct SpectrumBars: View {
    var source: () -> [Float]
    var active: Bool
    var barWidth: CGFloat
    var height: CGFloat
    var gap: CGFloat = 1
    var showPeaks = true
    var colors: [Color]? = nil      // top → bottom; defaults to the skin's spectrum colors
    var peakColor: Color? = nil
    @State private var motion = SpectrumMotion()
    @State private var settled = true
    @Environment(\.palette) private var palette
    var body: some View {
        // 60 fps while playing, and until the bars have fallen after a pause/stop; idle otherwise.
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !active && settled)) { context in
            Canvas { g, size in
                motion.step(to: active ? source() : [], at: context.date.timeIntervalSinceReferenceDate)
                let fill = GraphicsContext.Shading.linearGradient(Gradient(colors: colors ?? [palette["spectrumHigh"], palette["spectrumMid"], palette.display]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
                for i in motion.levels.indices {
                    let x = CGFloat(i) * (barWidth + gap)
                    let bar = CGFloat(motion.levels[i]) * size.height
                    if bar > 0.5 { g.fill(Path(CGRect(x: x, y: size.height - bar, width: barWidth, height: bar)), with: fill) }
                    let peak = CGFloat(motion.peaks[i]) * size.height
                    if showPeaks, peak > 0.5 { g.fill(Path(CGRect(x: x, y: max(0, size.height - peak - 1), width: barWidth, height: 1)), with: .color(peakColor ?? palette.displayHighlight.opacity(0.85))) }
                }
                let nowSettled = !active && motion.isIdle
                if nowSettled != settled { DispatchQueue.main.async { settled = nowSettled } }
            }
        }.frame(width: CGFloat(Spectrum.bands) * (barWidth + gap) - gap, height: height)
    }
}
struct VolumeRow: View {
    @ObservedObject var model: Model
    var body: some View {
        HStack(spacing: 2) {
            RetroSlider(value: $model.session.volume, range: 0...1).accessibilityLabel("Volume")
            RetroSlider(value: $model.session.balance, range: -1...1).frame(width: 44).accessibilityLabel("Balance")
        }.controlSize(.mini).onChange(of: model.session.volume) { model.changed() }.onChange(of: model.session.balance) { model.changed() }
    }
}
struct PanelButtons: View {
    @ObservedObject var model: Model
    var windows: Windows
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: 3) { Button("EQ") { windows.toggle(.equalizer) }; Button("PL") { windows.toggle(.playlist) }; Button("SK") { windows.toggle(.skins) }.help("Skins").accessibilityLabel("Skins"); Spacer(minLength: 0); Text("●").foregroundStyle(palette.panelAccent).font(.system(size: 7)) }.buttonStyle(RetroButton())
    }
}
struct TransportRow: View {
    @ObservedObject var model: Model
    var body: some View {
        HStack(spacing: 2) {
            Button("|◀") { model.advance(backwards: true) }.accessibilityLabel("Previous")
            Button("▶") { model.toggle() }.accessibilityLabel("Play or pause")
            Button("Ⅱ") { model.pause() }.accessibilityLabel("Pause")
            Button("■") { model.stop() }.accessibilityLabel("Stop")
            Button("▶|") { model.advance() }.accessibilityLabel("Next")
            Button("⏏") { model.choose() }.accessibilityLabel("Add music")
            Spacer(minLength: 0)
            Button(model.session.shuffle ? "SHUF ●" : "SHUF") { model.session.shuffle.toggle(); model.session.shuffleOrder = nil; model.save() }
            Button("R:\(model.session.repeatMode.rawValue.uppercased())") {
                let modes = RepeatMode.allCases; model.session.repeatMode = modes[(modes.firstIndex(of: model.session.repeatMode)! + 1) % modes.count]; model.save()
            }.accessibilityLabel("Repeat \(model.session.repeatMode.rawValue)")
        }.buttonStyle(RetroButton())
    }
}
struct PlaylistView: View {
    @ObservedObject var model: Model
    var windows: Windows
    @State private var selection = Set<UUID>()
    @State private var visible = Set<UUID>()
    @State private var searching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @Environment(\.palette) private var palette
    @Environment(\.renderingPreview) private var preview
    private var previewRows: some View {
        VStack(spacing: 0) {
            ForEach(rows.prefix(12), id: \.track.id) { row in
                let isCurrent = row.track.id == model.session.selected
                HStack(spacing: 3) {
                    Text(isCurrent ? "▶" : " ").foregroundStyle(palette.display).frame(width: 7)
                    Text(String(format: "%02d.", row.index + 1)).foregroundStyle(palette.displayDim)
                    Text(row.track.title).foregroundStyle(isCurrent ? palette.displayHighlight : palette.display).fontWeight(isCurrent ? .bold : .regular).lineLimit(1)
                    Spacer(minLength: 0); Text("MP3").foregroundStyle(palette.displayDim)
                }.font(palette.font("display", 9)).padding(.horizontal, 6).frame(height: 17)
                .background(isCurrent ? palette.playingRow : .clear)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(palette.surface("display", palette.displayBackground))
    }

    /// Tracks with their original position; filtered by every word typed in the search field.
    private var rows: [(index: Int, track: Track)] {
        let all = model.session.tracks.enumerated().map { (index: $0.offset, track: $0.element) }
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return all }
        return all.filter { row in let title = row.track.title.lowercased(); return words.allSatisfy { title.contains($0) } }
    }
    var body: some View {
        Chrome(title: "Mac-Amp • PLAYLIST", close: { windows.toggle(.playlist) }, slot: "playlist", grip: true) {
            ScrollViewReader { scroller in
                if searching {
                    HStack(spacing: 3) {
                        Text("FIND").font(palette.font("display", 8, .bold)).foregroundStyle(palette.display)
                        TextField("", text: $query, prompt: Text("type a title or artist").foregroundStyle(palette.displayDim))
                            .textFieldStyle(.plain).font(palette.font("display", 9)).foregroundStyle(palette.displayHighlight)
                            .focused($searchFocused)
                            .onAppear { focusSearch() }
                            .onSubmit { if let first = rows.first { model.play(first.track.id); closeSearch(scroller) } }
                            .onExitCommand { closeSearch(scroller) }
                            .accessibilityLabel("Search playlist")
                        Text("\(rows.count)").font(palette.font("display", 8)).foregroundStyle(palette.displayDim)
                        Button("×") { closeSearch(scroller) }.buttonStyle(RetroButton()).accessibilityLabel("Close search")
                    }.padding(.horizontal, 3).frame(height: 14).background(palette.surface("display", palette.displayBackground))
                }
                if preview {
                    previewRows   // the AppKit-backed List can't be captured in a preview image
                } else {
                List(selection: $selection) {
                    ForEach(rows, id: \.track.id) { row in
                        let track = row.track
                        let isCurrent = track.id == model.session.selected
                        HStack(spacing: 3) {
                            Text(isCurrent ? "▶" : " ").foregroundStyle(palette.display).frame(width: 7)
                            Text(String(format: "%02d.", row.index + 1)).foregroundStyle(palette.displayDim)
                            Text(track.title).foregroundStyle(isCurrent ? palette.displayHighlight : palette.display).fontWeight(isCurrent ? .bold : .regular).lineLimit(1)
                            Spacer(minLength: 0); Text(track.url.pathExtension.uppercased()).foregroundStyle(palette.displayDim)
                        }.font(palette.font("display", 9)).padding(.vertical, 2).tag(track.id)
                        .listRowBackground(isCurrent ? palette.playingRow : palette.hasImage("display") ? Color.clear : palette.displayBackground)
                        .onAppear { visible.insert(track.id) }.onDisappear { visible.remove(track.id) }
                        .onTapGesture(count: 2) { model.play(track.id) }
                        .onDrag { NSItemProvider(object: track.id.uuidString as NSString) }
                        .onDrop(of: [.text], isTargeted: nil) { providers in
                            guard let provider = providers.first else { return false }
                            _ = provider.loadObject(ofClass: String.self) { text, _ in
                                guard let text, let id = UUID(uuidString: text) else { return }
                                Task { @MainActor in
                                    guard let source = model.session.tracks.firstIndex(where: { $0.id == id }), let target = model.session.tracks.firstIndex(where: { $0.id == track.id }) else { return }
                                    model.session.tracks.move(fromOffsets: IndexSet(integer: source), toOffset: target > source ? target + 1 : target); model.save()
                                }
                            }; return true
                        }
                        .contextMenu { Button("Play") { model.play(track.id) }; Button("Remove") { model.remove([track.id]) } }
                    }
                    // Offsets only match the full list, so reordering is off while filtering.
                    .onMove(perform: query.isEmpty ? { source, target in model.session.tracks.move(fromOffsets: source, toOffset: target); model.save() } : nil)
                }.listStyle(.plain).scrollContentBackground(.hidden).background(palette.surface("display", palette.displayBackground)).environment(\.defaultMinListRowHeight, 17)
                    .onDeleteCommand { model.remove(selection); selection.removeAll() }
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        for provider in providers { _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in model.add([url]) } } } }; return true
                    }
                    // Follow the playing track when Next/Previous/shuffle jumps to a row that's off-screen.
                    .onChange(of: model.session.selected) { _, id in
                        guard let id, !visible.contains(id) else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { scroller.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: model.searchToken) { if searching { focusSearch() } else { searching = true } }
                    .onAppear { if let id = model.session.selected { scroller.scrollTo(id, anchor: .center) } }
                }
            }
            HStack(spacing: 3) {
                Button("+ ADD") { model.choose() }; Button("− REM") { model.remove(selection); selection.removeAll() }
                Button("CLEAR") { model.remove(Set(model.session.tracks.map(\.id))) }
                Button("FIND") { model.findInPlaylist() }.accessibilityLabel("Search playlist")
                Spacer(); Text(model.importing ? "READING…" : "\(model.session.tracks.count) TRACKS").font(palette.font("ui", 8)).foregroundStyle(palette.panelAccent)
            }.buttonStyle(RetroButton()).padding(.trailing, 9)   // room for the size grip
        }.frame(width: 275).frame(maxHeight: .infinity)
    }
    /// The field only exists after the next render, and the window must be key to accept typing.
    private func focusSearch() {
        DispatchQueue.main.async {
            windows.panels[.playlist]?.makeKeyAndOrderFront(nil)
            searchFocused = true
        }
    }
    private func closeSearch(_ scroller: ScrollViewProxy) {
        query = ""; searching = false; searchFocused = false
        if let id = model.session.selected { DispatchQueue.main.async { scroller.scrollTo(id, anchor: .center) } }
    }
}
struct EqualizerView: View {
    @ObservedObject var model: Model
    var windows: Windows
    let labels = ["31","62","125","250","500","1K","2K","4K","8K","16K"]
    @Environment(\.palette) private var palette
    var body: some View {
        Chrome(title: "Mac-Amp • EQUALIZER", close: { windows.toggle(.equalizer) }, slot: "equalizer") {
            HStack {
                Button(model.session.eqEnabled ? "ON ●" : "OFF") { model.session.eqEnabled.toggle(); model.changed() }
                Button("FLAT") { model.session.bands = Array(repeating: 0, count: 10); model.session.preamp = 0; model.changed() }
                Spacer(); Text("±12 dB").font(palette.font("ui", 7)).foregroundStyle(palette.panelAccent)
            }.buttonStyle(RetroButton())
            HStack(spacing: 2) {
                fader("PRE", value: $model.session.preamp).help("Preamp automatically reserves headroom for EQ boosts. Applied gain: \(Int(model.session.safePreamp)) dB")
                Rectangle().fill(palette.border).frame(width: 1)
                ForEach(0..<10) { i in fader(labels[i], value: $model.session.bands[i]) }
            }
        }.frame(width: 275, height: 116)
    }
    func fader(_ name: String, value: Binding<Float>) -> some View {
        VStack(spacing: 0) {
            Text(String(format: "%.0f", value.wrappedValue)).font(palette.font("ui", 6)).foregroundStyle(palette.panelAccent)
            GeometryReader { proxy in
                ZStack {
                    Rectangle().fill(palette.displayBackground).frame(width: 3)
                    Rectangle().fill(palette.border).frame(height: 1)
                    Rectangle().fill(palette.knob).frame(width: 15, height: 6).offset(y: -CGFloat(value.wrappedValue / 12) * (proxy.size.height - 6) / 2)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { event in value.wrappedValue = Float(max(-12, min(12, (0.5 - event.location.y / proxy.size.height) * 24))); model.changed() })
            }.accessibilityElement().accessibilityLabel("\(name) gain").accessibilityValue("\(Int(value.wrappedValue)) decibels")
                .accessibilityAdjustableAction { direction in value.wrappedValue = max(-12,min(12,value.wrappedValue + (direction == .increment ? 1 : -1))); model.changed() }
            Text(name).font(palette.font("ui", 6))
        }.frame(maxWidth: .infinity)
    }
}
