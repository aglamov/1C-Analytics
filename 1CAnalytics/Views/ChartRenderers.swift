import Charts
import SwiftUI

extension AnalyticsChart {
    var verticalBars: some View {
        GeometryReader { geometry in
            let contentWidth = ChartPresentationPolicy.contentWidth(
                availableWidth: geometry.size.width
            )

            ValidChartGeometry(size: geometry.size) {
                Chart(indicator.orderedRows) { row in
                BarMark(
                    x: .value("Группа", row.label),
                    y: .value("Значение", animatedValue(for: row)),
                    width: barMarkDimension
                )
                .position(by: .value("Серия", verticalBarPosition(for: row)), axis: .horizontal)
                .foregroundStyle(verticalBarStyle(for: row))
                .alignsMarkStylesWithPlotArea(false)
                .opacity(opacity(for: row))
                .cornerRadius(3)
                .annotation(
                    position: .top,
                    alignment: .center,
                    overflowResolution: .init(
                        x: .fit(to: .chart),
                        y: .fit(to: .chart)
                    )
                ) {
                    if shouldShowValueLabel(for: row) {
                        valueLabel(for: row)
                    }
                }
            }
            .chartForegroundStyleScale(domain: indicator.chartColorDomain, range: chartColors)
            .chartYScale(domain: verticalBarValueLabelDomain)
            .chartYAxis {
                humanReadableValueAxis(
                    position: .leading,
                    font: histogramYAxisFont
                )
            }
            .chartXAxis {
                if indicator.showsXAxisLabels {
                    responsiveCategoryAxis(availableWidth: contentWidth)
                }
            }
            .chartOverlay { proxy in
                chartTapOverlay(
                    proxy: proxy,
                    mode: indicator.barLayout == .stacked ? .stackedBar : .verticalBar
                )
            }
                .frame(width: contentWidth, height: geometry.size.height)
            }
        }
    }

    var horizontalBars: some View {
        let domain = HorizontalBarTrackScale.domain(for: indicator.orderedRows.map(\.value))

        return VStack(alignment: .leading, spacing: 18 * dashboardContentScale) {
            ForEach(indicator.rowGroups) { group in
                horizontalBarGroup(group, domain: domain)
            }
        }
        .padding(.vertical, 4 * dashboardContentScale)
    }

    private func horizontalBarGroup(
        _ group: IndicatorRowGroup,
        domain: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10 * dashboardContentScale) {
            if group.rows.count > 1 {
                HStack(alignment: .firstTextBaseline, spacing: 10 * dashboardContentScale) {
                    Text(group.label)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                    Spacer(minLength: 8 * dashboardContentScale)

                    if HorizontalBarLabelPolicy.showsGroupTotal(
                        rowCount: group.rows.count,
                        showsAggregateValue: indicator.showsAggregateValue
                    ) {
                        Text(group.totalLabel ?? indicator.formattedNumber(group.totalValue))
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10 * dashboardContentScale) {
                ForEach(group.rows) { row in
                    horizontalBarRow(row, group: group, domain: domain)
                }
            }
        }
    }

    private func horizontalBarRow(
        _ row: IndicatorRow,
        group: IndicatorRowGroup,
        domain: ClosedRange<Double>
    ) -> some View {
        let title = group.rows.count > 1 ? (row.series ?? "Значение") : group.label
        let color = chartColor(for: row)
        let isSelected = rowMatchesSelection(row)

        return Button {
            toggleSelection(row.id)
        } label: {
            VStack(alignment: .leading, spacing: 6 * dashboardContentScale) {
                HStack(alignment: .firstTextBaseline, spacing: 10 * dashboardContentScale) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                    Spacer(minLength: 8 * dashboardContentScale)

                    if HorizontalBarLabelPolicy.showsRowValue(
                        showRowValues: indicator.showRowValues,
                        showValueLabels: indicator.showValueLabels
                    ) {
                        Text(displayValue(for: row))
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(indicator.valueColor(for: row))
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                horizontalBarTrack(row, domain: domain)
            }
            .padding(.horizontal, 7 * dashboardContentScale)
            .padding(.vertical, 5 * dashboardContentScale)
            .background(color.opacity(isSelected ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(color.opacity(isSelected ? 0.24 : 0), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .opacity(opacity(for: row))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(displayValue(for: row))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func horizontalBarTrack(
        _ row: IndicatorRow,
        domain: ClosedRange<Double>
    ) -> some View {
        GeometryReader { geometry in
            let segment = HorizontalBarTrackScale.segment(
                for: animatedValue(for: row),
                in: domain
            )
            let width = geometry.size.width * segment.lengthFraction

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5 * dashboardContentScale)
                    .fill(Color.secondary.opacity(colorScheme == .dark ? 0.16 : 0.10))

                RoundedRectangle(cornerRadius: 5 * dashboardContentScale)
                    .fill(horizontalGradient(for: row))
                    .frame(width: segment.lengthFraction > 0 ? max(width, 1) : 0)
                    .offset(x: geometry.size.width * segment.startFraction)
            }
        }
        .frame(height: 10 * dashboardContentScale)
    }

    var stackedBars: some View {
        GeometryReader { geometry in
            let contentWidth = ChartPresentationPolicy.contentWidth(
                availableWidth: geometry.size.width
            )

            ValidChartGeometry(size: geometry.size) {
                Chart(indicator.orderedRows) { row in
                    BarMark(
                        x: .value("Группа", row.label),
                        y: .value("Значение", animatedValue(for: row)),
                        width: barMarkDimension
                    )
                    .foregroundStyle(verticalBarStyle(for: row))
                    .alignsMarkStylesWithPlotArea(false)
                    .opacity(opacity(for: row))
                    .cornerRadius(3)
                    .annotation(position: .overlay, alignment: .center) {
                        if shouldShowStackedValueLabel(for: row) {
                            valueLabel(for: row, usesContrastingForeground: true)
                        }
                    }

                    if indicator.showsAggregateValue,
                       isLastRowInGroup(row),
                       let group = rowGroup(for: row) {
                        PointMark(
                            x: .value("Группа", group.label),
                            y: .value("Итого", group.totalValue)
                        )
                        .symbolSize(0)
                        .annotation(
                            position: .top,
                            alignment: .center,
                            spacing: 5,
                            overflowResolution: .init(
                                x: .fit(to: .chart),
                                y: .fit(to: .chart)
                            )
                        ) {
                            groupTotalLabel(group)
                        }
                    }
                }
                .chartForegroundStyleScale(domain: indicator.chartColorDomain, range: chartColors)
                .chartYScale(domain: stackedBarValueLabelDomain)
                .chartYAxis {
                    humanReadableValueAxis(position: .leading, font: histogramYAxisFont)
                }
                .chartXAxis {
                    if indicator.showsXAxisLabels {
                        responsiveCategoryAxis(availableWidth: contentWidth)
                    }
                }
                .chartOverlay { proxy in chartTapOverlay(proxy: proxy, mode: .stackedBar) }
                .frame(width: contentWidth, height: geometry.size.height)
            }
        }
    }

    func donut(showsPercentages: Bool) -> some View {
        GeometryReader { geometry in
            let plotSize = DonutPlotLayoutPolicy.plotSize(in: geometry.size)

            ValidChartGeometry(size: geometry.size) {
                ZStack {
                Chart(indicator.orderedRows) { row in
                    SectorMark(
                        angle: .value("Доля", animatedValue(for: row)),
                        innerRadius: .ratio(0.62),
                        outerRadius: rowMatchesSelection(row) ? .ratio(1.0) : .ratio(0.92),
                        angularInset: rowMatchesSelection(row) ? 0 : donutAngularInset
                    )
                    .cornerRadius(3)
                    .foregroundStyle(sectorGradient(for: row))
                    .alignsMarkStylesWithPlotArea(false)
                    .opacity(opacity(for: row))
                    .annotation(position: .overlay, alignment: .center) {
                        if shouldShowValueLabel(for: row),
                            !shouldPlaceDonutLabelOutside(row, plotSize: plotSize)
                        {
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

                donutExternalLabels(
                    showsPercentages: showsPercentages,
                    size: geometry.size
                )
                .zIndex(20)
                }
            }
        }
    }

    func trendLine(smooth: Bool) -> some View {
        GeometryReader { geometry in
            let contentWidth = trendContentWidth(availableWidth: geometry.size.width)

            ValidChartGeometry(size: geometry.size) {
                Chart {
                    ForEach(indicator.orderedRows) { row in
                        LineMark(
                            x: .value("Группа", trendXValue(for: row)),
                            y: .value("Значение", animatedValue(for: row)),
                            series: .value("Серия", row.series ?? indicator.title)
                        )
                        .interpolationMethod(smooth ? .catmullRom : .monotone)
                        .lineStyle(strokeStyle(for: row))
                        .foregroundStyle(chartColor(for: row))
                        .opacity(opacity(for: row))

                        PointMark(
                            x: .value("Группа", trendXValue(for: row)),
                            y: .value("Значение", animatedValue(for: row))
                        )
                        .foregroundStyle(chartColor(for: row))
                        .symbolSize((rowMatchesSelection(row) ? 62 : 24) * dashboardContentScale * dashboardContentScale)
                        .opacity(opacity(for: row))
                        .annotation(
                            position: trendAnnotationPosition(for: row),
                            alignment: trendAnnotationAlignment(for: row),
                            overflowResolution: .init(x: .disabled, y: .disabled)
                        ) {
                            if shouldShowValueLabel(for: row), selectedRowID != row.id { valueLabel(for: row) }
                        }
                    }
                    crossingHighlightMarks(smooth: smooth, forecastAware: false)
                }
                .chartForegroundStyleScale(domain: indicator.chartColorDomain, range: chartColors)
                .chartXScale(domain: trendXDomain, range: .plotDimension(startPadding: 0, endPadding: 5))
                .chartYScale(domain: trendValueLabelDomain(includesZero: false))
                .chartYAxis { valueAxis }
                .chartXAxis {
                    if indicator.showsXAxisLabels {
                        responsiveTrendAxis(availableWidth: contentWidth)
                    }
                }
                .chartOverlay { proxy in trendChartOverlay(proxy: proxy) }
                .frame(width: contentWidth, height: geometry.size.height)
            }
        }
    }

    func trendArea(smooth: Bool) -> some View {
        GeometryReader { geometry in
            let contentWidth = trendContentWidth(availableWidth: geometry.size.width)

            ValidChartGeometry(size: geometry.size) {
                Chart {
                    ForEach(indicator.orderedRows) { row in
                        AreaMark(
                            x: .value("Группа", trendXValue(for: row)),
                            yStart: .value("Основание", 0),
                            yEnd: .value("Значение", animatedValue(for: row)),
                            series: .value("Серия", row.series ?? indicator.title)
                        )
                        .interpolationMethod(smooth ? .catmullRom : .monotone)
                        .foregroundStyle(areaGradient(for: row))
                        .alignsMarkStylesWithPlotArea(false)
                        .opacity(opacity(for: row))

                        LineMark(
                            x: .value("Группа", trendXValue(for: row)),
                            y: .value("Значение", animatedValue(for: row)),
                            series: .value("Серия", row.series ?? indicator.title)
                        )
                        .interpolationMethod(smooth ? .catmullRom : .monotone)
                        .lineStyle(strokeStyle(for: row))
                        .foregroundStyle(chartColor(for: row))
                        .opacity(opacity(for: row))

                        PointMark(x: .value("Группа", trendXValue(for: row)), y: .value("Значение", animatedValue(for: row)))
                            .foregroundStyle(chartColor(for: row))
                            .symbolSize((rowMatchesSelection(row) ? 58 : 20) * dashboardContentScale * dashboardContentScale)
                            .opacity(opacity(for: row))
                            .annotation(
                                position: trendAnnotationPosition(for: row),
                                alignment: trendAnnotationAlignment(for: row),
                                overflowResolution: .init(x: .disabled, y: .disabled)
                            ) {
                                if shouldShowValueLabel(for: row), selectedRowID != row.id { valueLabel(for: row) }
                            }
                    }
                    crossingHighlightMarks(smooth: smooth, forecastAware: false)
                }
                .chartForegroundStyleScale(domain: indicator.chartColorDomain, range: chartColors)
                .chartXScale(domain: trendXDomain, range: .plotDimension(startPadding: 0, endPadding: 5))
                .chartYScale(domain: trendValueLabelDomain(includesZero: true))
                .chartYAxis { valueAxis }
                .chartXAxis {
                    if indicator.showsXAxisLabels {
                        responsiveTrendAxis(availableWidth: contentWidth)
                    }
                }
                .chartOverlay { proxy in trendChartOverlay(proxy: proxy) }
                .frame(width: contentWidth, height: geometry.size.height)
            }
        }
    }

    var forecastLine: some View {
        GeometryReader { geometry in
            let contentWidth = trendContentWidth(availableWidth: geometry.size.width)

            ValidChartGeometry(size: geometry.size) {
                Chart {
                ForEach(indicator.orderedRows) { row in
                    LineMark(
                        x: .value("Группа", trendXValue(for: row)),
                        y: .value("Значение", animatedValue(for: row)),
                        series: .value("Серия", row.series ?? indicator.title)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(strokeStyle(for: row, isForecast: isForecast(row)))
                    .foregroundStyle(chartColor(for: row))
                    .opacity(opacity(for: row))

                    PointMark(
                        x: .value("Группа", trendXValue(for: row)),
                        y: .value("Значение", animatedValue(for: row))
                    )
                    .foregroundStyle(chartColor(for: row))
                    .symbolSize(
                        (rowMatchesSelection(row) ? 62 : 24)
                            * dashboardContentScale * dashboardContentScale
                    )
                    .opacity(opacity(for: row))
                    .annotation(
                        position: trendAnnotationPosition(for: row),
                        alignment: trendAnnotationAlignment(for: row),
                        overflowResolution: .init(x: .disabled, y: .disabled)
                    ) {
                        if shouldShowValueLabel(for: row), selectedRowID != row.id {
                            valueLabel(for: row)
                        }
                    }
                }

                crossingHighlightMarks(smooth: false, forecastAware: true)

                if let forecastStartLabel {
                    RuleMark(x: .value("Начало прогноза", trendXValue(for: forecastStartLabel)))
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
            .chartXScale(
                domain: trendXDomain,
                range: .plotDimension(startPadding: 0, endPadding: 5)
            )
            .chartYScale(domain: trendValueLabelDomain(includesZero: false))
            .chartYAxis {
                valueAxis
            }
            .chartXAxis {
                if indicator.showsXAxisLabels {
                    responsiveTrendAxis(availableWidth: contentWidth)
                }
            }
            .chartOverlay { proxy in
                trendChartOverlay(proxy: proxy)
            }
                .frame(width: contentWidth, height: geometry.size.height)
            }
        }
    }

}
