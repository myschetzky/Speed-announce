import CoreLocation

/// Small planar geometry helpers. Over a few hundred metres an equirectangular
/// projection is accurate enough for snapping a GPS fix to a road.
enum RoadGeometry {
    static let earthRadius = 6_371_000.0

    /// Projects `point` to metres relative to `origin` (x east, y north).
    static func project(_ point: CLLocationCoordinate2D, origin: CLLocationCoordinate2D) -> (x: Double, y: Double) {
        let latRad = origin.latitude * .pi / 180
        let x = (point.longitude - origin.longitude) * .pi / 180 * earthRadius * cos(latRad)
        let y = (point.latitude - origin.latitude) * .pi / 180 * earthRadius
        return (x, y)
    }

    struct SegmentMatch {
        let distance: Double
        /// Bearing of the segment in node order, degrees 0..<360.
        let bearing: Double
    }

    /// Distance from `point` to segment a–b and the segment's bearing.
    static func match(point: CLLocationCoordinate2D, a: CLLocationCoordinate2D, b: CLLocationCoordinate2D) -> SegmentMatch {
        let pa = project(a, origin: point)
        let pb = project(b, origin: point)
        let dx = pb.x - pa.x
        let dy = pb.y - pa.y
        let lengthSquared = dx * dx + dy * dy
        var t = 0.0
        if lengthSquared > 0 {
            t = max(0, min(1, -(pa.x * dx + pa.y * dy) / lengthSquared))
        }
        let cx = pa.x + t * dx
        let cy = pa.y + t * dy
        var bearing = atan2(dx, dy) * 180 / .pi
        if bearing < 0 { bearing += 360 }
        return SegmentMatch(distance: (cx * cx + cy * cy).squareRoot(), bearing: bearing)
    }

    /// Smallest absolute difference between two bearings, 0...180.
    static func angleDifference(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
        return diff > 180 ? 360 - diff : diff
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let p = project(b, origin: a)
        return (p.x * p.x + p.y * p.y).squareRoot()
    }
}
