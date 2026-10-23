import Foundation

/// Uses `primary` and falls back to `fallback` when it fails or has no limit for the road.
final class FallbackSpeedLimitProvider: SpeedLimitProvider {
    let primary: SpeedLimitProvider
    let fallback: SpeedLimitProvider
    var name: String { primary.name }
    /// Last error from the primary provider, shown in the UI.
    private(set) var primaryError: Error?
    /// Last outcome of the primary provider, for diagnostics.
    private(set) var primaryStatus: String?

    init(primary: SpeedLimitProvider, fallback: SpeedLimitProvider) {
        self.primary = primary
        self.fallback = fallback
    }

    func speedLimit(for sample: LocationSample) async throws -> SpeedLimit? {
        do {
            let limit = try await primary.speedLimit(for: sample)
            primaryError = nil
            primaryStatus = limit.map { $0.kmh.map { "\($0) km/t" } ?? "ingen grænse" } ?? "ukendt (ikke på en kendt vej)"
            if let limit { return limit }
        } catch {
            primaryError = error
            primaryStatus = "fejl: \(error.localizedDescription)"
        }
        return try await fallback.speedLimit(for: sample)
    }
}
