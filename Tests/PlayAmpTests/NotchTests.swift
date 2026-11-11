import XCTest
import SwiftUI
import PlayAmpCore
@testable import PlayAmp
final class NotchTests: XCTestCase {
    func testTitlesSplitIntoSongAndArtist() {
        XCTAssertEqual(NotchContent.split("Lumen — Glass Rivers").0, "Glass Rivers")
        XCTAssertEqual(NotchContent.split("Lumen - Glass Rivers").1, "Lumen")
        XCTAssertEqual(NotchContent.split("Untitled").0, "Untitled")
        XCTAssertEqual(NotchContent.split(nil).0, "PlayAmp")
    }
    func testPanelCoversOnlyTheNotchUntilOpened() {
        let geometry = NotchGeometry(notch: CGRect(x: 771.5, y: 1085, width: 185, height: 32), hasNotch: true)
        XCTAssertEqual(geometry.collapsedFrame.midX, geometry.notch.midX)
        XCTAssertEqual(geometry.collapsedFrame.maxY, 1117)
        XCTAssertEqual(geometry.expandedFrame.maxY, 1117, "flush with the top of the screen")
        XCTAssertEqual(geometry.expandedFrame.midX, geometry.notch.midX)
        XCTAssertGreaterThan(geometry.expandedFrame.height, geometry.notch.height)
    }
    /// Writes the open notch player to NOTCH_PREVIEW (a .png path) when that variable is set.
    @MainActor func testRendersOpenPlayer() throws {
        let model = SkinTool.sampleModel(state: "playing", progress: 0.4, skin: Skin.classic)
        let state = NotchState(); state.geometry = NotchGeometry(notch: CGRect(x: 0, y: 0, width: 185, height: 32), hasNotch: true); state.expanded = true
        let view = NotchRoot(state: state, model: model, showPlayer: {})
            .frame(width: NotchGeometry.width, height: state.geometry.expandedHeight).background(Color(white: 0.85))
        let renderer = ImageRenderer(content: view.environment(\.renderingPreview, true)); renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.width, NotchGeometry.width)
        if let path = ProcessInfo.processInfo.environment["NOTCH_PREVIEW"], let tiff = image.tiffRepresentation {
            try NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
}
