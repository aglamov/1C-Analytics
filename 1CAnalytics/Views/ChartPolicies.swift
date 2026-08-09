import SwiftUI

enum ChartValueLabelPolicy {
    static func isVisible(
        rowMatchesSelection: Bool,
        hasSelection: Bool,
        contractPreference: Bool?,
        defaultLabelsEnabled: Bool
    ) -> Bool {
        if let contractPreference {
            guard contractPreference else {
                return false
            }

            return !hasSelection || rowMatchesSelection
        }

        return hasSelection ? rowMatchesSelection : defaultLabelsEnabled
    }
}

enum ChartPresentationPolicy {
    enum Style {
        case groupedBar
        case stackedBar
        case trend
    }

    static func contentWidth(
        availableWidth: CGFloat,
        categoryCount: Int,
        seriesCount: Int,
        longestValueCharacterCount: Int,
        style: Style,
        allowsHorizontalOverflow: Bool = true
    ) -> CGFloat {
        guard allowsHorizontalOverflow else {
            return availableWidth
        }

        guard categoryCount > 0 else {
            return availableWidth
        }

        let readableValueWidth = min(
            max(CGFloat(longestValueCharacterCount) * 7 + 18, 58),
            132
        )
        let categoryWidth: CGFloat

        switch style {
        case .groupedBar:
            categoryWidth = max(76, readableValueWidth * CGFloat(max(seriesCount, 1)) * 0.78)
        case .stackedBar:
            categoryWidth = max(76, readableValueWidth)
        case .trend:
            categoryWidth = max(82, readableValueWidth * min(CGFloat(max(seriesCount, 1)), 2) * 0.62)
        }

        let requestedWidth = categoryWidth * CGFloat(categoryCount) + 52
        return max(availableWidth, requestedWidth)
    }
}

enum ChartHeightPolicy {
    static func horizontalBarHeight(categoryCount: Int, seriesCount: Int) -> CGFloat {
        let rowsPerCategory = max(seriesCount, 1)
        let categoryHeight = max(46, CGFloat(rowsPerCategory) * 23 + 24)
        return max(196, CGFloat(max(categoryCount, 1)) * categoryHeight + 52)
    }

    static func detailHeight(for indicator: Indicator, availableWidth: CGFloat) -> CGFloat {
        let categoryCount = max(indicator.orderedRows.uniqueValues(\.label).count, 1)
        let seriesCount = max(indicator.barDataShape.series.count, 1)

        if indicator.prefersHorizontalGroupedBars || indicator.chartType == .horizontalBar {
            return horizontalBarHeight(categoryCount: categoryCount, seriesCount: seriesCount)
        }

        switch indicator.chartType {
        case .horizontalBar:
            return horizontalBarHeight(categoryCount: categoryCount, seriesCount: seriesCount)
        case .donut, .percentDonut:
            return indicator.orderedRows.count > 4 ? 380 : 340
        case .line, .area, .splineLine, .splineArea, .forecastLine:
            return min(max(availableWidth * 0.72, 300), 420)
        case .bar, .compactBar, .stackedBar:
            return min(max(availableWidth * 0.68, 280), 390)
        case .oneValue:
            return 180
        case .linearProgress:
            return 110
        case .gauge:
            return 300
        case .geoMap:
            return 300
        }
    }
}

enum StackedBarLabelPolicy {
    static func isReadable(
        value: Double,
        groupTotal: Double,
        labelCharacterCount: Int
    ) -> Bool {
        guard groupTotal > 0, value > 0 else {
            return false
        }

        let share = value / groupTotal
        let minimumShare = min(0.34, 0.08 + Double(max(labelCharacterCount - 3, 0)) * 0.018)
        return share >= minimumShare
    }
}

enum TrendValueLabelScale {
    static let headroomFraction = 0.16

    static func domain(for values: [Double], includesZero: Bool) -> ClosedRange<Double> {
        let finiteValues = values.filter(\.isFinite)
        guard let minimum = finiteValues.min(), let maximum = finiteValues.max() else {
            return 0...1
        }

        let baseLowerBound = includesZero ? min(minimum, 0) : minimum
        let baseUpperBound = includesZero ? max(maximum, 0) : maximum
        let naturalSpan = baseUpperBound - baseLowerBound
        let fallbackSpan = max(max(abs(baseLowerBound), abs(baseUpperBound)) * 0.12, 1)
        let span = max(naturalSpan, fallbackSpan)
        let headroom = span * headroomFraction

        return (baseLowerBound - headroom)...(baseUpperBound + headroom)
    }
}

enum TrendLabelPlacement: Equatable {
    case above
    case below
}

enum TrendLabelPlacementPolicy {
    static func placement(
        for row: IndicatorRow,
        in rows: [IndicatorRow]
    ) -> TrendLabelPlacement {
        let categoryRows = rows
            .filter { $0.label == row.label }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }

                return (lhs.sortOrder ?? .max, lhs.series ?? "", lhs.id)
                    < (rhs.sortOrder ?? .max, rhs.series ?? "", rhs.id)
            }

        guard categoryRows.count > 1,
              let index = categoryRows.firstIndex(where: { $0.id == row.id }) else {
            return .above
        }

        if index == 0 {
            return .above
        }
        if index == categoryRows.count - 1 {
            return .below
        }

        // Keep intermediate labels away from the point center when several
        // series meet or cross in the same category.
        return index.isMultiple(of: 2) ? .above : .below
    }
}

enum ForecastPresentationPolicy {
    static func startIndex(pointCount: Int, explicitIndex: Int?) -> Int? {
        guard pointCount > 0 else {
            return nil
        }

        let forecastPointCount = max(1, Int((Double(pointCount) * 0.25).rounded(.up)))
        let defaultIndex = max(pointCount - forecastPointCount, 0)
        return min(max(explicitIndex ?? defaultIndex, 0), pointCount - 1)
    }
}

/// Vertical value labels are part of the chart contract, not optional overflow.
/// Keep enough room for them inside the plot so future clipping/layout changes cannot hide them.
enum VerticalBarValueLabelScale {
    static let topHeadroomFraction = 0.22

    static func domain(for values: [Double]) -> ClosedRange<Double> {
        let finiteValues = values.filter(\.isFinite)
        guard let minimum = finiteValues.min(), let maximum = finiteValues.max() else {
            return 0...1
        }

        let lowerBound = min(minimum, 0)
        let upperBound = max(maximum, 0)
        let span = max(upperBound - lowerBound, 1)
        let labelHeadroom = span * topHeadroomFraction

        return lowerBound...(upperBound + labelHeadroom)
    }
}

enum DonutLabelPlacementPolicy {
    static func shouldPlaceOutside(
        share: Double,
        labelCharacterCount: Int,
        radius: CGFloat
    ) -> Bool {
        guard share > 0, radius > 0 else {
            return false
        }

        let availableArcLength = 2 * Double.pi * Double(radius) * share
        let estimatedLabelWidth = Double(max(labelCharacterCount, 1)) * 7.2 + 18
        return share < 0.12 || availableArcLength < estimatedLabelWidth
    }

}

enum DonutSelectionGeometryPolicy {
    static func middleAngle(
        for selectedRowID: IndicatorRow.ID,
        in rows: [IndicatorRow]
    ) -> Double? {
        let total = rows.reduce(0) { $0 + max($1.value, 0) }
        guard total > 0 else {
            return nil
        }

        var cumulativeValue = 0.0
        for row in rows {
            let visibleValue = max(row.value, 0)
            if row.id == selectedRowID {
                let middleValue = cumulativeValue + visibleValue / 2
                return -.pi / 2 + middleValue / total * 2 * .pi
            }
            cumulativeValue += visibleValue
        }

        return nil
    }
}

enum ChartSelectionPolicy {
    static func matches(
        rowID: IndicatorRow.ID,
        rowSeriesKey: String,
        selectedRowID: IndicatorRow.ID,
        selectedSeriesKey: String?
    ) -> Bool {
        if let selectedSeriesKey {
            return rowSeriesKey == selectedSeriesKey
        }

        return rowID == selectedRowID
    }
}

enum LegendSelectionPolicy {
    static func isSelected(
        usesSeriesLegend: Bool,
        rowMatchesSelection: Bool,
        selectedSeriesKey: String?
    ) -> Bool {
        usesSeriesLegend
            ? selectedSeriesKey != nil && rowMatchesSelection
            : rowMatchesSelection
    }
}


enum BarSelectionResolver {
    static func positionKey(
        at coordinate: CGFloat,
        in categoryBounds: ClosedRange<CGFloat>,
        domain: [String]
    ) -> String? {
        guard !domain.isEmpty, categoryBounds.contains(coordinate) else {
            return nil
        }

        guard domain.count > 1 else {
            return domain.first
        }

        let categoryWidth = categoryBounds.upperBound - categoryBounds.lowerBound
        guard categoryWidth > 0 else {
            return nil
        }

        let relativePosition = (coordinate - categoryBounds.lowerBound) / categoryWidth
        let index = min(Int(relativePosition * CGFloat(domain.count)), domain.count - 1)
        return domain[index]
    }
}

struct ChartChromeModifier: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground).opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.10), lineWidth: 1)
                }
        } else {
            content
        }
    }
}
