import XCTest
import CoreGraphics
@testable import PlayAmpCore
final class WindowDockingTests: XCTestCase {
    let player = CGRect(x: 300, y: 400, width: 275, height: 116)
    func testSnapsAllFourEdges() {
        for origin in [CGPoint(x: 28,y: 400), CGPoint(x: 578,y: 400), CGPoint(x: 300,y: 519), CGPoint(x: 300,y: 281)] {
            let result = WindowDocking.snapped(CGRect(origin: origin, size: player.size), to: [player])
            XCTAssertTrue(WindowDocking.touching(result, player))
            XCTAssertEqual(result.intersection(player).width * result.intersection(player).height, 0)
        }
    }
    func testSnapsFromWiderReleaseZone() {
        let below = CGRect(x: 310, y: 264, width: 275, height: 116) // 20 pt gap, 10 pt off-axis
        let result = WindowDocking.snapped(below, to: [player], distance: 24)
        XCTAssertEqual(result.origin, CGPoint(x: 300, y: 284))
    }
    func testDetachedAndCornerWindowsStayIndependent() {
        let far = CGRect(x: 600,y: 400,width: 275,height: 116)
        XCTAssertEqual(WindowDocking.snapped(far,to: [player]), far)
        XCTAssertFalse(WindowDocking.touching(player, CGRect(x: 575,y: 516,width: 275,height: 116)))
    }
    func testConnectedChainAndDetachment() {
        var frames = ["player": player, "eq": CGRect(x:300,y:284,width:275,height:116), "playlist": CGRect(x:300,y:39,width:275,height:245)]
        XCTAssertEqual(WindowDocking.connected(to: "player", frames: frames), ["player","eq","playlist"])
        frames["eq"]?.origin.x += 400
        XCTAssertEqual(WindowDocking.connected(to: "player", frames: frames), ["player"])
    }
    func testScreenEdgeSnapping() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
        XCTAssertEqual(WindowDocking.snappedToEdges(CGRect(x: 15, y: 300, width: 275, height: 116), in: screen, distance: 24).origin, CGPoint(x: 0, y: 300))
        XCTAssertEqual(WindowDocking.snappedToEdges(CGRect(x: 1230, y: 820, width: 275, height: 116), in: screen, distance: 24).origin, CGPoint(x: 1237, y: 828))
        let middle = CGRect(x: 600, y: 400, width: 275, height: 116)
        XCTAssertEqual(WindowDocking.snappedToEdges(middle, in: screen, distance: 24), middle)
    }
}
