import Foundation

struct Dashboard: Identifiable, Decodable, Equatable {
    let id: String
    let title: String
    let updatedAt: Date?
    let indicators: [Indicator]
}

struct Indicator: Identifiable, Decodable, Equatable {
    let id: String
    let title: String
    let value: Decimal?
    let unit: String?
    let chartType: ChartType
    let source: String?
    let rows: [IndicatorRow]
}

struct IndicatorRow: Identifiable, Decodable, Equatable {
    let id: String
    let label: String
    let value: Double
    let series: String?
    let sortOrder: Int?
}

enum ChartType: String, CaseIterable, Decodable {
    case bar = "BarMark"
    case horizontalBar = "BarMarkHorizon"
    case stackedBar = "BarMarkStacking"
    case donut = "SectorMarkInnerRadius"

    var title: String {
        switch self {
        case .bar:
            "BarMark"
        case .horizontalBar:
            "BarMarkHorizon"
        case .stackedBar:
            "BarMarkStacking"
        case .donut:
            "SectorMarkInnerRadius"
        }
    }
}

