import Foundation

/// Placeholder for Saphe's speed limit data.
///
/// Saphe does not publish a public API. If Saphe grants partner access, adapt
/// `makeRequest` and `Response` to their actual contract. Until then this
/// provider expects a simple JSON endpoint:
///
///     GET {endpoint}?lat=55.67&lon=12.56&heading=90
///     Authorization: Bearer {apiKey}
///     → { "speedLimit": 80, "roadName": "Køgevej" }   // speedLimit null = unknown
final class SapheSpeedLimitProvider: SpeedLimitProvider {
    let name = "Saphe"

    private let endpoint: URL?
    private let apiKey: String
    private let session: URLSession

    init(endpoint: String, apiKey: String, session: URLSession = .shared) {
        self.endpoint = URL(string: endpoint.trimmingCharacters(in: .whitespaces))
        self.apiKey = apiKey.trimmingCharacters(in: .whitespaces)
        self.session = session
    }

    func speedLimit(for sample: LocationSample) async throws -> SpeedLimit? {
        guard let endpoint, endpoint.scheme == "https", !apiKey.isEmpty else {
            throw SpeedLimitProviderError.notConfigured("Saphe kræver API-adgang. Angiv endpoint og nøgle under Indstillinger.")
        }
        let (data, response) = try await session.data(for: makeRequest(endpoint: endpoint, sample: sample))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SpeedLimitProviderError.badResponse(status) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let limit = decoded.speedLimit else { return nil }
        return SpeedLimit(kmh: limit, roadName: decoded.roadName, source: name)
    }

    private func makeRequest(endpoint: URL, sample: LocationSample) -> URLRequest {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "lat", value: String(sample.coordinate.latitude)),
            URLQueryItem(name: "lon", value: String(sample.coordinate.longitude)),
            URLQueryItem(name: "heading", value: String(Int(max(sample.course, 0)))),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private struct Response: Decodable {
        let speedLimit: Int?
        let roadName: String?
    }
}
