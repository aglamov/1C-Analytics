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
    let showValueLabels: Bool?
    let showYAxisLabels: Bool?
    let detailsOrientation: DetailsOrientation?
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
        showValueLabels: Bool? = nil,
        showYAxisLabels: Bool? = nil,
        detailsOrientation: DetailsOrientation? = nil,
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
        self.showValueLabels = showValueLabels
        self.showYAxisLabels = showYAxisLabels
        self.detailsOrientation = detailsOrientation
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
    let totalLabel: String?
    let valueLabel: String?

    init(
        id: String,
        label: String,
        value: Double,
        series: String?,
        sortOrder: Int?,
        colorGraph: String? = nil,
        colorValue: String? = nil,
        lineStyle: ChartLineStyle? = nil,
        totalLabel: String? = nil,
        valueLabel: String? = nil
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.series = series
        self.sortOrder = sortOrder
        self.colorGraph = colorGraph
        self.colorValue = colorValue
        self.lineStyle = lineStyle
        self.totalLabel = totalLabel
        self.valueLabel = valueLabel
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

enum DetailsOrientation: String, Codable, Sendable {
    case vertical
    case horizontal
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

    var totalLabel: String? {
        rows.lazy.compactMap(\.totalLabel).first
    }

    var selectedFallbackRowID: IndicatorRow.ID? {
        rows.first?.id
    }
}

enum ContractPlanFactPeriod: Int, Identifiable, Sendable {
    case current
    case previous

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .current:
            "Текущий год"
        case .previous:
            "Прошлый год"
        }
    }

    init?(series: String?) {
        let normalized = series?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if normalized.contains("текущ") {
            self = .current
        } else if normalized.contains("прошл") {
            self = .previous
        } else {
            return nil
        }
    }
}

struct ContractPlanFactPeriodRows: Identifiable, Equatable, Sendable {
    let period: ContractPlanFactPeriod
    let rows: [IndicatorRow]

    var id: ContractPlanFactPeriod.ID { period.id }

    var planRow: IndicatorRow? {
        rows.first(where: \.isContractPlanMetric)
    }

    var paidRow: IndicatorRow? {
        rows.first { !$0.isContractPlanMetric }
    }

    var completionRatio: Double? {
        guard let plan = planRow?.value,
              let paid = paidRow?.value,
              plan > 0 else {
            return nil
        }

        return paid / plan
    }
}

struct ContractPlanFactCategory: Identifiable, Equatable, Sendable {
    let label: String
    let periods: [ContractPlanFactPeriodRows]

    var id: String { label }

    var maximumValue: Double {
        max(periods.flatMap(\.rows).map(\.value).max() ?? 0, 1)
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
        showTotal ?? (chartType != .geoMap)
    }

    var displayUnit: String? {
        if let unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty {
            return unit
        }

        return nil
    }

    var showsLegend: Bool {
        showLegend ?? (chartType != .geoMap)
    }

    var showsValueLabels: Bool {
        showValueLabels ?? true
    }

    var showsYAxisLabels: Bool {
        showYAxisLabels ?? false
    }

    var resolvedDetailsOrientation: DetailsOrientation {
        detailsOrientation ?? .vertical
    }

    var resolvedWidthPercent: Double {
        widthPercent ?? 100
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

    func formattedValueWithUnit(_ value: Decimal) -> String {
        let number = formattedNumber(value)
        guard let displayUnit else {
            return number
        }

        return "\(number) \(displayUnit)"
    }

    var orderedRows: [IndicatorRow] {
        rows.sortedByOrder()
    }

    var hasOnlyZeroValues: Bool {
        !orderedRows.isEmpty && orderedRows.allSatisfy { abs($0.value) < 0.000_001 }
    }

    var usesMixedUnitPersonnelPresentation: Bool {
        let normalizedTitle = title.lowercased()
        guard normalizedTitle.contains("доля ауп") && normalizedTitle.contains("увп") else {
            return false
        }

        let seriesNames = orderedRows.compactMap(\.series).map { $0.lowercased() }
        return seriesNames.contains { $0.contains("процент") }
            && seriesNames.contains { $0.contains("численност") }
    }

    var usesRankedCategoryPresentation: Bool {
        let normalizedTitle = title.lowercased()
        return (chartType == .donut || chartType == .percentDonut)
            && orderedRows.count > 4
            && normalizedTitle.contains("учеными званиями")
    }

    var usesDenseEnrollmentCompositionPresentation: Bool {
        title.lowercased().contains("динамика зачисления иг")
            && barDataShape.series.count >= 4
            && rowGroups.count >= 2
    }

    var usesCitizenshipCompositionPresentation: Bool {
        title.lowercased().contains("всего обучающихся рф и иг")
            && barDataShape.series.count >= 2
            && !rowGroups.isEmpty
    }

    var usesEducationLevelDonutPresentation: Bool {
        let normalizedTitle = title.lowercased()
        return (chartType == .donut || chartType == .percentDonut)
            && orderedRows.count >= 6
            && normalizedTitle.contains("иг по уровням подготовки")
    }

    var usesStackedCompositionPresentation: Bool {
        chartType == .stackedBar
            && !rowGroups.isEmpty
            && !barDataShape.series.isEmpty
    }

    var prefersTrendPresentation: Bool {
        guard chartType == .bar || chartType == .compactBar,
              barDataShape.series.isEmpty,
              orderedRows.count >= 3,
              !title.isPlanFactIndicatorTitle else {
            return false
        }

        return orderedRows.allSatisfy { row in
            let digits = row.label.filter(\.isNumber)
            return digits.count >= 4 && row.label.contains("20")
        }
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

    var prefersHorizontalGroupedBars: Bool {
        guard useCompactNumbers != true,
              chartType == .bar || chartType == .compactBar else {
            return false
        }

        if title.isPlanFactIndicatorTitle {
            return orderedRows.count > 1
        }

        let seriesCount = barDataShape.series.count
        if chartType == .bar,
           seriesCount > 1,
           rowGroups.count * seriesCount >= 4 {
            let longestValue = orderedRows
                .map { formattedNumber($0.value).count }
                .max() ?? 0
            if longestValue >= 6 {
                return true
            }
        }

        guard barLayout == .stacked,
              seriesCount > 1 else {
            return false
        }

        let positiveValues = orderedRows.map(\.value).filter { $0 > 0 }
        guard let largestValue = positiveValues.max(),
              let smallestValue = positiveValues.min() else {
            return false
        }

        return rowGroups.count >= 4 || smallestValue < largestValue * 0.18
    }

    var usesContractPlanFactPresentation: Bool {
        guard title.isPlanFactIndicatorTitle,
              title.lowercased().contains("контракт"),
              !orderedRows.isEmpty else {
            return false
        }

        return orderedRows.allSatisfy {
            ContractPlanFactPeriod(series: $0.series) != nil
        }
    }

    var contractPlanFactCategories: [ContractPlanFactCategory] {
        guard usesContractPlanFactPresentation else {
            return []
        }

        return rowGroups.map { group in
            let periods = [ContractPlanFactPeriod.current, .previous].compactMap { period in
                let rows = group.rows
                    .filter { ContractPlanFactPeriod(series: $0.series) == period }
                    .sorted { lhs, rhs in
                        let lhsPriority = lhs.contractPlanFactMetricPriority
                        let rhsPriority = rhs.contractPlanFactMetricPriority
                        return lhsPriority == rhsPriority
                            ? (lhs.sortOrder ?? .max) < (rhs.sortOrder ?? .max)
                            : lhsPriority < rhsPriority
                    }

                return rows.isEmpty
                    ? nil
                    : ContractPlanFactPeriodRows(period: period, rows: rows)
            }

            return ContractPlanFactCategory(label: group.label, periods: periods)
        }
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
        showDetails ?? true
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

extension IndicatorRow {
    var contractPlanFactMetricLabel: String {
        let normalized = series?.lowercased() ?? ""

        if normalized.contains("план") {
            return "План"
        }
        if normalized.contains("опл") {
            return "Опл."
        }
        if normalized.contains("факт") {
            return "Факт"
        }

        return series ?? label
    }

    var isContractPlanMetric: Bool {
        (series?.lowercased() ?? "").contains("план")
    }

    fileprivate var contractPlanFactMetricPriority: Int {
        isContractPlanMetric ? 0 : 1
    }
}

extension Array where Element == IndicatorRow {
    func sortedByOrder() -> [IndicatorRow] {
        sorted {
            ($0.sortOrder ?? .max, $0.label, $0.id) < ($1.sortOrder ?? .max, $1.label, $1.id)
        }
    }
}
