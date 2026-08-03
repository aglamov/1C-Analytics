import Charts
import SwiftUI

struct AnalyticsChart: View {
    let indicator: Indicator
    var showsTitle = true
    var usesCardBackground = true
    var showsLegend = true
    var showsValueLabels = true
    var animatesOnAppear = true
    var showsLineAreaFill = false
    private var externalSelection: Binding<IndicatorRow.ID?>?
    @State private var internalSelectedRowID: IndicatorRow.ID?
    @State private var selectedSeriesKey: String?
    @State private var selectedSeriesAnchorID: IndicatorRow.ID?
    @State private var hasAppeared = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.chartPaletteScheme) private var chartPaletteScheme

    init(
        indicator: Indicator,
        showsTitle: Bool = true,
        usesCardBackground: Bool = true,
        showsLegend: Bool = true,
        showsValueLabels: Bool = true,
        animatesOnAppear: Bool = true,
        showsLineAreaFill: Bool = false,
        selectedRowID: Binding<IndicatorRow.ID?>? = nil
    ) {
        self.indicator = indicator
        self.showsTitle = showsTitle
        self.usesCardBackground = usesCardBackground
        self.showsLegend = showsLegend
        self.showsValueLabels = showsValueLabels
        self.animatesOnAppear = animatesOnAppear
        self.showsLineAreaFill = showsLineAreaFill
        self.externalSelection = selectedRowID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle, indicator.showValueLabels != false, let selectedRow {
                HStack {
                    Spacer()

                    Text(selectedRowTitle(for: selectedRow))
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .allowsTightening(true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .background(selectedTitleBackground, in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.secondary.opacity(colorScheme == .dark ? 0.20 : 0.12), lineWidth: 1)
                        }
                        .subtleTextShadow()
                        .transition(.move(edge: .trailing))
                }
            }

            chartContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()

            if displaysLegend, !indicator.orderedRows.isEmpty {
                interactiveLegend
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
        }
        .modifier(ChartChromeModifier(isEnabled: usesCardBackground))
        .chartLegend(.hidden)
        .onAppear {
            guard animatesOnAppear else {
                return
            }
            withAnimation(.easeOut(duration: 0.7)) {
                hasAppeared = true
            }
        }
        .onDisappear {
            clearSelection()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                clearSelection()
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selectedRowID)
    }

    @ViewBuilder
    private var chartContent: some View {
        if indicator.hasOnlyZeroValues {
            emptyDataState
        } else if indicator.usesMixedUnitPersonnelPresentation {
            personnelComposition
        } else if indicator.usesRankedCategoryPresentation {
            rankedCategoryBars
        } else if indicator.usesDenseEnrollmentCompositionPresentation {
            horizontalStackedComposition
        } else if indicator.prefersTrendPresentation {
            trendLine(smooth: false)
        } else {
            switch indicator.chartType {
            case .bar, .compactBar:
                if indicator.prefersHorizontalGroupedBars {
                    horizontalBars
                } else {
                    verticalBars
                }
            case .horizontalBar:
                horizontalBars
            case .stackedBar:
                if indicator.usesStackedCompositionPresentation {
                    horizontalStackedBars
                } else {
                    stackedBars
                }
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
            case .oneValue, .linearProgress, .gauge, .geoMap:
                EmptyView()
            }
        }
    }

    private var emptyDataState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(indicator.graphColor.opacity(0.72))

            Text("Данные пока отсутствуют")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Плановые и фактические значения равны нулю")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }

    private var rankedCategoryBars: some View {
        let rows = rankedPresentationRows
        let maximum = rows.map(\.value).max() ?? 1

        return VStack(alignment: .leading, spacing: 11) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .subtleTextShadow()

                        Spacer(minLength: 6)

                        if shouldShowValueLabel(for: row) {
                            if rowMatchesSelection(row) {
                                valueLabel(for: row)
                            } else {
                                Text(indicator.formattedNumber(row.value))
                                    .font(.caption.monospacedDigit().weight(.bold))
                                    .foregroundStyle(.primary)
                                    .subtleTextShadow()
                            }
                        }
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(chartColor(for: row).opacity(0.12))

                            Capsule()
                                .fill(horizontalGradient(for: row))
                                .frame(width: proxy.size.width * max(row.value / maximum, 0.012))
                        }
                    }
                    .frame(height: 7)
                }
                .accessibilityElement(children: .combine)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleSelection(row.id)
                }
            }
        }
    }

    private var rankedPresentationRows: [IndicatorRow] {
        let sorted = indicator.orderedRows.sorted { $0.value > $1.value }
        guard sorted.count > 5 else {
            return sorted
        }

        let visibleRows = Array(sorted.prefix(4))
        let remainingRows = sorted.dropFirst(4)
        let other = IndicatorRow(
            id: "\(indicator.id)-other",
            label: "Прочие звания",
            value: remainingRows.reduce(0) { $0 + $1.value },
            series: nil,
            sortOrder: nil,
            colorGraph: nil,
            colorValue: nil
        )
        return visibleRows + [other]
    }

    private var personnelComposition: some View {
        let countRows = indicator.orderedRows.filter { !($0.series ?? "").lowercased().contains("процент") }
        let percentRows = indicator.orderedRows.filter { ($0.series ?? "").lowercased().contains("процент") }

        return VStack(alignment: .leading, spacing: 16) {
            presentationMetricGroup(title: "Численность, чел.", rows: countRows, maximum: countRows.map(\.value).max() ?? 1, isPercent: false)

            Divider()

            presentationMetricGroup(title: "Доля в ССЧ", rows: percentRows, maximum: 100, isPercent: true)
        }
    }

    private func presentationMetricGroup(
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
                        .lineLimit(1)
                        .frame(width: 104, alignment: .leading)
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
                            Text(isPercent ? "\(indicator.formattedNumber(row.value))%" : indicator.formattedNumber(row.value))
                                .font(.caption.monospacedDigit().weight(.bold))
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

    private func presentationLabel(for row: IndicatorRow) -> String {
        let raw = row.series ?? row.label
        return raw
            .replacingOccurrences(of: "Общая численность", with: "Всего")
            .replacingOccurrences(of: "Численность ", with: "")
            .replacingOccurrences(of: "Процент ", with: "")
    }

    private var horizontalStackedComposition: some View {
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
                   indicator.showValueLabels == true
                    || rowMatchesSelection(row)
                    || compositionShare(for: row) >= 0.10 {
                    valueLabel(for: row, usesContrastingForeground: true)
                }
            }

            if isLastRowInGroup(row), let group = rowGroup(for: row) {
                PointMark(
                    x: .value("Итого", group.totalValue),
                    y: .value("Период", group.label)
                )
                .symbolSize(0)
                .annotation(position: .trailing, alignment: .center, spacing: 6) {
                    groupTotalLabel(group)
                }
            }
        }
        .chartForegroundStyleScale(domain: indicator.chartColorDomain, range: chartColors)
        .chartXAxis {
            humanReadableValueAxis(position: .bottom)
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .foregroundStyle(Color.secondary)
                    .font(.caption2)
            }
        }
        .chartOverlay { proxy in
            chartTapOverlay(proxy: proxy, mode: .stackedBar)
        }
    }

    private func compositionShare(for row: IndicatorRow) -> Double {
        let total = indicator.rowGroups.first { $0.label == row.label }?.totalValue ?? 0
        return total > 0 ? row.value / total : 0
    }

    private var horizontalStackedBars: some View {
        let groups = indicator.rowGroups
        let maximum = max(groups.map(\.totalValue).max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: 17) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(group.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .subtleTextShadow()

                        Spacer(minLength: 8)

                        Text(stackedGroupValueLabel(group))
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .subtleTextShadow()
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.tertiarySystemFill))

                            HStack(spacing: 0) {
                                ForEach(group.rows) { row in
                                    Rectangle()
                                        .fill(horizontalGradient(for: row))
                                        .frame(
                                            width: proxy.size.width
                                                * max(animatedValue(for: row), 0)
                                                / maximum
                                        )
                                        .opacity(opacity(for: row))
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            toggleSelection(row.id)
                                        }
                                        .overlay {
                                            if showsStackedSegmentValue(
                                                row,
                                                availableWidth: proxy.size.width,
                                                maximum: maximum
                                            ) {
                                                Text(indicator.formattedNumber(row.value))
                                                    .font(.caption2.monospacedDigit().weight(.bold))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.72)
                                                    .padding(.horizontal, 4)
                                                    .subtleTextShadow()
                                                    .allowsHitTesting(false)
                                            }
                                        }
                                        .accessibilityLabel(stackedSegmentAccessibilityLabel(row))
                                        .accessibilityAddTraits(.isButton)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                            if let selectedRow = group.rows.first(where: rowMatchesSelection),
                               shouldShowValueLabel(for: selectedRow) {
                                valueLabel(for: selectedRow)
                                    .position(
                                        x: stackedSelectedLabelX(
                                            selectedRow,
                                            in: group,
                                            availableWidth: proxy.size.width,
                                            maximum: maximum
                                        ),
                                        y: proxy.size.height / 2
                                    )
                                    .zIndex(1)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    .frame(height: 32)
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private func stackedGroupValueLabel(_ group: IndicatorRowGroup) -> String {
        if let totalLabel = group.totalLabel {
            return totalLabel
        }

        guard valueLabelsEnabledWhenIdle() else {
            return indicator.formattedNumber(group.totalValue)
        }

        return group.rows
            .map { indicator.formattedNumber($0.value) }
            .joined(separator: " / ")
    }

    private func stackedSegmentAccessibilityLabel(_ row: IndicatorRow) -> String {
        let series = row.series.map { ", \($0)" } ?? ""
        return "\(row.label)\(series): \(indicator.formattedNumber(row.value))"
    }

    private func showsStackedSegmentValue(
        _ row: IndicatorRow,
        availableWidth: CGFloat,
        maximum: Double
    ) -> Bool {
        guard !rowMatchesSelection(row),
              shouldShowValueLabel(for: row),
              maximum > 0 else {
            return false
        }

        if indicator.showValueLabels == true {
            return true
        }

        let segmentWidth = availableWidth * max(row.value, 0) / maximum
        let characterCount = indicator.formattedNumber(row.value).count
        let estimatedLabelWidth = CGFloat(characterCount) * 6.5 + 10
        return segmentWidth >= estimatedLabelWidth
    }

    private func stackedSelectedLabelX(
        _ row: IndicatorRow,
        in group: IndicatorRowGroup,
        availableWidth: CGFloat,
        maximum: Double
    ) -> CGFloat {
        let precedingValue = group.rows
            .prefix { $0.id != row.id }
            .reduce(0) { $0 + max($1.value, 0) }
        let midpoint = precedingValue + max(row.value, 0) / 2
        let naturalX = availableWidth * midpoint / max(maximum, 1)
        let labelWidth = CGFloat(indicator.formattedNumber(row.value).count) * 11 + 30
        let halfLabelWidth = min(max(labelWidth / 2, 30), availableWidth / 2)

        return min(max(naturalX, halfLabelWidth), availableWidth - halfLabelWidth)
    }

    private var verticalBars: some View {
        GeometryReader { geometry in
            Chart(indicator.orderedRows) { row in
                BarMark(
                    x: .value("Группа", row.label),
                    y: .value("Значение", animatedValue(for: row)),
                    width: barMarkDimension
                )
                .position(by: .value("Серия", verticalBarPosition(for: row)), axis: .horizontal)
                .foregroundStyle(verticalGradient(for: row))
                .alignsMarkStylesWithPlotArea(false)
                .opacity(opacity(for: row))
                .cornerRadius(3)
                .annotation(
                    position: .top,
                    alignment: .center,
                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                ) {
                    if shouldShowValueLabel(for: row) {
                        valueLabel(for: row)
                    }
                }
            }
            .chartForegroundStyleScale(domain: indicator.chartColorDomain, range: chartColors)
            .chartYAxis {
                humanReadableValueAxis(position: .leading)
            }
            .chartXAxis {
                responsiveCategoryAxis(availableWidth: geometry.size.width)
            }
            .chartOverlay { proxy in
                chartTapOverlay(
                    proxy: proxy,
                    mode: indicator.barLayout == .stacked ? .stackedBar : .verticalBar
                )
            }
        }
    }

    private var horizontalBars: some View {
        Chart(indicator.orderedRows) { row in
            BarMark(
                x: .value("Значение", animatedValue(for: row)),
                y: .value("Группа", row.label),
                height: barMarkDimension
            )
            .position(by: .value("Серия", horizontalBarPosition(for: row)), axis: .vertical)
            .foregroundStyle(horizontalGradient(for: row))
            .alignsMarkStylesWithPlotArea(false)
            .opacity(opacity(for: row))
            .cornerRadius(3)
            .annotation(
                position: .trailing,
                alignment: .center,
                spacing: 5,
                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
            ) {
                if shouldShowValueLabel(for: row) {
                    valueLabel(for: row)
                }
            }
        }
        .chartForegroundStyleScale(domain: indicator.chartColorDomain, range: chartColors)
        .chartXAxis {
            humanReadableValueAxis(position: .bottom)
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .foregroundStyle(Color.secondary)
                    .font(.caption2)
            }
        }
        .chartOverlay { proxy in
            chartTapOverlay(proxy: proxy, mode: .horizontalBar)
        }
    }

    private var stackedBars: some View {
        GeometryReader { geometry in
            Chart(indicator.orderedRows) { row in
                BarMark(
                    x: .value("Группа", row.label),
                    y: .value("Значение", animatedValue(for: row)),
                    width: barMarkDimension
                )
                .foregroundStyle(verticalGradient(for: row))
                .alignsMarkStylesWithPlotArea(false)
                .opacity(opacity(for: row))
                .cornerRadius(3)
                .annotation(position: .overlay, alignment: .center) {
                    if shouldShowValueLabel(for: row) {
                        valueLabel(for: row, usesContrastingForeground: true)
                    }
                }

                if isLastRowInGroup(row), let group = rowGroup(for: row) {
                    PointMark(
                        x: .value("Группа", group.label),
                        y: .value("Итого", group.totalValue)
                    )
                    .symbolSize(0)
                    .annotation(position: .top, alignment: .center, spacing: 5) {
                        groupTotalLabel(group)
                    }
                }
            }
            .chartForegroundStyleScale(domain: indicator.chartColorDomain, range: chartColors)
            .chartYAxis {
                humanReadableValueAxis(position: .leading)
            }
            .chartXAxis {
                responsiveCategoryAxis(availableWidth: geometry.size.width)
            }
            .chartOverlay { proxy in
                chartTapOverlay(proxy: proxy, mode: .stackedBar)
            }
        }
    }

    private func donut(showsPercentages: Bool) -> some View {
        GeometryReader { geometry in
            let labelInset = donutExternalLabelInset(in: geometry.size)
            let plotSize = CGSize(
                width: max(geometry.size.width - labelInset * 2, 1),
                height: geometry.size.height
            )

            ZStack {
                Chart(indicator.orderedRows) { row in
                    SectorMark(
                        angle: .value("Доля", animatedValue(for: row)),
                        innerRadius: .ratio(0.62),
                        outerRadius: rowMatchesSelection(row) ? .ratio(1.0) : .ratio(0.92),
                        angularInset: donutAngularInset
                    )
                    .cornerRadius(3)
                    .foregroundStyle(sectorGradient(for: row))
                    .alignsMarkStylesWithPlotArea(false)
                    .opacity(opacity(for: row))
                    .annotation(position: .overlay, alignment: .center) {
                        if shouldShowValueLabel(for: row),
                           !shouldPlaceDonutLabelOutside(row, plotSize: plotSize) {
                            if showsPercentages {
                                percentLabel(for: row)
                            } else {
                                valueLabel(for: row, usesContrastingForeground: true)
                            }
                        }
                    }
                }
                .chartForegroundStyleScale(domain: indicator.chartColorDomain, range: chartColors)
                .chartOverlay { proxy in
                    donutTapOverlay(proxy: proxy)
                }
                .padding(.horizontal, labelInset)

                donutExternalLabels(
                    showsPercentages: showsPercentages,
                    size: geometry.size,
                    labelInset: labelInset
                )
            }
        }
    }

    private func trendLine(smooth: Bool) -> some View {
        GeometryReader { geometry in
            Chart(indicator.orderedRows) { row in
                if showsLineAreaFill {
                    AreaMark(
                        x: .value("Группа", row.label),
                        yStart: .value("Основание", 0),
                        yEnd: .value("Значение", animatedValue(for: row)),
                        series: .value("Серия", row.series ?? indicator.title)
                    )
                    .interpolationMethod(smooth ? .catmullRom : .monotone)
                    .foregroundStyle(areaGradient(for: row))
                    .alignsMarkStylesWithPlotArea(false)
                    .opacity(opacity(for: row))
                }

                LineMark(
                    x: .value("Группа", row.label),
                    y: .value("Значение", animatedValue(for: row)),
                    series: .value("Серия", row.series ?? indicator.title)
                )
                .interpolationMethod(smooth ? .catmullRom : .monotone)
                .lineStyle(strokeStyle(for: row))
                .foregroundStyle(chartColor(for: row))
                .opacity(opacity(for: row))

                PointMark(
                    x: .value("Группа", row.label),
                    y: .value("Значение", animatedValue(for: row))
                )
                .foregroundStyle(chartColor(for: row))
                .symbolSize(rowMatchesSelection(row) ? 62 : 24)
                .opacity(opacity(for: row))
                .annotation(position: .top, alignment: .center) {
                    if shouldShowValueLabel(
                        for: row,
                        defaultWhenIdle: indicator.prefersTrendPresentation
                    ) {
                        valueLabel(for: row)
                    }
                }
            }
            .chartForegroundStyleScale(domain: indicator.chartColorDomain, range: chartColors)
            .chartYAxis {
                valueAxis
            }
            .chartXAxis {
                responsiveCategoryAxis(availableWidth: geometry.size.width)
            }
            .chartOverlay { proxy in
                chartTapOverlay(proxy: proxy, mode: .point)
            }
        }
    }

    private func trendArea(smooth: Bool) -> some View {
        GeometryReader { geometry in
            Chart(indicator.orderedRows) { row in
                AreaMark(
                    x: .value("Группа", row.label),
                    yStart: .value("Основание", 0),
                    yEnd: .value("Значение", animatedValue(for: row)),
                    series: .value("Серия", row.series ?? indicator.title)
                )
                .interpolationMethod(smooth ? .catmullRom : .monotone)
                .foregroundStyle(areaGradient(for: row))
                .alignsMarkStylesWithPlotArea(false)
                .opacity(opacity(for: row))

                LineMark(
                    x: .value("Группа", row.label),
                    y: .value("Значение", animatedValue(for: row)),
                    series: .value("Серия", row.series ?? indicator.title)
                )
                .interpolationMethod(smooth ? .catmullRom : .monotone)
                .lineStyle(strokeStyle(for: row))
                .foregroundStyle(chartColor(for: row))
                .opacity(opacity(for: row))

                PointMark(
                    x: .value("Группа", row.label),
                    y: .value("Значение", animatedValue(for: row))
                )
                .foregroundStyle(chartColor(for: row))
                .symbolSize(rowMatchesSelection(row) ? 58 : 20)
                .opacity(opacity(for: row))
                .annotation(position: .top, alignment: .center) {
                    if shouldShowValueLabel(for: row, defaultWhenIdle: false) {
                        valueLabel(for: row)
                    }
                }
            }
            .chartForegroundStyleScale(domain: indicator.chartColorDomain, range: chartColors)
            .chartYAxis {
                valueAxis
            }
            .chartXAxis {
                responsiveCategoryAxis(availableWidth: geometry.size.width)
            }
            .chartOverlay { proxy in
                chartTapOverlay(proxy: proxy, mode: .point)
            }
        }
    }

    private var forecastLine: some View {
        GeometryReader { geometry in
            Chart {
                ForEach(indicator.orderedRows) { row in
                    LineMark(
                        x: .value("Группа", row.label),
                        y: .value("Значение", animatedValue(for: row)),
                        series: .value("Серия", row.series ?? indicator.title)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(strokeStyle(for: row, isForecast: isForecast(row)))
                    .foregroundStyle(chartColor(for: row))
                    .opacity(opacity(for: row))

                    PointMark(
                        x: .value("Группа", row.label),
                        y: .value("Значение", animatedValue(for: row))
                    )
                    .foregroundStyle(chartColor(for: row))
                    .symbolSize(rowMatchesSelection(row) ? 62 : 24)
                    .opacity(opacity(for: row))
                    .annotation(position: .top, alignment: .center) {
                        if shouldShowValueLabel(for: row, defaultWhenIdle: false) {
                            valueLabel(for: row)
                        }
                    }
                }

                if let forecastStartLabel {
                    RuleMark(x: .value("Начало прогноза", forecastStartLabel))
                        .foregroundStyle(Color.secondary.opacity(0.42))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Прогноз")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .chartForegroundStyleScale(domain: indicator.chartColorDomain, range: chartColors)
            .chartYAxis {
                valueAxis
            }
            .chartXAxis {
                responsiveCategoryAxis(availableWidth: geometry.size.width)
            }
            .chartOverlay { proxy in
                chartTapOverlay(proxy: proxy, mode: .point)
            }
        }
    }

    private var valueAxis: some AxisContent {
        humanReadableValueAxis(position: .leading)
    }

    private func humanReadableValueAxis(position: AxisMarkPosition) -> some AxisContent {
        AxisMarks(position: position) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                .foregroundStyle(Color.secondary.opacity(0.16))
            AxisTick(stroke: StrokeStyle(lineWidth: 0.6))
                .foregroundStyle(Color.secondary.opacity(0.26))
            AxisValueLabel {
                if let number = value.as(Double.self) {
                    Text(formattedAxisValue(number))
                }
            }
            .foregroundStyle(Color.secondary)
            .font(.caption2)
        }
    }

    private func formattedAxisValue(_ value: Double) -> String {
        let absoluteValue = abs(value)
        if absoluteValue >= 1_000_000 {
            return "\((value / 1_000_000).formatted(.number.precision(.fractionLength(0...1)))) млн"
        }
        if absoluteValue >= 1_000 {
            return "\((value / 1_000).formatted(.number.precision(.fractionLength(0...1)))) тыс."
        }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private var interactiveLegend: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: legendColumnMinimumWidth), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(legendRows.prefix(8)) { row in
                Button {
                    toggleLegendSelection(row)
                } label: {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: indicator.usesStackedCompositionPresentation ? 2 : 4)
                            .fill(chartColor(for: row).opacity(rowMatchesSelection(row) ? 1 : 0.72))
                            .frame(
                                width: indicator.usesStackedCompositionPresentation ? 10 : 7,
                                height: indicator.usesStackedCompositionPresentation ? 10 : 7
                            )

                        Text(legendTitle(for: row))
                            .font(.caption2.weight(.semibold))
                            .lineLimit(indicator.usesDenseEnrollmentCompositionPresentation ? 2 : 1)
                            .minimumScaleFactor(0.78)

                        Spacer(minLength: 0)

                        if let legendValue = legendValue(for: row) {
                            Text(legendValue)
                                .font(.caption2.monospacedDigit().weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .frame(minHeight: indicator.usesDenseEnrollmentCompositionPresentation ? 38 : 28)
                    .background {
                        legendBackground(for: row)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(rowMatchesSelection(row) ? chartColor(for: row).opacity(0.22) : .clear, lineWidth: 1)
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
            }
        }
    }

    private var legendRows: [IndicatorRow] {
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

    private func legendTitle(for row: IndicatorRow) -> String {
        if usesSeriesLegend {
            return row.series ?? indicator.title
        }

        return row.label
    }

    private var legendColumnMinimumWidth: CGFloat {
        if indicator.usesDenseEnrollmentCompositionPresentation {
            return 140
        }

        if indicator.usesStackedCompositionPresentation {
            return 92
        }

        return switch indicator.chartType {
        case .donut, .percentDonut:
            142
        default:
            96
        }
    }

    private func legendValue(for row: IndicatorRow) -> String? {
        switch indicator.chartType {
        case .donut:
            return indicator.formattedNumber(row.value)
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

    private var usesSeriesLegend: Bool {
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

    private var displaysLegend: Bool {
        if let showLegend = indicator.showLegend {
            return showLegend
        }

        if indicator.hasOnlyZeroValues
            || indicator.usesMixedUnitPersonnelPresentation
            || indicator.usesRankedCategoryPresentation {
            return false
        }

        if indicator.usesDenseEnrollmentCompositionPresentation {
            return true
        }

        if indicator.usesStackedCompositionPresentation {
            return indicator.showLegend ?? true
        }

        return switch indicator.chartType {
        case .donut, .percentDonut:
            true
        default:
            showsLegend
                || (indicator.prefersHorizontalGroupedBars
                    && !indicator.barDataShape.series.isEmpty)
        }
    }

    private var selectedRow: IndicatorRow? {
        guard let selectedRowID else {
            return nil
        }

        return indicator.rows.first { $0.id == selectedRowID }
    }

    @ViewBuilder
    private func legendBackground(for row: IndicatorRow) -> some View {
        if indicator.usesStackedCompositionPresentation, !rowMatchesSelection(row) {
            Color.clear
        } else {
            ZStack {
                opaqueLabelBackground

                if rowMatchesSelection(row) {
                    chartColor(for: row).opacity(0.12)
                }
            }
        }
    }

    private var selectedRowID: IndicatorRow.ID? {
        externalSelection?.wrappedValue ?? internalSelectedRowID
    }

    private var chartColors: [Color] {
        ChartPalette.colors(for: chartPaletteScheme)
    }

    private func chartColor(for row: IndicatorRow) -> Color {
        indicator.chartColor(for: row, scheme: chartPaletteScheme)
    }

    private func verticalGradient(for row: IndicatorRow) -> LinearGradient {
        let color = chartColor(for: row)
        return LinearGradient(
            colors: [vividColor(color, brightness: 1.10), color, vividColor(color, brightness: 0.70)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func horizontalGradient(for row: IndicatorRow) -> LinearGradient {
        let color = chartColor(for: row)
        return LinearGradient(
            colors: [vividColor(color, brightness: 1.08), color, vividColor(color, brightness: 0.72)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func sectorGradient(for row: IndicatorRow) -> LinearGradient {
        let color = chartColor(for: row)
        return LinearGradient(
            colors: [vividColor(color, brightness: 1.10), color, vividColor(color, brightness: 0.76)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func areaGradient(for row: IndicatorRow) -> LinearGradient {
        let color = chartColor(for: row)
        return LinearGradient(
            colors: [vividColor(color, brightness: 1.06).opacity(0.54), color.opacity(0.04)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func vividColor(_ color: Color, brightness factor: CGFloat) -> Color {
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

    private func selectedRowTitle(for row: IndicatorRow) -> String {
        let value = indicator.formattedNumber(row.value)
        if let series = row.series {
            return "\(row.label), \(series): \(value)"
        }

        return "\(row.label): \(value)"
    }

    private var selectedTitleBackground: Color {
        opaqueLabelBackground
    }

    private var opaqueLabelBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.11, blue: 0.12)
            : .white
    }

    private func animatedValue(for row: IndicatorRow) -> Double {
        !animatesOnAppear || hasAppeared ? row.value : 0
    }

    private func opacity(for row: IndicatorRow) -> Double {
        guard selectedRowID != nil else {
            return 1
        }

        return rowMatchesSelection(row) ? 1 : 0.28
    }

    private func valueLabel(
        for row: IndicatorRow,
        usesContrastingForeground: Bool = false
    ) -> some View {
        ChartValueLabel(
            value: row.value,
            isSelected: rowMatchesSelection(row),
            selectionColor: chartColor(for: row),
            usesContrastingForeground: usesContrastingForeground,
            useCompactNumbers: indicator.useCompactNumbers
        )
    }

    private func shouldShowValueLabel(
        for row: IndicatorRow,
        defaultWhenIdle: Bool = true
    ) -> Bool {
        ChartValueLabelPolicy.isVisible(
            rowMatchesSelection: rowMatchesSelection(row),
            hasSelection: selectedRowID != nil,
            contractPreference: indicator.showValueLabels,
            defaultLabelsEnabled: showsValueLabels && defaultWhenIdle
        )
    }

    private func valueLabelsEnabledWhenIdle(defaultWhenIdle: Bool = true) -> Bool {
        indicator.showValueLabels ?? (showsValueLabels && defaultWhenIdle)
    }

    private func rowGroup(for row: IndicatorRow) -> IndicatorRowGroup? {
        indicator.rowGroups.first { $0.label == row.label }
    }

    private func isLastRowInGroup(_ row: IndicatorRow) -> Bool {
        rowGroup(for: row)?.rows.last?.id == row.id
    }

    private func groupTotalLabel(_ group: IndicatorRowGroup) -> some View {
        Text(group.totalLabel ?? indicator.formattedNumber(group.totalValue))
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .subtleTextShadow()
    }

    private func percentLabel(for row: IndicatorRow) -> some View {
        let total = indicator.orderedRows.reduce(0) { $0 + max($1.value, 0) }
        let share = total > 0 ? row.value / total : 0

        return Text(share.formatted(.percent.precision(.fractionLength(0))))
            .font(.title3.monospacedDigit().weight(.bold))
            .foregroundStyle(colorScheme == .dark ? Color.white : chartColor(for: row))
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

    private func donutExternalLabels(
        showsPercentages: Bool,
        size: CGSize,
        labelInset: CGFloat
    ) -> some View {
        let positions = donutExternalLabelPositions(in: size, labelInset: labelInset)

        return ZStack {
            ForEach(positions) { position in
                Path { path in
                    path.move(to: position.anchor)
                    path.addLine(to: position.elbow)
                    path.addLine(to: position.lineEnd)
                }
                .stroke(
                    chartColor(for: position.row).opacity(0.72),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                )

                Text(donutLabelText(for: position.row, showsPercentages: showsPercentages))
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(colorScheme == .dark ? Color.white : chartColor(for: position.row))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(opaqueLabelBackground, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                chartColor(for: position.row).opacity(colorScheme == .dark ? 0.46 : 0.28),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.09), radius: 4, y: 2)
                    .position(position.labelCenter)
            }
        }
        .allowsHitTesting(false)
    }

    private func donutExternalLabelInset(in size: CGSize) -> CGFloat {
        let candidateInset = min(max(size.width * 0.12, 42), 56)
        let plotSize = CGSize(
            width: max(size.width - candidateInset * 2, 1),
            height: size.height
        )

        let needsExternalLabels = indicator.orderedRows.contains { row in
            shouldShowValueLabel(for: row)
                && shouldPlaceDonutLabelOutside(row, plotSize: plotSize)
        }

        return needsExternalLabels ? candidateInset : 0
    }

    private func shouldPlaceDonutLabelOutside(
        _ row: IndicatorRow,
        plotSize: CGSize
    ) -> Bool {
        let total = indicator.orderedRows.reduce(0) { $0 + max($1.value, 0) }
        guard total > 0 else {
            return false
        }

        let share = max(row.value, 0) / total
        let radius = min(plotSize.width, plotSize.height) * 0.36
        return DonutLabelPlacementPolicy.shouldPlaceOutside(
            share: share,
            labelCharacterCount: indicator.formattedNumber(row.value).count,
            radius: radius
        )
    }

    private func donutExternalLabelPositions(
        in size: CGSize,
        labelInset: CGFloat
    ) -> [DonutExternalLabelPosition] {
        guard labelInset > 0 else {
            return []
        }

        let rows = indicator.orderedRows
        let total = rows.reduce(0) { $0 + max($1.value, 0) }
        guard total > 0 else {
            return []
        }

        let plotSize = CGSize(width: max(size.width - labelInset * 2, 1), height: size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(plotSize.width, plotSize.height) * 0.46
        var cumulativeShare = 0.0
        var candidates: [DonutExternalLabelCandidate] = []

        for row in rows {
            let share = max(row.value, 0) / total
            let middleAngle = -.pi / 2 + (cumulativeShare + share / 2) * 2 * .pi
            cumulativeShare += share

            guard shouldShowValueLabel(for: row),
                  shouldPlaceDonutLabelOutside(row, plotSize: plotSize) else {
                continue
            }

            candidates.append(
                DonutExternalLabelCandidate(
                    row: row,
                    angle: middleAngle,
                    isRightSide: cos(middleAngle) >= 0,
                    preferredY: center.y + CGFloat(sin(middleAngle)) * (radius + 34)
                )
            )
        }

        var resolvedYByID: [IndicatorRow.ID: CGFloat] = [:]
        for isRightSide in [false, true] {
            let sideCandidates = candidates
                .filter { $0.isRightSide == isRightSide }
                .sorted { $0.preferredY < $1.preferredY }
            let resolved = DonutLabelPlacementPolicy.distributedVerticalPositions(
                sideCandidates.map(\.preferredY),
                bounds: 16...max(16, size.height - 16),
                minimumSpacing: 28
            )

            for (candidate, y) in zip(sideCandidates, resolved) {
                resolvedYByID[candidate.row.id] = y
            }
        }

        return candidates.compactMap { candidate in
            guard let labelY = resolvedYByID[candidate.row.id] else {
                return nil
            }

            let cosine = CGFloat(cos(candidate.angle))
            let sine = CGFloat(sin(candidate.angle))
            let anchor = CGPoint(
                x: center.x + cosine * radius,
                y: center.y + sine * radius
            )
            let elbow = CGPoint(
                x: center.x + cosine * (radius + 9),
                y: center.y + sine * (radius + 9)
            )
            let labelCenter = CGPoint(
                x: min(
                    max(center.x + cosine * (radius + 34), 42),
                    max(42, size.width - 42)
                ),
                y: labelY
            )
            let connectorX = labelCenter.x - elbow.x
            let connectorY = labelCenter.y - elbow.y
            let connectorLength = max(hypot(connectorX, connectorY), 1)
            let labelClearance = min(24, connectorLength * 0.55)
            let lineEnd = CGPoint(
                x: labelCenter.x - connectorX / connectorLength * labelClearance,
                y: labelCenter.y - connectorY / connectorLength * labelClearance
            )

            return DonutExternalLabelPosition(
                row: candidate.row,
                anchor: anchor,
                elbow: elbow,
                lineEnd: lineEnd,
                labelCenter: labelCenter
            )
        }
    }

    private func donutLabelText(for row: IndicatorRow, showsPercentages: Bool) -> String {
        guard showsPercentages else {
            return indicator.formattedNumber(row.value)
        }

        let total = indicator.orderedRows.reduce(0) { $0 + max($1.value, 0) }
        let share = total > 0 ? row.value / total : 0
        return share.formatted(.percent.precision(.fractionLength(0)))
    }

    private var donutAngularInset: Double {
        guard let valueSpacing = indicator.valueSpacing else {
            return 1.5
        }

        return min(max(valueSpacing / 16, 0), 4)
    }

    private var barMarkDimension: MarkDimension {
        if let valueSpacing = indicator.valueSpacing {
            return .ratio(max(0.18, 1 - valueSpacing / 80))
        }

        if indicator.barLayout == .compact {
            return .ratio(0.94)
        }

        return .automatic
    }

    private func verticalBarPosition(for row: IndicatorRow) -> String {
        indicator.barLayout == .stacked ? "Значение" : (row.series ?? "Значение")
    }

    private func strokeStyle(for row: IndicatorRow, isForecast: Bool = false) -> StrokeStyle {
        let style = row.lineStyle ?? indicator.lineStyle
        let usesDash = isForecast || style == .dashed
        return StrokeStyle(
            lineWidth: rowMatchesSelection(row) ? 3.5 : 2.5,
            lineCap: .round,
            lineJoin: .round,
            dash: usesDash ? [7, 5] : []
        )
    }

    private var forecastLabels: [String] {
        indicator.orderedRows.uniqueValues(\.label)
    }

    private var forecastStartIndex: Int? {
        guard !forecastLabels.isEmpty else {
            return nil
        }

        let defaultIndex = max(forecastLabels.count - max(1, forecastLabels.count / 4), 0)
        return min(indicator.forecastFromIndex ?? defaultIndex, forecastLabels.count - 1)
    }

    private var forecastStartLabel: String? {
        guard let forecastStartIndex else {
            return nil
        }

        return forecastLabels[forecastStartIndex]
    }

    private func isForecast(_ row: IndicatorRow) -> Bool {
        guard let forecastStartIndex,
              let rowIndex = forecastLabels.firstIndex(of: row.label) else {
            return false
        }

        return rowIndex >= forecastStartIndex
    }

    private func responsiveCategoryAxis(availableWidth: CGFloat) -> some AxisContent {
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

    private func wrappedAxisLabel(_ label: String) -> String {
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

    private func axisLineLengthDifference(words: [String], breakIndex: Int) -> Int {
        let firstLineLength = words[..<breakIndex].joined(separator: " ").count
        let secondLineLength = words[breakIndex...].joined(separator: " ").count
        return abs(firstLineLength - secondLineLength)
    }

    private func toggleSelection(_ rowID: IndicatorRow.ID) {
        selectedSeriesKey = nil
        selectedSeriesAnchorID = nil
        setSelection(selectedRowID == rowID ? nil : rowID)
    }

    private func toggleLegendSelection(_ row: IndicatorRow) {
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

    private func clearSelection() {
        selectedSeriesKey = nil
        selectedSeriesAnchorID = nil
        setSelection(nil)
    }

    private func rowMatchesSelection(_ row: IndicatorRow) -> Bool {
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

    private func selectionSeriesKey(for row: IndicatorRow) -> String {
        row.series ?? indicator.title
    }

    private func setSelection(_ rowID: IndicatorRow.ID?) {
        if let externalSelection {
            externalSelection.wrappedValue = rowID
        } else {
            internalSelectedRowID = rowID
        }
    }

    private func chartTapOverlay(proxy: ChartProxy, mode: ChartSelectionMode) -> some View {
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

    private func donutTapOverlay(proxy: ChartProxy) -> some View {
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

    private func selectedRowID(at location: CGPoint, proxy: ChartProxy, mode: ChartSelectionMode) -> IndicatorRow.ID? {
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
                let label = proxy.value(atX: location.x, as: String.self),
                let value = proxy.value(atY: location.y, as: Double.self)
            else {
                return nil
            }

            return indicator.orderedRows
                .filter { $0.label == label }
                .min { abs($0.value - value) < abs($1.value - value) }?
                .id
        }
    }

    private var verticalBarPositionDomain: [String] {
        indicator.orderedRows.uniqueValues { verticalBarPosition(for: $0) }
    }

    private var horizontalBarPositionDomain: [String] {
        indicator.orderedRows.uniqueValues { horizontalBarPosition(for: $0) }
    }

    private func horizontalBarPosition(for row: IndicatorRow) -> String {
        row.series ?? "Значение"
    }

    private func categoryBounds(
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

    private func valueIsInsideBar(_ value: Double, rowValue: Double) -> Bool {
        value >= min(0, rowValue) && value <= max(0, rowValue)
    }

    private func selectedDonutRowID(at location: CGPoint, in size: CGSize) -> IndicatorRow.ID? {
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

private enum ChartSelectionMode {
    case verticalBar
    case horizontalBar
    case stackedBar
    case point
}

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

    static func distributedVerticalPositions(
        _ preferredPositions: [CGFloat],
        bounds: ClosedRange<CGFloat>,
        minimumSpacing: CGFloat
    ) -> [CGFloat] {
        guard !preferredPositions.isEmpty else {
            return []
        }

        var positions = preferredPositions.map { min(max($0, bounds.lowerBound), bounds.upperBound) }
        for index in positions.indices.dropFirst() {
            positions[index] = max(positions[index], positions[index - 1] + minimumSpacing)
        }

        if let overflow = positions.last.map({ max($0 - bounds.upperBound, 0) }), overflow > 0 {
            for index in positions.indices {
                positions[index] -= overflow
            }
        }

        if positions[0] < bounds.lowerBound {
            positions[0] = bounds.lowerBound
            for index in positions.indices.dropFirst() {
                positions[index] = max(positions[index], positions[index - 1] + minimumSpacing)
            }
        }

        return positions
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

private struct DonutExternalLabelCandidate {
    let row: IndicatorRow
    let angle: Double
    let isRightSide: Bool
    let preferredY: CGFloat
}

private struct DonutExternalLabelPosition: Identifiable {
    let row: IndicatorRow
    let anchor: CGPoint
    let elbow: CGPoint
    let lineEnd: CGPoint
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
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    var body: some View {
        if isSelected {
            Text(valueText)
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(selectedForeground)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selectedBackground, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(selectionColor.opacity(colorScheme == .dark ? 0.46 : 0.26), lineWidth: 1)
                }
                .subtleTextShadow()
                .transition(.identity)
        } else {
            Text(valueText)
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(usesContrastingForeground ? Color.white : Color.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
                .subtleTextShadow()
        }
    }

    private var valueText: String {
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
        colorScheme == .dark ? .white : selectionColor
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

private struct ChartChromeModifier: ViewModifier {
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
