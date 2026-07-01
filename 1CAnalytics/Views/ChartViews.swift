import Charts
import SwiftUI

struct AnalyticsChart: View {
    let indicator: Indicator
    var showsTitle = true
    var usesCardBackground = true
    var showsLegend = true
    var showsValueLabels = true
    private var externalSelection: Binding<IndicatorRow.ID?>?
    @State private var internalSelectedRowID: IndicatorRow.ID?
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
        selectedRowID: Binding<IndicatorRow.ID?>? = nil
    ) {
        self.indicator = indicator
        self.showsTitle = showsTitle
        self.usesCardBackground = usesCardBackground
        self.showsLegend = showsLegend
        self.showsValueLabels = showsValueLabels
        self.externalSelection = selectedRowID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle, let selectedRow {
                HStack {
                    Spacer()

                    Text(selectedRowTitle(for: selectedRow))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .background(selectedTitleBackground, in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.secondary.opacity(colorScheme == .dark ? 0.20 : 0.12), lineWidth: 1)
                        }
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }

            switch indicator.chartType {
            case .bar:
                verticalBars
            case .horizontalBar:
                horizontalBars
            case .stackedBar:
                stackedBars
            case .donut:
                donut
            }

            if showsLegend {
                interactiveLegend
            }
        }
        .modifier(ChartChromeModifier(isEnabled: usesCardBackground))
        .chartLegend(.hidden)
        .onAppear {
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

    private var verticalBars: some View {
        Chart(indicator.orderedRows) { row in
            BarMark(
                x: .value("Группа", row.label),
                y: .value("Значение", animatedValue(for: row))
            )
            .foregroundStyle(by: .value("Группа", row.label))
            .opacity(opacity(for: row))
            .cornerRadius(3)
            .annotation(position: .top, alignment: .center) {
                if showsValueLabels {
                    valueLabel(for: row)
                }
            }
        }
        .chartForegroundStyleScale(domain: indicator.chartColorDomain, range: chartColors)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(Color.secondary.opacity(0.16))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(Color.secondary.opacity(0.26))
                AxisValueLabel()
                    .foregroundStyle(Color.secondary)
                    .font(.caption2)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .foregroundStyle(Color.secondary)
                    .font(.caption2)
            }
        }
        .chartOverlay { proxy in
            chartTapOverlay(proxy: proxy, mode: .verticalBar)
        }
    }

    private var horizontalBars: some View {
        Chart(indicator.orderedRows) { row in
            BarMark(
                x: .value("Значение", animatedValue(for: row)),
                y: .value("Группа", row.label)
            )
            .foregroundStyle(by: .value("Группа", row.label))
            .opacity(opacity(for: row))
            .cornerRadius(3)
            .annotation(position: .trailing, alignment: .center) {
                if showsValueLabels {
                    valueLabel(for: row)
                }
            }
        }
        .chartForegroundStyleScale(domain: indicator.chartColorDomain, range: chartColors)
        .chartXAxis {
            AxisMarks(position: .bottom) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(Color.secondary.opacity(0.16))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(Color.secondary.opacity(0.26))
                AxisValueLabel()
                    .foregroundStyle(Color.secondary)
                    .font(.caption2)
            }
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
        Chart(indicator.orderedRows) { row in
            BarMark(
                x: .value("Группа", row.label),
                y: .value("Значение", animatedValue(for: row))
            )
            .foregroundStyle(by: .value("Серия", row.series ?? "Значение"))
            .opacity(opacity(for: row))
            .cornerRadius(3)
            .annotation(position: .overlay, alignment: .center) {
                if showsValueLabels {
                    valueLabel(for: row)
                }
            }
        }
        .chartForegroundStyleScale(domain: indicator.chartColorDomain, range: chartColors)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(Color.secondary.opacity(0.16))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(Color.secondary.opacity(0.26))
                AxisValueLabel()
                    .foregroundStyle(Color.secondary)
                    .font(.caption2)
            }
        }
        .chartXAxis {
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

    private var donut: some View {
        Chart(indicator.orderedRows) { row in
            SectorMark(
                angle: .value("Доля", animatedValue(for: row)),
                innerRadius: .ratio(0.62),
                outerRadius: selectedRowID == row.id ? .ratio(1.0) : .ratio(0.92),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(by: .value("Группа", row.label))
            .opacity(opacity(for: row))
            .annotation(position: .overlay, alignment: .center) {
                if showsValueLabels {
                    valueLabel(for: row)
                }
            }
        }
        .chartForegroundStyleScale(domain: indicator.chartColorDomain, range: chartColors)
        .chartOverlay { proxy in
            donutTapOverlay(proxy: proxy)
        }
    }

    private var interactiveLegend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(indicator.orderedRows.prefix(8)) { row in
                Button {
                    toggleSelection(row.id)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(chartColor(for: row).opacity(selectedRowID == row.id ? 1 : 0.72))
                            .frame(width: 7, height: 7)

                        Text(row.label)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .frame(minHeight: 28)
                    .background(
                        selectedRowID == row.id ? chartColor(for: row).opacity(0.12) : Color(.tertiarySystemGroupedBackground).opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(selectedRowID == row.id ? chartColor(for: row).opacity(0.22) : .clear, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Выбрать \(row.label)")
            }
        }
    }

    private var selectedRow: IndicatorRow? {
        guard let selectedRowID else {
            return nil
        }

        return indicator.rows.first { $0.id == selectedRowID }
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

    private func selectedRowTitle(for row: IndicatorRow) -> String {
        let value = row.value.formatted(.number.grouping(.automatic).precision(.fractionLength(0)))
        if let series = row.series {
            return "\(row.label), \(series): \(value)"
        }

        return "\(row.label): \(value)"
    }

    private var selectedTitleBackground: Color {
        colorScheme == .dark ? Color(.tertiarySystemGroupedBackground).opacity(0.92) : Color(.systemBackground).opacity(0.86)
    }

    private func animatedValue(for row: IndicatorRow) -> Double {
        hasAppeared ? row.value : 0
    }

    private func opacity(for row: IndicatorRow) -> Double {
        guard let selectedRowID else {
            return 1
        }

        return selectedRowID == row.id ? 1 : 0.28
    }

    private func valueLabel(for row: IndicatorRow) -> some View {
        ChartValueLabel(
            value: row.value,
            isSelected: selectedRowID == row.id,
            selectionColor: chartColor(for: row)
        )
    }

    private func toggleSelection(_ rowID: IndicatorRow.ID) {
        setSelection(selectedRowID == rowID ? nil : rowID)
    }

    private func clearSelection() {
        setSelection(nil)
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
                .gesture(
                    DragGesture(minimumDistance: 0)
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
                .gesture(
                    DragGesture(minimumDistance: 0)
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
                let row = indicator.orderedRows.first(where: { $0.label == label }),
                value >= 0,
                value <= row.value
            else {
                return nil
            }

            return row.id

        case .horizontalBar:
            guard
                let label = proxy.value(atY: location.y, as: String.self),
                let value = proxy.value(atX: location.x, as: Double.self),
                let row = indicator.orderedRows.first(where: { $0.label == label }),
                value >= 0,
                value <= row.value
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
        }
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
}

private struct ChartValueLabel: View {
    let value: Double
    let isSelected: Bool
    let selectionColor: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(valueText)
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(isSelected ? selectedForeground : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .allowsTightening(true)
            .frame(maxWidth: isSelected ? 88 : 54)
            .padding(.horizontal, isSelected ? 8 : 0)
            .padding(.vertical, isSelected ? 5 : 0)
            .background(
                isSelected ? selectedBackground : .clear,
                in: Capsule()
            )
            .overlay {
                if isSelected {
                    Capsule()
                        .strokeBorder(selectionColor.opacity(colorScheme == .dark ? 0.46 : 0.26), lineWidth: 1)
                }
            }
            .shadow(color: isSelected ? .black.opacity(colorScheme == .dark ? 0.24 : 0.10) : .clear, radius: 6, x: 0, y: 3)
            .animation(.spring(response: 0.32, dampingFraction: 0.66), value: isSelected)
    }

    private var valueText: String {
        if isSelected {
            return value.formatted(.number.grouping(.automatic).precision(.fractionLength(0)))
        }

        return value.formatted(.number.notation(.compactName).precision(.fractionLength(0)))
    }

    private var selectedBackground: Color {
        colorScheme == .dark ? Color(.secondarySystemGroupedBackground).opacity(0.96) : Color(.systemBackground).opacity(0.94)
    }

    private var selectedForeground: Color {
        colorScheme == .dark ? .white : selectionColor
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
