import Foundation

struct Dashboard: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let fetchedAt: Date?
    let sections: [DashboardSection]

    var indicators: [Indicator] {
        sections.flatMap(\.indicators)
    }

    init(id: String, title: String, fetchedAt: Date?, indicators: [Indicator]) {
        self.id = id
        self.title = title
        self.fetchedAt = fetchedAt
        self.sections = [
            DashboardSection(id: id, title: title, indicators: indicators)
        ]
    }

    init(id: String, title: String, fetchedAt: Date?, sections: [DashboardSection]) {
        self.id = id
        self.title = title
        self.fetchedAt = fetchedAt
        self.sections = sections
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case fetchedAt
        case legacyUpdatedAt = "updatedAt"
        case sections
        case indicators
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        fetchedAt = try container.decodeIfPresent(Date.self, forKey: .fetchedAt)
            ?? container.decodeIfPresent(Date.self, forKey: .legacyUpdatedAt)
        if let decodedSections = try container.decodeIfPresent([DashboardSection].self, forKey: .sections) {
            sections = decodedSections
        } else {
            let legacyIndicators = try container.decodeIfPresent([Indicator].self, forKey: .indicators) ?? []
            sections = [
                DashboardSection(id: id, title: title, indicators: legacyIndicators)
            ]
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(fetchedAt, forKey: .fetchedAt)
        try container.encode(sections, forKey: .sections)
    }
}

struct DashboardSection: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let indicators: [Indicator]
}

struct Indicator: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let value: Decimal?
    let valueMax: Double?
    let unit: String?
    let chartType: ChartType
    let source: String?
    let colorGraph: String?
    let colorValue: String?
    let showLegend: Bool?
    let showTotal: Bool?
    let showDetails: Bool?
    let widthPercent: Double?
    let useCompactNumbers: Bool?
    let valueSpacing: Double?
    let barLayout: BarLayout?
    let lineStyle: ChartLineStyle?
    let forecastFromIndex: Int?
    let rows: [IndicatorRow]

    init(
        id: String,
        title: String,
        value: Decimal?,
        valueMax: Double? = nil,
        unit: String?,
        chartType: ChartType,
        source: String?,
        colorGraph: String? = nil,
        colorValue: String? = nil,
        showLegend: Bool? = nil,
        showTotal: Bool? = nil,
        showDetails: Bool? = nil,
        widthPercent: Double? = nil,
        useCompactNumbers: Bool? = nil,
        valueSpacing: Double? = nil,
        barLayout: BarLayout? = nil,
        lineStyle: ChartLineStyle? = nil,
        forecastFromIndex: Int? = nil,
        rows: [IndicatorRow]
    ) {
        self.id = id
        self.title = title
        self.value = value
        self.valueMax = valueMax
        self.unit = unit
        self.chartType = chartType
        self.source = source
        self.colorGraph = colorGraph
        self.colorValue = colorValue
        self.showLegend = showLegend
        self.showTotal = showTotal
        self.showDetails = showDetails
        self.widthPercent = widthPercent
        self.useCompactNumbers = useCompactNumbers
        self.valueSpacing = valueSpacing
        self.barLayout = barLayout
        self.lineStyle = lineStyle
        self.forecastFromIndex = forecastFromIndex
        self.rows = rows
    }
}

struct IndicatorRow: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let label: String
    let value: Double
    let series: String?
    let sortOrder: Int?
    let colorGraph: String?
    let colorValue: String?
    let lineStyle: ChartLineStyle?

    init(
        id: String,
        label: String,
        value: Double,
        series: String?,
        sortOrder: Int?,
        colorGraph: String? = nil,
        colorValue: String? = nil,
        lineStyle: ChartLineStyle? = nil
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.series = series
        self.sortOrder = sortOrder
        self.colorGraph = colorGraph
        self.colorValue = colorValue
        self.lineStyle = lineStyle
    }
}

enum BarLayout: String, Codable, Sendable {
    case spaced
    case compact
    case stacked
}

enum ChartLineStyle: String, Codable, Sendable {
    case solid
    case dashed
}

struct IndicatorRowGroup: Identifiable, Equatable, Sendable {
    let label: String
    let rows: [IndicatorRow]

    var id: String {
        label
    }

    var totalValue: Double {
        rows.reduce(0) { $0 + $1.value }
    }

    var selectedFallbackRowID: IndicatorRow.ID? {
        rows.first?.id
    }
}

enum BarChartDataShape: Equatable, Sendable {
    case singleValuePerGroup
    case multipleValuesPerGroup(series: [String])

    var series: [String] {
        switch self {
        case .singleValuePerGroup:
            []
        case .multipleValuesPerGroup(let series):
            series
        }
    }
}

enum ChartType: String, CaseIterable, Codable, Sendable {
    case bar = "BarMark"
    case compactBar = "BarMarkCompact"
    case horizontalBar = "BarMarkHorizon"
    case stackedBar = "BarMarkStacking"
    case donut = "SectorMarkInnerRadius"
    case percentDonut = "PercentDonut"
    case line = "LineMark"
    case area = "AreaMark"
    case splineLine = "SplineLineMark"
    case splineArea = "SplineAreaMark"
    case forecastLine = "ForecastLineMark"
    case oneValue = "OneValue"
    case linearProgress = "LinearProgressIndicator"
    case gauge = "Gauge"
    case geoMap = "GeoMap"

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = (try? container.decode(String.self)) ?? ""

        switch value {
        case Self.oneValue.rawValue:
            self = .oneValue
        case Self.linearProgress.rawValue:
            self = .linearProgress
        case "Gauge", "GaugeIndicator", "Speedometer", "CircularProgressIndicator":
            self = .gauge
        case Self.compactBar.rawValue:
            self = .compactBar
        case Self.bar.rawValue:
            self = .bar
        case Self.donut.rawValue:
            self = .donut
        case "PercentDonut", "DonutPercent", "SectorMarkPercent":
            self = .percentDonut
        case "LineMark", "LineChart", "Line":
            self = .line
        case "AreaMark", "AreaChart", "Area":
            self = .area
        case "SplineLineMark", "SmoothLineMark", "SplineLine", "SmoothLine":
            self = .splineLine
        case "SplineAreaMark", "LayeredAreaMark", "SmoothAreaMark", "SplineArea":
            self = .splineArea
        case "ForecastLineMark", "ForecastLine", "PredictionLineMark":
            self = .forecastLine
        case Self.stackedBar.rawValue:
            self = .stackedBar
        case Self.horizontalBar.rawValue:
            self = .horizontalBar
        case "GeoMap", "WorldMap", "Map", "GeoChoropleth":
            self = .geoMap
        default:
            self = .bar
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var title: String {
        switch self {
        case .bar:
            "BarMark"
        case .compactBar:
            "BarMarkCompact"
        case .horizontalBar:
            "BarMarkHorizon"
        case .stackedBar:
            "BarMarkStacking"
        case .donut:
            "SectorMarkInnerRadius"
        case .percentDonut:
            "PercentDonut"
        case .line:
            "LineMark"
        case .area:
            "AreaMark"
        case .splineLine:
            "SplineLineMark"
        case .splineArea:
            "SplineAreaMark"
        case .forecastLine:
            "ForecastLineMark"
        case .oneValue:
            "OneValue"
        case .linearProgress:
            "LinearProgressIndicator"
        case .gauge:
            "Gauge"
        case .geoMap:
            "GeoMap"
        }
    }
}

extension Indicator {
    var showsAggregateValue: Bool {
        showTotal ?? !title.isPlanFactIndicatorTitle
    }

    var showsLegend: Bool {
        showLegend ?? false
    }

    func formattedNumber(_ value: Double) -> String {
        if useCompactNumbers == true {
            return value.formatted(
                .number.notation(.compactName).precision(.fractionLength(0...2))
            )
        }

        return value.formatted(.number.grouping(.automatic).precision(.fractionLength(0...2)))
    }

    func formattedNumber(_ value: Decimal) -> String {
        if useCompactNumbers == true {
            return value.formatted(
                .number.notation(.compactName).precision(.fractionLength(0...2))
            )
        }

        return value.formatted(.number.grouping(.automatic).precision(.fractionLength(0...2)))
    }

    var orderedRows: [IndicatorRow] {
        rows.sortedByOrder()
    }

    var rowGroups: [IndicatorRowGroup] {
        orderedRows.reduce(into: [IndicatorRowGroup]()) { groups, row in
            if let index = groups.firstIndex(where: { $0.label == row.label }) {
                let group = groups[index]
                groups[index] = IndicatorRowGroup(label: group.label, rows: group.rows + [row])
            } else {
                groups.append(IndicatorRowGroup(label: row.label, rows: [row]))
            }
        }
    }

    var barDataShape: BarChartDataShape {
        let series = orderedRows.reduce(into: [String]()) { result, row in
            guard let series = row.series, !result.contains(series) else {
                return
            }
            result.append(series)
        }

        return series.isEmpty
            ? .singleValuePerGroup
            : .multipleValuesPerGroup(series: series)
    }

    var accent: AppAccent {
        switch id {
        case "students-total":
            .blue
        case "citizenship":
            .green
        case "students-persons":
            .violet
        case "full-time":
            .orange
        default:
            switch chartType {
            case .bar, .compactBar, .line, .forecastLine:
                .blue
            case .horizontalBar, .area:
                .green
            case .stackedBar, .splineLine, .splineArea:
                .violet
            case .donut, .percentDonut:
                .orange
            case .oneValue:
                .orange
            case .linearProgress, .gauge:
                .blue
            case .geoMap:
                .green
            }
        }
    }

    var supportsDetail: Bool {
        switch chartType {
        case .oneValue, .linearProgress, .gauge:
            false
        case .bar, .compactBar, .horizontalBar, .stackedBar, .donut, .percentDonut,
             .line, .area, .splineLine, .splineArea, .forecastLine, .geoMap:
            showDetails ?? true
        }
    }

}

extension String {
    var isPlanFactIndicatorTitle: Bool {
        let normalized = lowercased()
            .replacingOccurrences(of: "‑", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")

        return normalized.contains("план-факт")
            || normalized.contains("план факт")
    }
}

extension Array where Element == IndicatorRow {
    func sortedByOrder() -> [IndicatorRow] {
        sorted {
            ($0.sortOrder ?? .max, $0.label, $0.id) < ($1.sortOrder ?? .max, $1.label, $1.id)
        }
    }
}
