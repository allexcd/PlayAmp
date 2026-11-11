import Foundation
public struct Track: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var url: URL
    public var title: String
    public var bookmark: Data?
    public var relativePath: String?
    public init(url: URL, title: String? = nil, bookmark: Data? = nil, relativePath: String? = nil) { self.url = url; self.title = title ?? url.deletingPathExtension().lastPathComponent; self.bookmark = bookmark; self.relativePath = relativePath }
}
public enum RepeatMode: String, Codable, CaseIterable { case off, all, one }
public struct Session: Codable {
    public var tracks: [Track] = []
    public var selected: UUID?
    public var position: Double = 0
    public var volume: Float = 0.65
    public var balance: Float = 0
    public var bands: [Float] = Array(repeating: 0, count: 10)
    public var preamp: Float = 0
    public var eqEnabled = true
    public var shuffle = false
    public var shuffleOrder: [UUID]?
    public var repeatMode = RepeatMode.off
    public var scale: Double = 1
    public var playlistVisible = true
    public var eqVisible = true
    /// Optional so sessions saved before skins existed still decode.
    public var skin: String?
    public var skinsVisible: Bool?
    /// Heights the user dragged the playlist and skins panel to (unscaled points); nil = default.
    public var playlistHeight: Double?
    public var skinsHeight: Double?
    public init() {}
    public mutating func next(after id: UUID?, backwards: Bool = false, automatic: Bool = false) -> UUID? {
        guard !tracks.isEmpty else { return nil }
        guard let id, let index = tracks.firstIndex(where: { $0.id == id }) else { return tracks.first?.id }
        if automatic && repeatMode == .one { return id }
        if shuffle {
            let valid = Set(tracks.map(\.id))
            var order = (shuffleOrder ?? []).filter { valid.contains($0) }
            if !order.contains(id) { order = [id] + tracks.map(\.id).filter { $0 != id }.shuffled() }
            else { order.append(contentsOf: tracks.map(\.id).filter { !order.contains($0) }.shuffled()) }
            let current = order.firstIndex(of: id) ?? 0
            let target = current + (backwards ? -1 : 1)
            shuffleOrder = order
            if order.indices.contains(target) { return order[target] }
            if automatic && repeatMode == .off { return nil }
            if backwards { return order.last }
            order = [id] + tracks.map(\.id).filter { $0 != id }.shuffled(); shuffleOrder = order
            return order.count > 1 ? order[1] : id
        }
        let next = index + (backwards ? -1 : 1)
        if tracks.indices.contains(next) { return tracks[next].id }
        return repeatMode == .all || !automatic ? tracks[(next + tracks.count) % tracks.count].id : nil
    }
    public var safePreamp: Float { min(preamp, -bands.reduce(0) { $0 + max(0, $1) }) }
}
public enum SessionStore {
    public static func load(from url: URL) -> Session { (try? JSONDecoder().decode(Session.self, from: Data(contentsOf: url))) ?? Session() }
    public static func save(_ session: Session, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: url, options: .atomic)
    }
}
