import Charts
import SwiftUI
import UIKit

struct IndicatorDetailView: View {
    let indicator: Indicator
    @State private var selectedRowID: IndicatorRow.ID?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let usesSplitLayout = horizontalSizeClass == .regular && proxy.size.width > proxy.size.height
            let horizontalPadding: CGFloat = horizontalSizeClass == .regular ? 20 : 16
            let verticalPadding: CGFloat = 16

            if usesSplitLayout {
                splitDetailContent(availableSize: proxy.size)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
            } else {
                ScrollView(.vertical) {
                    compactDetailContent(availableSize: proxy.size)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, verticalPadding)
                }
                .scrollBounceBehavior(.always)
            }
        }
        .background(AppBackground())
        .navigationTitle(indicator.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            selectedRowID = nil
        }
    }

    private func splitDetailContent(availableSize: CGSize) -> some View {
        let headerHeight = splitHeaderHeight(for: availableSize)
        let lowerHeight = splitLowerSectionHeight(for: availableSize, headerHeight: headerHeight)

        return VStack(alignment: .leading, spacing: 16) {
            IndicatorHero(indicator: indicator)
                .frame(maxWidth: .infinity, minHeight: headerHeight, maxHeight: headerHeight, alignment: .leading)

            if indicator.usesContractPlanFactPresentation {
                OverflowAwareScrollView {
                    contractPlanFactSection
                }
                .frame(maxWidth: .infinity, minHeight: lowerHeight, maxHeight: lowerHeight, alignment: .topLeading)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    chartSection(fillsAvailableHeight: false)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: lowerHeight,
                            alignment: .top
                        )

                    OverflowAwareScrollView {
                        rowsSection
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, minHeight: lowerHeight, maxHeight: lowerHeight, alignment: .topLeading)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func compactDetailContent(availableSize: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            IndicatorHero(indicator: indicator)

            if indicator.usesContractPlanFactPresentation {
                contractPlanFactSection
            } else {
                chartSection(fillsAvailableHeight: false, aspectRatio: compactChartAspectRatio(for: availableSize))
                rowsSection
            }
        }
    }

    private var contractPlanFactSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ContractPlanFactCompletionChart(indicator: indicator)
                .padding(16)
                .premiumPanel()

            ContractPlanFactView(indicator: indicator)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(16)
                .premiumPanel()
        }
    }

    private func splitHeaderHeight(for availableSize: CGSize) -> CGFloat {
        min(156, max(132, availableSize.height * 0.13))
    }

    private func splitLowerSectionHeight(for availableSize: CGSize, headerHeight: CGFloat) -> CGFloat {
        let verticalPadding: CGFloat = 32
        let contentSpacing: CGFloat = 16
        let remainingHeight = availableSize.height - verticalPadding - headerHeight - contentSpacing

        return max(320, remainingHeight)
    }

    private func compactChartAspectRatio(for availableSize: CGSize) -> CGFloat {
        let availableWidth = max(availableSize.width - (horizontalSizeClass == .regular ? 72 : 64), 240)
        let desiredHeight = ChartHeightPolicy.detailHeight(
            for: indicator,
            availableWidth: availableWidth
        )
        return availableWidth / max(desiredHeight, 1)
    }

    @ViewBuilder
    private func chartSection(fillsAvailableHeight: Bool, aspectRatio: CGFloat = 1.0) -> some View {
        Group {
            if indicator.chartType == .geoMap {
                GeoMapIndicatorView(indicator: indicator)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if indicator.chartType == .oneValue {
                OneValueDashboardContent(indicator: indicator)
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            } else if indicator.chartType == .linearProgress {
                LinearProgressIndicatorView(indicator: indicator)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if indicator.chartType == .gauge {
                GaugeIndicatorView(indicator: indicator)
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                let chart = AnalyticsChart(
                    indicator: indicator,
                    usesCardBackground: false,
                    showsLegend: true,
                    selectedRowID: $selectedRowID
                )
                    .frame(maxWidth: .infinity)

                if fillsAvailableHeight {
                    chart
                        .frame(maxHeight: .infinity)
                } else {
                    chart
                        .aspectRatio(aspectRatio, contentMode: .fit)
                }
            }
        }
        .padding(16)
        .premiumPanel()
    }

    private var rowsSection: some View {
        let groups = detailGroups
        let hasMultipleParameters = DetailPresentationPolicy.hasMultipleParameters(in: groups)
        let maximumValue = groups
            .flatMap { group in
                group.rows.count > 1 ? group.rows.map(\.value) : [group.totalValue]
            }
            .max() ?? 0
        let aggregateTotal = DetailPresentationPolicy.aggregateTotal(for: groups)
        let seriesTotals = DetailPresentationPolicy.seriesTotals(for: groups)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Детализация")
                        .font(.title3.weight(.bold))

                    Text("В порядке значений на графике")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if indicator.showsAggregateValue, let aggregateTotal {
                    Text(totalText(for: aggregateTotal))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            LazyVStack(spacing: 0) {
                ForEach(groups) { group in
                    detailGroupRow(
                        group,
                        maximumValue: maximumValue,
                        aggregateTotal: aggregateTotal,
                        seriesTotals: seriesTotals,
                        hidesGroupTotal: hasMultipleParameters
                    )

                    if group.id != groups.last?.id {
                        Divider()
                            .padding(.leading, 2)
                    }
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(rowsBackgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.10), lineWidth: 1)
            }
        }
    }

    private var detailGroups: [IndicatorRowGroup] {
        let groups = indicator.rowGroups
        guard indicator.chartType == .geoMap else {
            return groups
        }

        return groups
            .enumerated()
            .sorted { left, right in
                if left.element.totalValue == right.element.totalValue {
                    return left.offset < right.offset
                }

                return left.element.totalValue > right.element.totalValue
            }
            .map(\.element)
    }

    private var rowsBackgroundColor: Color {
        colorScheme == .dark ? Color(.tertiarySystemGroupedBackground).opacity(0.44) : Color(.systemBackground).opacity(0.56)
    }

    private func detailGroupRow(
        _ group: IndicatorRowGroup,
        maximumValue: Double,
        aggregateTotal: Double?,
        seriesTotals: [String: Double],
        hidesGroupTotal: Bool
    ) -> some View {
        DetailGroupRowView(
            group: group,
            maxValue: maximumValue,
            aggregateTotal: aggregateTotal,
            seriesTotals: seriesTotals,
            hidesGroupTotal: hidesGroupTotal,
            indicator: indicator,
            selectedRowID: selectedRowID,
            animatesOnAppear: indicator.chartType != .geoMap,
            selectionEnabled: indicator.chartType != .geoMap,
            onSelect: selectRow
        )
    }

    private func totalText(for totalValue: Double) -> String {
        "Итого \(indicator.formattedNumber(totalValue))"
    }

    private func selectRow(_ rowID: IndicatorRow.ID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            selectedRowID = selectedRowID == rowID ? nil : rowID
        }
    }
}

struct ContractPlanFactCompletionChart: View {
    let indicator: Indicator
    @State private var selectedPointID: ContractPlanFactCompletionPoint.ID?
    @Environment(\.chartPaletteScheme) private var chartPaletteScheme

    private var periods: [ContractPlanFactPeriod] {
        [.current, .previous]
    }

    private var points: [ContractPlanFactCompletionPoint] {
        indicator.contractPlanFactCategories.flatMap { category in
            category.periods.compactMap { periodRows in
                guard let ratio = periodRows.completionRatio, ratio >= 0 else {
                    return nil
                }

                return ContractPlanFactCompletionPoint(
                    category: category.label,
                    period: periodRows.period,
                    ratio: ratio
                )
            }
        }
    }

    private var yDomain: ClosedRange<Double> {
        let largestRatio = points.map(\.ratio).max() ?? 1
        return 0...max(1.15, largestRatio * 1.18)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Выполнение плана")
                    .font(.title3.weight(.bold))

                Text("Оплачено относительно плана")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(points) { point in
                    BarMark(
                        x: .value("Категория", point.category),
                        y: .value("Выполнение", point.ratio)
                    )
                    .position(by: .value("Период", point.period.title))
                    .foregroundStyle(barGradient(for: point.period))
                    .alignsMarkStylesWithPlotArea(false)
                    .cornerRadius(5)
                    .opacity(selectedPointID == nil || selectedPointID == point.id ? 1 : 0.28)
                    .annotation(position: .top, spacing: 5) {
                        completionLabel(for: point)
                    }
                }

                RuleMark(y: .value("План", 1))
                    .foregroundStyle(.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .chartYScale(domain: yDomain)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                        .foregroundStyle(.secondary.opacity(0.16))
                    AxisTick()

                    AxisValueLabel {
                        if let ratio = value.as(Double.self) {
                            Text(ratio.formatted(.percent.precision(.fractionLength(0))))
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                chartTapOverlay(proxy: proxy)
            }
            .frame(height: 220)
            .accessibilityLabel("Выполнение плана по контрактам")

            HStack(spacing: 16) {
                ForEach(periods) { period in
                    HStack(spacing: 6) {
                        Capsule()
                            .fill(barGradient(for: period))
                            .frame(width: 18, height: 8)

                        Text(period.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selectedPointID)
        .onDisappear {
            selectedPointID = nil
        }
    }

    private func completionLabel(for point: ContractPlanFactCompletionPoint) -> some View {
        let isSelected = selectedPointID == point.id

        return Text(point.ratio.formatted(.percent.precision(.fractionLength(0))))
            .font(
                isSelected
                    ? .title3.monospacedDigit().weight(.bold)
                    : .caption2.monospacedDigit().weight(.bold)
            )
            .foregroundStyle(isSelected ? Color.primary : periodColor(for: point.period))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, isSelected ? 12 : 0)
            .padding(.vertical, isSelected ? 7 : 0)
            .background {
                if isSelected {
                    Color(.systemBackground)
                        .clipShape(Capsule())
                }
            }
            .overlay {
                if isSelected {
                    Capsule()
                        .strokeBorder(periodColor(for: point.period).opacity(0.32), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(isSelected ? 0.09 : 0), radius: 4, y: 2)
    }

    private func barGradient(for period: ContractPlanFactPeriod) -> LinearGradient {
        let color = periodColor(for: period)
        return LinearGradient(
            colors: [
                vividColor(color, brightness: 1.10),
                color,
                vividColor(color, brightness: 0.70)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func periodColor(for period: ContractPlanFactPeriod) -> Color {
        period.contractPlanFactColor(in: chartPaletteScheme)
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

    private func chartTapOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            guard let plotFrame = proxy.plotFrame else {
                                selectedPointID = nil
                                return
                            }

                            let frame = geometry[plotFrame]
                            let location = CGPoint(
                                x: value.location.x - frame.origin.x,
                                y: value.location.y - frame.origin.y
                            )

                            guard let point = selectedPoint(at: location, proxy: proxy) else {
                                selectedPointID = nil
                                return
                            }

                            selectedPointID = selectedPointID == point.id ? nil : point.id
                        }
                )
        }
    }

    private func selectedPoint(
        at location: CGPoint,
        proxy: ChartProxy
    ) -> ContractPlanFactCompletionPoint? {
        guard let category = proxy.value(atX: location.x, as: String.self),
              let tappedValue = proxy.value(atY: location.y, as: Double.self),
              let categoryIndex = categories.firstIndex(of: category),
              let categoryCenter = proxy.position(forX: category) else {
            return nil
        }

        let lowerBound: CGFloat
        if categoryIndex == categories.startIndex {
            lowerBound = 0
        } else if let previousCenter = proxy.position(forX: categories[categoryIndex - 1]) {
            lowerBound = (previousCenter + categoryCenter) / 2
        } else {
            lowerBound = 0
        }

        let upperBound: CGFloat
        if categoryIndex == categories.index(before: categories.endIndex) {
            upperBound = proxy.plotSize.width
        } else if let nextCenter = proxy.position(forX: categories[categoryIndex + 1]) {
            upperBound = (categoryCenter + nextCenter) / 2
        } else {
            upperBound = proxy.plotSize.width
        }

        guard upperBound > lowerBound else {
            return nil
        }

        let fraction = min(max((location.x - lowerBound) / (upperBound - lowerBound), 0), 0.999)
        let periodIndex = min(Int(fraction * CGFloat(periods.count)), periods.count - 1)
        let period = periods[periodIndex]

        guard let point = points.first(where: {
            $0.category == category && $0.period == period
        }),
        tappedValue >= 0,
        tappedValue <= point.ratio else {
            return nil
        }

        return point
    }

    private var categories: [String] {
        indicator.contractPlanFactCategories.map(\.label)
    }
}

private struct ContractPlanFactCompletionPoint: Identifiable {
    let category: String
    let period: ContractPlanFactPeriod
    let ratio: Double

    var id: String {
        "\(category)-\(period.rawValue)"
    }
}

private struct OverflowAwareScrollView<Content: View>: View {
    let content: Content
    @State private var viewportHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var contentBottom: CGFloat = 0

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var hasOverflow: Bool {
        contentHeight > viewportHeight + 1
    }

    private var showsMoreBelow: Bool {
        hasOverflow && contentBottom > viewportHeight + 8
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            content
                .padding(.bottom, hasOverflow ? 38 : 0)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: DetailContentHeightKey.self, value: proxy.size.height)
                            .preference(
                                key: DetailContentBottomKey.self,
                                value: proxy.frame(in: .named("detail-scroll")).maxY
                            )
                    }
                }
        }
        .coordinateSpace(name: "detail-scroll")
        .scrollBounceBehavior(.basedOnSize)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: DetailViewportHeightKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(DetailContentHeightKey.self) { contentHeight = $0 }
        .onPreferenceChange(DetailContentBottomKey.self) { contentBottom = $0 }
        .onPreferenceChange(DetailViewportHeightKey.self) { viewportHeight = $0 }
        .overlay(alignment: .bottom) {
            if showsMoreBelow {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, Color(.systemGroupedBackground).opacity(0.94)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 24)

                    Label("Прокрутите, чтобы увидеть ещё", systemImage: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 6)
                        .background(Color(.systemGroupedBackground).opacity(0.94))
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsMoreBelow)
    }
}

private struct DetailContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DetailViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DetailContentBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct DetailGroupRowView: View {
    let group: IndicatorRowGroup
    let maxValue: Double
    let aggregateTotal: Double?
    let seriesTotals: [String: Double]
    let hidesGroupTotal: Bool
    let indicator: Indicator
    let selectedRowID: IndicatorRow.ID?
    let animatesOnAppear: Bool
    let selectionEnabled: Bool
    let onSelect: (IndicatorRow.ID) -> Void
    @State private var hasAppeared = false
    @Environment(\.chartPaletteScheme) private var chartPaletteScheme

    var body: some View {
        VStack(alignment: .leading, spacing: group.rows.count > 1 ? 14 : 8) {
            if group.rows.count > 1 {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(group.label)
                        .font(.body.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                    Spacer(minLength: 6)

                    if !hidesGroupTotal {
                        Text(group.totalLabel ?? indicator.formattedNumber(group.totalValue))
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                ForEach(group.rows) { row in
                    groupedSeriesRow(row)
                }
            } else if let row = group.rows.first {
                singleValueRow(row)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(isSelected ? groupColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? groupColor.opacity(0.24) : .clear, lineWidth: 1)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isSelected)
        .onAppear {
            guard animatesOnAppear else {
                return
            }

            withAnimation(.easeOut(duration: 0.65)) {
                hasAppeared = true
            }
        }
    }

    private var isSelected: Bool {
        guard let selectedRowID else {
            return false
        }

        return group.rows.contains { $0.id == selectedRowID }
    }

    private var groupColor: Color {
        indicator.chartColor(forGroupLabel: group.label, scheme: chartPaletteScheme)
    }

    private func shareText(for value: Double, denominator: Double?) -> String {
        guard let denominator, denominator > 0 else {
            return "0%"
        }

        return (value / denominator).formatted(.percent.precision(.fractionLength(0)))
    }

    private func progress(for value: Double) -> Double {
        guard maxValue > 0, !animatesOnAppear || hasAppeared else {
            return 0
        }

        return value / maxValue
    }

    @ViewBuilder
    private func groupedSeriesRow(_ row: IndicatorRow) -> some View {
        if selectionEnabled {
            Button {
                onSelect(row.id)
            } label: {
                groupedSeriesRowContent(row)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Выбрать \(group.label) \(seriesTitle(for: row))")
        } else {
            groupedSeriesRowContent(row)
        }
    }

    @ViewBuilder
    private func singleValueRow(_ row: IndicatorRow) -> some View {
        if selectionEnabled {
            Button {
                onSelect(row.id)
            } label: {
                singleValueRowContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Выбрать \(group.label)")
        } else {
            singleValueRowContent
        }
    }

    private func groupedSeriesRowContent(_ row: IndicatorRow) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            valueHeader(
                title: seriesTitle(for: row),
                value: row.value,
                color: segmentColor(for: row),
                valueColor: indicator.valueColor(for: row),
                displayValue: row.valueLabel,
                shareDenominator: detailDenominator(for: row)
            )

            progressBar(value: row.value, color: segmentColor(for: row))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            selectedRowID == row.id ? segmentColor(for: row).opacity(0.08) : .clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var singleValueRowContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            valueHeader(
                title: group.label,
                value: group.totalValue,
                color: groupColor,
                valueColor: group.rows.first.map { indicator.valueColor(for: $0) } ?? .primary,
                displayValue: group.rows.first?.valueLabel ?? group.totalLabel,
                shareDenominator: aggregateTotal
            )
            progressBar(value: group.totalValue, color: groupColor)
        }
    }

    private func valueHeader(
        title: String,
        value: Double,
        color: Color,
        valueColor: Color,
        displayValue: String? = nil,
        shareDenominator: Double?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(alignment: .top, spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .padding(.top, 7)

                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(displayValue ?? indicator.formattedNumber(value))
                    .font(.body.monospacedDigit().weight(.bold))
                    .foregroundStyle(valueColor)
                    .contentTransition(.numericText())
                    .lineLimit(1)

                Text(shareText(for: value, denominator: shareDenominator))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func progressBar(value: Double, color: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemGroupedBackground))

                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * progress(for: value))
            }
        }
        .frame(height: 6)
    }

    private func detailDenominator(for row: IndicatorRow) -> Double? {
        guard let series = row.series else {
            return aggregateTotal
        }

        return seriesTotals[series]
    }

    private func seriesTitle(for row: IndicatorRow) -> String {
        guard let series = row.series else {
            return "Значение"
        }

        return DetailPresentationPolicy.seriesTitle(
            series,
            aggregateValue: seriesTotals[series]
        )
    }

    private func segmentColor(for row: IndicatorRow) -> Color {
        indicator.chartColor(for: row, scheme: chartPaletteScheme)
    }
}

enum DetailPresentationPolicy {
    static func hasMultipleParameters(in groups: [IndicatorRowGroup]) -> Bool {
        groups.contains { $0.rows.count > 1 }
    }

    static func aggregateTotal(for groups: [IndicatorRowGroup]) -> Double? {
        guard !hasMultipleParameters(in: groups) else {
            return nil
        }

        return groups.reduce(0) { $0 + $1.totalValue }
    }

    static func seriesTotals(for groups: [IndicatorRowGroup]) -> [String: Double] {
        groups
            .flatMap(\.rows)
            .reduce(into: [:]) { totals, row in
                guard let series = row.series else {
                    return
                }

                totals[series, default: 0] += row.value
            }
    }

    static func seriesTitle(_ title: String, aggregateValue: Double?) -> String {
        guard let aggregateValue,
              aggregateValue.isFinite,
              let separatorIndex = title.lastIndex(of: ":") else {
            return title
        }

        let prefix = title[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = title[title.index(after: separatorIndex)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let groupingCharacters: Set<Character> = [" ", " ", " ", ",", ".", "'", "_"]

        guard !prefix.isEmpty,
              !suffix.isEmpty,
              suffix.allSatisfy({ $0.isNumber || groupingCharacters.contains($0) }) else {
            return title
        }

        let digits = suffix.filter(\.isNumber)
        guard let displayedAggregate = Double(digits),
              abs(displayedAggregate - abs(aggregateValue)) < 0.5 else {
            return title
        }

        return prefix
    }
}
