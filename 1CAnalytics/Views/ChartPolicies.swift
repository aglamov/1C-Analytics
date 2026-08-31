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

enum TrendPointValueLabelPolicy {
    static func isVisible(
        rowMatchesSelection: Bool,
        showValueLabels: Bool?,
        alwaysShowPointValues: Bool?
    ) -> Bool {
        if showValueLabels == false {
            return false
        }

        if alwaysShowPointValues == false {
            return rowMatchesSelection
        }

        return true
    }
}

struct ChartValueLabelLayoutMetrics: Equatable {
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let maximumTextWidth: CGFloat
}

enum ChartValueLabelLayoutPolicy {
    static func metrics(
        isSelected: Bool,
        usesContrastingForeground: Bool
    ) -> ChartValueLabelLayoutMetrics {
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let maximumTextWidth: CGFloat

        if isSelected {
            horizontalPadding = usesContrastingForeground ? 4 : 7
            verticalPadding = usesContrastingForeground ? 2 : 4
            maximumTextWidth = 96
        } else {
            horizontalPadding = usesContrastingForeground ? 0 : 5
            verticalPadding = usesContrastingForeground ? 0 : 3
            maximumTextWidth = 120
        }

        return ChartValueLabelLayoutMetrics(
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            maximumTextWidth: maximumTextWidth
        )
    }
}

enum ChartPresentationPolicy {
    static func contentWidth(availableWidth: CGFloat) -> CGFloat {
        max(availableWidth, 0)
    }
}

enum ChartRenderGeometryPolicy {
    static func canRender(in size: CGSize) -> Bool {
        size.width.isFinite
            && size.height.isFinite
            && size.width >= 1
            && size.height >= 1
    }
}

struct ValidChartGeometry<Content: View>: View {
    let size: CGSize
    private let content: () -> Content

    init(size: CGSize, @ViewBuilder content: @escaping () -> Content) {
        self.size = size
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if ChartRenderGeometryPolicy.canRender(in: size) {
            content()
        } else {
            Color.clear
        }
    }
}

enum ChartHeightPolicy {
    static let dashboardTileHeight: CGFloat = 260

    static func horizontalBarHeight(categoryCount: Int, seriesCount: Int) -> CGFloat {
        let rowsPerCategory = max(seriesCount, 1)
        let groupHeaderHeight: CGFloat = rowsPerCategory > 1 ? 28 : 0
        let categoryHeight = max(
            52,
            CGFloat(rowsPerCategory) * 40 + groupHeaderHeight + 16
        )
        return max(196, CGFloat(max(categoryCount, 1)) * categoryHeight + 16)
    }

    static func dashboardExpandableHierarchyHeight(for indicator: Indicator) -> CGFloat {
        if indicator.resolvedExpandableOverviewType == .tile {
            return dashboardTileHeight
        }

        let rootCount = max(indicator.hierarchy?.nodes.count ?? 0, 1)
        let seriesCount = max(indicator.hierarchy?.displayedSeries.count ?? 0, 1)
        let rowHeight: CGFloat = indicator.hierarchy?.barMode == .grouped
            ? CGFloat(seriesCount) * 32 + 40
            : 70
        return max(190, CGFloat(rootCount) * rowHeight + 52)
    }

    static func detailHeight(for indicator: Indicator, availableWidth: CGFloat) -> CGFloat {
        let categoryCount = max(indicator.orderedRows.uniqueValues(\.label).count, 1)
        let seriesCount = max(indicator.barDataShape.series.count, 1)

        switch indicator.chartType {
        case .horizontalBar:
            return horizontalBarHeight(categoryCount: categoryCount, seriesCount: seriesCount)
        case .donut, .percentDonut:
            return indicator.orderedRows.count > 4 ? 380 : 340
        case .line, .area, .splineLine, .splineArea, .forecastLine, .radar:
            return min(max(availableWidth * 0.72, 300), 420)
        case .expandableHierarchy:
            let rootCount = max(indicator.hierarchy?.nodes.count ?? 0, 1)
            let seriesCount = max(indicator.hierarchy?.displayedSeries.count ?? 0, 1)
            let rowHeight: CGFloat = indicator.hierarchy?.barMode == .grouped
                ? CGFloat(seriesCount) * 34 + 42
                : 74
            return max(220, CGFloat(rootCount) * rowHeight + 64)
        case .stackedBar:
            return horizontalBarHeight(categoryCount: categoryCount, seriesCount: 1)
        case .bar, .compactBar:
            return min(max(availableWidth * 0.68, 280), 390)
        case .oneValue:
            return 180
        case .linearProgress:
            return 110
        case .gauge:
            return 300
        case .geoMap:
            return 300
        case .tile:
            return 300
        }
    }
}

struct HorizontalBarTrackSegment: Equatable {
    let startFraction: Double
    let lengthFraction: Double
}

enum HorizontalBarLabelPolicy {
    static func showsRowValue(
        showRowValues: Bool?,
        showValueLabels: Bool?
    ) -> Bool {
        (showRowValues ?? true) || (showValueLabels ?? true)
    }

    static func showsGroupTotal(
        rowCount: Int,
        showsAggregateValue: Bool
    ) -> Bool {
        rowCount > 1 && showsAggregateValue
    }
}

enum HorizontalBarTrackScale {
    static func domain(for values: [Double]) -> ClosedRange<Double> {
        let finiteValues = values.filter(\.isFinite)
        guard let minimum = finiteValues.min(), let maximum = finiteValues.max() else {
            return 0...1
        }

        let lowerBound = min(minimum, 0)
        let upperBound = max(maximum, 0)
        guard lowerBound < upperBound else {
            return 0...1
        }

        return lowerBound...upperBound
    }

    static func segment(
        for value: Double,
        in domain: ClosedRange<Double>
    ) -> HorizontalBarTrackSegment {
        let span = domain.upperBound - domain.lowerBound
        guard value.isFinite, span.isFinite, span > 0 else {
            return HorizontalBarTrackSegment(startFraction: 0, lengthFraction: 0)
        }

        let clampedValue = min(max(value, domain.lowerBound), domain.upperBound)
        let zeroFraction = min(max(-domain.lowerBound / span, 0), 1)
        let valueFraction = min(max((clampedValue - domain.lowerBound) / span, 0), 1)

        return HorizontalBarTrackSegment(
            startFraction: min(zeroFraction, valueFraction),
            lengthFraction: abs(valueFraction - zeroFraction)
        )
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

enum TrendAxisLabelPositionPolicy {
    static func clampedCenter(
        proposedX: CGFloat,
        labelWidth: CGFloat,
        plotRange: ClosedRange<CGFloat>
    ) -> CGFloat {
        let plotWidth = max(plotRange.upperBound - plotRange.lowerBound, 0)
        let effectiveLabelWidth = min(max(labelWidth, 0), plotWidth)
        let halfWidth = effectiveLabelWidth / 2
        let lowerBound = plotRange.lowerBound + halfWidth
        let upperBound = plotRange.upperBound - halfWidth

        guard lowerBound <= upperBound else {
            return (plotRange.lowerBound + plotRange.upperBound) / 2
        }

        return min(max(proposedX, lowerBound), upperBound)
    }
}

enum SelectedTrendLabelPositionPolicy {
    static func center(
        for point: CGPoint,
        placement: TrendLabelPlacement,
        in containerSize: CGSize,
        contentScale: CGFloat
    ) -> CGPoint {
        let scale = max(contentScale, 0.8)
        let horizontalInset = min(64 * scale, max(containerSize.width / 2, 0))
        let verticalInset = min(20 * scale, max(containerSize.height / 2, 0))
        let verticalOffset = 24 * scale
        let proposedY = point.y + (placement == .above ? -verticalOffset : verticalOffset)

        return CGPoint(
            x: min(
                max(point.x, horizontalInset),
                max(horizontalInset, containerSize.width - horizontalInset)
            ),
            y: min(
                max(proposedY, verticalInset),
                max(verticalInset, containerSize.height - verticalInset)
            )
        )
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

enum DonutPlotLayoutPolicy {
    static func plotSize(in availableSize: CGSize) -> CGSize {
        availableSize
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

enum LegendVisibilityPolicy {
    static func isVisible(
        contractPreference: Bool?,
        defaultEnabled: Bool,
        itemCount: Int
    ) -> Bool {
        if let contractPreference {
            return contractPreference
        }

        return defaultEnabled && itemCount > 1
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
