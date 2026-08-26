import Charts
import SwiftUI
import UIKit

struct AnalyticsChart: View {
    let indicator: Indicator
    let crossingConfiguration: TrendCrossingConfiguration?
    var usesCardBackground = true
    var showsLegend = true
    var showsValueLabels = true
    var animatesOnAppear = true
    var animationTrigger = ""
    var externalSelection: Binding<IndicatorRow.ID?>?
    @State var internalSelectedRowID: IndicatorRow.ID?
    @State var selectedSeriesKey: String?
    @State var selectedSeriesAnchorID: IndicatorRow.ID?
    @State var hasAppeared = false
    @State var isVisible = false
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.chartPaletteScheme) var chartPaletteScheme
    @Environment(\.dashboardContentScale) var dashboardContentScale
    @Environment(\.accessibilityReduceMotion) var accessibilityReduceMotion

    init(
        indicator: Indicator,
        usesCardBackground: Bool = true,
        showsLegend: Bool = true,
        showsValueLabels: Bool = true,
        animatesOnAppear: Bool = true,
        animationTrigger: String = "",
        selectedRowID: Binding<IndicatorRow.ID?>? = nil
    ) {
        self.indicator = indicator
        self.crossingConfiguration = Self.makeCrossingConfiguration(for: indicator)
        self.usesCardBackground = usesCardBackground
        self.showsLegend = showsLegend
        self.showsValueLabels = showsValueLabels
        self.animatesOnAppear = animatesOnAppear
        self.animationTrigger = animationTrigger
        self.externalSelection = selectedRowID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * dashboardContentScale) {
            chartContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .frame(minHeight: isDonutChart ? 220 * dashboardContentScale : nil)
                .zIndex(selectedRowID == nil ? 0 : 10)

            if displaysLegend, !indicator.orderedRows.isEmpty {
                interactiveLegend
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
        }
        .modifier(ChartChromeModifier(isEnabled: usesCardBackground))
        .chartLegend(.hidden)
        .onAppear {
            isVisible = true
            animateIfNeeded()
        }
        .onDisappear {
            isVisible = false
            clearSelection()
        }
        .onChange(of: animationTrigger) { _, _ in
            prepareReplayAnimation()
        }
        .onChange(of: accessibilityReduceMotion) { _, reduceMotion in
            if reduceMotion {
                setAppearedWithoutAnimation()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                clearSelection()
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selectedRowID)
        .dashboardScaledTypography()
    }

    func animateIfNeeded() {
        guard animatesOnAppear, !hasAppeared else {
            return
        }
        guard !accessibilityReduceMotion else {
            setAppearedWithoutAnimation()
            return
        }

        withAnimation(.easeOut(duration: 0.7)) {
            hasAppeared = true
        }
    }

    func prepareReplayAnimation() {
        guard animatesOnAppear else {
            return
        }
        guard !accessibilityReduceMotion else {
            setAppearedWithoutAnimation()
            return
        }

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            hasAppeared = false
        }

        guard isVisible else {
            return
        }

        Task { @MainActor in
            await Task.yield()
            guard isVisible else {
                return
            }
            animateIfNeeded()
        }
    }

    func setAppearedWithoutAnimation() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            hasAppeared = true
        }
    }

    @ViewBuilder
    var chartContent: some View {
        if indicator.orderedRows.isEmpty {
            emptyDataState(message: "Для показателя пока нет значений")
        } else if indicator.hasOnlyZeroValues {
            emptyDataState
        } else {
            switch indicator.chartType {
            case .bar, .compactBar:
                verticalBars
            case .horizontalBar:
                if indicator.usesMixedUnitPersonnelPresentation {
                    personnelComposition
                } else if indicator.usesCitizenshipCompositionPresentation {
                    citizenshipComposition
                } else {
                    horizontalBars
                }
            case .stackedBar:
                horizontalStackedComposition
            case .donut:
                donut(showsPercentages: false)
            case .percentDonut:
                donut(showsPercentages: true)
            case .line:
                trendLine(smooth: false)
            case .splineLine:
                trendLine(smooth: true)
            case .area:
                trendArea(smooth: false)
            case .splineArea:
                trendArea(smooth: true)
            case .forecastLine:
                forecastLine
            case .radar:
                radarChart
            case .oneValue, .linearProgress, .gauge, .geoMap, .expandableHierarchy, .tile:
                EmptyView()
            }
        }
    }

    var emptyDataState: some View {
        emptyDataState(message: "Плановые и фактические значения равны нулю")
    }

    func emptyDataState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(indicator.paletteColor(scheme: chartPaletteScheme).opacity(0.72))

            Text("Данные пока отсутствуют")
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }

    var personnelComposition: some View {
        let countRows = indicator.orderedRows.filter { !($0.series ?? "").lowercased().contains("процент") }
        let percentRows = indicator.orderedRows.filter { ($0.series ?? "").lowercased().contains("процент") }

        return VStack(alignment: .leading, spacing: 16) {
            presentationMetricGroup(
                title: indicator.displayUnit.map { "Численность, \($0)" } ?? "Численность",
                rows: countRows,
                maximum: countRows.map(\.value).max() ?? 1,
                isPercent: false
            )

            Divider()

            presentationMetricGroup(title: "Доля в ССЧ", rows: percentRows, maximum: 100, isPercent: true)
        }
    }

    func presentationMetricGroup(
        title: String,
        rows: [IndicatorRow],
        maximum: Double,
        isPercent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .subtleTextShadow()

            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Text(presentationLabel(for: row))
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.80)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 112, alignment: .leading)
                        .subtleTextShadow()

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(chartColor(for: row).opacity(0.12))

                            Capsule()
                                .fill(horizontalGradient(for: row))
                                .frame(width: proxy.size.width * min(max(row.value / max(maximum, 1), 0.012), 1))
                        }
                    }
                    .frame(height: 9)

                    if shouldShowValueLabel(for: row) {
                        if rowMatchesSelection(row) {
                            valueLabel(for: row)
                        } else {
                            Text(isPercent ? "\(displayValue(for: row))%" : displayValue(for: row))
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(indicator.valueColor(for: row))
                                .frame(minWidth: 48, alignment: .trailing)
                                .subtleTextShadow()
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleSelection(row.id)
                }
            }
        }
    }

    func presentationLabel(for row: IndicatorRow) -> String {
        let raw = row.series ?? row.label
        return raw
            .replacingOccurrences(of: "Общая численность", with: "Всего")
            .replacingOccurrences(of: "Численность ", with: "")
            .replacingOccurrences(of: "Процент ", with: "")
    }

    var horizontalStackedComposition: some View {
        Chart(indicator.orderedRows) { row in
            BarMark(
                x: .value("Значение", animatedValue(for: row)),
                y: .value("Период", row.label),
                height: .ratio(0.58)
            )
            .foregroundStyle(horizontalGradient(for: row))
            .alignsMarkStylesWithPlotArea(false)
            .cornerRadius(2)
            .opacity(opacity(for: row))
            .annotation(position: .overlay, alignment: .center) {
                if shouldShowValueLabel(for: row),
                   rowMatchesSelection(row)
                    || compositionShare(for: row) >= 0.10 {
                    valueLabel(for: row, usesContrastingForeground: true)
                }
            }

            if indicator.showsAggregateValue,
               isLastRowInGroup(row),
               let group = rowGroup(for: row) {
                PointMark(
                    x: .value("Итого", group.totalValue),
                    y: .value("Период", group.label)
                )
                .symbolSize(0)
                .annotation(
                    position: .trailing,
                    alignment: .center,
                    spacing: 6,
                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                ) {
                    groupTotalLabel(group)
                }
            }
        }
        .chartForegroundStyleScale(domain: indicator.chartColorDomain, range: chartColors)
        .chartXScale(
            domain: VerticalBarValueLabelScale.domain(
                for: indicator.rowGroups.map(\.totalValue)
            )
        )
        .chartXAxis {
            humanReadableValueAxis(position: .bottom)
        }
        .chartYAxis {
            readableHorizontalCategoryAxis
        }
        .chartOverlay { proxy in
            chartTapOverlay(proxy: proxy, mode: .stackedBar)
        }
    }

    var citizenshipComposition: some View {
        let groups = indicator.rowGroups
        let maximumTotal = max(groups.map(\.totalValue).max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: 18) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(group.label)
                            .font(histogramYAxisFont.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(citizenshipValuesLabel(for: group))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    GeometryReader { geometry in
                        let filledWidth = geometry.size.width
                            * min(max(group.totalValue / maximumTotal, 0), 1)

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(colorScheme == .dark ? 0.16 : 0.10))

                            HStack(spacing: 0) {
                                ForEach(group.rows) { row in
                                    Rectangle()
                                        .fill(horizontalGradient(for: row))
                                        .frame(
                                            width: filledWidth
                                                * max(row.value, 0)
                                                / max(group.totalValue, 1)
                                        )
                                        .opacity(opacity(for: row))
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            toggleSelection(row.id)
                                        }
                                }
                            }
                            .frame(width: filledWidth, alignment: .leading)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                            ForEach(group.rows.filter(rowMatchesSelection)) { row in
                                Text(displayValue(for: row))
                                    .font(.headline.monospacedDigit().weight(.bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(opaqueLabelBackground, in: Capsule())
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(chartColor(for: row).opacity(0.42), lineWidth: 1)
                                    }
                                    .position(
                                        x: citizenshipSelectedLabelX(
                                            for: row,
                                            in: group,
                                            filledWidth: filledWidth,
                                            availableWidth: geometry.size.width
                                        ),
                                        y: geometry.size.height / 2
                                    )
                                    .subtleTextShadow()
                                    .allowsHitTesting(false)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    .frame(height: 26)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    func citizenshipSelectedLabelX(
        for row: IndicatorRow,
        in group: IndicatorRowGroup,
        filledWidth: CGFloat,
        availableWidth: CGFloat
    ) -> CGFloat {
        let leadingValue = group.rows
            .prefix { $0.id != row.id }
            .reduce(0) { $0 + max($1.value, 0) }
        let centerValue = leadingValue + max(row.value, 0) / 2
        let naturalX = filledWidth * centerValue / max(group.totalValue, 1)
        return min(max(naturalX, 42), max(availableWidth - 42, 42))
    }

    func citizenshipValuesLabel(for group: IndicatorRowGroup) -> String {
        group.rows.map { row in
            let name = row.series?.replacingOccurrences(of: ", чел", with: "")
            return [name, displayValue(for: row)]
                .compactMap { $0 }
                .joined(separator: ": ")
        }
        .joined(separator: "  ·  ")
    }

    func compositionShare(for row: IndicatorRow) -> Double {
        let total = indicator.rowGroups.first { $0.label == row.label }?.totalValue ?? 0
        return total > 0 ? row.value / total : 0
    }

}
