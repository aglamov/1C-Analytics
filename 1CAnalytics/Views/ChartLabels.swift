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
        if indicator.prefersTrendPresentation {
            return true
        }

        switch indicator.chartType {
        case .line, .area, .splineLine, .splineArea, .forecastLine:
            return true
        case .bar, .compactBar, .horizontalBar, .stackedBar, .donut,
             .percentDonut, .oneValue, .linearProgress, .gauge, .geoMap:
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
                if isSelected {
                    Capsule()
                        .strokeBorder(selectionColor.opacity(colorScheme == .dark ? 0.46 : 0.26), lineWidth: 1)
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
