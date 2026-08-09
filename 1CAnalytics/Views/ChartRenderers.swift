import Charts
import SwiftUI

extension AnalyticsChart {
    var verticalBars: some View {
        GeometryReader { geometry in
            let contentWidth = ChartPresentationPolicy.contentWidth(
                availableWidth: geometry.size.width,
                categoryCount: categoryLabels.count,
                seriesCount: max(indicator.barDataShape.series.count, 1),
                longestValueCharacterCount: longestDisplayValueCharacterCount,
                style: .groupedBar,
                allowsHorizontalOverflow: allowsHorizontalChartScrolling
            )

            ScrollView(.horizontal) {
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
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
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
                    responsiveCategoryAxis(availableWidth: contentWidth)
                }
                .chartOverlay { proxy in
                    chartTapOverlay(
                        proxy: proxy,
                        mode: indicator.barLayout == .stacked ? .stackedBar : .verticalBar
                    )
                }
                .frame(width: contentWidth, height: geometry.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .scrollDisabled(!allowsHorizontalChartScrolling)
        }
    }

    var horizontalBars: some View {
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
        .chartXScale(domain: horizontalBarValueLabelDomain)
        .chartXAxis {
            humanReadableValueAxis(position: .bottom)
        }
        .chartYAxis {
            readableHorizontalCategoryAxis
        }
        .chartOverlay { proxy in
            chartTapOverlay(proxy: proxy, mode: .horizontalBar)
        }
    }

    var stackedBars: some View {
        GeometryReader { geometry in
            let contentWidth = ChartPresentationPolicy.contentWidth(
                availableWidth: geometry.size.width,
                categoryCount: categoryLabels.count,
                seriesCount: 1,
                longestValueCharacterCount: longestDisplayValueCharacterCount,
                style: .stackedBar,
                allowsHorizontalOverflow: allowsHorizontalChartScrolling
            )

            ScrollView(.horizontal) {
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
                .chartYScale(domain: stackedBarValueLabelDomain)
                .chartYAxis {
                    humanReadableValueAxis(
                        position: .leading,
                        font: histogramYAxisFont
                    )
                }
                .chartXAxis {
                    responsiveCategoryAxis(availableWidth: contentWidth)
                }
                .chartOverlay { proxy in
                    chartTapOverlay(proxy: proxy, mode: .stackedBar)
                }
                .frame(width: contentWidth, height: geometry.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .scrollDisabled(!allowsHorizontalChartScrolling)
        }
    }

    func donut(showsPercentages: Bool) -> some View {
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
                        angularInset: rowMatchesSelection(row) ? 0 : donutAngularInset
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

                donutCenterSummary(showsPercentages: showsPercentages)

                donutExternalLabels(
                    showsPercentages: showsPercentages,
                    size: geometry.size,
                    labelInset: labelInset
                )
            }
        }
    }

    func trendLine(smooth: Bool) -> some View {
        GeometryReader { geometry in
            let contentWidth = trendContentWidth(availableWidth: geometry.size.width)

            ScrollView(.horizontal) {
                Chart(indicator.orderedRows) { row in
                    if showsLineAreaFill {
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
                    }

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
                    .symbolSize(rowMatchesSelection(row) ? 62 : 24)
                    .opacity(opacity(for: row))
                    .annotation(
                        position: trendAnnotationPosition(for: row),
                        alignment: trendAnnotationAlignment(for: row),
                        overflowResolution: .init(x: .disabled, y: .disabled)
                    ) {
                        if shouldShowValueLabel(for: row) {
                            valueLabel(for: row)
                        }
                    }
                }
                .chartForegroundStyleScale(domain: indicator.chartColorDomain, range: chartColors)
                .chartXScale(
                    domain: trendXDomain,
                    range: .plotDimension(startPadding: 0, endPadding: 5)
                )
                .chartYScale(domain: trendValueLabelDomain(includesZero: showsLineAreaFill))
                .chartYAxis {
                    valueAxis
                }
                .chartXAxis {
                    responsiveTrendAxis(availableWidth: contentWidth)
                }
                .chartOverlay { proxy in
                    trendChartOverlay(proxy: proxy)
                }
                .frame(width: contentWidth, height: geometry.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .scrollDisabled(!allowsHorizontalChartScrolling)
        }
    }

    func trendArea(smooth: Bool) -> some View {
        GeometryReader { geometry in
            let contentWidth = trendContentWidth(availableWidth: geometry.size.width)

            ScrollView(.horizontal) {
                Chart(indicator.orderedRows) { row in
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

                    PointMark(
                        x: .value("Группа", trendXValue(for: row)),
                        y: .value("Значение", animatedValue(for: row))
                    )
                    .foregroundStyle(chartColor(for: row))
                    .symbolSize(rowMatchesSelection(row) ? 58 : 20)
                    .opacity(opacity(for: row))
                    .annotation(
                        position: trendAnnotationPosition(for: row),
                        alignment: trendAnnotationAlignment(for: row),
                        overflowResolution: .init(x: .disabled, y: .disabled)
                    ) {
                        if shouldShowValueLabel(for: row) {
                            valueLabel(for: row)
                        }
                    }
                }
                .chartForegroundStyleScale(domain: indicator.chartColorDomain, range: chartColors)
                .chartXScale(
                    domain: trendXDomain,
                    range: .plotDimension(startPadding: 0, endPadding: 5)
                )
                .chartYScale(domain: trendValueLabelDomain(includesZero: true))
                .chartYAxis {
                    valueAxis
                }
                .chartXAxis {
                    responsiveTrendAxis(availableWidth: contentWidth)
                }
                .chartOverlay { proxy in
                    trendChartOverlay(proxy: proxy)
                }
                .frame(width: contentWidth, height: geometry.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .scrollDisabled(!allowsHorizontalChartScrolling)
        }
    }

    var forecastLine: some View {
        GeometryReader { geometry in
            let contentWidth = trendContentWidth(availableWidth: geometry.size.width)

            ScrollView(.horizontal) {
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
                        .symbolSize(rowMatchesSelection(row) ? 62 : 24)
                        .opacity(opacity(for: row))
                        .annotation(
                            position: trendAnnotationPosition(for: row),
                            alignment: trendAnnotationAlignment(for: row),
                            overflowResolution: .init(x: .disabled, y: .disabled)
                        ) {
                            if shouldShowValueLabel(for: row) {
                                valueLabel(for: row)
                            }
                        }
                    }

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
                    responsiveTrendAxis(availableWidth: contentWidth)
                }
                .chartOverlay { proxy in
                    trendChartOverlay(proxy: proxy)
                }
                .frame(width: contentWidth, height: geometry.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .scrollDisabled(!allowsHorizontalChartScrolling)
        }
    }

}
