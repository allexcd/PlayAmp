import Foundation
import CoreGraphics

public enum WindowDocking {
    /// Attach only along a real shared edge, never by corner contact alone.
    public static func touching(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 1) -> Bool {
        let xOverlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let yOverlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return (xOverlap > 1 && min(abs(a.maxY-b.minY), abs(a.minY-b.maxY)) <= tolerance)
            || (yOverlap > 1 && min(abs(a.maxX-b.minX), abs(a.minX-b.maxX)) <= tolerance)
    }

    public static func connected(to root: String, frames: [String: CGRect]) -> Set<String> {
        var result: Set<String> = [root]
        var pending = [root]
        while let key = pending.popLast(), let frame = frames[key] {
            for (other, rect) in frames where !result.contains(other) && touching(frame, rect) {
                result.insert(other); pending.append(other)
            }
        }
        return result
    }

    public static func snapped(_ moving: CGRect, to targets: [CGRect], distance: CGFloat = 12) -> CGRect {
        var best = moving
        var bestDistance = CGFloat.infinity
        for target in targets {
            let candidates = [
                CGPoint(x: target.minX-moving.width, y: moving.minY),
                CGPoint(x: target.maxX, y: moving.minY),
                CGPoint(x: moving.minX, y: target.minY-moving.height),
                CGPoint(x: moving.minX, y: target.maxY)
            ]
            for (index, origin) in candidates.enumerated() {
                var candidate = CGRect(origin: origin, size: moving.size)
                let delta = hypot(origin.x-moving.minX, origin.y-moving.minY)
                guard delta <= distance else { continue }
                if index < 2 {
                    let alignments = [target.maxY-moving.height, target.minY]
                    if let y = alignments.min(by: { abs($0-moving.minY) < abs($1-moving.minY) }), abs(y-moving.minY) <= distance { candidate.origin.y = y }
                } else {
                    let alignments = [target.minX, target.maxX-moving.width]
                    if let x = alignments.min(by: { abs($0-moving.minX) < abs($1-moving.minX) }), abs(x-moving.minX) <= distance { candidate.origin.x = x }
                }
                guard touching(candidate, target), !targets.contains(where: { candidate.intersection($0).width > 1 && candidate.intersection($0).height > 1 }) else { continue }
                let score = hypot(candidate.minX-moving.minX, candidate.minY-moving.minY)
                if score < bestDistance { best = candidate; bestDistance = score }
            }
        }
        return best
    }

    /// Pulls a window (or a docked group's bounding box) flush to screen edges within `distance`.
    public static func snappedToEdges(_ rect: CGRect, in bounds: CGRect, distance: CGFloat) -> CGRect {
        var result = rect
        if abs(rect.minX - bounds.minX) <= distance { result.origin.x = bounds.minX }
        else if abs(rect.maxX - bounds.maxX) <= distance { result.origin.x = bounds.maxX - rect.width }
        if abs(rect.maxY - bounds.maxY) <= distance { result.origin.y = bounds.maxY - rect.height }
        else if abs(rect.minY - bounds.minY) <= distance { result.origin.y = bounds.minY }
        return result
    }
}
