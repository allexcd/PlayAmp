import AppKit
import SwiftUI
import AVFoundation
import SFBAudioEngine
import MediaPlayer
#if canImport(PlayAmpCore)
import PlayAmpCore
#endif

/// Values that change many times a second. Only the player window observes this,
/// so the playlist and equalizer don't redraw on every timer tick.
@MainActor final class LiveState: ObservableObject {
    @Published var playing = false
    @Published var duration: Double = 0
    @Published var position: Double = 0 { didSet { positionDate = Date() } }
    /// When `position` last changed; lets animations extrapolate smoothly between updates.
    var positionDate = Date()
}

@MainActor final class Model: ObservableObject {
    @Published var session: Session
    @Published var searchToken = 0
    @Published var skins: [Skin] = Skin.builtIn
    @Published private(set) var skin = Skin.classic
    @Published private(set) var palette = Palette.classic
    /// True while a track is loaded (playing or paused).
    var isLoaded: Bool { loaded != nil || previewLoaded }
    private var previewLoaded = false
    private(set) var isPreview = false
    private var previewBars: [Float]?
    /// User skins live in the app's (sandboxed) Application Support folder.
    let skinFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PlayAmp/Skins")
    let live = LiveState()
    // Forwarders only publish real changes, so an idle player triggers no redraws.
    var playing: Bool { get { live.playing } set { if live.playing != newValue { live.playing = newValue } } }
    var duration: Double { get { live.duration } set { if live.duration != newValue { live.duration = newValue } } }
    var position: Double { get { live.position } set { if live.position != newValue { live.position = newValue } } }
    private static let silent = Array(repeating: Float(0), count: 20)
    private var pendingSave: DispatchWorkItem?
    private var nowPlayingKey = ""
    @Published var message: String?
    @Published var remaining = false
    @Published var importing = false
    let audio = Playback()
    private var timer: Timer?
    private var scopes: [URL] = []
    private var failed = Set<UUID>()
    private var loaded: UUID?
    private var pendingSeek: Double?
    private var ticks = 0
    private let stateURL: URL
    var current: Track? { session.tracks.first { $0.id == session.selected } }
    init(stateURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PlayAmp/session.json")) {
        self.stateURL = stateURL
        session = SessionStore.load(from: stateURL)
        session.scale = [1,2,3].contains(session.scale) ? session.scale : 1
        if session.bands.count != 10 { session.bands = Array(repeating: 0, count: 10) }
        position = session.position
        audio.apply(session)
        reloadSkins()
        audio.onEnd = { [weak self] in self?.advance(automatic: true) }
        audio.onError = { [weak self] error in self?.handleFailure(error) }
        setUpRemoteCommands()
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    func tick() {
        playing = audio.player.isPlaying
        if let value = audio.player.totalTime, value.isFinite { duration = value }
        if let target = pendingSeek, audio.player.supportsSeeking { _ = audio.player.seek(time: target); pendingSeek = nil }
        if loaded != nil, pendingSeek == nil, let value = audio.player.currentTime, value.isFinite { position = value }
        ticks += 1; if playing && ticks % 50 == 0 { save() }
        let key = "\(loaded?.uuidString ?? "-")|\(playing)|\(Int(duration))"
        if key != nowPlayingKey { nowPlayingKey = key; updateNowPlaying() }
    }
    func save() {
        pendingSave?.cancel(); pendingSave = nil
        if session.position != position { session.position = position }
        do { try SessionStore.save(session, to: stateURL) } catch { message = "Could not save session: \(error.localizedDescription)" } }
    /// Sliders call this on every drag step: apply the sound now, write to disk once they settle.
    func changed() {
        audio.apply(session)
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    func pause() { if audio.player.isPlaying { _ = audio.player.pause() } }
    func toggle() {
        if audio.player.isPlaying { _ = audio.player.pause() }
        else if audio.player.isPaused { _ = audio.player.resume() }
        else if let id = session.selected ?? session.tracks.first?.id { play(id, resume: true) }
        else { choose() }
    }
    func play(_ id: UUID, resume: Bool = false, recovery: Bool = false) {
        guard let track = session.tracks.first(where: { $0.id == id }) else { return }
        if !recovery { failed.removeAll() }
        audio.player.stop(); releaseScopes(); loaded = nil
        session.selected = id
        let target = resume ? position : 0
        do {
            var url = track.url
            if let data = track.bookmark {
                var stale = false
                let root = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
                if root.startAccessingSecurityScopedResource() { scopes.append(root) }
                url = track.relativePath.map { root.appendingPathComponent($0) } ?? root
                if stale, let index = session.tracks.firstIndex(where: { $0.id == id }) {
                    session.tracks[index].bookmark = try root.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
                }
            }
            guard FileManager.default.isReadableFile(atPath: url.path) else { throw CocoaError(.fileReadNoPermission) }
            if url.pathExtension.lowercased() == "aac" {
                let decoder = try AudioDecoder(url: url, decoderName: .coreAudio)
                try audio.player.play(decoder)
            } else { try audio.player.play(url) }
            loaded = id; pendingSeek = target; position = target; duration = 0; save()
        } catch { handleFailure("\(track.title): \(error.localizedDescription)") }
    }
    func handleFailure(_ error: String) {
        message = error
        guard let id = session.selected, failed.insert(id).inserted else { return }
        audio.player.stop(); loaded = nil; pendingSeek = nil
        let count = session.tracks.count
        let start = session.tracks.firstIndex(where: { $0.id == id }) ?? 0
        let candidates = session.tracks.indices.map { session.tracks[(start + 1 + $0) % count] }
        if let next = candidates.first(where: { !failed.contains($0.id) }) {
            Task { @MainActor [weak self] in
                guard let self, self.session.selected == id, self.failed.contains(id) else { return }
                self.play(next.id, recovery: true)
            }
        } else { stop() }
    }
    func releaseScopes() { for url in scopes { url.stopAccessingSecurityScopedResource() }; scopes.removeAll() }
    func stop() { audio.player.stop(); releaseScopes(); loaded = nil; pendingSeek = nil; position = 0; playing = false; save() }
    func advance(automatic: Bool = false, backwards: Bool = false) {
        if let id = session.next(after: session.selected, backwards: backwards, automatic: automatic) { play(id) } else { stop() }
    }
    func seek(_ value: Double) { position = value; if loaded != nil { _ = audio.player.seek(time: value) }; changed(); updateNowPlaying() }
    func findInPlaylist() { searchToken += 1 }
    /// Spectrum levels for the current display frame (silent unless playing).
    func spectrumNow() -> [Float] { if let previewBars { return previewBars }; return audio.player.isPlaying ? audio.spectrum.read(at: ProcessInfo.processInfo.systemUptime) : Self.silent }

    // MARK: Skins
    func reloadSkins() {
        skins = SkinLibrary.all(in: skinFolder)
        let resolved = SkinLibrary.resolved(session.skin, in: skins)
        if resolved != skin || palette.name != resolved.name { skin = resolved; palette = Palette(resolved) }
    }
    /// Re-reads skin files, images and fonts from disk (after editing a skin).
    func refreshSkins() { SkinImage.clearCache(); skin = Skin.classic; reloadSkins() }
    /// Puts the model in a fixed state for `--render-skin` previews (no audio is played).
    func preview(skin: Skin, state: String, progress: Double, duration: Double) {
        self.skin = skin; palette = Palette(skin); isPreview = true
        previewLoaded = state != "stopped"
        live.duration = duration
        position = state == "stopped" ? 0 : progress * duration
        live.playing = state == "playing"
        previewBars = state == "playing" ? (0..<Spectrum.bands).map { i in Float(max(0.1, 0.82 - Double(i) * 0.028 + [0.1, -0.06, 0.04, -0.02][i % 4])) } : nil
    }
    func toggleShuffle() { session.shuffle.toggle(); session.shuffleOrder = nil; save() }
    func cycleRepeat() {
        let modes = RepeatMode.allCases
        session.repeatMode = modes[(modes.firstIndex(of: session.repeatMode)! + 1) % modes.count]; save()
    }
    func useSkin(_ id: String) { session.skin = id; reloadSkins(); save() }
    /// Creates the folder with a README and an example skin the first time, then returns it.
    func prepareSkinFolder() -> URL {
        let manager = FileManager.default
        try? manager.createDirectory(at: skinFolder, withIntermediateDirectories: true)
        let readme = skinFolder.appendingPathComponent("README.txt"), example = skinFolder.appendingPathComponent("Example.json")
        if !manager.fileExists(atPath: readme.path) { try? SkinLibrary.readme().write(to: readme, atomically: true, encoding: .utf8) }
        if !manager.fileExists(atPath: example.path) { try? SkinLibrary.exampleJSON().write(to: example, atomically: true, encoding: .utf8) }
        // Example skins bundled with the app (VU Radio, Walnut Turntable, Midnight Tape); never overwrite edits.
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("SkinExamples"),
           let items = try? manager.contentsOfDirectory(at: bundled, includingPropertiesForKeys: nil) {
            for item in items where !manager.fileExists(atPath: skinFolder.appendingPathComponent(item.lastPathComponent).path) {
                try? manager.copyItem(at: item, to: skinFolder.appendingPathComponent(item.lastPathComponent))
            }
        }
        return skinFolder
    }

    // MARK: Media keys, Control Center and the Now Playing widget
    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        func on(_ command: MPRemoteCommand, _ action: @escaping @MainActor (Model) -> Void) {
            command.isEnabled = true
            command.addTarget { [weak self] _ in
                guard let self else { return .commandFailed }
                Task { @MainActor in action(self) }
                return .success
            }
        }
        on(center.togglePlayPauseCommand) { $0.toggle() }
        on(center.playCommand) { if !$0.audio.player.isPlaying { $0.toggle() } }
        on(center.pauseCommand) { $0.pause() }
        on(center.stopCommand) { $0.stop() }
        on(center.nextTrackCommand) { $0.advance() }
        on(center.previousTrackCommand) { $0.advance(backwards: true) }
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            Task { @MainActor in self?.seek(time) }
            return .success
        }
    }
    func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard loaded != nil, let track = current else {
            center.nowPlayingInfo = nil; center.playbackState = .stopped; return
        }
        let parts = track.title.components(separatedBy: " — ")
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: parts.count > 1 ? parts.dropFirst().joined(separator: " — ") : track.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if parts.count > 1 { info[MPMediaItemPropertyArtist] = parts[0] }
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let icon = NSApp?.applicationIconImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: icon.size) { _ in icon }
        }
        center.nowPlayingInfo = info
        center.playbackState = playing ? .playing : .paused
    }
    func remove(_ ids: Set<UUID>) {
        if let selected = session.selected, ids.contains(selected) { stop(); session.selected = nil }
        session.tracks.removeAll { ids.contains($0.id) }; save()
    }
    func choose() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.message = "Add local music files or folders"
        panel.begin { result in if result == .OK { self.add(panel.urls) } }
    }
    nonisolated static func scan(_ root: URL) -> [URL] {
        var files: [URL] = []
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey,.isSymbolicLinkKey], options: [.skipsHiddenFiles,.skipsPackageDescendants]) {
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey,.isRegularFileKey])
                if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if values?.isRegularFile == true { files.append(url) }
            }
        }
        return files
    }
    func add(_ urls: [URL]) {
        importing = true
        Task {
            let tracks = await Task.detached(priority: .userInitiated) { () -> [Track] in
                var result: [Track] = []
                let extensions: Set<String> = ["wav","mp3","opus","flac","m4a","aac","aif","aiff","ogg"]
                for root in urls {
                    let access = root.startAccessingSecurityScopedResource(); defer { if access { root.stopAccessingSecurityScopedResource() } }
                    let bookmark = try? root.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
                    let info = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard info?.isSymbolicLink != true else { continue }
                    var files = [root]
                    if info?.isDirectory == true {
                        files = []
                        files = Self.scan(root)
                    }
                    for url in files.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) where extensions.contains(url.pathExtension.lowercased()) {
                        var title = url.deletingPathExtension().lastPathComponent
                        let metadata = (try? await AVURLAsset(url: url).load(.commonMetadata)) ?? []
                        var artist: String?; var name: String?
                        for item in metadata {
                            if item.commonKey == .commonKeyTitle { name = try? await item.load(.stringValue) }
                            if item.commonKey == .commonKeyArtist { artist = try? await item.load(.stringValue) }
                        }
                        if let name { title = artist.map { "\($0) — \(name)" } ?? name }
                        result.append(Track(url: url, title: title, bookmark: bookmark, relativePath: info?.isDirectory == true ? String(url.path.dropFirst(root.path.count + 1)) : nil))
                    }
                }
                return result
            }.value
            let existing = Set(session.tracks.map(\.url)); session.tracks.append(contentsOf: tracks.filter { !existing.contains($0.url) })
            if session.selected == nil { session.selected = session.tracks.first?.id }
            importing = false; if tracks.isEmpty { message = "No supported audio files found." }; save()
        }
    }
}
