import Charts
import SwiftUI
import UIKit

extension AnalyticsChart {
    @AxisContentBuilder
    var valueAxis: some AxisContent {
        if indicator.showsYAxisLabels {
            humanReadableValueAxis(
                position: .leading,
                labelMaximumWidth: trendYAxisLabelMaximumWidth
            )
        } else {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(Color.secondary.opacity(0.16))
            }
        }
    }

    func humanReadableValueAxis(
        position: AxisMarkPosition,
        font: Font = .caption2,
        labelMaximumWidth: CGFloat? = nil
    ) -> some AxisContent {
        AxisMarks(position: position) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                .foregroundStyle(Color.secondary.opacity(0.16))
            AxisTick(stroke: StrokeStyle(lineWidth: 0.6))
                .foregroundStyle(Color.secondary.opacity(0.26))
            AxisValueLabel {
                if let number = value.as(Double.self) {
                    Text(formattedAxisValue(number))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                        .frame(maxWidth: labelMaximumWidth, alignment: .trailing)
                }
            }
            .foregroundStyle(Color.secondary)
            .font(font)
        }
    }

    var readableHorizontalCategoryAxis: some AxisContent {
        AxisMarks { value in
            AxisValueLabel {
                if let label = value.as(String.self) {
                    Text(wrappedAxisLabel(label))
                        .font(histogramYAxisFont)
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .allowsTightening(true)
                        .frame(maxWidth: histogramYAxisLabelMaximumWidth, alignment: .trailing)
                }
            }
        }
    }

    func formattedAxisValue(_ value: Double) -> String {
        let absoluteValue = abs(value)
        if absoluteValue >= 1_000_000 {
            return "\((value / 1_000_000).formatted(.number.precision(.fractionLength(0...1)))) млн"
        }
        if absoluteValue >= 1_000 {
            return "\((value / 1_000).formatted(.number.precision(.fractionLength(0...1)))) тыс."
        }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }

    var histogramYAxisFont: Font {
        .system(size: UIFont.preferredFont(forTextStyle: .caption2).pointSize * 0.7)
    }

    var histogramYAxisLabelMaximumWidth: CGFloat {
        44
    }

    var trendYAxisLabelMaximumWidth: CGFloat {
        24
    }

    var interactiveLegend: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: legendColumnMinimumWidth), spacing: 8 * dashboardContentScale)],
            alignment: .leading,
            spacing: 8 * dashboardContentScale
        ) {
            ForEach(displayedLegendRows) { row in
                Button {
                    toggleLegendSelection(row)
                } label: {
                    HStack(alignment: .top, spacing: 6 * dashboardContentScale) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(chartColor(for: row).opacity(legendRowMatchesSelection(row) ? 1 : 0.72))
                            .frame(width: 7 * dashboardContentScale, height: 7 * dashboardContentScale)
                            .padding(.top, 4 * dashboardContentScale)

                        Text(legendTitle(for: row))
                            .font(legendRowMatchesSelection(row) ? .caption.weight(.semibold) : .caption2.weight(.semibold))
                            .lineLimit(legendRowMatchesSelection(row) ? nil : legendTitleLineLimit)
                            .minimumScaleFactor(legendRowMatchesSelection(row) ? 1 : 0.78)
                            .fixedSize(horizontal: false, vertical: legendRowMatchesSelection(row))

                        Spacer(minLength: 0)

                        if let legendValue = legendValue(for: row) {
                            Text(legendValue)
                                .font(.caption2.monospacedDigit().weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .padding(.horizontal, 9 * dashboardContentScale)
                    .padding(.vertical, 7 * dashboardContentScale)
                    .frame(minHeight: legendItemMinimumHeight)
                    .background {
                        legendBackground(for: row)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(legendRowMatchesSelection(row) ? chartColor(for: row).opacity(0.22) : .clear, lineWidth: 1)
                    }
                    .shadow(
                        color: .black.opacity(colorScheme == .dark ? 0.28 : 0.14),
                        radius: 5,
                        x: 0,
                        y: 3
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Выбрать \(legendTitle(for: row))")
                .accessibilityValue(legendValue(for: row) ?? "")
            }
        }
    }

    var selectedDonutRow: IndicatorRow? {
        guard isDonutChart, let selectedRowID else {
            return nil
        }

        return indicator.orderedRows.first { $0.id == selectedRowID }
    }

    var displayedLegendRows: [IndicatorRow] {
        isDonutChart ? legendRows : Array(legendRows.prefix(8))
    }

    var isDonutChart: Bool {
        indicator.chartType == .donut || indicator.chartType == .percentDonut
    }

    var legendTitleLineLimit: Int {
        return indicator.usesDenseEnrollmentCompositionPresentation ? 2 : 1
    }

    var legendItemMinimumHeight: CGFloat {
        if isDonutChart {
            return 36 * dashboardContentScale
        }

        return (indicator.usesDenseEnrollmentCompositionPresentation ? 38 : 28) * dashboardContentScale
    }

    var legendRows: [IndicatorRow] {
        guard usesSeriesLegend else {
            return indicator.orderedRows
        }

        guard !indicator.barDataShape.series.isEmpty else {
            return Array(indicator.orderedRows.prefix(1))
        }

        return indicator.barDataShape.series.compactMap { series in
            indicator.orderedRows.first { $0.series == series }
        }
    }

    func legendTitle(for row: IndicatorRow) -> String {
        if usesSeriesLegend {
            return row.series ?? indicator.title
        }

        return row.label
    }

    var legendColumnMinimumWidth: CGFloat {
        if indicator.usesDenseEnrollmentCompositionPresentation
            || indicator.usesCitizenshipCompositionPresentation {
            return 140 * dashboardContentScale
        }

        return switch indicator.chartType {
        case .donut, .percentDonut:
            142 * dashboardContentScale
        default:
            96 * dashboardContentScale
        }
    }

    func legendValue(for row: IndicatorRow) -> String? {
        switch indicator.chartType {
        case .donut:
            return displayValue(for: row)
        case .percentDonut:
            let total = indicator.orderedRows.reduce(0) { $0 + max($1.value, 0) }
            guard total > 0 else {
                return "0%"
            }
            return (row.value / total).formatted(.percent.precision(.fractionLength(0)))
        default:
            return nil
        }
    }

    var usesSeriesLegend: Bool {
        switch indicator.chartType {
        case .line, .area, .splineLine, .splineArea, .forecastLine:
            return true
        case .bar, .horizontalBar:
            return !indicator.barDataShape.series.isEmpty
        case .stackedBar:
            return !indicator.barDataShape.series.isEmpty
        case .compactBar:
            return indicator.prefersHorizontalGroupedBars
                && !indicator.barDataShape.series.isEmpty
        case .donut, .percentDonut,
             .oneValue, .linearProgress, .gauge, .geoMap:
            return false
        }
    }

    var displaysLegend: Bool {
        indicator.showLegend ?? showsLegend
    }

    @ViewBuilder
    func legendBackground(for row: IndicatorRow) -> some View {
        ZStack {
            opaqueLabelBackground

            if legendRowMatchesSelection(row) {
                chartColor(for: row).opacity(0.12)
            }
        }
    }

    var selectedRowID: IndicatorRow.ID? {
        externalSelection?.wrappedValue ?? internalSelectedRowID
    }

    var chartColors: [Color] {
        ChartPalette.colors(for: chartPaletteScheme)
    }

    func chartColor(for row: IndicatorRow) -> Color {
        indicator.chartColor(for: row, scheme: chartPaletteScheme)
    }

    func verticalBarStyle(for row: IndicatorRow) -> AnyShapeStyle {
        let color = chartColor(for: row)

        guard indicator.orderedRows.count < 2 else {
            return AnyShapeStyle(color)
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [vividColor(color, brightness: 1.10), color, vividColor(color, brightness: 0.70)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    func horizontalGradient(for row: IndicatorRow) -> LinearGradient {
        let color = chartColor(for: row)
        return LinearGradient(
            colors: [vividColor(color, brightness: 1.08), color, vividColor(color, brightness: 0.72)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    func sectorGradient(for row: IndicatorRow) -> LinearGradient {
        let color = chartColor(for: row)
        return LinearGradient(
            colors: [vividColor(color, brightness: 1.10), color, vividColor(color, brightness: 0.76)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func areaGradient(for row: IndicatorRow) -> LinearGradient {
        let color = chartColor(for: row)
        return LinearGradient(
            colors: [vividColor(color, brightness: 1.06).opacity(0.54), color.opacity(0.04)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    func vividColor(_ color: Color, brightness factor: CGFloat) -> Color {
        let resolvedColor = UIColor(color)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        guard resolvedColor.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        ) else {
            return color
        }

        return Color(
            hue: Double(hue),
            saturation: Double(min(saturation * 1.08, 1)),
            brightness: Double(min(max(brightness * factor, 0), 1)),
            opacity: Double(alpha)
        )
    }

    var opaqueLabelBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.11, blue: 0.12)
            : .white
    }

    func animatedValue(for row: IndicatorRow) -> Double {
        !animatesOnAppear || hasAppeared ? row.value : 0
    }

    func opacity(for row: IndicatorRow) -> Double {
        guard selectedRowID != nil else {
            return 1
        }

        return rowMatchesSelection(row) ? 1 : 0.28
    }

}
