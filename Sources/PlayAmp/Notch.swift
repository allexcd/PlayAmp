import AppKit
import SwiftUI
#if canImport(PlayAmpCore)
import PlayAmpCore
#endif

/// Where the notch is. On a Mac without one (or with only external screens) a hover zone
/// at the top centre of the main screen stands in for it.
struct NotchGeometry: Equatable {
    var notch: CGRect = CGRect(x: 0, y: 0, width: 200, height: 32)   // global coordinates
    var hasNotch = true
    static let width: CGFloat = 380
    static let contentHeight: CGFloat = 96
    static let flare: CGFloat = 6   // the little outward curves where the panel meets the menu bar
    var collapsedWidth: CGFloat { notch.width + 2 * Self.flare }
    var expandedHeight: CGFloat { notch.height + Self.contentHeight }
    var collapsedFrame: CGRect { CGRect(x: notch.midX - collapsedWidth / 2, y: notch.maxY - notch.height, width: collapsedWidth, height: notch.height) }
    var expandedFrame: CGRect { CGRect(x: notch.midX - Self.width / 2, y: notch.maxY - expandedHeight, width: Self.width, height: expandedHeight) }

    static func current() -> NotchGeometry? {
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let frame = screen.frame, height = screen.safeAreaInsets.top
            let width = frame.width - left.width - right.width
            return NotchGeometry(notch: CGRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height), hasNotch: true)
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let frame = screen.frame
        let height = max(24, frame.maxY - screen.visibleFrame.maxY)
        return NotchGeometry(notch: CGRect(x: frame.midX - 100, y: frame.maxY - height, width: 200, height: height), hasNotch: false)
    }
}

@MainActor final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published var geometry = NotchGeometry()
}

/// A small player that drops out of the notch while the pointer rests on it.
@MainActor final class NotchController {
    static let enabledKey = "NotchPlayer"
    let model: Model
    let windows: Windows
    let state = NotchState()
    private var panel: NotchPanel?
    private var pendingOpen: DispatchWorkItem?
    private var pendingClose: DispatchWorkItem?
    private let spring = Animation.spring(response: 0.34, dampingFraction: 0.82)

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey); refresh() }
    }

    init(model: Model, windows: Windows) {
        self.model = model; self.windows = windows
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    /// Creates, moves or removes the panel to match the setting and the current screens.
    func refresh() {
        guard enabled, let geometry = NotchGeometry.current() else { panel?.orderOut(nil); panel = nil; return }
        pendingOpen?.cancel(); pendingClose?.cancel()
        state.geometry = geometry; state.expanded = false
        let panel = self.panel ?? makePanel()
        panel.setFrame(geometry.collapsedFrame, display: true)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel(contentRect: state.geometry.collapsedFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true   // before the level: this setter resets it
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)   // above the menu bar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.canHide = false   // stays when PlayAmp is hidden
        panel.isMovable = false; panel.isReleasedWhenClosed = false
        let host = NotchHostingView(rootView: AnyView(NotchRoot(state: state, model: model, showPlayer: { [weak self] in self?.showPlayer() })))
        host.sizingOptions = []   // the controller sizes the panel, not SwiftUI
        host.onEnter = { [weak self] in self?.pointerEntered() }
        host.onExit = { [weak self] in self?.pointerExited() }
        panel.contentView = host
        self.panel = panel
        return panel
    }

    private func pointerEntered() {
        pendingClose?.cancel(); pendingClose = nil
        guard !state.expanded, pendingOpen == nil else { return }
        // A short rest, so sweeping the pointer across the top of the screen doesn't open it.
        let work = DispatchWorkItem { [weak self] in self?.pendingOpen = nil; self?.open() }
        pendingOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func pointerExited() {
        pendingOpen?.cancel(); pendingOpen = nil
        guard state.expanded else { return }
        let work = DispatchWorkItem { [weak self] in self?.pendingClose = nil; self?.close() }
        pendingClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func open() {
        guard let panel, NSEvent.pressedMouseButtons == 0 else { return }   // not while dragging something
        panel.setFrame(state.geometry.expandedFrame, display: true)
        withAnimation(spring) { state.expanded = true }
    }

    func close() {
        withAnimation(spring) { state.expanded = false }
        // Shrink the panel once the animation is done, so it only covers the notch again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.state.expanded else { return }
            self.panel?.setFrame(self.state.geometry.collapsedFrame, display: true)
        }
    }

    func showPlayer() {
        NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true)
        windows.panels[.player]?.deminiaturize(nil)
        windows.panels[.player]?.makeKeyAndOrderFront(nil)
        close()
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // AppKit would otherwise push the panel down below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Reports the pointer entering and leaving, even though PlayAmp is usually not the active app.
final class NotchHostingView: NSHostingView<AnyView> {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var area: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); self.area = area
    }
    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The black shape: flush with the top of the screen, flaring into the menu bar, rounded below.
struct NotchShape: Shape {
    var top: CGFloat
    var bottom: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { top = newValue.first; bottom = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, b = min(bottom, (w - 2 * top) / 2, h - top)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: top, y: top), control: CGPoint(x: top, y: 0))
        p.addLine(to: CGPoint(x: top, y: h - b))
        p.addQuadCurve(to: CGPoint(x: top + b, y: h), control: CGPoint(x: top, y: h))
        p.addLine(to: CGPoint(x: w - top - b, y: h))
        p.addQuadCurve(to: CGPoint(x: w - top, y: h - b), control: CGPoint(x: w - top, y: h))
        p.addLine(to: CGPoint(x: w - top, y: top))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - top, y: 0))
        p.closeSubpath()
        return p
    }
}

struct NotchRoot: View {
    @ObservedObject var state: NotchState
    @ObservedObject var model: Model
    let showPlayer: () -> Void
    var body: some View {
        let geometry = state.geometry
        ZStack(alignment: .top) {
            NotchShape(top: NotchGeometry.flare, bottom: state.expanded ? 22 : 9)
                .fill(Color.black)
                .frame(width: state.expanded ? NotchGeometry.width : geometry.collapsedWidth,
                       height: state.expanded ? geometry.expandedHeight : geometry.notch.height)
                .opacity(state.expanded || geometry.hasNotch ? 1 : 0)   // no fake notch on screens without one
            if state.expanded {
                // Only this part watches playback, so the collapsed notch never redraws.
                NotchContent(model: model, live: model.live, showPlayer: showPlayer)
                    .frame(width: NotchGeometry.width - 2 * NotchGeometry.flare - 36, height: NotchGeometry.contentHeight - 8)
                    .padding(.top, geometry.notch.height + 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.palette, model.palette)
    }
}

struct NotchContent: View {
    @ObservedObject var model: Model
    @ObservedObject var live: LiveState
    let showPlayer: () -> Void
    @Environment(\.palette) private var palette
    var body: some View {
        let accent = palette.display
        let (title, artist) = Self.split(model.current?.title)
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                NotchDisc(spinning: live.playing, accent: accent).frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(artist).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 6)
                SpectrumBars(source: model.spectrumNow, active: live.playing, barWidth: 2, height: 20, gap: 1, showPeaks: false,
                             colors: [palette["spectrumHigh"], palette["spectrumMid"], accent])
            }
            HStack(spacing: 7) {
                Text(clock(live.position)).frame(width: 34, alignment: .leading)
                NotchSeekBar(position: live.position, duration: live.duration, accent: accent) { model.seek($0) }
                Text("-" + clock(max(0, live.duration - live.position))).frame(width: 38, alignment: .trailing)
            }.font(.system(size: 9, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 24) {
                NotchButton(symbol: "shuffle", size: 11, on: model.session.shuffle, accent: accent, help: "Shuffle") { model.toggleShuffle() }
                NotchButton(symbol: "backward.fill", size: 13, help: "Previous") { model.advance(backwards: true) }
                NotchButton(symbol: live.playing ? "pause.fill" : "play.fill", size: 18, help: live.playing ? "Pause" : "Play") {
                    if model.session.tracks.isEmpty { showPlayer(); model.choose() } else { model.toggle() }
                }
                NotchButton(symbol: "forward.fill", size: 13, help: "Next") { model.advance() }
                NotchButton(symbol: "macwindow", size: 12, help: "Show PlayAmp") { showPlayer() }
            }
        }
    }
    /// "Artist — Title" (or "Artist - Title") becomes a title line and an artist line.
    static func split(_ name: String?) -> (String, String) {
        guard let name, !name.isEmpty else { return ("PlayAmp", "Add music to the playlist") }
        for separator in [" — ", " – ", " - "] {
            if let range = name.range(of: separator) {
                return (String(name[range.upperBound...]), String(name[..<range.lowerBound]))
            }
        }
        return (name, "PlayAmp")
    }
}

/// A tiny record that turns while music plays.
struct NotchDisc: View {
    let spinning: Bool
    let accent: Color
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !spinning)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8 * 360
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(white: 0.22), Color(white: 0.08)], center: .center, startRadius: 2, endRadius: 15))
                ForEach([0.82, 0.66], id: \.self) { ring in Circle().stroke(Color.white.opacity(0.07), lineWidth: 0.6).scaleEffect(ring) }
                Circle().fill(accent).scaleEffect(0.36)
                Circle().fill(Color.white.opacity(0.85)).frame(width: 2.5, height: 2.5).offset(y: -3.2)
                Circle().fill(Color.black).frame(width: 2, height: 2)
            }.rotationEffect(.degrees(angle))
        }
    }
}

struct NotchSeekBar: View {
    let position: Double
    let duration: Double
    let accent: Color
    let seek: (Double) -> Void
    @State private var dragging: Double?
    var body: some View {
        GeometryReader { proxy in
            let fraction = dragging ?? (duration > 0 ? min(1, max(0, position / duration)) : 0)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule().fill(accent).frame(width: max(4, proxy.size.width * fraction))
            }
            .frame(height: dragging == nil ? 4 : 6).frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { dragging = min(1, max(0, $0.location.x / proxy.size.width)) }
                .onEnded { _ in if let value = dragging, duration > 0 { seek(value * duration) }; dragging = nil })
        }.frame(height: 12).opacity(duration > 0 ? 1 : 0.4).allowsHitTesting(duration > 0)
        .accessibilityLabel("Position")
    }
}

struct NotchButton: View {
    let symbol: String
    let size: CGFloat
    var on = false
    var accent: Color = .white
    let help: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                .foregroundStyle(on ? accent : .white.opacity(hovering ? 1 : 0.82))
                .frame(width: 26, height: 24)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }
        .help(help).accessibilityLabel(help)
    }
}
