import SwiftUI

struct IndicatorDashboardCard: View {
    let indicator: Indicator
    let animationTrigger: String
    @Environment(\.dashboardContentScale) private var contentScale

    var body: some View {
        VStack(alignment: .leading, spacing: 16 * contentScale) {
            cardContent
        }
        .padding(.horizontal, 18 * contentScale)
        .padding(.vertical, cardVerticalPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: indicator.chartType == .oneValue ? 110 * contentScale : nil,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .premiumPanel(isElevated: false)
        .dashboardScaledTypography()
    }

    private var cardVerticalPadding: CGFloat {
        (indicator.chartType == .oneValue ? 8 : 18) * contentScale
    }

    @ViewBuilder
    private var cardContent: some View {
        if indicator.chartType == .oneValue {
            OneValueDashboardContent(
                indicator: indicator,
                reservesDetailButtonSpace: true
            )
        } else {
            header
            visualization
        }
    }

    @ViewBuilder
    private var visualization: some View {
        if indicator.usesContractPlanFactPresentation {
            ContractPlanFactCompletionChart(indicator: indicator)
        } else {
            standardVisualization
        }
    }

    @ViewBuilder
    private var standardVisualization: some View {
        switch indicator.chartType {
        case .oneValue:
            EmptyView()
        case .linearProgress:
            LinearProgressIndicatorView(indicator: indicator)
        case .gauge:
            GaugeIndicatorView(
                indicator: indicator,
                animationTrigger: animationTrigger,
                maximumDialWidth: 200
            )
            .frame(maxWidth: .infinity)
        case .geoMap:
            GeoMapIndicatorView(indicator: indicator)
                .frame(maxWidth: .infinity)
                .frame(minHeight: chartHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        case .expandableHierarchy:
            ExpandableHierarchyChartView(indicator: indicator, showsExpandedHierarchy: false)
                .frame(minHeight: chartHeight, alignment: .top)
        case .compactBar:
            VStack(alignment: .leading, spacing: 12) {
                AnalyticsChart(
                    indicator: indicator,
                    usesCardBackground: false,
                    showsLegend: true,
                    animatesOnAppear: true,
                    animationTrigger: animationTrigger
                )
                    .frame(minHeight: chartHeight, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 2)

                if !indicator.prefersHorizontalGroupedBars, indicator.showsValueLabels {
                    CompactBarValues(indicator: indicator)
                }
            }
        case .bar, .horizontalBar, .stackedBar, .donut, .percentDonut,
             .line, .area, .splineLine, .splineArea, .forecastLine, .radar:
            AnalyticsChart(
                indicator: indicator,
                usesCardBackground: false,
                showsLegend: true,
                animatesOnAppear: true,
                showsLineAreaFill: true,
                animationTrigger: animationTrigger
            )
                .frame(minHeight: chartHeight, maxHeight: .infinity, alignment: .top)
                .padding(.top, 2)
        }
    }

    private var chartHeight: CGFloat {
        unscaledChartHeight * contentScale
    }

    private var unscaledChartHeight: CGFloat {
        let categoryCount = max(Set(indicator.orderedRows.map(\.label)).count, 1)

        if indicator.usesMixedUnitPersonnelPresentation {
            return max(250, CGFloat(indicator.orderedRows.count) * 30 + 96)
        }

        if indicator.usesDenseEnrollmentCompositionPresentation {
            return max(CGFloat(categoryCount) * 50 + 142, 296)
        }

        if indicator.prefersHorizontalGroupedBars {
            return ChartHeightPolicy.horizontalBarHeight(
                categoryCount: categoryCount,
                seriesCount: max(indicator.barDataShape.series.count, 1)
            )
        }

        switch indicator.chartType {
        case .horizontalBar:
            return ChartHeightPolicy.horizontalBarHeight(
                categoryCount: categoryCount,
                seriesCount: max(indicator.barDataShape.series.count, 1)
            )
        case .bar:
            return 238
        case .stackedBar:
            return 252
        case .compactBar:
            return 214
        case .line, .area, .splineLine, .splineArea, .forecastLine:
            return 264
        case .radar:
            return 300
        case .expandableHierarchy:
            let rootCount = max(indicator.hierarchy?.nodes.count ?? 0, 1)
            let seriesCount = max(indicator.hierarchy?.displayedSeries.count ?? 0, 1)
            let rowHeight: CGFloat = indicator.hierarchy?.barMode == .grouped
                ? CGFloat(seriesCount) * 32 + 40
                : 70
            return max(190, CGFloat(rootCount) * rowHeight + 52)
        case .donut, .percentDonut:
            return indicator.orderedRows.count > 4 ? 310 : 286
        case .gauge:
            return 250
        case .oneValue, .linearProgress, .geoMap:
            return 220
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(indicator.title)
                    .font(.headline)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .subtleTextShadow()

                Spacer(minLength: 0)
            }
            .padding(.trailing, indicator.supportsDetail ? 42 : 0)

            if indicator.showsAggregateValueInHeader {
                Text(valueText)
                    .font(.system(.title2, design: .default).weight(.semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .subtleTextShadow()
            }

        }
    }

    private var valueText: String {
        guard let value = indicator.value else {
            return "нет данных"
        }

        return indicator.formattedValueWithUnit(value)
    }

}
