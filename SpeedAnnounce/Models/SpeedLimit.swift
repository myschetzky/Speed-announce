import CoreLocation

/// A speed limit for the road the vehicle is currently on.
struct SpeedLimit: Equatable {
    /// Limit in km/h. `nil` means no limit (e.g. German Autobahn "none").
    let kmh: Int?
    /// Human readable road name if the source has one.
    let roadName: String?
    /// Which provider produced the value.
    let source: String
}

/// Input a provider gets for every lookup.
struct LocationSample {
    let coordinate: CLLocationCoordinate2D
    /// Course over ground in degrees (0 = north), negative when unknown.
    let course: CLLocationDirection
    /// Speed in m/s, negative when unknown.
    let speed: CLLocationSpeed
    let horizontalAccuracy: CLLocationAccuracy
    let timestamp: Date

    init(_ location: CLLocation) {
        coordinate = location.coordinate
        course = location.course
        speed = location.speed
        horizontalAccuracy = location.horizontalAccuracy
        timestamp = location.timestamp
    }

    init(coordinate: CLLocationCoordinate2D, course: CLLocationDirection = -1, speed: CLLocationSpeed = -1,
         horizontalAccuracy: CLLocationAccuracy = 5, timestamp: Date = Date()) {
        self.coordinate = coordinate
        self.course = course
        self.speed = speed
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }

    var speedKmh: Double? { speed >= 0 ? speed * 3.6 : nil }
}
