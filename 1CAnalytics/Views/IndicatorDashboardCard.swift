import SwiftUI

struct IndicatorDashboardCard: View {
    let indicator: Indicator
    let animationTrigger: String
    @Environment(\.chartPaletteScheme) private var chartPaletteScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardContent
        }
        .padding(18)
        .frame(
            maxWidth: .infinity,
            minHeight: indicator.chartType == .oneValue ? 164 : nil,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(
            indicator.chartType == .oneValue ? paletteColor.opacity(0.075) : .clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .premiumPanel(isElevated: false)
        .overlay(alignment: .leading) {
            if indicator.chartType == .oneValue {
                Capsule()
                    .fill(paletteColor)
                    .frame(width: 4)
                    .padding(.vertical, 14)
                    .offset(x: 6)
                    .accessibilityHidden(true)
            }
        }
    }

    private var paletteColor: Color {
        indicator.paletteColor(scheme: chartPaletteScheme)
    }

    @ViewBuilder
    private var cardContent: some View {
        if indicator.chartType == .oneValue {
            OneValueDashboardContent(indicator: indicator, reservesDetailButtonSpace: true)
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
                animationTrigger: animationTrigger
            )
                .frame(height: chartHeight)
        case .geoMap:
            GeoMapIndicatorView(indicator: indicator)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
             .line, .area, .splineLine, .splineArea, .forecastLine:
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
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .subtleTextShadow()

                Spacer(minLength: 0)
            }
            .padding(.trailing, indicator.supportsDetail ? 42 : 0)

            if indicator.showsAggregateValue && !indicator.usesContractPlanFactPresentation {
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

