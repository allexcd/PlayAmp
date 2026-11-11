import AppKit
import SwiftUI
#if canImport(MacAmpCore)
import MacAmpCore
#endif

@MainActor final class Windows: NSObject, NSWindowDelegate {
    enum Panel: String { case player, playlist, equalizer, skins }
    let model: Model
    var panels: [Panel: NSWindow] = [:]
    init(model: Model) { self.model = model; super.init() }
    func show() {
        make(.player, size: NSSize(width: 275,height: 116), origin: NSPoint(x: 240,y: 600))
        make(.equalizer, size: NSSize(width: 275,height: 116), origin: NSPoint(x: 240,y: 474))
        make(.playlist, size: NSSize(width: 275,height: 245), origin: NSPoint(x: 240,y: 219))
        let skinsSaved = UserDefaults.standard.string(forKey: "NSWindow Frame MacAmp.skins") != nil
        make(.skins, size: NSSize(width: 275,height: Self.skinsHeight), origin: NSPoint(x: 515,y: 600))
        if !skinsSaved { placeBesidePlayer(.skins) }
        panels[.player]?.makeKeyAndOrderFront(nil)
        if !model.session.eqVisible { panels[.equalizer]?.orderOut(nil) }
        if !model.session.playlistVisible { panels[.playlist]?.orderOut(nil) }
        if model.session.skinsVisible != true { panels[.skins]?.orderOut(nil) }
    }
    static let skinsHeight: CGFloat = 174
    /// Panels whose height the user can drag, with their default and smallest heights.
    static let resizable: [Panel: (standard: CGFloat, minimum: CGFloat)] = [.playlist: (245, 116), .skins: (skinsHeight, 96)]
    func height(of panel: Panel) -> CGFloat {
        guard let limits = Self.resizable[panel] else { return 116 }
        let saved = panel == .playlist ? model.session.playlistHeight : model.session.skinsHeight
        guard let saved, saved.isFinite else { return limits.standard }
        return min(2000, max(limits.minimum, CGFloat(saved)))
    }
    /// Drags the bottom edge of the playlist or skins panel. The top stays put, and panels
    /// docked below it (directly or through each other) move with the bottom edge.
    func resize(_ panel: Panel, with event: NSEvent) {
        guard let window = panels[panel], let limits = Self.resizable[panel] else { return }
        let scale = model.session.scale
        let start = window.frame, mouseStart = NSEvent.mouseLocation
        let others = panels.filter { $0.key != panel && $0.value.isVisible }.mapValues(\.frame)
        var below: [Panel: CGRect] = [:], edges = [start]
        while let (next, frame) = others.first(where: { item in below[item.key] == nil && item.value.maxY <= start.minY + 1
            && edges.contains { abs(item.value.maxY - $0.minY) <= 1 && item.value.maxX > $0.minX + 1 && item.value.minX < $0.maxX - 1 } }) {
            below[next] = frame; edges.append(frame)
        }
        let bottom = (window.screen ?? NSScreen.main)?.visibleFrame.minY ?? 0
        let lowest = below.values.map(\.minY).min().map { start.minY - $0 } ?? 0   // keep docked panels on screen
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let wanted = start.height + mouseStart.y - NSEvent.mouseLocation.y
            let height = max(limits.minimum * scale, min(wanted, start.maxY - bottom - lowest)).rounded()
            window.setFrame(CGRect(x: start.minX, y: start.maxY - height, width: start.width, height: height), display: true)
            let dy = start.height - height
            for (other, frame) in below { panels[other]?.setFrameOrigin(CGPoint(x: frame.minX, y: frame.minY - dy)) }
            if next.type == .leftMouseUp { break }
        }
        let saved = Double(window.frame.height / scale)
        if panel == .playlist { model.session.playlistHeight = saved } else { model.session.skinsHeight = saved }
        window.invalidateShadow(); saveFrames(); model.save()
    }
    /// Docks a panel against the player's right edge, top-aligned (used the first time it opens).
    func placeBesidePlayer(_ panel: Panel) {
        guard let player = panels[.player]?.frame, let window = panels[panel] else { return }
        window.setFrameOrigin(CGPoint(x: player.maxX, y: player.maxY - window.frame.height))
    }
    func useSkin(_ id: String) { model.useSkin(id); applySkin() }
    func make(_ panel: Panel, size: NSSize, origin: NSPoint) {
        let window = PlayerWindow(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .miniaturizable], backing: .buffered, defer: false)
        window.titleDrag = { [weak self] event in self?.drag(panel, with: event) }
        window.cornerDrag = { [weak self] event in self?.resize(panel, with: event) }
        window.title = "Mac-Amp \(panel.rawValue)"; window.isReleasedWhenClosed = false; window.isMovableByWindowBackground = false; window.delegate = self
        // Transparent so skins can round corners or draw non-rectangular players.
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.setFrameAutosaveName("MacAmp.\(panel.rawValue)")
        panels[panel] = window; update(panel); window.orderFront(nil)
    }
    func update(_ panel: Panel) {
        guard let window = panels[panel] else { return }
        let scale = model.session.scale
        // Layout players mark their own drag areas instead of a fixed title strip.
        (window as? PlayerWindow)?.titleDragHeight = panel == .player ? (model.palette.layout == nil ? 24 * scale : 0) : 18 * scale
        (window as? PlayerWindow)?.closeButtonWidth = 24 * scale
        (window as? PlayerWindow)?.gripSize = Self.resizable[panel] != nil ? 14 * scale : 0
        var width: CGFloat = 275, height: CGFloat
        switch panel {
        case .player: (width, height) = Self.playerSize(model.palette)
        case .playlist, .skins: height = self.height(of: panel)
        case .equalizer: height = 116
        }
        let size = NSSize(width: width, height: height)
        let view: AnyView
        switch panel {
        case .player: view = AnyView(PlayerView(model: model, live: model.live, windows: self))
        case .playlist: view = AnyView(PlaylistView(model: model, windows: self))
        case .equalizer: view = AnyView(EqualizerView(model: model, windows: self))
        case .skins: view = AnyView(SkinsView(model: model, windows: self))
        }
        // The content follows the window's size, so a live resize needs no rebuild.
        let model = self.model
        let host = NSHostingView(rootView: GeometryReader { proxy in
            Themed(model: model, content: view).frame(width: proxy.size.width / scale, height: proxy.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
        })
        host.sizingOptions = []
        window.contentView = host
        let top = window.frame.maxY; window.setContentSize(NSSize(width: size.width * scale,height: size.height * scale)); window.setFrameOrigin(NSPoint(x: window.frame.minX,y: top - window.frame.height))
        window.invalidateShadow()
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: max(visible.minX,min(window.frame.minX,visible.maxX - window.frame.width)), y: max(visible.minY,min(window.frame.minY,visible.maxY - window.frame.height))))
        }
    }
    /// The cassette face is taller; everything else keeps the classic 116 pt player.
    static func playerHeight(_ face: Skin.Face) -> CGFloat { face == .cassette ? 179 : 116 }
    /// A layout skin sets its own size; built-in faces are 275 wide.
    static func playerSize(_ palette: Palette) -> (CGFloat, CGFloat) {
        if let layout = palette.layout { return (CGFloat(layout.width), CGFloat(layout.height)) }
        return (275, playerHeight(palette.face))
    }
    /// Re-renders every window with the current skin. The player keeps its top edge, so panels
    /// docked below it (directly or through another panel) shift by the change in its height.
    func applySkin() {
        let old = panels.mapValues(\.frame)
        let connected = WindowDocking.connected(to: Panel.player.rawValue, frames: Dictionary(uniqueKeysWithValues: old.map { ($0.key.rawValue, $0.value) }))
        // Windows restyle themselves (see Themed), so their state such as scroll positions survives.
        // Only the player is rebuilt, because a skin can change its size and drag areas.
        update(.player)
        DispatchQueue.main.async { for window in self.panels.values { window.invalidateShadow() } }   // rounded corners may change
        if let before = old[.player], let after = panels[.player]?.frame, before.size != after.size {
            // Keep docked panels attached: those below move with the bottom edge, those to the right with the right edge.
            let down = after.height - before.height, right = after.width - before.width
            for (panel, frame) in old where panel != .player && connected.contains(panel.rawValue) {
                let dy = frame.maxY <= before.minY + 1 ? -down : 0
                let dx = frame.minX >= before.maxX - 1 ? right : 0
                if dx != 0 || dy != 0 { panels[panel]?.setFrameOrigin(CGPoint(x: frame.minX + dx, y: frame.minY + dy)) }
            }
        }
        saveFrames()
    }
    func scale(_ value: Double) {
        let old = panels.mapValues(\.frame)
        let connected = WindowDocking.connected(to: Panel.player.rawValue, frames: Dictionary(uniqueKeysWithValues: old.map { ($0.key.rawValue, $0.value) }))
        let ratio = value / model.session.scale
        model.session.scale = value
        for panel in panels.keys { update(panel) }
        if let anchor = panels[.player]?.frame.origin, let original = old[.player]?.origin {
            for (panel, frame) in old where panel != .player && connected.contains(panel.rawValue) {
                panels[panel]?.setFrameOrigin(CGPoint(x: anchor.x + (frame.minX-original.x)*ratio, y: anchor.y + (frame.minY-original.y)*ratio))
            }
        }
        saveFrames(); model.save()
    }
    /// Moves windows ourselves instead of via AppKit's window-server drag, so attached
    /// panels follow every mouse step. While dragging, a window snaps to other panels' edges
    /// (the player to loose panels, which then become attached) and then to screen edges,
    /// and the group is never pushed under the menu bar.
    func drag(_ panel: Panel, with event: NSEvent) {
        guard let window = panels[panel], let origin = panels[panel]?.frame.origin else { return }
        let start = panels.mapValues(\.frame)
        var followers: [Panel] = []
        if panel == .player {
            let connected = WindowDocking.connected(to: panel.rawValue, frames: Dictionary(uniqueKeysWithValues: start.map { ($0.key.rawValue, $0.value) }))
            followers = panels.keys.filter { $0 != panel && connected.contains($0.rawValue) }
        }
        let targets = panels.filter { $0.key != panel && !followers.contains($0.key) && $0.value.isVisible }.map(\.value.frame)
        let groupStart = ([panel] + followers.filter { panels[$0]?.isVisible == true }).compactMap { start[$0] }.reduce(CGRect.null) { $0.union($1) }
        let snapDistance = max(24, 12 * model.session.scale)
        for follower in followers where panels[follower]?.isVisible == true { panels[follower]?.orderFront(nil) }
        window.makeKeyAndOrderFront(nil)
        let mouseStart = NSEvent.mouseLocation
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let mouse = NSEvent.mouseLocation
            let raw = CGRect(origin: CGPoint(x: origin.x + mouse.x - mouseStart.x, y: origin.y + mouse.y - mouseStart.y), size: window.frame.size)
            var frame = WindowDocking.snapped(raw, to: targets, distance: snapDistance)
            let bounds = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? window.screen ?? NSScreen.main)?.visibleFrame
            if let bounds {
                var group = groupStart.offsetBy(dx: frame.minX - origin.x, dy: frame.minY - origin.y)
                if frame == raw {
                    let edged = WindowDocking.snappedToEdges(group, in: bounds, distance: snapDistance)
                    frame = frame.offsetBy(dx: edged.minX - group.minX, dy: edged.minY - group.minY); group = edged
                }
                if group.maxY > bounds.maxY { frame.origin.y -= group.maxY - bounds.maxY }
            }
            window.setFrameOrigin(frame.origin)
            for follower in followers {
                guard let initial = start[follower] else { continue }
                panels[follower]?.setFrameOrigin(CGPoint(x: initial.minX + frame.minX - origin.x, y: initial.minY + frame.minY - origin.y))
            }
            if next.type == .leftMouseUp { break }
        }
        saveFrames()
    }
    private func saveFrames() {
        for (panel, window) in panels { window.saveFrame(usingName: "MacAmp.\(panel.rawValue)") }
    }
    func toggle(_ panel: Panel) {
        guard let window = panels[panel] else { return }
        if window.isVisible { window.orderOut(nil) } else { window.makeKeyAndOrderFront(nil) }
        model.session.eqVisible = panels[.equalizer]?.isVisible ?? false; model.session.playlistVisible = panels[.playlist]?.isVisible ?? false
        model.session.skinsVisible = panels[.skins]?.isVisible ?? false; model.save()
    }
}
/// Supplies the current skin to a window's views and restyles them live when the skin changes.
struct Themed: View {
    @ObservedObject var model: Model
    let content: AnyView
    var body: some View { content.environment(\.palette, model.palette) }
}
final class PlayerWindow: NSWindow {
    var titleDragHeight: CGFloat = 24
    var closeButtonWidth: CGFloat = 24
    var gripSize: CGFloat = 0
    var cornerDrag: ((NSEvent) -> Void)?
    override func sendEvent(_ event: NSEvent) {
        let point = event.locationInWindow
        if event.type == .leftMouseDown, gripSize > 0, point.x >= frame.width - gripSize, point.y <= gripSize {
            cornerDrag?(event)
            return
        }
        if event.type == .leftMouseDown, titleDragHeight > 0, point.y >= frame.height - titleDragHeight,
           point.x >= 0, point.x < frame.width - closeButtonWidth {
            titleDrag?(event)
            return
        }
        super.sendEvent(event)
    }
    var titleDrag: ((NSEvent) -> Void)?
    override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { true } }
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    var model: Model!
    var windows: Windows!
    var notch: NotchController!
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set the Dock icon directly so a stale LaunchServices cache can't show the generic one.
        if let icon = Bundle.main.image(forResource: "AppIcon") { NSApp.applicationIconImage = icon }
        model = Model()
        // Safe start: holding Option while Mac-Amp opens goes back to the Classic skin,
        // in case a skin from somewhere else misbehaves.
        if NSEvent.modifierFlags.contains(.option) { model.useSkin(Skin.classic.id) }
        windows = Windows(model: model); windows.show(); notch = NotchController(model: model, windows: windows); menus(); menuNeedsUpdate(NSApp.mainMenu!.items.first { $0.submenu?.title == "Skins" }!.submenu!); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) { model.save() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { windows.panels[.player]?.makeKeyAndOrderFront(nil); return true }
    func application(_ sender: NSApplication, openFiles filenames: [String]) { model.add(filenames.map { URL(filePath: $0) }); sender.reply(toOpenOrPrint: .success) }
    func menus() {
        let main = NSMenu(); NSApp.mainMenu = main
        func menu(_ name: String) -> NSMenu { let item = NSMenuItem(); let sub = NSMenu(title: name); item.submenu = sub; main.addItem(item); return sub }
        func item(_ menu: NSMenu, _ name: String, _ action: Selector, _ key: String = "", modifiers: NSEvent.ModifierFlags = .command) { let i = NSMenuItem(title: name,action: action,keyEquivalent: key); i.target = self; i.keyEquivalentModifierMask = modifiers; menu.addItem(i) }
        let app = menu("Mac-Amp"); item(app,"About Mac-Amp",#selector(about)); app.addItem(.separator()); item(app,"Hide Mac-Amp",#selector(hide),"h"); item(app,"Quit Mac-Amp",#selector(quit),"q")
        let file = menu("File"); item(file,"Add Files or Folders…",#selector(add),"o")
        let edit = menu("Edit")
        for (name, action, key) in [("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] { edit.addItem(NSMenuItem(title: name, action: action, keyEquivalent: key)) }
        item(edit, "Find in Playlist…", #selector(find), "f"); item(edit, "Jump to Track…", #selector(find), "j", modifiers: [])
        let playback = menu("Playback"); item(playback,"Play / Pause",#selector(toggle)," ",modifiers: []); item(playback,"Stop",#selector(stop),"."); item(playback,"Next",#selector(next),"]"); item(playback,"Previous",#selector(previous),"[")
        let view = menu("View"); item(view,"Playlist",#selector(playlist),"l"); item(view,"Equalizer",#selector(eq),"e")
        for scale in 1...3 { let i = NSMenuItem(title: "\(scale)× Size",action: #selector(resize(_:)),keyEquivalent: "\(scale)"); i.target = self; i.tag = scale; view.addItem(i) }
        view.addItem(.separator())
        let notchItem = NSMenuItem(title: "Notch Player", action: #selector(toggleNotch(_:)), keyEquivalent: ""); notchItem.target = self
        notchItem.state = notch.enabled ? .on : .off; view.addItem(notchItem)
        let skins = menu("Skins"); skins.delegate = self   // rebuilt from disk each time it opens
        let window = menu("Window"); NSApp.windowsMenu = window; item(window,"Minimize Player",#selector(minimize),"m"); item(window,"Show Player",#selector(showPlayer),"0")
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "Skins" else { return }
        model.reloadSkins(); menu.removeAllItems()
        for (index, skin) in model.skins.enumerated() {
            if index == Skin.builtIn.count { menu.addItem(.separator()) }
            let item = NSMenuItem(title: skin.name, action: #selector(chooseSkin(_:)), keyEquivalent: index < 9 ? "\(index + 1)" : "")
            item.keyEquivalentModifierMask = [.command, .option]
            item.target = self; item.representedObject = skin.id; item.state = skin.id == model.skin.id ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let panel = NSMenuItem(title: "Skins Panel", action: #selector(skinsPanel), keyEquivalent: "k"); panel.target = self; menu.addItem(panel)
        let open = NSMenuItem(title: "Open Skins Folder", action: #selector(openSkins), keyEquivalent: ""); open.target = self; menu.addItem(open)
    }
    @objc func chooseSkin(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        windows.useSkin(id)
    }
    @objc func toggleNotch(_ sender: NSMenuItem) { notch.enabled.toggle(); sender.state = notch.enabled ? .on : .off }
    @objc func skinsPanel() { windows.toggle(.skins) }
    @objc func openSkins() { NSWorkspace.shared.open(model.prepareSkinFolder()) }
    /// Plain-key shortcuts (Space, J) step aside while a text field is being edited.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        !(menuItem.keyEquivalentModifierMask.isEmpty && !menuItem.keyEquivalent.isEmpty && NSApp.keyWindow?.firstResponder is NSTextView)
    }
    @objc func find() {
        if windows.panels[.playlist]?.isVisible != true { windows.toggle(.playlist) }
        windows.panels[.playlist]?.makeKeyAndOrderFront(nil); model.findInPlaylist()
    }
    @objc func minimize() { windows.panels[.player]?.miniaturize(nil) }
    @objc func showPlayer() { windows.panels[.player]?.deminiaturize(nil); windows.panels[.player]?.makeKeyAndOrderFront(nil) }
    @objc func add() { model.choose() }; @objc func toggle() { model.toggle() }; @objc func stop() { model.stop() }
    @objc func next() { model.advance() }; @objc func previous() { model.advance(backwards: true) }
    @objc func playlist() { windows.toggle(.playlist) }; @objc func eq() { windows.toggle(.equalizer) }
    @objc func resize(_ sender: NSMenuItem) { windows.scale(Double(sender.tag)) }
    @objc func hide() { NSApp.hide(nil) }; @objc func quit() { NSApp.terminate(nil) }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName:"Mac-Amp", .applicationVersion:"0.3.2", .credits:NSAttributedString(string:"Local music. Familiar little windows.\nOriginal retro artwork. Audio powered by SFBAudioEngine.\nSee THIRD_PARTY_NOTICES.md in the app resources.")]) }
}
@main struct MacAmpApp {
    @MainActor static func main() {
        if let code = SkinTool.run(CommandLine.arguments) { exit(code) }   // --validate-skin, --render-skin, --skin-reference
        let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.regular); app.run(); withExtendedLifetime(delegate) {}
    }
}
