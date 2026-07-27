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
        request.timeoutInterval = 30
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
        guard !sections.isEmpty else {
            throw AnalyticsError.invalidResponse
        }

        let dashboardSections = sections.enumerated().map { sectionIndex, section in
            let sectionID = "\(sectionIndex)-\(section.name.stableID)"
            return DashboardSection(
                id: sectionID,
                title: section.name,
                indicators: section.values.enumerated().map { indicatorIndex, indicator in
                    indicator.toIndicator(index: indicatorIndex, sectionID: sectionID)
                }
            )
        }

        return Dashboard(
            id: dashboardSections.count == 1 ? dashboardSections[0].id : "analytics",
            title: dashboardSections.count == 1 ? dashboardSections[0].title : "Аналитика",
            fetchedAt: Date(),
            sections: dashboardSections
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
    let value: Double?
    let valueMax: Double?
    let unit: String?
    let colorGraph: String?
    let colorValue: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case values
        case type
        case value
        case valueMax
        case unit
        case colorGraph
        case colorValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        values = try container.decodeIfPresent([AnalyticsAPIValue].self, forKey: .values) ?? []
        type = try container.decode(ChartType.self, forKey: .type)
        value = try container.decodeIfPresent(Double.self, forKey: .value)
        valueMax = try container.decodeIfPresent(Double.self, forKey: .valueMax)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        colorGraph = try container.decodeIfPresent(String.self, forKey: .colorGraph)
        colorValue = try container.decodeIfPresent(String.self, forKey: .colorValue)
    }

    func toIndicator(index: Int, sectionID: String) -> Indicator {
        let totalRow = values.first { $0.normalizedGroup.isEmpty }
        let rowValues = type == .compactBar
            ? values.filter(\.hasCompactBarValues)
            : values.filter { !$0.normalizedGroup.isEmpty }
        let rows = rowValues
            .enumerated()
            .flatMap { rowIndex, value in
                value.toRows(index: rowIndex, chartType: type)
            }
        let calculatedTotal = rows.isEmpty
            ? nil
            : rows.reduce(0) { $0 + $1.value }
        let scalarValue = value
            ?? totalRow?.value
            ?? (name.isPlanFactIndicatorTitle ? nil : calculatedTotal)
        let primaryValue = values.first

        return Indicator(
            id: "\(sectionID)-\(index)-\(name.stableID)",
            title: name,
            value: scalarValue.map { Decimal($0) },
            valueMax: valueMax ?? totalRow?.valueMax ?? primaryValue?.valueMax,
            unit: unit ?? totalRow?.unit ?? defaultUnit,
            chartType: type,
            source: "DGU_APP_Mobile_Client/analitycs",
            colorGraph: colorGraph ?? totalRow?.colorGraph ?? primaryValue?.colorGraph,
            colorValue: colorValue ?? totalRow?.colorValue ?? primaryValue?.colorValue,
            rows: rows
        )
    }

    private var defaultUnit: String? {
        switch type {
        case .oneValue, .linearProgress, .compactBar:
            nil
        case .bar, .horizontalBar, .stackedBar, .donut:
            "чел."
        }
    }
}

struct AnalyticsAPIValue: Decodable {
    let name: String?
    let group: String?
    let value: Double?
    let valueMax: Double?
    let unit: String?
    let colorGraph: String?
    let colorValue: String?
    let subgroup: [AnalyticsAPISubgroup]?

    private enum CodingKeys: String, CodingKey {
        case name
        case group
        case value
        case valueMax
        case unit
        case colorGraph
        case colorValue
        case subgroup
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        if let textGroup = try? container.decode(String.self, forKey: .group) {
            group = textGroup
        } else if let numericGroup = try? container.decode(Decimal.self, forKey: .group) {
            group = NSDecimalNumber(decimal: numericGroup).stringValue
        } else {
            group = nil
        }
        value = try container.decodeIfPresent(Double.self, forKey: .value)
        valueMax = try container.decodeIfPresent(Double.self, forKey: .valueMax)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        colorGraph = try container.decodeIfPresent(String.self, forKey: .colorGraph)
        colorValue = try container.decodeIfPresent(String.self, forKey: .colorValue)
        subgroup = try container.decodeIfPresent([AnalyticsAPISubgroup].self, forKey: .subgroup)
    }

    var normalizedGroup: String {
        (group ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedName: String {
        (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasCompactBarValues: Bool {
        value != nil || subgroup?.isEmpty == false
    }

    func toRows(index: Int, chartType: ChartType) -> [IndicatorRow] {
        if let subgroup, !subgroup.isEmpty {
            if chartType == .compactBar {
                return subgroup.enumerated().map { subgroupIndex, subgroup in
                    let label = subgroup.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return IndicatorRow(
                        id: "\(index)-\(subgroupIndex)-\(label.stableID)",
                        label: label.isEmpty ? fallbackLabel(index: subgroupIndex) : label,
                        value: subgroup.value,
                        series: nil,
                        sortOrder: index * 100 + subgroupIndex,
                        colorGraph: subgroup.colorGraph ?? colorGraph,
                        colorValue: subgroup.colorValue ?? colorValue
                    )
                }
            }

            return subgroup.enumerated().map { subgroupIndex, subgroup in
                IndicatorRow(
                    id: "\(normalizedGroup.stableID)-\(subgroup.name.stableID)",
                    label: normalizedGroup,
                    value: subgroup.value,
                    series: subgroup.name,
                    sortOrder: index * 100 + subgroupIndex,
                    colorGraph: subgroup.colorGraph ?? colorGraph,
                    colorValue: subgroup.colorValue ?? colorValue
                )
            }
        }

        let label = preferredLabel(index: index)
        return [
            IndicatorRow(
                id: "\(index)-\(label.stableID)",
                label: label,
                value: value ?? 0,
                series: nil,
                sortOrder: index,
                colorGraph: colorGraph,
                colorValue: colorValue
            )
        ]
    }

    private func preferredLabel(index: Int) -> String {
        if !normalizedGroup.isEmpty {
            return normalizedGroup
        }
        if !normalizedName.isEmpty {
            return normalizedName
        }
        return fallbackLabel(index: index)
    }

    private func fallbackLabel(index: Int) -> String {
        String(index + 1)
    }
}

struct AnalyticsAPISubgroup: Decodable {
    let name: String
    let value: Double
    let colorGraph: String?
    let colorValue: String?
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
