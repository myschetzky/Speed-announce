import Foundation

/// Parses OpenStreetMap `maxspeed` values, see https://wiki.openstreetmap.org/wiki/Key:maxspeed
enum MaxspeedValue: Equatable {
    case kmh(Int)
    case unlimited
    case unknown
}

enum MaxspeedParser {
    /// Implicit limits for zone values like `DK:urban`.
    static let zoneLimits: [String: MaxspeedValue] = [
        "DK:urban": .kmh(50), "DK:rural": .kmh(80), "DK:motorway": .kmh(130), "DK:trunk": .kmh(80),
        "DE:urban": .kmh(50), "DE:rural": .kmh(100), "DE:motorway": .unlimited, "DE:living_street": .kmh(7),
        "SE:urban": .kmh(50), "SE:rural": .kmh(70), "SE:motorway": .kmh(110),
        "NO:urban": .kmh(50), "NO:rural": .kmh(80), "NO:motorway": .kmh(110),
        "NL:urban": .kmh(50), "NL:rural": .kmh(80), "NL:motorway": .kmh(100),
        "FR:urban": .kmh(50), "FR:rural": .kmh(80), "FR:motorway": .kmh(130),
        "GB:nsl_single": .kmh(97), "GB:nsl_dual": .kmh(113), "GB:motorway": .kmh(113),
    ]

    static func parse(_ raw: String?) -> MaxspeedValue {
        guard var value = raw?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return .unknown }
        // Multiple values ("50;30") — use the first one.
        if let first = value.split(separator: ";").first {
            value = first.trimmingCharacters(in: .whitespaces)
        }
        if value == "none" { return .unlimited }
        if let zone = zoneLimits[value] { return zone }

        let lower = value.lowercased()
        let isMph = lower.hasSuffix("mph")
        let digits = lower
            .replacingOccurrences(of: "mph", with: "")
            .replacingOccurrences(of: "km/h", with: "")
            .replacingOccurrences(of: "kmh", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let number = Double(digits), number > 0 else { return .unknown }
        return .kmh(Int((isMph ? number * 1.609344 : number).rounded()))
    }
}
