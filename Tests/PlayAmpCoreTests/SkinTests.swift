import XCTest
@testable import PlayAmpCore
final class SkinTests: XCTestCase {
    func testBuiltInsDefineEveryToken() {
        for skin in Skin.builtIn {
            let resolved = SkinLibrary.resolved(skin.id, in: Skin.builtIn)
            for token in Skin.tokens { XCTAssertNotNil(SkinLibrary.rgba(resolved.colors[token.name] ?? ""), "\(skin.name) \(token.name)") }
        }
    }
    func testFileSkinInheritsAndOverrides() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try ##"{"name":"Blue","basedOn":"cassette","colors":{"display":"#0000FF"}}"##.write(to: folder.appendingPathComponent("blue.json"), atomically: true, encoding: .utf8)
        try "not json".write(to: folder.appendingPathComponent("broken.json"), atomically: true, encoding: .utf8)
        let skins = SkinLibrary.all(in: folder)
        XCTAssertEqual(skins.map(\.id), ["classic", "cassette", "turntable", "file:blue.json"])
        let blue = SkinLibrary.resolved("file:blue.json", in: skins)
        XCTAssertEqual(blue.face, .cassette)
        XCTAssertEqual(blue.colors["display"], "#0000FF")
        XCTAssertEqual(blue.colors["tape"], Skin.cassette.colors["tape"])
    }
    func testExampleIsValidAndUnknownFallsBack() throws {
        let example = try JSONDecoder().decode(Skin.self, from: Data(SkinLibrary.exampleJSON().utf8))
        XCTAssertEqual(example.colors.count, Skin.tokens.count)
        XCTAssertEqual(SkinLibrary.resolved("file:gone.json", in: Skin.builtIn).id, "classic")
        XCTAssertEqual(SkinLibrary.rgba("#FF000080")?.alpha ?? 0, 128.0/255, accuracy: 0.001)
        XCTAssertNil(SkinLibrary.rgba("#XYZ"))
    }
    func testOldSessionsStillDecode() throws {
        var session = Session(); session.tracks = [Track(url: URL(fileURLWithPath: "/tmp/a.mp3"))]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as! [String: Any]
        json.removeValue(forKey: "skin")
        let decoded = try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.tracks.count, 1); XCTAssertNil(decoded.skin)
    }
    func testFolderPackageResolvesImagesFontsAndShape() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let package = root.appendingPathComponent("Wood")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try ##"""
        { "name": "Wood", "basedOn": "turntable",
          "images": { "panel": { "file": "wood.png", "mode": "tile" }, "recordLabel": "label.png", "button": "../escape.png" },
          "fonts": { "label": "Hand.ttf", "display": "Menlo" },
          "shape": { "windowCorner": 10, "reels": "spokes" } }
        """##.write(to: package.appendingPathComponent("skin.json"), atomically: true, encoding: .utf8)
        let skins = SkinLibrary.all(in: root)
        XCTAssertEqual(skins.last?.id, "folder:Wood")
        let wood = SkinLibrary.resolved("folder:Wood", in: skins)
        XCTAssertNotNil(wood.layout, "inherits Turntable's layout")
        XCTAssertEqual(wood.layout?.width, 275)
        XCTAssertEqual(wood.images?["panel"]?.file, package.resolvingSymlinksInPath().appendingPathComponent("wood.png").path)
        XCTAssertEqual(wood.images?["panel"]?.mode, .tile)
        XCTAssertEqual(wood.images?["recordLabel"]?.mode, .stretch)
        XCTAssertEqual(wood.images?["button"]?.file, "", "paths may not leave the skin folder")
        XCTAssertEqual(wood.fonts?["label"], package.resolvingSymlinksInPath().appendingPathComponent("Hand.ttf").path)
        XCTAssertEqual(wood.fonts?["display"], "Menlo")
        XCTAssertEqual(wood.shape?.windowCorner, 10)
        XCTAssertEqual(wood.shape?.buttonCorner, 3, "inherited from Turntable")
        XCTAssertEqual(wood.shape?.reels, "spokes")
        XCTAssertEqual(wood.colors["vinyl"], Skin.turntable.colors["vinyl"])
    }
    func testBuiltInsAreValid() {
        for skin in Skin.builtIn {
            let issues = SkinValidator.validate(skin, others: Skin.builtIn)
            XCTAssertTrue(issues.isEmpty, "\(skin.name): \(issues)")
        }
    }
    func testValidatorExplainsMistakes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("bad.json")
        try ##"""
        { "name": "Bad", "colors": { "display": "green" },
          "layout": { "size": [200, 100], "elements": [
            { "type": "blob", "frame": [0, 0, 10, 10] },
            { "type": "text", "frame": [0, 0, 300, 10], "text": "{tme}" },
            { "type": "button", "frame": [0, 0, 10, 10], "action": "fly" },
            { "type": "image", "frame": [0, 0, 10, 10], "file": "missing.png" },
            { "type": "group", "frame": [0, 0, 50, 50], "rotation": { "bind": "speed" }, "children": [ { "type": "rect" } ] } ] } }
        """##.write(to: file, atomically: true, encoding: .utf8)
        let messages = SkinValidator.validate(at: file).map(\.description).joined(separator: "\n")
        for expected in ["color \"display\"", "unknown element type", "unknown placeholder {tme}", "reaches outside", "needs an \"action\"",
                         "file \"missing.png\" not found", "unknown binding \"speed\"", "needs \"frame\"", "no \"dragArea\""] {
            XCTAssertTrue(messages.contains(expected), "missing: \(expected)\n\(messages)")
        }
        let broken = folder.appendingPathComponent("broken.json")
        try ##"{ "colors": {} }"##.write(to: broken, atomically: true, encoding: .utf8)
        XCTAssertTrue(SkinValidator.validate(at: broken).first?.message.contains("missing \"name\"") == true)
    }
    func testFacePickOverridesInheritedLayout() {
        let tape = Skin(id: "file:t.json", name: "T", face: .cassette, basedOn: "turntable", colors: [:])
        XCTAssertNil(SkinLibrary.resolved("file:t.json", in: Skin.builtIn + [tape]).layout)
    }
}
