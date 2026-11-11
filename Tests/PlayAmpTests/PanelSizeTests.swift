import XCTest
import PlayAmpCore
@testable import PlayAmp
final class PanelSizeTests: XCTestCase {
    @MainActor func testPanelsStartAtDefaultSizeAndKeepTheirResizedHeight() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("playamp-sizes-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = Model(stateURL: url), windows = Windows(model: first)
        XCTAssertEqual(windows.height(of: .playlist), 245, "first launch uses the default")
        XCTAssertEqual(windows.height(of: .skins), Windows.skinsHeight)
        first.session.playlistHeight = 380; first.session.skinsHeight = 300; first.save()
        let reopened = Windows(model: Model(stateURL: url))
        XCTAssertEqual(reopened.height(of: .playlist), 380, "restored after reopening")
        XCTAssertEqual(reopened.height(of: .skins), 300)
        first.session.playlistHeight = 20
        XCTAssertEqual(windows.height(of: .playlist), 116, "never smaller than the minimum")
    }
}
