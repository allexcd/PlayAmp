import XCTest
@testable import PlayAmpCore
/// Skins are shared between people, so a skin file must never be able to reach other files,
/// crash the app, hang it, or open an absurd window.
final class SkinSafetyTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("skin-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testFilesOutsideTheSkinFolderAreRejected() throws {
        let root = try folder(), skin = root.appendingPathComponent("skin")
        try FileManager.default.createDirectory(at: skin, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("secret.png"))
        try Data("x".utf8).write(to: skin.appendingPathComponent("ok.png"))
        try FileManager.default.createSymbolicLink(at: skin.appendingPathComponent("link.png"), withDestinationURL: root.appendingPathComponent("secret.png"))
        XCTAssertTrue(SkinLibrary.absolute("ok.png", in: skin).hasSuffix("/skin/ok.png"))
        XCTAssertEqual(SkinLibrary.absolute("/etc/hosts", in: skin), "", "absolute paths")
        XCTAssertEqual(SkinLibrary.absolute("../secret.png", in: skin), "", "parent folders")
        XCTAssertEqual(SkinLibrary.absolute("sub/../../secret.png", in: skin), "")
        XCTAssertEqual(SkinLibrary.absolute("~/Documents/x.png", in: skin), "")
        XCTAssertEqual(SkinLibrary.absolute("link.png", in: skin), "", "symlinks that leave the folder")
        XCTAssertEqual(SkinLibrary.absolute("", in: skin), "")
    }
    func testUnusableLayoutSizesFallBackToABuiltInFace() throws {
        let root = try folder()
        for (name, size) in [("huge", "[100000, 100000]"), ("tiny", "[1, 1]"), ("negative", "[-300, 200]"), ("short", "[300]")] {
            try Data("{\"name\":\"\(name)\",\"layout\":{\"size\":\(size),\"elements\":[]}}".utf8).write(to: root.appendingPathComponent("\(name).json"))
        }
        let loaded = SkinLibrary.all(in: root).filter { $0.id.hasPrefix("file:") }
        XCTAssertEqual(loaded.count, 4)
        for skin in loaded { XCTAssertNil(skin.layout, skin.name) }
    }
    func testLayoutNumbersAreForcedIntoSaneRanges() throws {
        var bad = LayoutElement(type: "text", frame: [0, 0, 50, 10]); bad.fontSize = 1e9; bad.strokeWidth = -5; bad.text = String(repeating: "a", count: 5000)
        bad.knobSize = [0, -3]; bad.pivot = [1e12, 0]; bad.opacity = .bound(bind: "level", from: .infinity, to: 1, idle: nil)
        let layout = SkinLayout(size: [300, 150], elements: [
            bad,
            LayoutElement(type: "rect", frame: [0, 0, .nan, 10]),      // dropped: not a number
            LayoutElement(type: "rect", frame: [0, 0, 1e9, 10]),       // dropped: absurd size
            LayoutElement(type: "rect", frame: [0, 0, 10])             // dropped: malformed
        ])
        let safe = try XCTUnwrap(layout.sanitized())
        XCTAssertEqual(safe.elements.count, 1)
        XCTAssertEqual(safe.elements[0].fontSize, 400); XCTAssertEqual(safe.elements[0].strokeWidth, 0)
        XCTAssertEqual(safe.elements[0].text?.count, 500)
        XCTAssertNil(safe.elements[0].knobSize); XCTAssertNil(safe.elements[0].pivot); XCTAssertNil(safe.elements[0].opacity)
    }
    func testElementCountAndNestingAreCapped() throws {
        var nested = LayoutElement(type: "rect", frame: [0, 0, 10, 10])
        for _ in 0..<40 { var group = LayoutElement(type: "group", frame: [0, 0, 10, 10]); group.children = [nested]; nested = group }
        let many = Array(repeating: LayoutElement(type: "rect", frame: [0, 0, 10, 10]), count: 50_000)
        let safe = try XCTUnwrap(SkinLayout(size: [300, 150], elements: [nested] + many).sanitized())
        func depth(_ e: LayoutElement) -> Int { 1 + ((e.children ?? []).map(depth).max() ?? 0) }
        func count(_ e: [LayoutElement]) -> Int { e.reduce(0) { $0 + 1 + count($1.children ?? []) } }
        XCTAssertLessThanOrEqual(depth(safe.elements[0]), SkinLayout.maxDepth)
        XCTAssertLessThanOrEqual(count(safe.elements), SkinLayout.maxElements)
    }
    func testOversizedSkinFilesAreSkippedAndFlagged() throws {
        let root = try folder(), file = root.appendingPathComponent("big.json")
        try Data(("{\"name\":\"Big\",\"colors\":{},\"pad\":\"" + String(repeating: "x", count: SkinLibrary.maxSkinFileBytes) + "\"}").utf8).write(to: file)
        XCTAssertFalse(SkinLibrary.all(in: root).contains { $0.name == "Big" })
        XCTAssertTrue(SkinValidator.validate(at: file).contains { $0.severity == .error && $0.message.contains("not loaded") })
    }
    func testBuiltInAndExampleLayoutsSurviveUnchanged() throws {
        let turntable = try XCTUnwrap(Skin.turntable.layout)
        XCTAssertEqual(turntable.sanitized(), turntable)
        let examples = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("skills/playamp-skins/examples")
        let raw = try JSONDecoder().decode(Skin.self, from: Data(contentsOf: examples.appendingPathComponent("vu-radio/skin.json")))
        XCTAssertEqual(raw.layout?.sanitized(), raw.layout)
    }
}
