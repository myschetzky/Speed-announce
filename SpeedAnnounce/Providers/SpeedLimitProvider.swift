import Foundation

enum SpeedLimitProviderError: LocalizedError {
    case notConfigured(String)
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let message): return message
        case .badResponse(let status): return "Datakilden svarede med status \(status)"
        }
    }
}

/// A source of speed limit data. Returns `nil` when the limit for the current road is unknown.
protocol SpeedLimitProvider: AnyObject {
    var name: String { get }
    func speedLimit(for sample: LocationSample) async throws -> SpeedLimit?
}
