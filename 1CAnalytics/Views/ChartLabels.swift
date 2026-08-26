import Charts
import SwiftUI

extension AnalyticsChart {
    func valueLabel(
        for row: IndicatorRow,
        usesContrastingForeground: Bool = false,
        displayText: String? = nil
    ) -> some View {
        ChartValueLabel(
            value: row.value,
            isSelected: rowMatchesSelection(row),
            selectionColor: chartColor(for: row),
            borderColor: isCrossingHighlighted(row) ? .red : nil,
            usesContrastingForeground: usesContrastingForeground,
            useCompactNumbers: indicator.useCompactNumbers,
            displayText: displayText ?? row.valueLabel,
            valueColor: indicator.apiValueColor(for: row)
        )
    }

    func displayValue(for row: IndicatorRow) -> String {
        row.valueLabel ?? indicator.formattedNumber(row.value)
    }

    func shouldShowValueLabel(
        for row: IndicatorRow,
        defaultWhenIdle: Bool = true
    ) -> Bool {
        if usesTrendValueLabelContract {
            return TrendPointValueLabelPolicy.isVisible(
                rowMatchesSelection: rowMatchesSelection(row),
                showValueLabels: indicator.showValueLabels,
                alwaysShowPointValues: indicator.alwaysShowPointValues
            )
        }

        return ChartValueLabelPolicy.isVisible(
            rowMatchesSelection: rowMatchesSelection(row),
            hasSelection: selectedRowID != nil,
            contractPreference: indicator.showValueLabels,
            defaultLabelsEnabled: showsValueLabels && defaultWhenIdle
        )
    }

    private var usesTrendValueLabelContract: Bool {
        switch indicator.chartType {
        case .line, .area, .splineLine, .splineArea, .forecastLine:
            return true
        case .bar, .compactBar, .horizontalBar, .stackedBar, .donut,
             .percentDonut, .radar, .expandableHierarchy,
             .oneValue, .linearProgress, .gauge, .geoMap, .tile:
            return false
        }
    }

    func valueLabelsEnabledWhenIdle(defaultWhenIdle: Bool = true) -> Bool {
        indicator.showValueLabels ?? (showsValueLabels && defaultWhenIdle)
    }

    var verticalBarValueLabelDomain: ClosedRange<Double> {
        VerticalBarValueLabelScale.domain(for: indicator.orderedRows.map(\.value))
    }

    var horizontalBarValueLabelDomain: ClosedRange<Double> {
        VerticalBarValueLabelScale.domain(for: indicator.orderedRows.map(\.value))
    }

    var stackedBarValueLabelDomain: ClosedRange<Double> {
        VerticalBarValueLabelScale.domain(for: indicator.rowGroups.map(\.totalValue))
    }

    func trendValueLabelDomain(includesZero: Bool) -> ClosedRange<Double> {
        TrendValueLabelScale.domain(
            for: indicator.orderedRows.map(\.value),
            includesZero: includesZero
        )
    }

    func shouldShowStackedValueLabel(for row: IndicatorRow) -> Bool {
        guard shouldShowValueLabel(for: row) else {
            return false
        }

        if rowMatchesSelection(row) {
            return true
        }

        let total = rowGroup(for: row)?.totalValue ?? 0
        return StackedBarLabelPolicy.isReadable(
            value: row.value,
            groupTotal: total,
            labelCharacterCount: displayValue(for: row).count
        )
    }

    func rowGroup(for row: IndicatorRow) -> IndicatorRowGroup? {
        indicator.rowGroups.first { $0.label == row.label }
    }

    func isLastRowInGroup(_ row: IndicatorRow) -> Bool {
        rowGroup(for: row)?.rows.last?.id == row.id
    }

    func groupTotalLabel(_ group: IndicatorRowGroup) -> some View {
        Text(group.totalLabel ?? indicator.formattedNumber(group.totalValue))
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .subtleTextShadow()
    }

    func percentLabel(for row: IndicatorRow) -> some View {
        let total = indicator.orderedRows.reduce(0) { $0 + max($1.value, 0) }
        let share = total > 0 ? row.value / total : 0
        let label = row.valueLabel ?? share.formatted(.percent.precision(.fractionLength(0)))

        return Text(label)
            .font(.title3.monospacedDigit().weight(.bold))
            .foregroundStyle(row.colorValue == nil && colorScheme == .dark ? Color.white : indicator.valueColor(for: row))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(opaqueLabelBackground, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(chartColor(for: row).opacity(colorScheme == .dark ? 0.46 : 0.26), lineWidth: 1)
            }
            .subtleTextShadow()
            .transition(.identity)
    }

    func donutCenterSummary(showsPercentages: Bool) -> some View {
        let total = indicator.orderedRows.reduce(0) { $0 + max($1.value, 0) }
        let valueText = showsPercentages ? "100%" : indicator.formattedNumber(total)

        return VStack(spacing: 3) {
            Text(valueText)
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.64)

            Text("Итого")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 94)
        .padding(8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    func donutExternalLabels(
        showsPercentages: Bool,
        size: CGSize
    ) -> some View {
        let positions = donutExternalLabelPositions(in: size)

        return ZStack {
            ForEach(positions) { position in
                valueLabel(
                    for: position.row,
                    displayText: donutLabelText(
                        for: position.row,
                        showsPercentages: showsPercentages
                    )
                )
                    .zIndex(20)
                    .position(position.labelCenter)
            }
        }
        .allowsHitTesting(false)
    }

    func shouldPlaceDonutLabelOutside(
        _ row: IndicatorRow,
        plotSize: CGSize
    ) -> Bool {
        let total = indicator.orderedRows.reduce(0) { $0 + max($1.value, 0) }
        guard total > 0 else {
            return false
        }

        let share = max(row.value, 0) / total
        if rowMatchesSelection(row), share <= 0.12 {
            return true
        }

        let radius = min(plotSize.width, plotSize.height) * 0.36
        return DonutLabelPlacementPolicy.shouldPlaceOutside(
            share: share,
            labelCharacterCount: displayValue(for: row).count,
            radius: radius
        )
    }

    func donutExternalLabelPositions(
        in size: CGSize
    ) -> [DonutExternalLabelPosition] {
        let rows = indicator.orderedRows
        guard let selectedDonutRow,
              shouldPlaceDonutLabelOutside(selectedDonutRow, plotSize: size),
              let angle = DonutSelectionGeometryPolicy.middleAngle(
                  for: selectedDonutRow.id,
                  in: rows
              ) else {
            return []
        }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.46
        let cosine = CGFloat(cos(angle))
        let sine = CGFloat(sin(angle))
        let labelCenter = CGPoint(
            x: min(
                max(center.x + cosine * (radius + 36), 48),
                max(48, size.width - 48)
            ),
            y: min(
                max(center.y + sine * (radius + 36), 22),
                max(22, size.height - 22)
            )
        )

        return [
            DonutExternalLabelPosition(
                row: selectedDonutRow,
                labelCenter: labelCenter
            )
        ]
    }

    func donutLabelText(for row: IndicatorRow, showsPercentages: Bool) -> String {
        if let valueLabel = row.valueLabel {
            return valueLabel
        }

        guard showsPercentages else {
            return displayValue(for: row)
        }

        let total = indicator.orderedRows.reduce(0) { $0 + max($1.value, 0) }
        let share = total > 0 ? row.value / total : 0
        return share.formatted(.percent.precision(.fractionLength(0)))
    }

    var donutAngularInset: Double {
        guard let valueSpacing = indicator.valueSpacing else {
            return 1.5
        }

        return min(max(valueSpacing / 16, 0), 4)
    }

    var barMarkDimension: MarkDimension {
        if let valueSpacing = indicator.valueSpacing {
            return .ratio(max(0.18, 1 - valueSpacing / 80))
        }

        if indicator.barLayout == .compact {
            return .ratio(0.94)
        }

        return .automatic
    }

    func verticalBarPosition(for row: IndicatorRow) -> String {
        indicator.barLayout == .stacked ? "Значение" : (row.series ?? "Значение")
    }

    func strokeStyle(for row: IndicatorRow, isForecast: Bool = false) -> StrokeStyle {
        let style = row.lineStyle ?? indicator.lineStyle
        let usesDash = isForecast || style == .dashed
        return StrokeStyle(
            lineWidth: rowMatchesSelection(row) ? 3.5 : 2.5,
            lineCap: .round,
            lineJoin: .round,
            dash: usesDash ? [7, 5] : []
        )
    }

    var forecastLabels: [String] {
        indicator.orderedRows.uniqueValues(\.label)
    }

    var categoryLabels: [String] {
        indicator.orderedRows.uniqueValues(\.label)
    }

    var trendXDomain: ClosedRange<Double> {
        guard categoryLabels.count > 1 else {
            return -0.5...0.5
        }

        return 0...Double(categoryLabels.count - 1)
    }

    func trendXValue(for row: IndicatorRow) -> Double {
        trendXValue(for: row.label)
    }

    func trendXValue(for label: String) -> Double {
        Double(categoryLabels.firstIndex(of: label) ?? 0)
    }

    var longestDisplayValueCharacterCount: Int {
        indicator.orderedRows.map { displayValue(for: $0).count }.max() ?? 1
    }

    func trendContentWidth(availableWidth: CGFloat) -> CGFloat {
        ChartPresentationPolicy.contentWidth(
            availableWidth: availableWidth
        )
    }

    func trendAnnotationPosition(for row: IndicatorRow) -> AnnotationPosition {
        switch TrendLabelPlacementPolicy.placement(for: row, in: indicator.orderedRows) {
        case .above:
            return .top
        case .below:
            return .bottom
        }
    }

    func trendAnnotationAlignment(for row: IndicatorRow) -> Alignment {
        if row.label == categoryLabels.first {
            return .leading
        }

        if row.label == categoryLabels.last {
            return .trailing
        }

        return .center
    }

    var forecastStartIndex: Int? {
        ForecastPresentationPolicy.startIndex(
            pointCount: forecastLabels.count,
            explicitIndex: indicator.forecastFromIndex
        )
    }

    var forecastStartLabel: String? {
        guard let forecastStartIndex else {
            return nil
        }

        return forecastLabels[forecastStartIndex]
    }

    func isForecast(_ row: IndicatorRow) -> Bool {
        guard let forecastStartIndex,
              let rowIndex = forecastLabels.firstIndex(of: row.label) else {
            return false
        }

        return rowIndex >= forecastStartIndex
    }

}

struct TrendCrossingHighlightSegment: Identifiable {
    struct Point: Identifiable {
        let id: String
        let x: Double
        let y: Double
        let isIntersection: Bool
    }

    let id: String
    let points: [Point]
    let isForecast: Bool
}

struct TrendCrossingConfiguration {
    let controlledSeries: String
    let referenceSeries: String
    let source: [CrossingSourcePoint]
    let highlightedRowIDs: Set<IndicatorRow.ID>
}

extension AnalyticsChart {
    var crossingSeries: (controlled: String, reference: String)? {
        guard let crossingConfiguration else { return nil }
        return (
            crossingConfiguration.controlledSeries,
            crossingConfiguration.referenceSeries
        )
    }

    static func makeCrossingConfiguration(for indicator: Indicator) -> TrendCrossingConfiguration? {
        guard indicator.highlightCrossing == true,
              let controlledIndex = indicator.highlightSeriesIndex,
              let referenceIndex = indicator.referenceSeriesIndex,
              controlledIndex != referenceIndex else { return nil }

        let rows = indicator.orderedRows
        var seenSeries = Set<String>()
        let series = rows.reduce(into: [String]()) { result, row in
            let name = row.series ?? indicator.title
            if seenSeries.insert(name).inserted { result.append(name) }
        }
        guard series.indices.contains(controlledIndex), series.indices.contains(referenceIndex) else { return nil }
        let controlledSeries = series[controlledIndex]
        let referenceSeries = series[referenceIndex]
        var seenLabels = Set<String>()
        let labels = rows.reduce(into: [String]()) { result, row in
            if seenLabels.insert(row.label).inserted { result.append(row.label) }
        }
        var controlledByLabel: [String: IndicatorRow] = [:]
        var referenceByLabel: [String: IndicatorRow] = [:]
        for row in rows {
            let rowSeries = row.series ?? indicator.title
            if rowSeries == controlledSeries, controlledByLabel[row.label] == nil {
                controlledByLabel[row.label] = row
            } else if rowSeries == referenceSeries, referenceByLabel[row.label] == nil {
                referenceByLabel[row.label] = row
            }
        }

        var highlightedRowIDs = Set<IndicatorRow.ID>()
        let source = labels.enumerated().compactMap { index, label -> CrossingSourcePoint? in
            guard let controlled = controlledByLabel[label],
                  let reference = referenceByLabel[label] else { return nil }
            if controlled.value < reference.value { highlightedRowIDs.insert(controlled.id) }
            return CrossingSourcePoint(
                categoryIndex: index,
                x: Double(index),
                controlled: controlled.value,
                reference: reference.value
            )
        }
        guard source.count >= 2 else { return nil }
        return TrendCrossingConfiguration(
            controlledSeries: controlledSeries,
            referenceSeries: referenceSeries,
            source: source,
            highlightedRowIDs: highlightedRowIDs
        )
    }

    func isCrossingHighlighted(_ row: IndicatorRow) -> Bool {
        crossingConfiguration?.highlightedRowIDs.contains(row.id) == true
    }

    func crossingHighlightSegments(smooth: Bool) -> [TrendCrossingHighlightSegment] {
        guard let crossingConfiguration else { return [] }
        let source = crossingConfiguration.source
        let controlledValues = source.map(\.controlled)
        let referenceValues = source.map(\.reference)
        let controlledSlopes = smooth ? [] : monotoneSlopes(controlledValues)
        let referenceSlopes = smooth ? [] : monotoneSlopes(referenceValues)
        let samplesPerInterval = max(3, min(12, 240 / max(source.count - 1, 1)))
        let forecastIndex = forecastStartIndex ?? .max
        var result: [TrendCrossingHighlightSegment] = []

        for index in 0..<(source.count - 1) {
            let first = source[index]
            let second = source[index + 1]
            guard second.categoryIndex == first.categoryIndex + 1 else { continue }
            let samples = (0...samplesPerInterval).map { step -> CrossingCurveSample in
                let progress = Double(step) / Double(samplesPerInterval)
                let controlled = crossingCurveValue(
                    values: controlledValues,
                    slopes: controlledSlopes,
                    interval: index,
                    progress: progress,
                    smooth: smooth
                )
                let reference = crossingCurveValue(
                    values: referenceValues,
                    slopes: referenceSlopes,
                    interval: index,
                    progress: progress,
                    smooth: smooth
                )
                return CrossingCurveSample(
                    x: first.x + (second.x - first.x) * progress,
                    controlled: controlled,
                    difference: controlled - reference,
                    isIntersection: false
                )
            }
            result.append(contentsOf: crossingSegments(
                samples: samples,
                interval: index,
                isForecast: index + 1 >= forecastIndex
            ))
        }
        return result
    }

    func crossingIntersectionPoints(smooth: Bool) -> [TrendCrossingHighlightSegment.Point] {
        crossingHighlightSegments(smooth: smooth).flatMap { segment in
            segment.points.filter(\.isIntersection)
        }
    }

    @ChartContentBuilder
    func crossingHighlightMarks(smooth: Bool, forecastAware: Bool) -> some ChartContent {
        let segments = crossingHighlightSegments(smooth: smooth)

        ForEach(segments) { segment in
            ForEach(segment.points) { point in
                LineMark(
                    x: .value("Пересечение X", point.x),
                    y: .value("Пересечение Y", point.y),
                    series: .value("Контролируемый участок", segment.id)
                )
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(
                    lineWidth: 3,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: forecastAware && segment.isForecast ? [7, 5] : []
                ))
                .foregroundStyle(Color.red)
            }
        }

        ForEach(indicator.orderedRows.filter(isCrossingHighlighted)) { row in
            PointMark(
                x: .value("Контролируемая точка X", trendXValue(for: row)),
                y: .value("Контролируемая точка Y", row.value)
            )
            .foregroundStyle(Color.red)
            .symbolSize(34 * dashboardContentScale * dashboardContentScale)
        }

        ForEach(segments.flatMap { $0.points.filter(\.isIntersection) }) { point in
            PointMark(
                x: .value("Точка пересечения X", point.x),
                y: .value("Точка пересечения Y", point.y)
            )
            .foregroundStyle(Color.red)
            .symbolSize(42 * dashboardContentScale * dashboardContentScale)
        }
    }

    private func crossingCurveValue(
        values: [Double],
        slopes: [Double],
        interval: Int,
        progress: Double,
        smooth: Bool
    ) -> Double {
        let first = values[interval]
        let second = values[interval + 1]
        if smooth {
            let previous = values[max(0, interval - 1)]
            let next = values[min(values.count - 1, interval + 2)]
            let squared = progress * progress
            let cubed = squared * progress
            return 0.5 * (
                2 * first
                    + (-previous + second) * progress
                    + (2 * previous - 5 * first + 4 * second - next) * squared
                    + (-previous + 3 * first - 3 * second + next) * cubed
            )
        }

        let squared = progress * progress
        let cubed = squared * progress
        return (2 * cubed - 3 * squared + 1) * first
            + (cubed - 2 * squared + progress) * slopes[interval]
            + (-2 * cubed + 3 * squared) * second
            + (cubed - squared) * slopes[interval + 1]
    }

    private func monotoneSlopes(_ values: [Double]) -> [Double] {
        guard values.count > 1 else { return Array(repeating: 0, count: values.count) }
        let differences = zip(values, values.dropFirst()).map { $1 - $0 }
        var slopes = Array(repeating: 0.0, count: values.count)
        slopes[0] = differences[0]
        slopes[values.count - 1] = differences[differences.count - 1]
        if values.count > 2 {
            for index in 1..<(values.count - 1) {
                let previous = differences[index - 1]
                let next = differences[index]
                slopes[index] = previous * next <= 0
                    ? 0
                    : 2 * previous * next / (previous + next)
            }
        }
        return slopes
    }

    private func crossingSegments(
        samples: [CrossingCurveSample],
        interval: Int,
        isForecast: Bool
    ) -> [TrendCrossingHighlightSegment] {
        guard samples.count > 1 else { return [] }
        var runs: [[CrossingCurveSample]] = []
        var current: [CrossingCurveSample] = []

        for index in 0..<(samples.count - 1) {
            let first = samples[index]
            let second = samples[index + 1]
            let firstBelow = first.difference < 0
            let secondBelow = second.difference < 0
            let intersection = crossingIntersection(between: first, and: second)

            if firstBelow && current.isEmpty { current.append(first) }
            if firstBelow && secondBelow {
                current.append(second)
            } else if firstBelow {
                if let intersection { current.append(intersection) }
                if current.count > 1 { runs.append(current) }
                current = []
            } else if secondBelow {
                if let intersection { current.append(intersection) }
                current.append(second)
            }
        }
        if current.count > 1 { runs.append(current) }

        return runs.enumerated().map { runIndex, run in
            TrendCrossingHighlightSegment(
                id: "crossing-\(interval)-\(runIndex)",
                points: run.enumerated().map { pointIndex, point in
                    .init(
                        id: "crossing-\(interval)-\(runIndex)-\(pointIndex)",
                        x: point.x,
                        y: point.controlled,
                        isIntersection: point.isIntersection
                    )
                },
                isForecast: isForecast
            )
        }
    }

    private func crossingIntersection(
        between first: CrossingCurveSample,
        and second: CrossingCurveSample
    ) -> CrossingCurveSample? {
        guard (first.difference < 0) != (second.difference < 0) else { return nil }
        let progress = abs(first.difference)
            / max(abs(first.difference) + abs(second.difference), 0.000_001)
        return CrossingCurveSample(
            x: first.x + (second.x - first.x) * progress,
            controlled: first.controlled + (second.controlled - first.controlled) * progress,
            difference: 0,
            isIntersection: true
        )
    }
}

struct CrossingSourcePoint {
    let categoryIndex: Int
    let x: Double
    let controlled: Double
    let reference: Double
}

private struct CrossingCurveSample {
    let x: Double
    let controlled: Double
    let difference: Double
    let isIntersection: Bool
}

struct DonutExternalLabelPosition: Identifiable {
    let row: IndicatorRow
    let labelCenter: CGPoint

    var id: IndicatorRow.ID {
        row.id
    }
}

private struct ChartValueLabel: View {
    let value: Double
    let isSelected: Bool
    let selectionColor: Color
    let borderColor: Color?
    let usesContrastingForeground: Bool
    let useCompactNumbers: Bool?
    let displayText: String?
    let valueColor: Color?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dashboardContentScale) private var contentScale

    var body: some View {
        let metrics = ChartValueLabelLayoutPolicy.metrics(
            isSelected: isSelected,
            usesContrastingForeground: usesContrastingForeground
        )

        return Text(valueText)
            .font(
                (isSelected ? Font.caption : Font.caption2)
                    .monospacedDigit()
                    .weight(.bold)
            )
            .foregroundStyle(isSelected ? selectedForeground : displayTextColor)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .allowsTightening(true)
            .frame(maxWidth: metrics.maximumTextWidth)
            .padding(.horizontal, metrics.horizontalPadding * contentScale)
            .padding(.vertical, metrics.verticalPadding * contentScale)
            .background {
                if isSelected {
                    selectedBackground.clipShape(Capsule())
                } else if !usesContrastingForeground {
                    opaqueIdleBackground.clipShape(Capsule())
                }
            }
            .overlay {
                if isSelected || borderColor != nil {
                    Capsule()
                        .strokeBorder(
                            (borderColor ?? selectionColor).opacity(colorScheme == .dark ? 0.72 : 0.55),
                            lineWidth: borderColor == nil ? 1 : 1.5
                        )
                }
            }
            .subtleTextShadow()
            .transition(.identity)
            .zIndex(isSelected ? 20 : 0)
    }

    private var valueText: String {
        if let displayText {
            return displayText
        }

        if useCompactNumbers == true {
            return value.formatted(
                .number.notation(.compactName).precision(.fractionLength(0...2))
            )
        } else {
            return value.formatted(.number.grouping(.automatic).precision(.fractionLength(0...2)))
        }
    }

    private var selectedBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.11, blue: 0.12)
            : .white
    }

    private var selectedForeground: Color {
        valueColor ?? (colorScheme == .dark ? .white : selectionColor)
    }

    private var displayTextColor: Color {
        valueColor ?? (usesContrastingForeground ? .white : .primary)
    }

    private var opaqueIdleBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.92)
            : Color.white.opacity(0.90)
    }
}
