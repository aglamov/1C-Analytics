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
        var request = URLRequest(url: configuration.analyticsEndpointURL)
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

        let analyticsResponse = try decoder.decode(AnalyticsAPIResponse.self, from: data)
        return try analyticsResponse.toDashboard()
    }
}

private struct AnalyticsAPIResponse: Decodable {
    let sections: [AnalyticsAPISection]

    func toDashboard() throws -> Dashboard {
        guard let section = sections.first else {
            throw AnalyticsError.invalidResponse
        }

        return Dashboard(
            id: section.name.stableID,
            title: section.name,
            updatedAt: Date(),
            indicators: section.values.enumerated().map { index, indicator in
                indicator.toIndicator(index: index)
            }
        )
    }
}

private struct AnalyticsAPISection: Decodable {
    let name: String
    let values: [AnalyticsAPIIndicator]
}

private struct AnalyticsAPIIndicator: Decodable {
    let name: String
    let values: [AnalyticsAPIValue]
    let type: ChartType

    func toIndicator(index: Int) -> Indicator {
        let totalRow = values.first { $0.group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let rows = values
            .filter { !$0.group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .enumerated()
            .flatMap { rowIndex, value in
                value.toRows(index: rowIndex)
            }

        return Indicator(
            id: "\(index)-\(name.stableID)",
            title: name,
            value: Decimal(totalRow?.value ?? rows.reduce(0) { $0 + $1.value }),
            unit: "чел.",
            chartType: type,
            source: "DGU_APP_Mobile_Client/analitycs",
            rows: rows
        )
    }
}

private struct AnalyticsAPIValue: Decodable {
    let group: String
    let value: Double?
    let valueRF: Double?
    let valueIG: Double?

    func toRows(index: Int) -> [IndicatorRow] {
        if let valueRF, let valueIG {
            return [
                IndicatorRow(id: "\(group.stableID)-rf", label: group, value: valueRF, series: "РФ", sortOrder: index * 2),
                IndicatorRow(id: "\(group.stableID)-ig", label: group, value: valueIG, series: "ИГ", sortOrder: index * 2 + 1)
            ]
        }

        return [
            IndicatorRow(id: group.stableID, label: group, value: value ?? 0, series: nil, sortOrder: index)
        ]
    }
}

private extension String {
    var stableID: String {
        let allowed = CharacterSet.alphanumerics
        let scalars = unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar).lowercased() : "-"
        }

        return scalars.joined()
            .split(separator: "-")
            .joined(separator: "-")
    }
}
