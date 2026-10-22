import CoreLocation

/// A road (OSM way) with the tags relevant for speed limits.
struct OSMRoad: Equatable {
    let id: Int64
    let geometry: [CLLocationCoordinate2D]
    let tags: [String: String]

    var isOneway: Bool {
        let oneway = tags["oneway"]
        return oneway == "yes" || oneway == "1" || oneway == "-1"
            || (oneway == nil && (tags["highway"] == "motorway" || tags["junction"] == "roundabout"))
    }

    /// `oneway=-1` means traffic flows against the node order.
    var isReversedOneway: Bool { tags["oneway"] == "-1" }

    var name: String? { tags["name"] ?? tags["ref"] }

    static func == (lhs: OSMRoad, rhs: OSMRoad) -> Bool { lhs.id == rhs.id }
}

/// Snaps a GPS fix to the most likely road and reads its speed limit.
struct OSMRoadMatcher {
    /// Fixes farther than this from every road are treated as off-road.
    var maxDistance: Double = 35
    /// Metres of penalty for driving 90° off the road's direction.
    var headingPenaltyPer90Degrees: Double = 30
    /// Metres of bonus for staying on the previously matched road (prevents flicker at junctions).
    var stickinessBonus: Double = 6

    struct Match {
        let road: OSMRoad
        let distance: Double
        /// True when travelling in the road's node order.
        let isForward: Bool
    }

    func bestMatch(for sample: LocationSample, roads: [OSMRoad], previousRoadId: Int64?) -> Match? {
        let hasHeading = sample.course >= 0 && sample.speed > 2
        let allowed = max(maxDistance, min(sample.horizontalAccuracy, 60) + 10)
        var best: (match: Match, score: Double)?

        for road in roads where road.geometry.count >= 2 {
            for i in 0..<(road.geometry.count - 1) {
                let segment = RoadGeometry.match(point: sample.coordinate, a: road.geometry[i], b: road.geometry[i + 1])
                guard segment.distance <= allowed else { continue }

                var score = segment.distance
                var isForward = true
                if hasHeading {
                    let diff = RoadGeometry.angleDifference(sample.course, segment.bearing)
                    isForward = diff <= 90
                    let effectiveDiff: Double
                    if road.isOneway {
                        // Driving against a one-way road is very unlikely: use the raw difference.
                        effectiveDiff = road.isReversedOneway ? 180 - diff : diff
                    } else {
                        effectiveDiff = min(diff, 180 - diff)
                    }
                    score += effectiveDiff / 90 * headingPenaltyPer90Degrees
                }
                if road.id == previousRoadId { score -= stickinessBonus }

                if best == nil || score < best!.score {
                    best = (Match(road: road, distance: segment.distance, isForward: isForward), score)
                }
            }
        }
        return best?.match
    }

    /// Reads the speed limit for the direction of travel.
    static func maxspeed(for match: Match) -> MaxspeedValue {
        let tags = match.road.tags
        let directional = match.isForward ? tags["maxspeed:forward"] : tags["maxspeed:backward"]
        let parsedDirectional = MaxspeedParser.parse(directional)
        if parsedDirectional != .unknown { return parsedDirectional }
        let parsed = MaxspeedParser.parse(tags["maxspeed"])
        if parsed != .unknown { return parsed }
        // Fall back to the implicit zone if only source:maxspeed / maxspeed:type is set.
        return MaxspeedParser.parse(tags["source:maxspeed"] ?? tags["maxspeed:type"])
    }
}
