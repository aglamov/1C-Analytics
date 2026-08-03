import Foundation

@MainActor
final class APIAnalyticsProvider: AnalyticsProvider {
    private let configuration: AppConfiguration
    private let urlSession: URLSession
    private let credentialsStore: any AuthenticationRequestAuthorizing

    init(
        configuration: AppConfiguration = .load(),
        urlSession: URLSession = .shared,
        credentialsStore: any AuthenticationRequestAuthorizing = AuthenticationCredentialsStore.shared
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
        self.credentialsStore = credentialsStore
    }

    func fetchDashboard() async throws -> Dashboard {
        try await fetchDashboard { _ in }
    }

    func fetchDashboard(
        onSectionReceived: @escaping @MainActor @Sendable (DashboardSection) -> Void
    ) async throws -> Dashboard {
        let preparedRequests: [(Int, AnalyticsAPIContract.Section, URLRequest)]
        do {
            preparedRequests = try AnalyticsAPIContract.sections.enumerated().map { index, section in
                (index, section, try makeRequest(for: section))
            }
        } catch AuthenticationError.missingCredentials {
            throw AnalyticsError.authenticationRequired
        }

        let session = urlSession
        var receivedSections = [Int: DashboardSection]()
        var failedSections = [(index: Int, name: String)]()
        var authenticationFailed = false

        await withTaskGroup(of: SectionFetchOutcome.self) { group in
            for (index, section, request) in preparedRequests {
                group.addTask {
                    await Self.fetchSection(
                        index: index,
                        contract: section,
                        request: request,
                        session: session
                    )
                }
            }

            for await outcome in group {
                if let section = outcome.section {
                    receivedSections[outcome.index] = section
                    onSectionReceived(section)
                } else {
                    failedSections.append((outcome.index, outcome.displayName))
                    authenticationFailed = authenticationFailed || outcome.authenticationFailed
                }
            }
        }

        if authenticationFailed {
            throw AnalyticsError.authenticationRequired
        }

        if !failedSections.isEmpty {
            let sectionNames = failedSections
                .sorted { $0.index < $1.index }
                .map(\.name)
            throw AnalyticsError.partialFailure(sections: sectionNames)
        }

        let sections = receivedSections
            .sorted { $0.key < $1.key }
            .map(\.value)
        return Self.makeDashboard(sections: sections)
    }

    func makeRequest(for section: AnalyticsAPIContract.Section) throws -> URLRequest {
        guard var components = URLComponents(
            url: configuration.analyticsBaseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw AnalyticsError.invalidResponse
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "id" || $0.name == "section" }
        queryItems.append(contentsOf: [
            URLQueryItem(name: "id", value: AnalyticsAPIContract.requestID),
            URLQueryItem(name: "section", value: section.queryValue)
        ])
        components.queryItems = queryItems

        guard let url = components.url else {
            throw AnalyticsError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let apiKey = configuration.analyticsAPIKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        try credentialsStore.addAuthentication(to: &request)
        return request
    }

    private nonisolated static func fetchSection(
        index: Int,
        contract: AnalyticsAPIContract.Section,
        request: URLRequest,
        session: URLSession
    ) async -> SectionFetchOutcome {
        do {
            let (data, response) = try await session.data(for: request)
            try validate(response)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let analyticsResponse = try decoder.decode(AnalyticsAPIResponse.self, from: data)
            let section = try analyticsResponse.dashboardSection(preferredTitle: contract.displayName)
            return SectionFetchOutcome(
                index: index,
                displayName: contract.displayName,
                section: section,
                authenticationFailed: false
            )
        } catch AnalyticsError.authenticationRequired {
            return SectionFetchOutcome(
                index: index,
                displayName: contract.displayName,
                section: nil,
                authenticationFailed: true
            )
        } catch {
            return SectionFetchOutcome(
                index: index,
                displayName: contract.displayName,
                section: nil,
                authenticationFailed: false
            )
        }
    }

    nonisolated static func validate(_ response: URLResponse) throws {
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

    private nonisolated static func makeDashboard(sections: [DashboardSection]) -> Dashboard {
        Dashboard(
            id: "analytics",
            title: "Аналитика",
            fetchedAt: Date(),
            sections: sections
        )
    }
}

private struct SectionFetchOutcome: Sendable {
    let index: Int
    let displayName: String
    let section: DashboardSection?
    let authenticationFailed: Bool
}

struct AnalyticsAPIResponse: Decodable, Sendable {
    let sections: [AnalyticsAPISection]

    private enum CodingKeys: String, CodingKey {
        case sections
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sections = container.decodeFlexibleArray(AnalyticsAPISection.self, forKey: .sections)
    }

    func toDashboard() throws -> Dashboard {
        guard !sections.isEmpty else {
            throw AnalyticsError.invalidResponse
        }

        var sectionIDCounts = [String: Int]()
        let dashboardSections = sections.enumerated().map { index, section in
            let title = section.normalizedName.isEmpty ? "Раздел \(index + 1)" : section.normalizedName
            let baseID = title.stableID.isEmpty ? "section-\(index)" : title.stableID
            let sectionID = Self.uniqueID(baseID, counts: &sectionIDCounts)
            return section.toDashboardSection(title: title, sectionID: sectionID)
        }

        return Dashboard(
            id: dashboardSections.count == 1 ? dashboardSections[0].id : "analytics",
            title: dashboardSections.count == 1 ? dashboardSections[0].title : "Аналитика",
            fetchedAt: Date(),
            sections: dashboardSections
        )
    }

    func dashboardSection(preferredTitle: String) throws -> DashboardSection {
        guard !sections.isEmpty else {
            throw AnalyticsError.invalidResponse
        }

        let preferredName = AnalyticsAPIContract.normalize(preferredTitle)
        let section = sections.first {
            AnalyticsAPIContract.normalize($0.name) == preferredName
        } ?? sections[0]
        let rawTitle = section.normalizedName
        let title = rawTitle.isEmpty || AnalyticsAPIContract.normalize(rawTitle) == preferredName
            ? preferredTitle
            : rawTitle
        let sectionID = title.stableID.isEmpty ? preferredTitle.stableID : title.stableID
        return section.toDashboardSection(title: title, sectionID: sectionID)
    }

    private static func uniqueID(_ baseID: String, counts: inout [String: Int]) -> String {
        let occurrence = counts[baseID, default: 0]
        counts[baseID] = occurrence + 1
        return occurrence == 0 ? baseID : "\(baseID)#\(occurrence + 1)"
    }
}

struct AnalyticsAPISection: Decodable, Sendable {
    let name: String
    let values: [AnalyticsAPIIndicator]

    private enum CodingKeys: String, CodingKey {
        case name
        case values
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.decodeFlexibleString(forKey: .name) ?? ""
        values = container.decodeFlexibleArray(AnalyticsAPIIndicator.self, forKey: .values)
    }

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func toDashboardSection(title: String, sectionID: String) -> DashboardSection {
        var layoutIDCounts = [String: Int]()
        let indicators = values.enumerated().map { index, indicator in
            let baseLayoutID = indicator.layoutIdentifier(index: index)
            let occurrence = layoutIDCounts[baseLayoutID, default: 0]
            layoutIDCounts[baseLayoutID] = occurrence + 1
            let uniqueLayoutID = occurrence == 0
                ? baseLayoutID
                : "\(baseLayoutID)#\(occurrence + 1)"
            return indicator.toIndicator(layoutID: uniqueLayoutID, sectionID: sectionID)
        }

        return DashboardSection(id: sectionID, title: title, indicators: indicators)
    }
}

struct AnalyticsAPIIndicator: Decodable, Sendable {
    let id: String?
    let identifier: String?
    let name: String
    let values: [AnalyticsAPIValue]
    let type: ChartType
    let value: Double?
    let valueMax: Double?
    let unit: String?
    let colorGraph: String?
    let colorValue: String?
    let showLegend: Bool?
    let showTotal: Bool?
    let showDetails: Bool?
    let showValueLabels: Bool?
    let detailsOrientation: DetailsOrientation?
    let widthPercent: Double?
    let useCompactNumbers: Bool?
    let valueSpacing: Double?
    let barLayout: BarLayout?
    let lineStyle: ChartLineStyle?
    let forecastFromIndex: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case identifier
        case name
        case values
        case type
        case value
        case valueMax
        case unit
        case colorGraph
        case colorValue
        case showLegend
        case showTotal
        case showTotalSnake = "show_total"
        case displayTotal
        case showDetails
        case showDetailsSnake = "show_details"
        case displayDetails
        case showValueLabels
        case showLabels
        case detailsOrientation
        case useCompactNumbers
        case useAbbreviations
        case compactValues
        case valueSpacing
        case valueGap
        case itemSpacing
        case barLayout
        case lineStyle
        case dashed
        case forecastFromIndex
        case widthPercent
        case width
        case halfWidth
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleString(forKey: .id)
        identifier = container.decodeFlexibleString(forKey: .identifier)
        name = container.decodeFlexibleString(forKey: .name) ?? ""
        values = container.decodeFlexibleArray(AnalyticsAPIValue.self, forKey: .values)
        type = (try? container.decode(ChartType.self, forKey: .type)) ?? .bar
        value = container.decodeFlexibleDouble(forKey: .value)
        valueMax = container.decodeFlexibleDouble(forKey: .valueMax)
        unit = container.decodeFlexibleString(forKey: .unit)
        colorGraph = container.decodeFlexibleString(forKey: .colorGraph)
        colorValue = container.decodeFlexibleString(forKey: .colorValue)
        showLegend = container.decodeFlexibleBool(forKey: .showLegend)
        showTotal = container.decodeFlexibleBool(forKey: .showTotal)
            ?? container.decodeFlexibleBool(forKey: .showTotalSnake)
            ?? container.decodeFlexibleBool(forKey: .displayTotal)
        showDetails = container.decodeFlexibleBool(forKey: .showDetails)
            ?? container.decodeFlexibleBool(forKey: .showDetailsSnake)
            ?? container.decodeFlexibleBool(forKey: .displayDetails)
        showValueLabels = container.decodeFlexibleBool(forKey: .showValueLabels)
            ?? container.decodeFlexibleBool(forKey: .showLabels)
        detailsOrientation = container.decodeFlexibleString(forKey: .detailsOrientation)
            .flatMap {
                DetailsOrientation(
                    rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                )
            }
        useCompactNumbers = container.decodeFlexibleBool(forKey: .useCompactNumbers)
            ?? container.decodeFlexibleBool(forKey: .useAbbreviations)
            ?? container.decodeFlexibleBool(forKey: .compactValues)

        let rawSpacing = container.decodeFlexibleDouble(forKey: .valueSpacing)
            ?? container.decodeFlexibleDouble(forKey: .valueGap)
            ?? container.decodeFlexibleDouble(forKey: .itemSpacing)
        valueSpacing = rawSpacing.map { min(max($0, 0), 64) }

        let rawBarLayout = container.decodeFlexibleString(forKey: .barLayout)?.lowercased()
        barLayout = rawBarLayout.flatMap(BarLayout.init(rawValue:))
        lineStyle = normalizedLineStyle(
            container.decodeFlexibleString(forKey: .lineStyle),
            dashed: container.decodeFlexibleBool(forKey: .dashed)
        )
        forecastFromIndex = container.decodeFlexibleDouble(forKey: .forecastFromIndex)
            .map { max(0, Int($0)) }

        let rawWidth = container.decodeFlexibleDouble(forKey: .widthPercent)
            ?? container.decodeFlexibleDouble(forKey: .width)
        let halfWidth = container.decodeFlexibleBool(forKey: .halfWidth)
        if let rawWidth {
            widthPercent = rawWidth <= 50 ? 50 : 100
        } else if let halfWidth {
            widthPercent = halfWidth ? 50 : 100
        } else {
            widthPercent = nil
        }
    }

    func layoutIdentifier(index: Int) -> String {
        for candidate in [id, identifier] {
            if let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
               !candidate.isEmpty {
                return candidate
            }
        }
        return String(index)
    }

    func toIndicator(layoutID: String, sectionID: String) -> Indicator {
        let totalRow = values.first {
            $0.normalizedGroup.isEmpty && !$0.hasSubgroupValues
        }
        let rowValues = type == .compactBar
            ? values.filter(\.hasCompactBarValues)
            : values.filter { !$0.normalizedGroup.isEmpty || $0.hasSubgroupValues }
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
            id: "\(sectionID)-\(layoutID)",
            title: name,
            value: scalarValue.map { Decimal($0) },
            valueMax: valueMax ?? totalRow?.valueMax ?? primaryValue?.valueMax,
            unit: unit ?? totalRow?.unit ?? defaultUnit,
            chartType: type,
            source: "DGU_APP_Mobile_Client/analitycs",
            colorGraph: colorGraph ?? totalRow?.colorGraph ?? primaryValue?.colorGraph,
            colorValue: colorValue ?? totalRow?.colorValue ?? primaryValue?.colorValue,
            showLegend: showLegend,
            showTotal: showTotal,
            showDetails: showDetails,
            showValueLabels: showValueLabels,
            detailsOrientation: detailsOrientation,
            widthPercent: widthPercent,
            useCompactNumbers: useCompactNumbers,
            valueSpacing: valueSpacing,
            barLayout: barLayout,
            lineStyle: lineStyle,
            forecastFromIndex: forecastFromIndex,
            rows: rows
        )
    }

    private var defaultUnit: String? {
        switch type {
        case .oneValue, .linearProgress, .gauge, .geoMap, .compactBar:
            nil
        case .bar, .horizontalBar, .stackedBar, .donut, .percentDonut,
             .line, .area, .splineLine, .splineArea, .forecastLine:
            "чел."
        }
    }
}

struct AnalyticsAPIValue: Decodable, Sendable {
    let name: String?
    let group: String?
    let value: Double?
    let valueMax: Double?
    let unit: String?
    let colorGraph: String?
    let colorValue: String?
    let lineStyle: ChartLineStyle?
    let totalLabel: String?
    let subgroup: [AnalyticsAPISubgroup]?

    private enum CodingKeys: String, CodingKey {
        case name
        case group
        case value
        case valueMax
        case unit
        case colorGraph
        case colorValue
        case lineStyle
        case dashed
        case totalLabel
        case subgroup
        case values
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.decodeFlexibleString(forKey: .name)
        group = container.decodeFlexibleString(forKey: .group)
        value = container.decodeFlexibleDouble(forKey: .value)
        valueMax = container.decodeFlexibleDouble(forKey: .valueMax)
        unit = container.decodeFlexibleString(forKey: .unit)
        colorGraph = container.decodeFlexibleString(forKey: .colorGraph)
        colorValue = container.decodeFlexibleString(forKey: .colorValue)
        lineStyle = normalizedLineStyle(
            container.decodeFlexibleString(forKey: .lineStyle),
            dashed: container.decodeFlexibleBool(forKey: .dashed)
        )
        totalLabel = container.decodeFlexibleString(forKey: .totalLabel)

        let subgroupValues = container.decodeFlexibleArray(AnalyticsAPISubgroup.self, forKey: .subgroup)
        let nestedValues = container.decodeFlexibleArray(AnalyticsAPISubgroup.self, forKey: .values)
        let combinedValues = subgroupValues.isEmpty ? nestedValues : subgroupValues
        subgroup = combinedValues.isEmpty ? nil : combinedValues
    }

    var normalizedGroup: String {
        (group ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedName: String {
        (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasCompactBarValues: Bool {
        value != nil || hasSubgroupValues
    }

    var hasSubgroupValues: Bool {
        subgroup?.isEmpty == false
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
                        colorValue: subgroup.colorValue ?? colorValue,
                        lineStyle: subgroup.lineStyle ?? lineStyle,
                        totalLabel: totalLabel
                    )
                }
            }

            let groupLabel = normalizedGroup.isEmpty ? preferredLabel(index: index) : normalizedGroup
            return subgroup.enumerated().map { subgroupIndex, subgroup in
                IndicatorRow(
                    id: "\(groupLabel.stableID)-\(subgroupIndex)-\(subgroup.name.stableID)",
                    label: groupLabel,
                    value: subgroup.value,
                    series: subgroup.name,
                    sortOrder: index * 100 + subgroupIndex,
                    colorGraph: subgroup.colorGraph ?? colorGraph,
                    colorValue: subgroup.colorValue ?? colorValue,
                    lineStyle: subgroup.lineStyle ?? lineStyle,
                    totalLabel: totalLabel
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
                colorValue: colorValue,
                lineStyle: lineStyle,
                totalLabel: totalLabel
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

struct AnalyticsAPISubgroup: Decodable, Sendable {
    let name: String
    let value: Double
    let colorGraph: String?
    let colorValue: String?
    let lineStyle: ChartLineStyle?

    private enum CodingKeys: String, CodingKey {
        case name
        case group
        case value
        case colorGraph
        case colorValue
        case lineStyle
        case dashed
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.decodeFlexibleString(forKey: .name)
            ?? container.decodeFlexibleString(forKey: .group)
            ?? ""
        value = container.decodeFlexibleDouble(forKey: .value) ?? 0
        colorGraph = container.decodeFlexibleString(forKey: .colorGraph)
        colorValue = container.decodeFlexibleString(forKey: .colorValue)
        lineStyle = normalizedLineStyle(
            container.decodeFlexibleString(forKey: .lineStyle),
            dashed: container.decodeFlexibleBool(forKey: .dashed)
        )
    }
}

private func normalizedLineStyle(_ rawValue: String?, dashed: Bool?) -> ChartLineStyle? {
    switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case ChartLineStyle.dashed.rawValue:
        return .dashed
    case ChartLineStyle.solid.rawValue:
        return .solid
    default:
        return dashed.map { $0 ? .dashed : .solid }
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T] {
        if let values = try? decode([T].self, forKey: key) {
            return values
        }
        if let value = try? decode(T.self, forKey: key) {
            return [value]
        }
        return []
    }

    func decodeFlexibleString(forKey key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Decimal.self, forKey: key) {
            return NSDecimalNumber(decimal: value).stringValue
        }
        if let value = try? decode(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        return nil
    }

    func decodeFlexibleDouble(forKey key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        guard let text = try? decode(String.self, forKey: key) else {
            return nil
        }

        let normalized = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: "")
            .replacingOccurrences(of: "\u{202f}", with: "")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    func decodeFlexibleBool(forKey key: Key) -> Bool? {
        if let value = try? decode(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return value != 0
        }
        guard let value = try? decode(String.self, forKey: key) else {
            return nil
        }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            return nil
        }
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
