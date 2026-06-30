import Foundation

final class APIAnalyticsProvider: AnalyticsProvider {
    private let configuration: AppConfiguration
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(
        configuration: AppConfiguration = .load(),
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func fetchDashboard() async throws -> Dashboard {
        var request = URLRequest(url: configuration.analyticsBaseURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let apiKey = configuration.analyticsAPIKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw AnalyticsError.invalidResponse
        }

        return try decoder.decode(Dashboard.self, from: data)
    }
}

