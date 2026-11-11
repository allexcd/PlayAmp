import XCTest
import AVFoundation
import SFBAudioEngine
import PlayAmpCore
@testable import PlayAmp
final class PlaybackTests: XCTestCase {
    let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    @MainActor func testPlaybackPauseSeekResumeAndAnalysis() async throws {
        let audio = Playback(); var session = Session(); session.volume = 0.2
        audio.apply(session)
        for ext in ["wav","mp3","opus","flac","m4a","aiff","ogg","aac"] {
            let url = root.appendingPathComponent("Fixtures/tone.\(ext)")
            guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Generate fixtures first") }
            if ext == "aac" { try audio.player.play(AudioDecoder(url: url, decoderName: .coreAudio)) }
            else { try audio.player.play(url) }
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertTrue(audio.player.isPlaying, ext)
            XCTAssertGreaterThan(audio.player.totalTime ?? 0, 2.8, ext)
            XCTAssertTrue(audio.player.seek(time: 1), ext)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertGreaterThan(audio.player.currentTime ?? 0, 0.9, ext)
            XCTAssertTrue(audio.player.pause(), ext)
            let paused = audio.player.currentTime ?? 0
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(audio.player.currentTime ?? 0, paused, accuracy: 0.03, ext)
            XCTAssertTrue(audio.player.resume(), ext)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertTrue(audio.spectrum.read().contains { $0 > 0 }, ext)
            session.bands[4] = 6; session.preamp = 2; session.balance = -0.4; audio.apply(session)
            XCTAssertEqual(audio.eq.bands[4].gain, 6); XCTAssertLessThanOrEqual(audio.eq.globalGain, -4)
            XCTAssertEqual(audio.player.mainMixerNode.pan, -0.4, accuracy: 0.01)
            session.eqEnabled = false; audio.apply(session); XCTAssertTrue(audio.eq.bypass)
            session.eqEnabled = true; session.bands = Array(repeating: 0,count: 10); session.preamp = 0; audio.apply(session)
            XCTAssertEqual(audio.eq.globalGain, 0)
            audio.player.stop()
        }
    }
    @MainActor func testEndAdvancesMixedQueueAndStops() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        var session = Session(); session.volume = 0.1
        session.tracks = ["wav","opus","mp3"].map { Track(url: root.appendingPathComponent("Fixtures/tone.\($0)")) }
        session.selected = session.tracks[0].id; try SessionStore.save(session, to: url)
        let model = Model(stateURL: url)
        for track in session.tracks {
            if model.audio.player.isStopped { model.toggle() }
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertEqual(model.session.selected, track.id)
            let duration = try XCTUnwrap(model.audio.player.totalTime)
            model.seek(duration - 0.1)
            try await Task.sleep(for: .milliseconds(400))
        }
        XCTAssertTrue(model.audio.player.isStopped)
        XCTAssertEqual(model.position, 0)
    }
    @MainActor func testCorruptFileRecoversToFollowingTrack() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        var session = Session(); session.volume = 0.02
        session.tracks = ["tone.wav","corrupt.mp3","tone.opus"].map { Track(url: root.appendingPathComponent("Fixtures/\($0)")) }
        session.selected = session.tracks[1].id; try SessionStore.save(session, to: url)
        let model = Model(stateURL: url); model.toggle()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(model.session.selected, session.tracks[2].id)
        XCTAssertTrue(model.audio.player.isPlaying); XCTAssertNotNil(model.message); model.stop()
    }
    func testFolderScanDoesNotFollowSymlinks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let real = directory.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try Data([0]).write(to: real.appendingPathComponent("a.wav"))
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("link"), withDestinationURL: real)
        XCTAssertEqual(Model.scan(directory).count, 1)
    }
    @MainActor func testRestoreDoesNotAutoplayAndMissingFilesStop() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        var session = Session(); session.tracks = [Track(url: directory.appendingPathComponent("missing.opus"))]; session.selected = session.tracks[0].id; session.position = 1.5
        try SessionStore.save(session, to: url)
        let model = Model(stateURL: url)
        XCTAssertFalse(model.audio.player.isPlaying); XCTAssertEqual(model.position,1.5)
        model.toggle(); XCTAssertNotNil(model.message); XCTAssertTrue(model.audio.player.isStopped)
    }
}
