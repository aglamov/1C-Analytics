import Foundation

struct Dashboard: Identifiable, Codable, Equatable {
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

struct DashboardSection: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let indicators: [Indicator]
}

struct Indicator: Identifiable, Codable, Equatable {
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
        self.rows = rows
    }
}

struct IndicatorRow: Identifiable, Codable, Equatable {
    let id: String
    let label: String
    let value: Double
    let series: String?
    let sortOrder: Int?
    let colorGraph: String?
    let colorValue: String?

    init(
        id: String,
        label: String,
        value: Double,
        series: String?,
        sortOrder: Int?,
        colorGraph: String? = nil,
        colorValue: String? = nil
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.series = series
        self.sortOrder = sortOrder
        self.colorGraph = colorGraph
        self.colorValue = colorValue
    }
}

struct IndicatorRowGroup: Identifiable, Equatable {
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

enum BarChartDataShape: Equatable {
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

enum ChartType: String, CaseIterable, Codable {
    case bar = "BarMark"
    case compactBar = "BarMarkCompact"
    case horizontalBar = "BarMarkHorizon"
    case stackedBar = "BarMarkStacking"
    case donut = "SectorMarkInnerRadius"
    case oneValue = "OneValue"
    case linearProgress = "LinearProgressIndicator"
    case gauge = "Gauge"
    case geoMap = "GeoMap"

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
            case .bar, .compactBar:
                .blue
            case .horizontalBar:
                .green
            case .stackedBar:
                .violet
            case .donut:
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
        case .bar, .compactBar, .horizontalBar, .stackedBar, .donut, .geoMap:
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
