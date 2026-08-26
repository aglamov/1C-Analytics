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
        if presentationIndicator.usesContractPlanFactPresentation {
            if presentationIndicator.useOverviewStyle == true {
                ContractPlanFactCompletionChart(indicator: presentationIndicator)
            } else {
                ContractPlanFactView(indicator: presentationIndicator)
            }
        } else {
            standardVisualization
        }
    }

    @ViewBuilder
    private var standardVisualization: some View {
        switch presentationIndicator.chartType {
        case .oneValue:
            EmptyView()
        case .linearProgress:
            LinearProgressIndicatorView(indicator: presentationIndicator)
        case .gauge:
            GaugeIndicatorView(
                indicator: presentationIndicator,
                animationTrigger: animationTrigger,
                maximumDialWidth: 200
            )
            .frame(maxWidth: .infinity)
        case .geoMap:
            GeoMapIndicatorView(indicator: presentationIndicator)
                .frame(maxWidth: .infinity)
                .frame(minHeight: chartHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        case .expandableHierarchy:
            expandableHierarchyOverview
        case .tile:
            TileChartView(indicator: presentationIndicator, appliesCardLimit: true)
                .frame(minHeight: chartHeight, alignment: .top)
        case .compactBar:
            AnalyticsChart(
                indicator: presentationIndicator,
                usesCardBackground: false,
                showsLegend: true,
                animatesOnAppear: true,
                animationTrigger: animationTrigger
            )
                .frame(minHeight: chartHeight, maxHeight: .infinity, alignment: .top)
                .padding(.top, 2)
        case .bar, .horizontalBar, .stackedBar, .donut, .percentDonut,
             .line, .area, .splineLine, .splineArea, .forecastLine, .radar:
            AnalyticsChart(
                indicator: presentationIndicator,
                usesCardBackground: false,
                showsLegend: true,
                animatesOnAppear: true,
                animationTrigger: animationTrigger
            )
                .frame(minHeight: chartHeight, maxHeight: .infinity, alignment: .top)
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var expandableHierarchyOverview: some View {
        switch presentationIndicator.resolvedExpandableOverviewType {
        case .map:
            if let overview = presentationIndicator.hierarchyOverviewIndicator(chartType: .geoMap) {
                GeoMapIndicatorView(indicator: overview)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: chartHeight)
            }
        case .tile:
            if let overview = presentationIndicator.hierarchyOverviewIndicator(chartType: .tile) {
                TileChartView(indicator: overview, appliesCardLimit: true)
                    .frame(minHeight: chartHeight)
            }
        case nil:
            ExpandableHierarchyChartView(indicator: presentationIndicator, showsExpandedHierarchy: false)
                .frame(minHeight: chartHeight, alignment: .top)
        }
    }

    private var presentationIndicator: Indicator {
        indicator.cardPresentationIndicator
    }

    private var chartHeight: CGFloat {
        unscaledChartHeight * contentScale
    }

    private var unscaledChartHeight: CGFloat {
        let categoryCount = max(Set(presentationIndicator.orderedRows.map(\.label)).count, 1)

        if presentationIndicator.usesMixedUnitPersonnelPresentation {
            return max(250, CGFloat(presentationIndicator.orderedRows.count) * 30 + 96)
        }

        if presentationIndicator.usesDenseEnrollmentCompositionPresentation {
            return max(CGFloat(categoryCount) * 50 + 142, 296)
        }

        switch presentationIndicator.chartType {
        case .horizontalBar:
            return ChartHeightPolicy.horizontalBarHeight(
                categoryCount: categoryCount,
                seriesCount: max(presentationIndicator.barDataShape.series.count, 1)
            )
        case .bar:
            return 238
        case .stackedBar:
            return ChartHeightPolicy.horizontalBarHeight(
                categoryCount: categoryCount,
                seriesCount: 1
            )
        case .compactBar:
            return 214
        case .line, .area, .splineLine, .splineArea, .forecastLine:
            return 264
        case .radar:
            return 300
        case .expandableHierarchy:
            let rootCount = max(presentationIndicator.hierarchy?.nodes.count ?? 0, 1)
            let seriesCount = max(presentationIndicator.hierarchy?.displayedSeries.count ?? 0, 1)
            let rowHeight: CGFloat = presentationIndicator.hierarchy?.barMode == .grouped
                ? CGFloat(seriesCount) * 32 + 40
                : 70
            return max(190, CGFloat(rootCount) * rowHeight + 52)
        case .donut, .percentDonut:
            return presentationIndicator.orderedRows.count > 4 ? 310 : 286
        case .tile:
            return 260
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
