// MARK: - Geometry Helpers
// Small geometry utilities shared by the drag-to-reorder logic in the menu bar and Settings.
import CoreGraphics

extension CGRect {
    /// Creates a rect centered on a point, used by drag previews positioned from a center.
    init(center: CGPoint, size: CGSize) {
        self.init(
            x: center.x - (size.width * 0.5),
            y: center.y - (size.height * 0.5),
            width: size.width,
            height: size.height
        )
    }

    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    var area: CGFloat {
        guard isNull == false, isInfinite == false else { return 0 }
        return max(0, width) * max(0, height)
    }

    /// Returns how much of the smaller rect is covered by the intersection with another rect.
    func overlapRatio(with other: CGRect) -> CGFloat {
        let intersectionArea = intersection(other).area
        guard intersectionArea > 0 else { return 0 }
        let referenceArea = min(area, other.area)
        guard referenceArea > 0 else { return 0 }
        return intersectionArea / referenceArea
    }
}

extension CGPoint {
    /// Returns a translated copy of this point.
    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }

    /// Squared euclidean distance, used to compare proximity without extra sqrt calls.
    func distanceSquared(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx) + (dy * dy)
    }
}

extension Array where Element == CGFloat {
    /// Median value used for robust spacing estimates in drag/drop layouts.
    var median: CGFloat? {
        guard isEmpty == false else { return nil }
        let sorted = self.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) * 0.5
        }
        return sorted[mid]
    }
}
