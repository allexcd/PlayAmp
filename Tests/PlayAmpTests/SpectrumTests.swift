import XCTest
import PlayAmpCore
@testable import PlayAmp
final class SpectrumTests: XCTestCase {
    func testBarsRiseInstantlyFallSteadilyAndPeaksHoldThenDrop() {
        let motion = SpectrumMotion()
        var up = Array(repeating: Float(0), count: Spectrum.bands); up[0] = 0.8
        motion.step(to: up, at: 0)
        XCTAssertEqual(motion.levels[0], 0.8)
        motion.step(to: [], at: 0.1)
        XCTAssertEqual(motion.levels[0], 0.8 - SpectrumMotion.fallRate * 0.1, accuracy: 0.001)
        XCTAssertEqual(motion.peaks[0], 0.8, "peak holds")
        for t in stride(from: 0.2, through: 2.0, by: 0.05) { motion.step(to: [], at: t) }
        XCTAssertTrue(motion.isIdle, "everything falls back to zero")
    }
    func testFramesAreReleasedAtAudioPace() {
        let spectrum = Spectrum()
        let rate = 44_100.0
        let tone = (0..<4410).map { Float(sin(2 * Double.pi * 440 * Double($0) / rate)) * 0.5 }
        spectrum.analyze(tone, rate: rate, arrival: 100)
        let first = spectrum.read(at: 100)
        XCTAssertTrue(first.contains { $0 > 0 })
        XCTAssertEqual(spectrum.read(at: 99), first, "nothing newer is due yet")
        let last = spectrum.read(at: 100.2)
        XCTAssertEqual(last, spectrum.read(), "after the block's duration the newest slice is shown")
    }
}

final class SkinToolTests: XCTestCase {
    /// The skill's reference file must match what the app actually accepts.
    @MainActor func testSkillReferenceMatchesCode() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = try String(contentsOf: root.appendingPathComponent("skills/playamp-skins/reference.md"), encoding: .utf8)
        XCTAssertTrue(file.contains(SkinTool.reference()), "Regenerate skills/playamp-skins/reference.md with: PlayAmp --skin-reference")
    }
    /// Rendering resolves file names to full paths; that must not be mistaken for a skin reaching outside its folder.
    @MainActor func testBundledExamplesRenderWithoutErrors() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("render-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: out) }
        for name in ["walnut", "vu-radio", "midnight-tape.json"] {
            let skin = root.appendingPathComponent("skills/playamp-skins/examples/\(name)").path
            XCTAssertEqual(SkinTool.render(skin, options: ["out": out.path]), 0, name)
        }
        XCTAssertEqual(SkinTool.render("turntable", options: ["out": out.path]), 0)
    }
    func testBundledExamplesAreValid() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let examples = root.appendingPathComponent("skills/playamp-skins/examples")
        let items = try FileManager.default.contentsOfDirectory(at: examples, includingPropertiesForKeys: nil).filter { !$0.lastPathComponent.hasPrefix(".") }
        XCTAssertGreaterThanOrEqual(items.count, 3)
        for item in items { XCTAssertEqual(PlayAmpCore.SkinValidator.validate(at: item), [], item.lastPathComponent) }
    }
}
