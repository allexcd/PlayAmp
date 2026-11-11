import XCTest
@testable import PlayAmpCore
final class SessionTests: XCTestCase {
    func testQueueBoundariesAndRepeat() {
        var s = Session(); s.tracks = [Track(url: URL(filePath: "/a.wav")), Track(url: URL(filePath: "/b.opus"))]
        XCTAssertEqual(s.next(after: s.tracks[0].id, automatic: true), s.tracks[1].id)
        XCTAssertNil(s.next(after: s.tracks[1].id, automatic: true))
        s.repeatMode = .all; XCTAssertEqual(s.next(after: s.tracks[1].id, automatic: true), s.tracks[0].id)
        s.repeatMode = .one; XCTAssertEqual(s.next(after: s.tracks[0].id, automatic: true), s.tracks[0].id)
        s.tracks = []; XCTAssertNil(s.next(after: nil))
    }
    func testShuffleFinishesWithoutRepeating() {
        var s = Session(); s.tracks = (0..<5).map { Track(url: URL(filePath: "/track\($0).wav")) }; s.shuffle = true
        var current = s.tracks.first!.id; var visited: Set<UUID> = [current]
        while let next = s.next(after: current, automatic: true) { XCTAssertTrue(visited.insert(next).inserted); current = next }
        XCTAssertEqual(visited.count, 5)
        s.repeatMode = .all; XCTAssertNotNil(s.next(after: current, automatic: true))
    }
    func testPersistenceAndHeadroom() throws {
        var s = Session(); s.tracks = [Track(url: URL(filePath: "/music/a.opus"), bookmark: Data([1,2]))]; s.selected = s.tracks[0].id; s.position = 42; s.bands[4] = 8
        XCTAssertEqual(s.safePreamp, -8)
        s.bands[5] = 4; s.preamp = 12; XCTAssertEqual(s.safePreamp, -12)
        s.preamp = -15; XCTAssertEqual(s.safePreamp, -15)
        s.bands[5] = 0; s.preamp = 0
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("session.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try SessionStore.save(s, to: url)
        let restored = SessionStore.load(from: url)
        XCTAssertEqual(restored.tracks, s.tracks); XCTAssertEqual(restored.selected, s.selected); XCTAssertEqual(restored.position, 42)
        XCTAssertTrue(SessionStore.load(from: url.appendingPathComponent("missing")).tracks.isEmpty)
    }
}
