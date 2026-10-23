import CoreLocation

/// One thing the app announced (or a trip start), kept so a drive can be checked afterwards.
struct TripLogEntry: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case tripStart, limitChanged, periodic, speeding, limitLost
    }

    var id = UUID()
    let date: Date
    let kind: Kind
    /// Limit in km/h; nil for "no limit" or when not relevant.
    let limitKmh: Int?
    let speedKmh: Int?
    let road: String?
    let source: String?
    let latitude: Double?
    let longitude: Double?

    var title: String {
        switch kind {
        case .tripStart: return "Tur startet"
        case .limitChanged: return limitKmh.map { "Fartgrænse \($0)" } ?? "Ingen fartgrænse"
        case .periodic: return limitKmh.map { "Gentaget: \($0)" } ?? "Gentaget: ingen grænse"
        case .speeding: return "For hurtigt: \(speedKmh ?? 0) i \(limitKmh ?? 0)"
        case .limitLost: return "Grænse ukendt"
        }
    }

    /// Opens the position in Apple Maps.
    var mapURL: URL? {
        guard let latitude, let longitude else { return nil }
        return URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
    }
}

/// Stores the most recent announcements on disk.
@MainActor
final class TripLog: ObservableObject {
    @Published private(set) var entries: [TripLogEntry] = []

    private let fileURL: URL
    private let maxEntries = 2_000

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("triplog.json")
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode([TripLogEntry].self, from: data) {
            entries = decoded
        }
    }

    func add(_ entry: TripLogEntry) {
        entries.append(entry)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    /// Entries grouped per trip, newest trip first.
    var trips: [[TripLogEntry]] {
        var result: [[TripLogEntry]] = []
        for entry in entries {
            if entry.kind == .tripStart || result.isEmpty {
                result.append([entry])
            } else {
                result[result.count - 1].append(entry)
            }
        }
        return result.reversed()
    }

    /// Plain text version for sharing.
    var exportText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return entries.map { entry in
            var parts = [formatter.string(from: entry.date), entry.title]
            if let road = entry.road { parts.append(road) }
            if let speed = entry.speedKmh, entry.kind != .speeding { parts.append("\(speed) km/t") }
            if let source = entry.source { parts.append(source) }
            if let lat = entry.latitude, let lon = entry.longitude {
                parts.append(String(format: "%.5f,%.5f", lat, lon))
            }
            return parts.joined(separator: " | ")
        }.joined(separator: "\n")
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            // The log is a convenience; losing it must not affect announcements.
        }
    }
}
