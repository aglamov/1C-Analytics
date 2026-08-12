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
        onEvent: @escaping @MainActor @Sendable (AnalyticsSectionFetchEvent) -> Void
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
        var failedSections = [(index: Int, name: String, failure: SectionFetchFailure)]()

        AnalyticsAPIContract.sections.forEach { onEvent(.started($0)) }

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
                    let contract = AnalyticsAPIContract.sections[outcome.index]
                    onEvent(.succeeded(contract, section))
                } else if let failure = outcome.failure {
                    failedSections.append((outcome.index, outcome.displayName, failure))
                    let contract = AnalyticsAPIContract.sections[outcome.index]
                    onEvent(.failed(contract, failure.error.localizedDescription))
                }
            }
        }

        if Task.isCancelled || failedSections.contains(where: { $0.failure == .cancelled }) {
            throw CancellationError()
        }

        if failedSections.contains(where: { $0.failure == .authenticationRequired }) {
            throw AnalyticsError.authenticationRequired
        }

        if !failedSections.isEmpty {
            if receivedSections.isEmpty, let failure = failedSections.sorted(by: { $0.index < $1.index }).first?.failure {
                throw failure.error
            }

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

    func fetchExtendedSection(for section: AnalyticsAPIContract.Section) async throws -> DashboardSection {
        let request: URLRequest
        do {
            request = try makeRequest(for: section, isExtended: true)
        } catch AuthenticationError.missingCredentials {
            throw AnalyticsError.authenticationRequired
        }

        let (data, response) = try await urlSession.data(for: request)
        try Self.validate(response)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let analyticsResponse = try decoder.decode(AnalyticsAPIResponse.self, from: data)
        return try analyticsResponse.dashboardSection(
            preferredTitle: section.displayName,
            fetchedAt: Date(),
            indicatorIDNamespace: "extended"
        )
    }

    func makeRequest(
        for section: AnalyticsAPIContract.Section,
        isExtended: Bool = false
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: configuration.analyticsBaseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw AnalyticsError.invalidResponse
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "id" || $0.name == "section" }
        queryItems.append(URLQueryItem(
            name: "section",
            value: isExtended ? "\(section.queryValue)_Расширенный" : section.queryValue
        ))
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
            let section = try analyticsResponse.dashboardSection(
                preferredTitle: contract.displayName,
                fetchedAt: Date()
            )
            return SectionFetchOutcome(
                index: index,
                displayName: contract.displayName,
                section: section,
                failure: nil
            )
        } catch AnalyticsError.authenticationRequired {
            return SectionFetchOutcome(
                index: index,
                displayName: contract.displayName,
                section: nil,
                failure: .authenticationRequired
            )
        } catch let error as URLError where error.code == .cancelled {
            return SectionFetchOutcome(
                index: index,
                displayName: contract.displayName,
                section: nil,
                failure: .cancelled
            )
        } catch let error as URLError {
            return SectionFetchOutcome(
                index: index,
                displayName: contract.displayName,
                section: nil,
                failure: .network(error.code)
            )
        } catch let error as AnalyticsError {
            return SectionFetchOutcome(
                index: index,
                displayName: contract.displayName,
                section: nil,
                failure: .analytics(error)
            )
        } catch is DecodingError {
            return SectionFetchOutcome(
                index: index,
                displayName: contract.displayName,
                section: nil,
                failure: .invalidPayload
            )
        } catch is CancellationError {
            return SectionFetchOutcome(
                index: index,
                displayName: contract.displayName,
                section: nil,
                failure: .cancelled
            )
        } catch {
            return SectionFetchOutcome(
                index: index,
                displayName: contract.displayName,
                section: nil,
                failure: .other(error.localizedDescription)
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
    let failure: SectionFetchFailure?
}

private enum SectionFetchFailure: Sendable, Equatable {
    case authenticationRequired
    case network(URLError.Code)
    case analytics(AnalyticsError)
    case invalidPayload
    case cancelled
    case other(String)

    var error: Error {
        switch self {
        case .authenticationRequired:
            AnalyticsError.authenticationRequired
        case let .network(code):
            URLError(code)
        case let .analytics(error):
            error
        case .invalidPayload:
            AnalyticsError.invalidResponse
        case .cancelled:
            CancellationError()
        case .other:
            AnalyticsError.invalidResponse
        }
    }
}

struct AnalyticsAPIResponse: Decodable, Sendable {
    let sections: [AnalyticsAPISection]

    private enum CodingKeys: String, CodingKey {
        case sections
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sections = try container.decodeFlexibleArray(AnalyticsAPISection.self, forKey: .sections)
    }

    func toDashboard() throws -> Dashboard {
        guard !sections.isEmpty else {
            throw AnalyticsError.invalidResponse
        }

        let fetchedAt = Date()
        var sectionIDCounts = [String: Int]()
        let dashboardSections = sections.enumerated().map { index, section in
            let title = section.normalizedName.isEmpty ? "Раздел \(index + 1)" : section.normalizedName
            let baseID = title.stableID.isEmpty ? "section-\(index)" : title.stableID
            let sectionID = Self.uniqueID(baseID, counts: &sectionIDCounts)
            return section.toDashboardSection(title: title, sectionID: sectionID, fetchedAt: fetchedAt)
        }

        return Dashboard(
            id: dashboardSections.count == 1 ? dashboardSections[0].id : "analytics",
            title: dashboardSections.count == 1 ? dashboardSections[0].title : "Аналитика",
            fetchedAt: Date(),
            sections: dashboardSections
        )
    }

    func dashboardSection(
        preferredTitle: String,
        fetchedAt: Date = Date(),
        indicatorIDNamespace: String? = nil
    ) throws -> DashboardSection {
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
        return section.toDashboardSection(
            title: title,
            sectionID: sectionID,
            fetchedAt: fetchedAt,
            indicatorIDNamespace: indicatorIDNamespace
        )
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
    let hasExtended: Bool

    private enum CodingKeys: String, CodingKey {
        case name
        case values
        case hasExtended
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeFlexibleString(forKey: .name) ?? ""
        values = try container.decodeFlexibleArray(AnalyticsAPIIndicator.self, forKey: .values)
        hasExtended = try container.decodeFlexibleBool(forKey: .hasExtended) ?? false
    }

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func toDashboardSection(
        title: String,
        sectionID: String,
        fetchedAt: Date?,
        indicatorIDNamespace: String? = nil
    ) -> DashboardSection {
        var layoutIDCounts = [String: Int]()
        let indicators = values.enumerated().map { index, indicator in
            let baseLayoutID = indicator.layoutIdentifier(index: index)
            let occurrence = layoutIDCounts[baseLayoutID, default: 0]
            layoutIDCounts[baseLayoutID] = occurrence + 1
            let uniqueLayoutID = occurrence == 0
                ? baseLayoutID
                : "\(baseLayoutID)#\(occurrence + 1)"
            let namespacedLayoutID = indicatorIDNamespace.map { "\($0)-\(uniqueLayoutID)" }
                ?? uniqueLayoutID
            return indicator.toIndicator(layoutID: namespacedLayoutID, sectionID: sectionID)
        }

        return DashboardSection(
            id: sectionID,
            title: title,
            indicators: indicators,
            fetchedAt: fetchedAt,
            hasExtended: hasExtended
        )
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
    let showRowValues: Bool?
    let alwaysShowPointValues: Bool?
    let showYAxisLabels: Bool?
    let detailsOrientation: DetailsOrientation?
    let widthPercent: Double?
    let useCompactNumbers: Bool?
    let valueSpacing: Double?
    let barLayout: BarLayout?
    let lineStyle: ChartLineStyle?
    let forecastFromIndex: Int?
    let highlightCrossing: Bool?
    let highlightSeriesIndex: Int?
    let referenceSeriesIndex: Int?
    let isExplicitPlanFactProgress: Bool
    let hierarchy: ExpandableHierarchy?

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
        case showRowValues
        case showLabels
        case displayValueLabels
        case alwaysShowPointValues
        case showPointValues
        case displayPointValues
        case showYAxisLabels
        case showYAxis
        case showScale
        case displayYAxisLabels
        case detailsOrientation
        case detailOrientation
        case detailsLayout
        case useCompactNumbers
        case useAbbreviations
        case compactValues
        case abbreviateValues
        case valueSpacing
        case valueGap
        case itemSpacing
        case barLayout
        case lineStyle
        case dashed
        case forecastFromIndex
        case highlightCrossing
        case highlightSeriesIndex
        case referenceSeriesIndex
        case barMode
        case series
        case nodes
        case totalSeries
        case widthPercent
        case width
        case halfWidth
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(forKey: .id)
        identifier = try container.decodeFlexibleString(forKey: .identifier)
        name = try container.decodeFlexibleString(forKey: .name) ?? ""
        values = try container.decodeFlexibleArray(AnalyticsAPIValue.self, forKey: .values)
        type = try container.decodeIfPresent(ChartType.self, forKey: .type) ?? .bar
        isExplicitPlanFactProgress = try container.decodeFlexibleString(forKey: .type)
            == "PlanFactProgress"

        if type == .expandableHierarchy {
            let rawBarMode = try container.decodeFlexibleString(forKey: .barMode)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard let rawBarMode,
                  let barMode = ExpandableHierarchyBarMode(rawValue: rawBarMode) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .barMode,
                    in: container,
                    debugDescription: "ExpandableTableMark requires barMode: stacked, grouped, or single"
                )
            }

            let hierarchySeries = try container.decodeFlexibleArray(
                AnalyticsAPIHierarchySeries.self,
                forKey: .series
            )
            let hierarchyNodes = try container.decodeFlexibleArray(
                AnalyticsAPIHierarchyNode.self,
                forKey: .nodes
            )
            hierarchy = try AnalyticsAPIHierarchy(
                barMode: barMode,
                series: hierarchySeries,
                nodes: hierarchyNodes,
                totalSeries: try container.decodeFlexibleString(forKey: .totalSeries)
            ).toDomainModel()
        } else {
            hierarchy = nil
        }
        value = try container.decodeFlexibleDouble(forKey: .value)
        valueMax = try container.decodeFlexibleDouble(forKey: .valueMax)
        unit = try container.decodeFlexibleString(forKey: .unit)
        colorGraph = try container.decodeFlexibleString(forKey: .colorGraph)
        colorValue = try container.decodeFlexibleString(forKey: .colorValue)
        showLegend = try container.decodeFlexibleBool(forKey: .showLegend)
        showTotal = try container.decodeFlexibleBool(forKey: .showTotal)
            ?? container.decodeFlexibleBool(forKey: .showTotalSnake)
            ?? container.decodeFlexibleBool(forKey: .displayTotal)
        showDetails = try container.decodeFlexibleBool(forKey: .showDetails)
            ?? container.decodeFlexibleBool(forKey: .showDetailsSnake)
            ?? container.decodeFlexibleBool(forKey: .displayDetails)
        showValueLabels = try container.decodeFlexibleBool(forKey: .showValueLabels)
            ?? container.decodeFlexibleBool(forKey: .showLabels)
            ?? container.decodeFlexibleBool(forKey: .displayValueLabels)
        showRowValues = try container.decodeFlexibleBool(forKey: .showRowValues)
        alwaysShowPointValues = try container.decodeFlexibleBool(forKey: .alwaysShowPointValues)
            ?? container.decodeFlexibleBool(forKey: .showPointValues)
            ?? container.decodeFlexibleBool(forKey: .displayPointValues)
        showYAxisLabels = try container.decodeFlexibleBool(forKey: .showYAxisLabels)
            ?? container.decodeFlexibleBool(forKey: .showYAxis)
            ?? container.decodeFlexibleBool(forKey: .showScale)
            ?? container.decodeFlexibleBool(forKey: .displayYAxisLabels)
        let rawDetailsOrientation = try container.decodeFlexibleString(forKey: .detailsOrientation)
            ?? container.decodeFlexibleString(forKey: .detailOrientation)
            ?? container.decodeFlexibleString(forKey: .detailsLayout)
        detailsOrientation = rawDetailsOrientation
            .flatMap {
                DetailsOrientation(
                    rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                )
            }
        useCompactNumbers = try container.decodeFlexibleBool(forKey: .useCompactNumbers)
            ?? container.decodeFlexibleBool(forKey: .useAbbreviations)
            ?? container.decodeFlexibleBool(forKey: .compactValues)
            ?? container.decodeFlexibleBool(forKey: .abbreviateValues)

        let rawSpacing = try container.decodeFlexibleDouble(forKey: .valueSpacing)
            ?? container.decodeFlexibleDouble(forKey: .valueGap)
            ?? container.decodeFlexibleDouble(forKey: .itemSpacing)
        valueSpacing = rawSpacing.map { min(max($0, 0), 64) }

        let rawBarLayout = try container.decodeFlexibleString(forKey: .barLayout)?.lowercased()
        barLayout = rawBarLayout.flatMap(BarLayout.init(rawValue:))
        lineStyle = normalizedLineStyle(
            try container.decodeFlexibleString(forKey: .lineStyle),
            dashed: try container.decodeFlexibleBool(forKey: .dashed)
        )
        forecastFromIndex = try container.decodeFlexibleDouble(forKey: .forecastFromIndex)
            .map { max(0, Int($0)) }
        highlightCrossing = try container.decodeFlexibleBool(forKey: .highlightCrossing)
        highlightSeriesIndex = try container.decodeFlexibleDouble(forKey: .highlightSeriesIndex)
            .map(Int.init)
        referenceSeriesIndex = try container.decodeFlexibleDouble(forKey: .referenceSeriesIndex)
            .map(Int.init)

        if type == .radar {
            guard values.count >= 3, !values.contains(where: { value in
                if let scalar = value.value, scalar < 0 { return true }
                return value.subgroup?.contains(where: { ($0.value ?? 0) < 0 }) == true
            }) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .values,
                    in: container,
                    debugDescription: "RadarMark requires at least three axes and non-negative values"
                )
            }
        }

        let rawWidth = try container.decodeFlexibleDouble(forKey: .widthPercent)
            ?? container.decodeFlexibleDouble(forKey: .width)
        let halfWidth = try container.decodeFlexibleBool(forKey: .halfWidth)
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
        let chartType = resolvedChartType
        let categorizedValues = values.filter { $0.hasCategoryLabel || $0.hasSubgroupValues }
        let uncategorizedValues = values.filter {
            !$0.hasCategoryLabel && !$0.hasSubgroupValues
        }
        let totalRow = categorizedValues.isEmpty
            ? (chartType.displaysRows ? nil : uncategorizedValues.first)
            : uncategorizedValues.first
        let rowValues: [AnalyticsAPIValue]
        if chartType == .compactBar {
            rowValues = values.filter(\.hasCompactBarValues)
        } else if !categorizedValues.isEmpty {
            rowValues = categorizedValues
        } else if chartType.displaysRows {
            // Some 1C responses contain several numeric values without group
            // labels. They are separate data points, not duplicate total rows.
            rowValues = uncategorizedValues.filter { $0.value != nil }
        } else {
            rowValues = []
        }
        var rows = rowValues
            .enumerated()
            .flatMap { rowIndex, value in
                value.toRows(index: rowIndex, chartType: chartType)
            }
        let calculatedTotal = rows.isEmpty
            ? nil
            : rows.reduce(0) { $0 + $1.value }
        let scalarValue = value
            ?? totalRow?.value
            ?? calculatedTotal
        let primaryValue = values.first

        if rows.isEmpty,
           let scalarValue,
           chartType == .oneValue || chartType == .linearProgress || chartType == .gauge {
            rows = [
                IndicatorRow(
                    id: "scalar-value",
                    label: name.isEmpty ? "Значение" : name,
                    value: scalarValue,
                    series: nil,
                    sortOrder: 0,
                    colorGraph: primaryValue?.colorGraph ?? colorGraph,
                    colorValue: primaryValue?.colorValue ?? colorValue,
                    lineStyle: primaryValue?.lineStyle ?? lineStyle,
                    valueLabel: primaryValue?.valueLabel
                )
            ]
        }

        return Indicator(
            id: "\(sectionID)-\(layoutID)",
            title: name,
            value: scalarValue.map { Decimal($0) },
            valueMax: valueMax ?? totalRow?.valueMax ?? primaryValue?.valueMax,
            unit: unit ?? totalRow?.unit,
            chartType: chartType,
            source: "DGU_APP_Mobile_Client/analitycs",
            colorGraph: colorGraph ?? totalRow?.colorGraph ?? primaryValue?.colorGraph,
            colorValue: colorValue ?? totalRow?.colorValue ?? primaryValue?.colorValue,
            showLegend: isExplicitPlanFactProgress ? (showLegend ?? false) : showLegend,
            showTotal: isExplicitPlanFactProgress ? (showTotal ?? false) : showTotal,
            showDetails: showDetails,
            showValueLabels: showValueLabels,
            showRowValues: showRowValues,
            alwaysShowPointValues: alwaysShowPointValues,
            showYAxisLabels: showYAxisLabels,
            detailsOrientation: detailsOrientation,
            widthPercent: widthPercent,
            useCompactNumbers: useCompactNumbers,
            valueSpacing: valueSpacing,
            barLayout: barLayout,
            lineStyle: lineStyle,
            forecastFromIndex: forecastFromIndex,
            highlightCrossing: highlightCrossing,
            highlightSeriesIndex: highlightSeriesIndex,
            referenceSeriesIndex: referenceSeriesIndex,
            isExplicitPlanFactProgress: isExplicitPlanFactProgress,
            hierarchy: hierarchy,
            rows: rows
        )
    }

    private var resolvedChartType: ChartType {
        if type == .radar || type == .expandableHierarchy {
            return type
        }

        let normalizedName = AnalyticsAPIContract.normalize(name)
        let citizenshipIndicatorName = AnalyticsAPIContract.normalize("Всего обучающихся РФ и ИГ")

        if normalizedName == citizenshipIndicatorName {
            return .horizontalBar
        }

        let hasMultipleValues = values.reduce(0) { count, value in
            count + max(value.subgroup?.count ?? 0, value.value == nil ? 0 : 1)
        } >= 2

        if name.isPlanFactIndicatorTitle,
           normalizedName.contains(AnalyticsAPIContract.normalize("контракт")),
           hasMultipleValues {
            return .horizontalBar
        }

        if normalizedName.contains(AnalyticsAPIContract.normalize("средний балл егэ")),
           hasMultipleValues,
           !type.displaysRows {
            return .bar
        }

        return type
    }

}

private extension ChartType {
    var displaysRows: Bool {
        switch self {
        case .bar, .compactBar, .horizontalBar, .stackedBar, .donut, .percentDonut,
             .line, .area, .splineLine, .splineArea, .forecastLine, .radar, .geoMap:
            true
        case .oneValue, .linearProgress, .gauge, .expandableHierarchy:
            false
        }
    }
}

private struct AnalyticsAPIHierarchy: Sendable {
    let barMode: ExpandableHierarchyBarMode
    let series: [AnalyticsAPIHierarchySeries]
    let nodes: [AnalyticsAPIHierarchyNode]
    let totalSeries: String?

    func toDomainModel() throws -> ExpandableHierarchy {
        var seriesKeys = Set<String>()
        let uniqueSeries = series.compactMap { apiSeries -> ExpandableHierarchySeries? in
            let model = apiSeries.domainModel
            guard !model.key.isEmpty, seriesKeys.insert(model.key).inserted else {
                return nil
            }
            return model
        }

        return ExpandableHierarchy(
            barMode: barMode,
            series: uniqueSeries,
            nodes: try Self.domainNodes(nodes, parentPath: "node"),
            totalSeries: totalSeries
        )
    }

    private static func domainNodes(
        _ nodes: [AnalyticsAPIHierarchyNode],
        parentPath: String
    ) throws -> [ExpandableHierarchyNode] {
        var explicitSiblingIDs = Set<String>()

        return try nodes.enumerated().map { index, node in
            let explicitID = node.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !explicitID.isEmpty, !explicitSiblingIDs.insert(explicitID).inserted {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [],
                    debugDescription: "ExpandableTableMark contains duplicate sibling id: \(explicitID)"
                ))
            }
            let nodeID = explicitID.isEmpty ? String(index + 1) : explicitID
            let path = "\(parentPath)/\(nodeID)"

            return ExpandableHierarchyNode(
                id: path,
                label: node.label,
                values: node.values.mapValues(\.domainModel),
                children: try domainNodes(node.children, parentPath: path)
            )
        }
    }
}

private struct AnalyticsAPIHierarchySeries: Decodable, Sendable {
    let key: String
    let name: String
    let colorGraph: String?
    let colorValue: String?
    let unit: String?

    private enum CodingKeys: String, CodingKey {
        case key
        case name
        case colorGraph
        case colorValue
        case unit
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeFlexibleString(forKey: .key) ?? ""
        name = try container.decodeFlexibleString(forKey: .name) ?? key
        colorGraph = try container.decodeFlexibleString(forKey: .colorGraph)
        colorValue = try container.decodeFlexibleString(forKey: .colorValue)
        unit = try container.decodeFlexibleString(forKey: .unit)
    }

    var domainModel: ExpandableHierarchySeries {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExpandableHierarchySeries(
            key: normalizedKey,
            name: normalizedName.isEmpty ? normalizedKey : normalizedName,
            colorGraph: colorGraph,
            colorValue: colorValue,
            unit: unit
        )
    }
}

private struct AnalyticsAPIHierarchyNode: Decodable, Sendable {
    let id: String?
    let label: String
    let values: [String: AnalyticsAPIHierarchyValue]
    let children: [AnalyticsAPIHierarchyNode]

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case values
        case children
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(forKey: .id)
        label = try container.decodeFlexibleString(forKey: .label) ?? ""
        values = try container.decodeIfPresent(
            [String: AnalyticsAPIHierarchyValue].self,
            forKey: .values
        ) ?? [:]
        children = try container.decodeFlexibleArray(
            AnalyticsAPIHierarchyNode.self,
            forKey: .children
        )
    }
}

private struct AnalyticsAPIHierarchyValue: Decodable, Sendable {
    let value: Double
    let valueLabel: String?

    private enum CodingKeys: String, CodingKey {
        case value
        case valueLabel
        case displayValue
        case displayLabel
    }

    init(from decoder: any Decoder) throws {
        if let scalar = try? decoder.singleValueContainer(),
           let value = try? scalar.decode(Double.self) {
            self.value = value
            valueLabel = nil
            return
        }

        if let scalar = try? decoder.singleValueContainer(),
           let string = try? scalar.decode(String.self),
           let value = Double(string.replacingOccurrences(of: ",", with: ".")) {
            self.value = value
            valueLabel = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decodeFlexibleDouble(forKey: .value) ?? 0
        valueLabel = try container.decodeFlexibleString(forKey: .valueLabel)
            ?? container.decodeFlexibleString(forKey: .displayValue)
            ?? container.decodeFlexibleString(forKey: .displayLabel)
    }

    var domainModel: ExpandableHierarchyValue {
        ExpandableHierarchyValue(value: value, valueLabel: valueLabel)
    }
}

struct AnalyticsAPIValue: Decodable, Sendable {
    let name: String?
    let group: String?
    let title: String?
    let value: Double?
    let valueMax: Double?
    let unit: String?
    let colorGraph: String?
    let colorValue: String?
    let lineStyle: ChartLineStyle?
    let totalLabel: String?
    let valueLabel: String?
    let subgroup: [AnalyticsAPISubgroup]?

    private enum CodingKeys: String, CodingKey {
        case name
        case group
        case title
        case value
        case valueMax
        case unit
        case colorGraph
        case colorValue
        case lineStyle
        case dashed
        case totalLabel
        case displayTotal
        case totalValue
        case valueLabel
        case displayValue
        case displayLabel
        case subgroup
        case values
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeFlexibleString(forKey: .name)
        group = try container.decodeFlexibleString(forKey: .group)
        title = try container.decodeFlexibleString(forKey: .title)
        value = try container.decodeFlexibleDouble(forKey: .value)
        valueMax = try container.decodeFlexibleDouble(forKey: .valueMax)
        unit = try container.decodeFlexibleString(forKey: .unit)
        colorGraph = try container.decodeFlexibleString(forKey: .colorGraph)
        colorValue = try container.decodeFlexibleString(forKey: .colorValue)
        lineStyle = normalizedLineStyle(
            try container.decodeFlexibleString(forKey: .lineStyle),
            dashed: try container.decodeFlexibleBool(forKey: .dashed)
        )
        totalLabel = try container.decodeFlexibleString(forKey: .totalLabel)
            ?? container.decodeFlexibleString(forKey: .displayTotal)
            ?? container.decodeFlexibleString(forKey: .totalValue)
        valueLabel = try container.decodeFlexibleString(forKey: .valueLabel)
            ?? container.decodeFlexibleString(forKey: .displayValue)
            ?? container.decodeFlexibleString(forKey: .displayLabel)

        let subgroupValues = try container.decodeFlexibleArray(AnalyticsAPISubgroup.self, forKey: .subgroup)
        let nestedValues = try container.decodeFlexibleArray(AnalyticsAPISubgroup.self, forKey: .values)
        let combinedValues = subgroupValues.isEmpty ? nestedValues : subgroupValues
        subgroup = combinedValues.isEmpty ? nil : combinedValues
    }

    var normalizedGroup: String {
        (group ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedName: String {
        (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedTitle: String {
        (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasCategoryLabel: Bool {
        !normalizedGroup.isEmpty || !normalizedName.isEmpty || !normalizedTitle.isEmpty
    }

    var hasCompactBarValues: Bool {
        value != nil || hasSubgroupValues
    }

    var hasSubgroupValues: Bool {
        subgroup?.isEmpty == false
    }

    func toRows(index: Int, chartType: ChartType) -> [IndicatorRow] {
        if let subgroup, !subgroup.isEmpty {
            let flattenedSubgroups = subgroup.flatMap {
                $0.flattened(
                    inheritedGraphColor: colorGraph,
                    inheritedValueColor: colorValue,
                    inheritedLineStyle: lineStyle,
                    inheritedValueLabel: nil
                )
            }

            if chartType == .compactBar {
                return flattenedSubgroups.enumerated().map { subgroupIndex, subgroup in
                    let label = subgroup.name
                    return IndicatorRow(
                        id: "\(index)-\(subgroupIndex)-\(label.stableID)",
                        label: label.isEmpty ? fallbackLabel(index: subgroupIndex) : label,
                        value: subgroup.value,
                        series: nil,
                        sortOrder: index * 100 + subgroupIndex,
                        colorGraph: subgroup.colorGraph,
                        colorValue: subgroup.colorValue,
                        lineStyle: subgroup.lineStyle,
                        totalLabel: totalLabel,
                        valueLabel: subgroup.valueLabel
                    )
                }
            }

            let groupLabel = normalizedGroup.isEmpty ? preferredLabel(index: index) : normalizedGroup
            return flattenedSubgroups.enumerated().map { subgroupIndex, subgroup in
                IndicatorRow(
                    id: "\(groupLabel.stableID)-\(subgroupIndex)-\(subgroup.name.stableID)",
                    label: groupLabel,
                    value: subgroup.value,
                    series: subgroup.name,
                    sortOrder: index * 100 + subgroupIndex,
                    colorGraph: subgroup.colorGraph,
                    colorValue: subgroup.colorValue,
                    lineStyle: subgroup.lineStyle,
                    totalLabel: totalLabel,
                    valueLabel: subgroup.valueLabel
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
                totalLabel: totalLabel,
                valueLabel: valueLabel
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
        if !normalizedTitle.isEmpty {
            return normalizedTitle
        }
        return fallbackLabel(index: index)
    }

    private func fallbackLabel(index: Int) -> String {
        String(index + 1)
    }
}

struct AnalyticsAPISubgroup: Decodable, Sendable {
    let name: String
    let value: Double?
    let colorGraph: String?
    let colorValue: String?
    let lineStyle: ChartLineStyle?
    let valueLabel: String?
    let subgroup: [AnalyticsAPISubgroup]?

    private enum CodingKeys: String, CodingKey {
        case name
        case group
        case value
        case colorGraph
        case colorValue
        case lineStyle
        case dashed
        case valueLabel
        case displayValue
        case displayLabel
        case totalLabel
        case subgroup
        case values
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeFlexibleString(forKey: .name)
            ?? container.decodeFlexibleString(forKey: .group)
            ?? ""
        value = try container.decodeFlexibleDouble(forKey: .value)
        colorGraph = try container.decodeFlexibleString(forKey: .colorGraph)
        colorValue = try container.decodeFlexibleString(forKey: .colorValue)
        lineStyle = normalizedLineStyle(
            try container.decodeFlexibleString(forKey: .lineStyle),
            dashed: try container.decodeFlexibleBool(forKey: .dashed)
        )
        valueLabel = try container.decodeFlexibleString(forKey: .valueLabel)
            ?? container.decodeFlexibleString(forKey: .displayValue)
            ?? container.decodeFlexibleString(forKey: .displayLabel)
            ?? container.decodeFlexibleString(forKey: .totalLabel)

        let subgroupValues = try container.decodeFlexibleArray(AnalyticsAPISubgroup.self, forKey: .subgroup)
        let nestedValues = try container.decodeFlexibleArray(AnalyticsAPISubgroup.self, forKey: .values)
        let combinedValues = subgroupValues.isEmpty ? nestedValues : subgroupValues
        subgroup = combinedValues.isEmpty ? nil : combinedValues
    }

    func flattened(
        ancestors: [String] = [],
        inheritedGraphColor: String?,
        inheritedValueColor: String?,
        inheritedLineStyle: ChartLineStyle?,
        inheritedValueLabel: String?
    ) -> [AnalyticsAPIFlattenedSubgroup] {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let graphColor = colorGraph ?? inheritedGraphColor
        let valueColor = colorValue ?? inheritedValueColor
        let resolvedLineStyle = lineStyle ?? inheritedLineStyle
        let resolvedValueLabel = valueLabel ?? inheritedValueLabel

        if let subgroup, !subgroup.isEmpty {
            let nestedAncestors = normalizedName.isEmpty
                ? ancestors
                : ancestors + [normalizedName]
            return subgroup.flatMap {
                $0.flattened(
                    ancestors: nestedAncestors,
                    inheritedGraphColor: graphColor,
                    inheritedValueColor: valueColor,
                    inheritedLineStyle: resolvedLineStyle,
                    inheritedValueLabel: resolvedValueLabel
                )
            }
        }

        let nameComponents = ([normalizedName] + ancestors.reversed()).filter { !$0.isEmpty }
        return [
            AnalyticsAPIFlattenedSubgroup(
                name: nameComponents.joined(separator: " "),
                value: value ?? 0,
                colorGraph: graphColor,
                colorValue: valueColor,
                lineStyle: resolvedLineStyle,
                valueLabel: resolvedValueLabel
            )
        ]
    }
}

struct AnalyticsAPIFlattenedSubgroup: Sendable {
    let name: String
    let value: Double
    let colorGraph: String?
    let colorValue: String?
    let lineStyle: ChartLineStyle?
    let valueLabel: String?
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
    func decodeFlexibleArray<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> [T] {
        guard contains(key), try !decodeNil(forKey: key) else {
            return []
        }
        if let values = try? decode([T].self, forKey: key) {
            return values
        }
        if let value = try? decode(T.self, forKey: key) {
            return [value]
        }
        throw DecodingError.typeMismatch(
            [T].self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected an array or a single decodable value"
            )
        )
    }

    func decodeFlexibleString(forKey key: Key) throws -> String? {
        guard contains(key), try !decodeNil(forKey: key) else {
            return nil
        }
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Decimal.self, forKey: key) {
            return NSDecimalNumber(decimal: value).stringValue
        }
        if let value = try? decode(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected a string, number, or boolean"
            )
        )
    }

    func decodeFlexibleDouble(forKey key: Key) throws -> Double? {
        guard contains(key), try !decodeNil(forKey: key) else {
            return nil
        }
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        guard let text = try? decode(String.self, forKey: key) else {
            throw DecodingError.typeMismatch(
                Double.self,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "Expected a number or numeric string"
                )
            )
        }

        let normalized = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: "")
            .replacingOccurrences(of: "\u{202f}", with: "")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Invalid numeric value: \(text)"
            )
        }
        return value
    }

    func decodeFlexibleBool(forKey key: Key) throws -> Bool? {
        guard contains(key), try !decodeNil(forKey: key) else {
            return nil
        }
        if let value = try? decode(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return value != 0
        }
        guard let value = try? decode(String.self, forKey: key) else {
            throw DecodingError.typeMismatch(
                Bool.self,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "Expected a boolean, integer, or boolean string"
                )
            )
        }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Invalid boolean value: \(value)"
            )
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
