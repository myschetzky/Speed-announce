import CoreLocation

/// Decoder for HERE's Flexible Polyline encoding, used by the HERE Routing API.
/// https://github.com/heremaps/flexible-polyline
enum FlexiblePolyline {
    enum DecodeError: Error { case invalidCharacter, truncated, unsupportedVersion }

    private static let table: [Character: Int] = {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        return Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })
    }()

    static func decode(_ encoded: String) throws -> [CLLocationCoordinate2D] {
        var values: [Int64] = []
        var value: Int64 = 0
        var shift: Int64 = 0
        for character in encoded {
            guard let digit = table[character] else { throw DecodeError.invalidCharacter }
            value |= Int64(digit & 0x1F) << shift
            if digit & 0x20 != 0 {
                shift += 5
            } else {
                values.append(value)
                value = 0
                shift = 0
            }
        }
        guard shift == 0, values.count >= 2 else { throw DecodeError.truncated }
        guard values[0] == 1 else { throw DecodeError.unsupportedVersion }

        let header = values[1]
        let factor = pow(10, Double(header & 15))
        let hasThirdDimension = (header >> 4) & 7 != 0
        let stride = hasThirdDimension ? 3 : 2
        let deltas = values.dropFirst(2)
        guard deltas.count % stride == 0 else { throw DecodeError.truncated }

        func unzigzag(_ value: Int64) -> Int64 { value & 1 == 1 ? ~(value >> 1) : value >> 1 }

        var coordinates: [CLLocationCoordinate2D] = []
        var lat: Int64 = 0
        var lng: Int64 = 0
        var index = deltas.startIndex
        while index < deltas.endIndex {
            lat += unzigzag(deltas[index])
            lng += unzigzag(deltas[index + 1])
            index += stride
            coordinates.append(CLLocationCoordinate2D(latitude: Double(lat) / factor, longitude: Double(lng) / factor))
        }
        return coordinates
    }
}
