import Foundation

@MainActor
final class APIAnalyticsProvider: AnalyticsProvider {
    private let configuration: AppConfiguration
    private let urlSession: URLSession
    private let credentialsStore: any AuthenticationRequestAuthorizing
    private let decoder: JSONDecoder

    init(
        configuration: AppConfiguration = .load(),
        urlSession: URLSession = .shared,
        credentialsStore: any AuthenticationRequestAuthorizing = AuthenticationCredentialsStore.shared
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
        self.credentialsStore = credentialsStore
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

        try credentialsStore.addAuthentication(to: &request)

        let (data, response) = try await urlSession.data(for: request)

        try Self.validate(response)

        let analyticsResponse = try decoder.decode(AnalyticsAPIResponse.self, from: data)
        return try analyticsResponse.toDashboard()
    }

    static func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalyticsError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw AnalyticsError.authenticationRequired
        default:
            throw AnalyticsError.httpFailure(statusCode: httpResponse.statusCode)
        }
    }
}

struct AnalyticsAPIResponse: Decodable {
    let sections: [AnalyticsAPISection]

    func toDashboard() throws -> Dashboard {
        guard let section = sections.first else {
            throw AnalyticsError.invalidResponse
        }

        return Dashboard(
            id: section.name.stableID,
            title: section.name,
            fetchedAt: Date(),
            indicators: section.values.enumerated().map { index, indicator in
                indicator.toIndicator(index: index)
            }
        )
    }
}

struct AnalyticsAPISection: Decodable {
    let name: String
    let values: [AnalyticsAPIIndicator]
}

struct AnalyticsAPIIndicator: Decodable {
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

struct AnalyticsAPIValue: Decodable {
    let group: String
    let value: Double?
    let subgroup: [AnalyticsAPISubgroup]?

    func toRows(index: Int) -> [IndicatorRow] {
        if let subgroup, !subgroup.isEmpty {
            return subgroup.enumerated().map { subgroupIndex, subgroup in
                IndicatorRow(
                    id: "\(group.stableID)-\(subgroup.name.stableID)",
                    label: group,
                    value: subgroup.value,
                    series: subgroup.name,
                    sortOrder: index * 100 + subgroupIndex
                )
            }
        }

        return [
            IndicatorRow(id: group.stableID, label: group, value: value ?? 0, series: nil, sortOrder: index)
        ]
    }
}

struct AnalyticsAPISubgroup: Decodable {
    let name: String
    let value: Double
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
