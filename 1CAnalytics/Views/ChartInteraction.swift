import Charts
import SwiftUI

enum ChartSelectionMode {
    case verticalBar
    case horizontalBar
    case stackedBar
    case point
}

extension AnalyticsChart {
    func responsiveCategoryAxis(availableWidth: CGFloat) -> some AxisContent {
        let categoryCount = max(Set(indicator.orderedRows.map(\.label)).count, 1)
        let plotWidth = max(availableWidth - 52, 0)
        let labelWidth = min(120, max(40, plotWidth / CGFloat(categoryCount) - 4))

        return AxisMarks { value in
            AxisValueLabel(centered: true, collisionResolution: .truncate) {
                if let label = value.as(String.self) {
                    Text(wrappedAxisLabel(label))
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                        .frame(width: labelWidth)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    func responsiveTrendAxis(availableWidth: CGFloat) -> some AxisContent {
        let labels = categoryLabels
        let categoryCount = max(labels.count, 1)
        let plotWidth = max(availableWidth - 52, 0)
        let labelWidth = min(120, max(40, plotWidth / CGFloat(categoryCount) - 4))
        let values = labels.indices.map(Double.init)

        return AxisMarks(values: values) { value in
            AxisValueLabel(centered: false) {
                if let xValue = value.as(Double.self) {
                    let index = Int(xValue.rounded())
                    if labels.indices.contains(index) {
                        Text(wrappedAxisLabel(labels[index]))
                            .font(.caption2)
                            .lineLimit(2)
                            .frame(width: labelWidth)
                            .hidden()
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    func wrappedAxisLabel(_ label: String) -> String {
        let words = label.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > 1 else {
            return label
        }

        let breakIndex = (1..<words.count).min { leftIndex, rightIndex in
            axisLineLengthDifference(words: words, breakIndex: leftIndex)
                < axisLineLengthDifference(words: words, breakIndex: rightIndex)
        } ?? 1

        return words[..<breakIndex].joined(separator: " ")
            + "\n"
            + words[breakIndex...].joined(separator: " ")
    }

    func axisLineLengthDifference(words: [String], breakIndex: Int) -> Int {
        let firstLineLength = words[..<breakIndex].joined(separator: " ").count
        let secondLineLength = words[breakIndex...].joined(separator: " ").count
        return abs(firstLineLength - secondLineLength)
    }

    func toggleSelection(_ rowID: IndicatorRow.ID) {
        selectedSeriesKey = nil
        selectedSeriesAnchorID = nil
        setSelection(selectedRowID == rowID ? nil : rowID)
    }

    func toggleLegendSelection(_ row: IndicatorRow) {
        guard usesSeriesLegend else {
            toggleSelection(row.id)
            return
        }

        let seriesKey = selectionSeriesKey(for: row)
        if selectedSeriesKey == seriesKey, selectedRowID == row.id {
            clearSelection()
        } else {
            selectedSeriesKey = seriesKey
            selectedSeriesAnchorID = row.id
            setSelection(row.id)
        }
    }

    func clearSelection() {
        selectedSeriesKey = nil
        selectedSeriesAnchorID = nil
        setSelection(nil)
    }

    func rowMatchesSelection(_ row: IndicatorRow) -> Bool {
        guard let selectedRowID else {
            return false
        }

        let effectiveSeriesKey = selectedSeriesAnchorID == selectedRowID
            ? selectedSeriesKey
            : nil
        return ChartSelectionPolicy.matches(
            rowID: row.id,
            rowSeriesKey: selectionSeriesKey(for: row),
            selectedRowID: selectedRowID,
            selectedSeriesKey: effectiveSeriesKey
        )
    }

    func legendRowMatchesSelection(_ row: IndicatorRow) -> Bool {
        LegendSelectionPolicy.isSelected(
            usesSeriesLegend: usesSeriesLegend,
            rowMatchesSelection: rowMatchesSelection(row),
            selectedSeriesKey: selectedSeriesKey
        )
    }

    func selectionSeriesKey(for row: IndicatorRow) -> String {
        row.series ?? indicator.title
    }

    func setSelection(_ rowID: IndicatorRow.ID?) {
        if let externalSelection {
            externalSelection.wrappedValue = rowID
        } else {
            internalSelectedRowID = rowID
        }
    }

    func chartTapOverlay(proxy: ChartProxy, mode: ChartSelectionMode) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            guard let plotFrame = proxy.plotFrame else {
                                return
                            }

                            let frame = geometry[plotFrame]
                            let location = CGPoint(
                                x: value.location.x - frame.origin.x,
                                y: value.location.y - frame.origin.y
                            )

                            if let rowID = selectedRowID(at: location, proxy: proxy, mode: mode) {
                                toggleSelection(rowID)
                            } else {
                                clearSelection()
                            }
                        }
                )
        }
    }

    func trendChartOverlay(proxy: ChartProxy) -> some View {
        ZStack {
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    let axisHeight = max(geometry.size.height - frame.maxY, 1)
                    let labelWidth = min(
                        120,
                        max(40, frame.width / CGFloat(max(categoryLabels.count, 1)) - 4)
                    )

                    ForEach(Array(categoryLabels.enumerated()), id: \.offset) { index, label in
                        if let position = proxy.position(forX: Double(index)) {
                            Text(wrappedAxisLabel(label))
                                .font(.caption2)
                                .foregroundStyle(Color.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.72)
                                .allowsTightening(true)
                                .frame(width: labelWidth)
                                .position(
                                    x: frame.minX + position,
                                    y: frame.maxY + axisHeight / 2
                                )
                        }
                    }
                }
            }
            .allowsHitTesting(false)

            chartTapOverlay(proxy: proxy, mode: .point)

            selectedTrendValueOverlay(proxy: proxy)
                .zIndex(1_000)
        }
    }

    func selectedTrendValueOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            if let row = selectedTrendRow,
               shouldShowValueLabel(for: row),
               let plotFrame = proxy.plotFrame,
               let xPosition = proxy.position(forX: trendXValue(for: row)),
               let yPosition = proxy.position(forY: row.value) {
                let frame = geometry[plotFrame]
                let point = CGPoint(
                    x: frame.minX + xPosition,
                    y: frame.minY + yPosition
                )
                let placement = TrendLabelPlacementPolicy.placement(
                    for: row,
                    in: indicator.orderedRows
                )

                valueLabel(for: row)
                    .position(
                        SelectedTrendLabelPositionPolicy.center(
                            for: point,
                            placement: placement,
                            in: geometry.size,
                            contentScale: dashboardContentScale
                        )
                    )
                    .zIndex(1_000)
            }
        }
        .allowsHitTesting(false)
    }

    var selectedTrendRow: IndicatorRow? {
        guard let selectedRowID else {
            return nil
        }

        return indicator.orderedRows.first { $0.id == selectedRowID }
    }

    func donutTapOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            guard let plotFrame = proxy.plotFrame else {
                                clearSelection()
                                return
                            }

                            let frame = geometry[plotFrame]
                            let location = CGPoint(
                                x: value.location.x - frame.origin.x,
                                y: value.location.y - frame.origin.y
                            )

                            if let rowID = selectedDonutRowID(at: location, in: frame.size) {
                                toggleSelection(rowID)
                            } else {
                                clearSelection()
                            }
                        }
                )
        }
    }

    func selectedRowID(at location: CGPoint, proxy: ChartProxy, mode: ChartSelectionMode) -> IndicatorRow.ID? {
        switch mode {
        case .verticalBar:
            guard
                let label = proxy.value(atX: location.x, as: String.self),
                let value = proxy.value(atY: location.y, as: Double.self),
                let categoryBounds = categoryBounds(
                    for: label,
                    labels: indicator.orderedRows.uniqueValues(\.label),
                    plotLength: proxy.plotSize.width,
                    position: { proxy.position(forX: $0) }
                ),
                let positionKey = BarSelectionResolver.positionKey(
                    at: location.x,
                    in: categoryBounds,
                    domain: verticalBarPositionDomain
                ),
                let row = indicator.orderedRows.first(where: {
                    $0.label == label && verticalBarPosition(for: $0) == positionKey
                }),
                valueIsInsideBar(value, rowValue: row.value)
            else {
                return nil
            }

            return row.id

        case .horizontalBar:
            guard
                let label = proxy.value(atY: location.y, as: String.self),
                let value = proxy.value(atX: location.x, as: Double.self),
                let categoryBounds = categoryBounds(
                    for: label,
                    labels: indicator.orderedRows.uniqueValues(\.label),
                    plotLength: proxy.plotSize.height,
                    position: { proxy.position(forY: $0) }
                ),
                let positionKey = BarSelectionResolver.positionKey(
                    at: location.y,
                    in: categoryBounds,
                    domain: horizontalBarPositionDomain
                ),
                let row = indicator.orderedRows.first(where: {
                    $0.label == label && horizontalBarPosition(for: $0) == positionKey
                }),
                valueIsInsideBar(value, rowValue: row.value)
            else {
                return nil
            }

            return row.id

        case .stackedBar:
            guard
                let label = proxy.value(atX: location.x, as: String.self),
                let value = proxy.value(atY: location.y, as: Double.self),
                value >= 0
            else {
                return nil
            }

            var lowerBound = 0.0
            for row in indicator.orderedRows where row.label == label {
                let upperBound = lowerBound + row.value
                if value >= lowerBound && value <= upperBound {
                    return row.id
                }
                lowerBound = upperBound
            }

            return nil

        case .point:
            guard
                let xValue = proxy.value(atX: location.x, as: Double.self),
                let value = proxy.value(atY: location.y, as: Double.self)
            else {
                return nil
            }

            let categoryIndex = Int(xValue.rounded())
            guard categoryLabels.indices.contains(categoryIndex) else {
                return nil
            }
            let label = categoryLabels[categoryIndex]

            return indicator.orderedRows
                .filter { $0.label == label }
                .min { abs($0.value - value) < abs($1.value - value) }?
                .id
        }
    }

    var verticalBarPositionDomain: [String] {
        indicator.orderedRows.uniqueValues { verticalBarPosition(for: $0) }
    }

    var horizontalBarPositionDomain: [String] {
        indicator.orderedRows.uniqueValues { horizontalBarPosition(for: $0) }
    }

    func horizontalBarPosition(for row: IndicatorRow) -> String {
        row.series ?? "Значение"
    }

    func categoryBounds(
        for label: String,
        labels: [String],
        plotLength: CGFloat,
        position: (String) -> CGFloat?
    ) -> ClosedRange<CGFloat>? {
        let positionedLabels = labels.compactMap { label in
            position(label).map { (label: label, position: $0) }
        }
        guard let index = positionedLabels.firstIndex(where: { $0.label == label }) else {
            return nil
        }

        let currentPosition = positionedLabels[index].position
        let lowerBound: CGFloat
        let upperBound: CGFloat

        if index > 0 {
            lowerBound = (positionedLabels[index - 1].position + currentPosition) / 2
        } else {
            lowerBound = 0
        }

        if index + 1 < positionedLabels.count {
            upperBound = (currentPosition + positionedLabels[index + 1].position) / 2
        } else {
            upperBound = plotLength
        }

        guard lowerBound < upperBound else {
            return nil
        }

        return lowerBound...upperBound
    }

    func valueIsInsideBar(_ value: Double, rowValue: Double) -> Bool {
        value >= min(0, rowValue) && value <= max(0, rowValue)
    }

    func selectedDonutRowID(at location: CGPoint, in size: CGSize) -> IndicatorRow.ID? {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let radius = hypot(dx, dy)
        let outerRadius = min(size.width, size.height) / 2
        let innerRadius = outerRadius * 0.62

        guard radius >= innerRadius, radius <= outerRadius else {
            return nil
        }

        let total = indicator.orderedRows.reduce(0) { $0 + max($1.value, 0) }
        guard total > 0 else {
            return nil
        }

        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 {
            angle += 2 * .pi
        }

        let tappedValue = angle / (2 * .pi) * total
        var lowerBound = 0.0

        for row in indicator.orderedRows {
            let upperBound = lowerBound + max(row.value, 0)
            if tappedValue >= lowerBound && tappedValue <= upperBound {
                return row.id
            }
            lowerBound = upperBound
        }

        return nil
    }
}
