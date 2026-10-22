import Foundation

/// Uses `primary` and falls back to `fallback` when it fails or has no limit for the road.
final class FallbackSpeedLimitProvider: SpeedLimitProvider {
    let primary: SpeedLimitProvider
    let fallback: SpeedLimitProvider
    var name: String { primary.name }
    /// Last error from the primary provider, shown in the UI.
    private(set) var primaryError: Error?

    init(primary: SpeedLimitProvider, fallback: SpeedLimitProvider) {
        self.primary = primary
        self.fallback = fallback
    }

    func speedLimit(for sample: LocationSample) async throws -> SpeedLimit? {
        do {
            let limit = try await primary.speedLimit(for: sample)
            primaryError = nil
            if let limit { return limit }
        } catch {
            primaryError = error
        }
        return try await fallback.speedLimit(for: sample)
    }
}
