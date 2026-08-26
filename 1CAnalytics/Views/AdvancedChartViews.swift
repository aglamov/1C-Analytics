import SwiftUI

extension AnalyticsChart {
    var radarChart: some View {
        RadarChartView(
            indicator: indicator,
            progress: hasAppeared ? 1 : 0,
            selectedRowID: selectedRowID,
            onSelect: toggleSelection
        )
    }
}

private struct RadarChartView: View {
    let indicator: Indicator
    let progress: Double
    let selectedRowID: IndicatorRow.ID?
    let onSelect: (IndicatorRow.ID) -> Void

    @Environment(\.chartPaletteScheme) private var paletteScheme
    @Environment(\.dashboardContentScale) private var contentScale

    private var groups: [IndicatorRowGroup] {
        indicator.rowGroups
    }

    private var seriesNames: [String] {
        indicator.orderedRows.uniqueValues { $0.series ?? indicator.title }
    }

    private var maximumValue: Double {
        max(indicator.orderedRows.map { max($0.value, 0) }.max() ?? 0, 1)
    }

    var body: some View {
        if groups.count < 3 || seriesNames.isEmpty {
            ContentUnavailableView(
                "Недостаточно данных",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("Для диаграммы «паутина» нужны минимум три оси.")
            )
        } else {
            GeometryReader { geometry in
                let layout = RadarLayout(
                    size: geometry.size,
                    axisCount: groups.count,
                    scale: contentScale
                )

                ZStack {
                    Canvas { context, _ in
                        drawGrid(context: &context, layout: layout)
                        drawSeries(context: &context, layout: layout)
                        drawLabelLeaders(context: &context, layout: layout)
                    }

                    axisLabels(layout: layout)
                    pointLabels(layout: layout)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { gesture in
                            selectNearestPoint(to: gesture.location, layout: layout)
                        }
                )
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(indicator.title)
        }
    }

    private func drawGrid(context: inout GraphicsContext, layout: RadarLayout) {
        for level in 1...5 {
            let points = layout.polygonPoints(radiusFraction: Double(level) / 5)
            var path = Path()
            path.addLines(points)
            path.closeSubpath()
            context.stroke(
                path,
                with: .color(.secondary.opacity(level == 5 ? 0.30 : 0.15)),
                lineWidth: level == 5 ? 1.2 : 0.8
            )
        }

        for index in groups.indices {
            var path = Path()
            path.move(to: layout.center)
            path.addLine(to: layout.point(axis: index, radiusFraction: 1))
            context.stroke(path, with: .color(.secondary.opacity(0.20)), lineWidth: 0.8)
        }
    }

    private func drawSeries(context: inout GraphicsContext, layout: RadarLayout) {
        for seriesName in seriesNames {
            let rows = rows(for: seriesName)
            let points = rows.enumerated().map { index, row in
                layout.point(
                    axis: index,
                    radiusFraction: max(row?.value ?? 0, 0) / maximumValue * progress
                )
            }
            guard points.count == groups.count else {
                continue
            }

            let referenceRow = rows.compactMap { $0 }.first
            let color = referenceRow.map(seriesColor(for:)) ?? .accentColor
            let isSelectedSeries = selectedRowID.flatMap { selectedID in
                indicator.rows.first(where: { $0.id == selectedID })?.series
            } == seriesName
            let opacity = selectedRowID == nil || isSelectedSeries ? 1.0 : 0.28

            var path = Path()
            path.addLines(points)
            path.closeSubpath()
            context.fill(path, with: .color(color.opacity(0.14 * opacity)))
            context.stroke(
                path,
                with: .color(color.opacity(opacity)),
                style: StrokeStyle(
                    lineWidth: isSelectedSeries ? 3 : 2,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: (referenceRow?.lineStyle ?? indicator.lineStyle) == .dashed ? [7, 5] : []
                )
            )

            for (index, point) in points.enumerated() {
                guard let row = rows[index] else {
                    continue
                }
                let selected = row.id == selectedRowID
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - (selected ? 5 : 3),
                        y: point.y - (selected ? 5 : 3),
                        width: selected ? 10 : 6,
                        height: selected ? 10 : 6
                    )),
                    with: .color(color.opacity(opacity))
                )
            }
        }
    }

    private func drawLabelLeaders(context: inout GraphicsContext, layout: RadarLayout) {
        guard indicator.showsValueLabels else {
            return
        }

        for (axisIndex, group) in groups.enumerated() {
            for row in group.rows where selectedRowID == nil || row.id == selectedRowID {
                let valueFraction = max(row.value, 0) / maximumValue
                let labelFraction = RadarPresentationPolicy.labelRadiusFraction(
                    valueFraction: valueFraction,
                    axisCount: groups.count
                )
                guard abs(labelFraction - valueFraction) > 0.04 else {
                    continue
                }

                var path = Path()
                path.move(to: layout.point(axis: axisIndex, radiusFraction: valueFraction * progress))
                path.addLine(to: layout.point(axis: axisIndex, radiusFraction: labelFraction * progress))
                context.stroke(
                    path,
                    with: .color(seriesColor(for: row).opacity(0.28)),
                    style: StrokeStyle(lineWidth: 0.8, dash: [2, 3])
                )
            }
        }
    }

    private func axisLabels(layout: RadarLayout) -> some View {
        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
            let labelSize = CGSize(width: 72 * contentScale, height: 30 * contentScale)
            let position = layout.labelPosition(
                axis: index,
                radiusFraction: 1.14,
                labelSize: labelSize
            )
            Text(group.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(width: labelSize.width)
                .position(position)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func pointLabels(layout: RadarLayout) -> some View {
        ForEach(Array(groups.enumerated()), id: \.element.id) { axisIndex, group in
            ForEach(group.rows) { row in
                if indicator.showsValueLabels,
                   selectedRowID == nil || row.id == selectedRowID {
                    let seriesIndex = max(seriesNames.firstIndex(of: row.series ?? indicator.title) ?? 0, 0)
                    let valueFraction = max(row.value, 0) / maximumValue
                    let basePosition = layout.point(
                        axis: axisIndex,
                        radiusFraction: RadarPresentationPolicy.labelRadiusFraction(
                            valueFraction: valueFraction,
                            axisCount: groups.count
                        ) * progress
                    )
                    let horizontalOffset: CGFloat = seriesIndex.isMultiple(of: 2) ? -8 : 8
                    let adjustedPosition = CGPoint(
                        x: basePosition.x + horizontalOffset * contentScale,
                        y: basePosition.y + (CGFloat(seriesIndex) * 8 - 8) * contentScale
                    )
                    let position = layout.clampedLabelPosition(
                        adjustedPosition,
                        labelSize: CGSize(width: 92 * contentScale, height: 34 * contentScale)
                    )
                    pointLabel(row: row, seriesIndex: seriesIndex, position: position)
                }
            }
        }
    }

    private func pointLabel(
        row: IndicatorRow,
        seriesIndex: Int,
        position: CGPoint
    ) -> some View {
        let isSelected = row.id == selectedRowID
        let text = row.valueLabel ?? indicator.formattedNumber(row.value)
        let font: Font = isSelected ? .subheadline : .caption

        return Text(text)
            .font(font.monospacedDigit().weight(.bold))
            .foregroundStyle(isSelected ? seriesColor(for: row) : .primary)
            .lineLimit(1)
            .padding(.horizontal, isSelected ? 7 : 4)
            .padding(.vertical, isSelected ? 4 : 2)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(
                        seriesColor(for: row).opacity(isSelected ? 0.75 : 0.25),
                        lineWidth: isSelected ? 1.5 : 0.6
                    )
            }
            .position(position)
            .zIndex(isSelected ? 100 : Double(seriesIndex))
            .allowsHitTesting(false)
    }

    private func rows(for seriesName: String) -> [IndicatorRow?] {
        groups.map { group in
            group.rows.first { ($0.series ?? indicator.title) == seriesName }
        }
    }

    private func seriesColor(for row: IndicatorRow) -> Color {
        indicator.chartColor(for: row, scheme: paletteScheme)
    }

    private func selectNearestPoint(to location: CGPoint, layout: RadarLayout) {
        let candidates = groups.enumerated().flatMap { axisIndex, group in
            group.rows.map { row in
                (
                    row: row,
                    point: layout.point(
                        axis: axisIndex,
                        radiusFraction: max(row.value, 0) / maximumValue
                    )
                )
            }
        }
        guard let nearest = candidates.min(by: {
            $0.point.distance(to: location) < $1.point.distance(to: location)
        }), nearest.point.distance(to: location) <= 32 * contentScale else {
            return
        }
        onSelect(nearest.row.id)
    }
}

private struct RadarLayout {
    let size: CGSize
    let axisCount: Int
    let scale: CGFloat

    var center: CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    var radius: CGFloat {
        max(min(size.width, size.height) / 2 - 22 * scale, 24)
    }

    func point(axis: Int, radiusFraction: Double) -> CGPoint {
        rawPoint(axis: axis, radiusFraction: min(max(radiusFraction, 0), 1))
    }

    func labelPosition(
        axis: Int,
        radiusFraction: Double,
        labelSize: CGSize
    ) -> CGPoint {
        clampedLabelPosition(
            rawPoint(axis: axis, radiusFraction: radiusFraction),
            labelSize: labelSize
        )
    }

    func clampedLabelPosition(_ point: CGPoint, labelSize: CGSize) -> CGPoint {
        let horizontalInset = labelSize.width / 2
        let verticalInset = labelSize.height / 2
        return CGPoint(
            x: min(max(point.x, horizontalInset), max(size.width - horizontalInset, horizontalInset)),
            y: min(max(point.y, verticalInset), max(size.height - verticalInset, verticalInset))
        )
    }

    private func rawPoint(axis: Int, radiusFraction: Double) -> CGPoint {
        let angle = -Double.pi / 2 + Double(axis) * 2 * Double.pi / Double(max(axisCount, 1))
        let resolvedRadius = radius * CGFloat(max(radiusFraction, 0))
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * resolvedRadius,
            y: center.y + CGFloat(sin(angle)) * resolvedRadius
        )
    }

    func polygonPoints(radiusFraction: Double) -> [CGPoint] {
        (0..<axisCount).map { point(axis: $0, radiusFraction: radiusFraction) }
    }
}

enum RadarPresentationPolicy {
    static func labelRadiusFraction(valueFraction: Double, axisCount: Int) -> Double {
        let minimumFraction: Double
        switch axisCount {
        case 8...:
            minimumFraction = 0.62
        case 6...7:
            minimumFraction = 0.48
        default:
            minimumFraction = 0.34
        }

        let maximumFraction = axisCount >= 8 ? 0.82 : 0.84
        return min(max(valueFraction, minimumFraction), maximumFraction)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

struct TileChartView: View {
    let indicator: Indicator
    let appliesCardLimit: Bool
    private let externalSelectedRowID: IndicatorRow.ID?
    private let onSelect: ((IndicatorRow.ID) -> Void)?
    @State private var localSelectedRowID: IndicatorRow.ID?
    @Environment(\.chartPaletteScheme) private var paletteScheme
    @Environment(\.dashboardContentScale) private var contentScale

    init(
        indicator: Indicator,
        appliesCardLimit: Bool,
        selectedRowID: IndicatorRow.ID? = nil,
        onSelect: ((IndicatorRow.ID) -> Void)? = nil
    ) {
        self.indicator = indicator
        self.appliesCardLimit = appliesCardLimit
        self.externalSelectedRowID = selectedRowID
        self.onSelect = onSelect
        _localSelectedRowID = State(initialValue: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * contentScale) {
            chart
            if indicator.showsLegend, !items.isEmpty {
                legend
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "Данные пока отсутствуют",
                systemImage: "square.grid.2x2",
                description: Text("Для плитки нужны положительные значения.")
            )
        } else if indicator.resolvedTileLayout == .grid {
            grid
        } else {
            mosaic
        }
    }

    private var legend: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 120 * contentScale), spacing: 8 * contentScale)],
            alignment: .leading,
            spacing: 7 * contentScale
        ) {
            ForEach(items) { item in
                HStack(spacing: 6 * contentScale) {
                    Circle()
                        .fill(indicator.chartColor(for: item.row, scheme: paletteScheme))
                        .frame(width: 8 * contentScale, height: 8 * contentScale)
                    Text(item.title)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(formattedValue(item.value))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption2.weight(.semibold))
            }
        }
    }

    private var grid: some View {
        GeometryReader { geometry in
            let columnCount = TileGridLayout.columnCount(
                availableWidth: geometry.size.width,
                contentScale: contentScale
            )
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: spacing),
                count: columnCount
            )
            let itemWidth = max(
                (geometry.size.width - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount),
                1
            )

            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(items) { item in
                    tile(item, size: CGSize(width: itemWidth, height: 88 * contentScale))
                        .frame(minHeight: 80 * contentScale)
                }
            }
        }
    }

    private var mosaic: some View {
        GeometryReader { geometry in
            let frames = TileMosaicLayout.frames(
                for: items.map(\.value),
                in: CGRect(origin: .zero, size: geometry.size),
                spacing: spacing
            )
            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let frame = frames[index]
                    tile(item, size: frame.size)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
    }

    private func tile(_ item: TileChartItem, size: CGSize) -> some View {
        let row = item.row
        let color = indicator.chartColor(for: row, scheme: paletteScheme)
        let visibility = TileLabelVisibilityPolicy.visibility(
            for: size,
            contentScale: contentScale,
            showValueLabels: indicator.showsValueLabels
        )
        let isSelected = item.sourceRowIDs.contains(activeSelectedRowID ?? "")
        let isDimmed = activeSelectedRowID != nil && !isSelected

        return Button {
            select(item)
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 9 * contentScale, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.96), color.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(alignment: .leading, spacing: 3 * contentScale) {
                    if visibility.showsTitle {
                        Text(item.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(size.height >= 54 * contentScale ? 2 : 1)
                            .minimumScaleFactor(0.58)
                    }

                    if visibility.showsValue {
                        Text(formattedValue(item.value))
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundStyle(.white.opacity(0.96))
                            .lineLimit(1)
                    }

                    if visibility.showsPercentage {
                        Text(item.percentage.formatted(.percent.precision(.fractionLength(1))))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }
                .padding(8 * contentScale)

                RoundedRectangle(cornerRadius: 9 * contentScale, style: .continuous)
                    .strokeBorder(.white.opacity(isSelected ? 0.95 : 0), lineWidth: 3 * contentScale)
            }
        }
        .buttonStyle(.plain)
        .opacity(isDimmed ? 0.34 : 1)
        .scaleEffect(isSelected ? 0.97 : 1)
        .animation(.spring(response: 0.30, dampingFraction: 0.78), value: activeSelectedRowID)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(
            "\(formattedValue(item.value)), "
                + item.percentage.formatted(.percent.precision(.fractionLength(1)))
        )
        .accessibilityHint("Выбрать плитку")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var spacing: CGFloat {
        CGFloat(indicator.valueSpacing ?? 4) * contentScale
    }

    private func formattedValue(_ value: Double) -> String {
        let number = indicator.formattedNumber(value)
        guard let unit = indicator.displayUnit else { return number }
        return "\(number) \(unit)"
    }

    private var activeSelectedRowID: IndicatorRow.ID? {
        onSelect == nil ? localSelectedRowID : externalSelectedRowID
    }

    private var items: [TileChartItem] {
        TilePresentationPolicy.items(for: indicator, appliesLimit: appliesCardLimit)
    }

    private func select(_ item: TileChartItem) {
        if let onSelect {
            onSelect(item.selectionRowID)
        } else {
            localSelectedRowID = localSelectedRowID == item.selectionRowID
                ? nil
                : item.selectionRowID
        }
    }
}

struct TileChartItem: Identifiable, Equatable {
    let id: String
    let title: String
    let value: Double
    let percentage: Double
    let row: IndicatorRow
    let sourceRowIDs: Set<IndicatorRow.ID>
    let selectionRowID: IndicatorRow.ID
    let isRemainder: Bool
}

enum TilePresentationPolicy {
    static func items(for indicator: Indicator, appliesLimit: Bool) -> [TileChartItem] {
        let sorted = indicator.rowGroups
            .map { group in
                (group: group, value: group.rows.reduce(0) { $0 + $1.value })
            }
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.group.label < rhs.group.label }
                return lhs.value > rhs.value
            }

        struct DisplayedGroup {
            let id: String
            let title: String
            let value: Double
            let row: IndicatorRow
            let sourceRowIDs: Set<IndicatorRow.ID>
            let selectionRowID: IndicatorRow.ID
            let isRemainder: Bool
        }

        var displayed = sorted.compactMap { element -> DisplayedGroup? in
            guard let row = element.group.rows.first else { return nil }
            return DisplayedGroup(
                id: "tile-\(element.group.id)",
                title: element.group.label,
                value: element.value,
                row: row,
                sourceRowIDs: Set(element.group.rows.map(\.id)),
                selectionRowID: row.id,
                isRemainder: false
            )
        }

        let limit = indicator.resolvedMaximumTiles
        if appliesLimit, displayed.count > limit {
            let visibleCount = limit - 1
            let hidden = displayed.dropFirst(visibleCount)
            let hiddenValue = hidden.reduce(0) { $0 + $1.value }
            let hiddenRowIDs = hidden.reduce(into: Set<IndicatorRow.ID>()) {
                $0.formUnion($1.sourceRowIDs)
            }
            let selectionRowID = hidden.first?.selectionRowID ?? "tile-other"
            let otherRow = IndicatorRow(
                id: "tile-other",
                label: "Прочее",
                value: hiddenValue,
                series: nil,
                sortOrder: limit - 1
            )
            displayed = Array(displayed.prefix(visibleCount)) + [
                DisplayedGroup(
                    id: "tile-other",
                    title: "Прочее",
                    value: hiddenValue,
                    row: otherRow,
                    sourceRowIDs: hiddenRowIDs,
                    selectionRowID: selectionRowID,
                    isRemainder: true
                )
            ]
        }

        let percentages = TilePercentagePolicy.percentages(for: displayed.map(\.value))
        return displayed.enumerated().map { index, element in
            TileChartItem(
                id: element.id,
                title: element.title,
                value: element.value,
                percentage: percentages[index],
                row: element.row,
                sourceRowIDs: element.sourceRowIDs,
                selectionRowID: element.selectionRowID,
                isRemainder: element.isRemainder
            )
        }
    }
}

enum TilePercentagePolicy {
    static func percentages(for values: [Double]) -> [Double] {
        let total = values.reduce(0, +)
        guard total > 0 else { return Array(repeating: 0, count: values.count) }
        let rawUnits = values.map { max($0, 0) / total * 1_000 }
        var units = rawUnits.map { Int($0.rounded(.down)) }
        var remainder = 1_000 - units.reduce(0, +)
        let order = rawUnits.indices.sorted {
            let lhs = rawUnits[$0] - Double(units[$0])
            let rhs = rawUnits[$1] - Double(units[$1])
            return lhs == rhs ? $0 < $1 : lhs > rhs
        }
        for index in order where remainder > 0 {
            units[index] += 1
            remainder -= 1
        }
        return units.map { Double($0) / 1_000 }
    }
}

enum TileMosaicLayout {
    static func frames(for values: [Double], in rect: CGRect, spacing: CGFloat) -> [CGRect] {
        guard !values.isEmpty, rect.width > 0, rect.height > 0 else { return [] }
        var result = Array(repeating: CGRect.zero, count: values.count)
        let positiveTotal = CGFloat(values.reduce(0) { $0 + max($1, 0) })
        guard positiveTotal > 0 else { return result }

        let areaScale = rect.width * rect.height / positiveTotal
        var pending = values.indices
            .map { (index: $0, area: CGFloat(max(values[$0], 0)) * areaScale) }
            .filter { $0.area > 0 }
            .sorted { $0.area > $1.area }
        var remainingRect = rect
        var row: [(index: Int, area: CGFloat)] = []

        while let candidate = pending.first {
            let shortSide = max(min(remainingRect.width, remainingRect.height), 0.000_001)
            if row.isEmpty || worstAspectRatio(for: row + [candidate], side: shortSide)
                <= worstAspectRatio(for: row, side: shortSide) {
                row.append(candidate)
                pending.removeFirst()
            } else {
                remainingRect = layout(row: row, in: remainingRect, result: &result)
                row.removeAll(keepingCapacity: true)
            }
        }
        if !row.isEmpty {
            _ = layout(row: row, in: remainingRect, result: &result)
        }

        let insetAmount = max(spacing, 0) / 2
        return result.map { inset($0, by: insetAmount) }
    }

    private static func worstAspectRatio(
        for row: [(index: Int, area: CGFloat)],
        side: CGFloat
    ) -> CGFloat {
        guard !row.isEmpty else { return .infinity }
        let sum = row.reduce(0) { $0 + $1.area }
        let largest = row.map(\.area).max() ?? 0
        let smallest = row.map(\.area).min() ?? 0
        guard sum > 0, smallest > 0, side > 0 else { return .infinity }
        let sideSquared = side * side
        let sumSquared = sum * sum
        return max(
            sideSquared * largest / sumSquared,
            sumSquared / (sideSquared * smallest)
        )
    }

    private static func layout(
        row: [(index: Int, area: CGFloat)],
        in rect: CGRect,
        result: inout [CGRect]
    ) -> CGRect {
        guard !row.isEmpty else { return rect }
        let rowArea = row.reduce(0) { $0 + $1.area }

        if rect.width >= rect.height {
            let stripWidth = min(rowArea / max(rect.height, 0.000_001), rect.width)
            var y = rect.minY
            for (offset, item) in row.enumerated() {
                let height = offset == row.count - 1
                    ? rect.maxY - y
                    : min(item.area / max(stripWidth, 0.000_001), rect.maxY - y)
                result[item.index] = CGRect(x: rect.minX, y: y, width: stripWidth, height: height)
                y += height
            }
            return CGRect(
                x: rect.minX + stripWidth,
                y: rect.minY,
                width: max(rect.width - stripWidth, 0),
                height: rect.height
            )
        } else {
            let stripHeight = min(rowArea / max(rect.width, 0.000_001), rect.height)
            var x = rect.minX
            for (offset, item) in row.enumerated() {
                let width = offset == row.count - 1
                    ? rect.maxX - x
                    : min(item.area / max(stripHeight, 0.000_001), rect.maxX - x)
                result[item.index] = CGRect(x: x, y: rect.minY, width: width, height: stripHeight)
                x += width
            }
            return CGRect(
                x: rect.minX,
                y: rect.minY + stripHeight,
                width: rect.width,
                height: max(rect.height - stripHeight, 0)
            )
        }
    }

    private static func inset(_ rect: CGRect, by amount: CGFloat) -> CGRect {
        let horizontalInset = min(amount, rect.width / 2)
        let verticalInset = min(amount, rect.height / 2)
        return rect.insetBy(dx: horizontalInset, dy: verticalInset)
    }
}

struct TileLabelVisibility: Equatable {
    let showsTitle: Bool
    let showsValue: Bool
    let showsPercentage: Bool
}

enum TileLabelVisibilityPolicy {
    static func visibility(
        for size: CGSize,
        contentScale: CGFloat,
        showValueLabels: Bool
    ) -> TileLabelVisibility {
        let scale = max(contentScale, 0.1)
        let width = size.width / scale
        let height = size.height / scale
        let showsTitle = width >= 24 && height >= 20
        let showsValue = showsTitle && showValueLabels && width >= 42 && height >= 38
        let showsPercentage = showsValue && width >= 54 && height >= 56
        return TileLabelVisibility(
            showsTitle: showsTitle,
            showsValue: showsValue,
            showsPercentage: showsPercentage
        )
    }
}

enum TileGridLayout {
    static func columnCount(availableWidth: CGFloat, contentScale: CGFloat) -> Int {
        let normalizedWidth = availableWidth / max(contentScale, 0.1)
        if normalizedWidth >= 720 { return 4 }
        if normalizedWidth >= 500 { return 3 }
        return 2
    }
}

struct ExpandableHierarchyChartView: View {
    let indicator: Indicator
    let showsExpandedHierarchy: Bool

    @State private var expandedNodeIDs = Set<ExpandableHierarchyNode.ID>()
    @State private var hasAppeared = false
    @Environment(\.chartPaletteScheme) private var paletteScheme
    @Environment(\.dashboardContentScale) private var contentScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let hierarchy = indicator.hierarchy,
           !hierarchy.nodes.isEmpty,
           !hierarchy.displayedSeries.isEmpty {
            VStack(alignment: .leading, spacing: 12 * contentScale) {
                if showsExpandedHierarchy, !expandedNodeIDs.isEmpty {
                    HStack {
                        Spacer()
                        Button("Свернуть все") {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                expandedNodeIDs.removeAll()
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                    }
                }
                if indicator.showsLegend {
                    hierarchyLegend(hierarchy)
                }

                VStack(alignment: .leading, spacing: 14 * contentScale) {
                    ForEach(visibleNodes(in: hierarchy)) { visibleNode in
                        hierarchyNodeRow(visibleNode, hierarchy: hierarchy)
                    }

                    if indicator.showsAggregateValue {
                        Divider()
                        hierarchyNodeRow(
                            HierarchyVisibleNode(
                                node: totalNode(for: hierarchy),
                                depth: 0,
                                isTotal: true
                            ),
                            hierarchy: hierarchy
                        )
                    }
                }
            }
            .onAppear {
                guard !hasAppeared else { return }
                if reduceMotion {
                    hasAppeared = true
                } else {
                    withAnimation(.easeOut(duration: 0.7)) {
                        hasAppeared = true
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Данные пока отсутствуют",
                systemImage: "chart.bar.doc.horizontal",
                description: Text("Иерархическая диаграмма не содержит серий или узлов.")
            )
        }
    }

    private func hierarchyLegend(_ hierarchy: ExpandableHierarchy) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 108 * contentScale), spacing: 8 * contentScale)],
            alignment: .leading,
            spacing: 8 * contentScale
        ) {
            ForEach(hierarchy.displayedSeries) { series in
                HStack(spacing: 7 * contentScale) {
                    Circle()
                        .fill(seriesColor(series, in: hierarchy))
                        .frame(width: 8 * contentScale, height: 8 * contentScale)

                    Text(series.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 32 * contentScale, alignment: .leading)
                .padding(.horizontal, 9 * contentScale)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func hierarchyNodeRow(
        _ visibleNode: HierarchyVisibleNode,
        hierarchy: ExpandableHierarchy
    ) -> some View {
        VStack(alignment: .leading, spacing: 7 * contentScale) {
            HStack(alignment: .firstTextBaseline, spacing: 8 * contentScale) {
                if showsExpandedHierarchy,
                   !visibleNode.isTotal,
                   !visibleNode.node.children.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            toggleExpansion(visibleNode.node.id)
                        }
                    } label: {
                        Image(systemName: expandedNodeIDs.contains(visibleNode.node.id)
                            ? "chevron.down"
                            : "chevron.right")
                            .font(.caption.weight(.bold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(expandedNodeIDs.contains(visibleNode.node.id) ? "Свернуть" : "Развернуть")
                }

                Text(visibleNode.isTotal ? "Итого" : visibleNode.node.label)
                    .font(visibleNode.isTotal ? .subheadline.weight(.bold) : .caption.weight(.semibold))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let total = hierarchy.displayedTotal(for: visibleNode.node) {
                    Text(indicator.formattedNumber(total))
                        .font(.caption.monospacedDigit().weight(.bold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
            }

            hierarchyBars(for: visibleNode.node, hierarchy: hierarchy)
        }
        .padding(.leading, CGFloat(min(visibleNode.depth, 3)) * 16 * contentScale)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func hierarchyBars(
        for node: ExpandableHierarchyNode,
        hierarchy: ExpandableHierarchy
    ) -> some View {
        switch hierarchy.barMode {
        case .stacked:
            stackedBar(for: node, hierarchy: hierarchy)
        case .grouped:
            groupedBars(for: node, hierarchy: hierarchy)
        case .single:
            singleBar(for: node, hierarchy: hierarchy)
        }
    }

    private func stackedBar(
        for node: ExpandableHierarchyNode,
        hierarchy: ExpandableHierarchy
    ) -> some View {
        let series = hierarchy.displayedSeries
        let total = series.reduce(0) { $0 + max(node.values[$1.key]?.value ?? 0, 0) }

        return VStack(alignment: .leading, spacing: 5 * contentScale) {
            GeometryReader { geometry in
                let fraction = min(
                    max(total / max(maximumStackedTotal(in: hierarchy), 1), 0),
                    1
                )
                let width = geometry.size.width
                    * CGFloat(fraction)
                    * (hasAppeared ? 1 : 0)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.secondary.opacity(0.10))

                    HStack(spacing: 1 * contentScale) {
                        ForEach(series) { item in
                            let value = max(node.values[item.key]?.value ?? 0, 0)
                            Rectangle()
                                .fill(seriesColor(item, in: hierarchy).gradient)
                                .frame(width: width * CGFloat(value / max(total, 1)))
                        }
                    }
                    .frame(width: width, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .frame(height: 18 * contentScale)

            if indicator.showsValueLabels {
                valueSummary(for: node, hierarchy: hierarchy)
            }
        }
    }

    private func groupedBars(
        for node: ExpandableHierarchyNode,
        hierarchy: ExpandableHierarchy
    ) -> some View {
        VStack(alignment: .leading, spacing: 6 * contentScale) {
            ForEach(hierarchy.displayedSeries) { series in
                let item = node.values[series.key]
                HStack(spacing: 7 * contentScale) {
                    Text(series.name)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 74 * contentScale, alignment: .leading)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.10))
                            Capsule()
                                .fill(seriesColor(series, in: hierarchy).gradient)
                                .frame(width: groupedBarWidth(
                                    value: item?.value ?? 0,
                                    availableWidth: geometry.size.width,
                                    hierarchy: hierarchy
                                ))
                        }
                    }
                    .frame(height: 12 * contentScale)

                    if indicator.showsValueLabels {
                        Text(formatted(item, series: series))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .lineLimit(1)
                            .frame(minWidth: 52 * contentScale, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func singleBar(
        for node: ExpandableHierarchyNode,
        hierarchy: ExpandableHierarchy
    ) -> some View {
        guard let series = hierarchy.displayedSeries.first else {
            return AnyView(EmptyView())
        }
        let item = node.values[series.key]

        return AnyView(
            VStack(alignment: .leading, spacing: 5 * contentScale) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.10))
                        Capsule()
                            .fill(seriesColor(series, in: hierarchy).gradient)
                            .frame(width: groupedBarWidth(
                                value: item?.value ?? 0,
                                availableWidth: geometry.size.width,
                                hierarchy: hierarchy
                            ))
                    }
                }
                .frame(height: 16 * contentScale)

                if indicator.showsValueLabels {
                    Text(formatted(item, series: series))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                }
            }
        )
    }

    private func valueSummary(
        for node: ExpandableHierarchyNode,
        hierarchy: ExpandableHierarchy
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12 * contentScale) {
                valueSummaryItems(for: node, hierarchy: hierarchy)
            }

            VStack(alignment: .leading, spacing: 3 * contentScale) {
                valueSummaryItems(for: node, hierarchy: hierarchy)
            }
        }
    }

    @ViewBuilder
    private func valueSummaryItems(
        for node: ExpandableHierarchyNode,
        hierarchy: ExpandableHierarchy
    ) -> some View {
        ForEach(hierarchy.displayedSeries) { series in
            HStack(spacing: 4 * contentScale) {
                Circle()
                    .fill(seriesColor(series, in: hierarchy))
                    .frame(width: 6 * contentScale, height: 6 * contentScale)
                Text("\(series.name): \(formatted(node.values[series.key], series: series))")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
            }
        }
    }

    private func visibleNodes(in hierarchy: ExpandableHierarchy) -> [HierarchyVisibleNode] {
        guard showsExpandedHierarchy else {
            return hierarchy.nodes.map { HierarchyVisibleNode(node: $0, depth: 0) }
        }

        func append(_ nodes: [ExpandableHierarchyNode], depth: Int, to result: inout [HierarchyVisibleNode]) {
            for node in nodes {
                result.append(HierarchyVisibleNode(node: node, depth: depth))
                if expandedNodeIDs.contains(node.id) {
                    append(node.children, depth: depth + 1, to: &result)
                }
            }
        }

        var result: [HierarchyVisibleNode] = []
        append(hierarchy.nodes, depth: 0, to: &result)
        return result
    }

    private func allNodes(in hierarchy: ExpandableHierarchy) -> [ExpandableHierarchyNode] {
        func flatten(_ nodes: [ExpandableHierarchyNode], into result: inout [ExpandableHierarchyNode]) {
            for node in nodes {
                result.append(node)
                flatten(node.children, into: &result)
            }
        }

        var result: [ExpandableHierarchyNode] = []
        flatten(hierarchy.nodes, into: &result)
        return result
    }

    private func totalNode(for hierarchy: ExpandableHierarchy) -> ExpandableHierarchyNode {
        let values = hierarchy.series.reduce(into: [String: ExpandableHierarchyValue]()) {
            result, series in
            let total = hierarchy.nodes.reduce(0) { partial, node in
                partial + (node.values[series.key]?.value ?? 0)
            }
            result[series.key] = ExpandableHierarchyValue(value: total, valueLabel: nil)
        }
        return ExpandableHierarchyNode(
            id: "hierarchy-total",
            label: "Итого",
            values: values,
            children: []
        )
    }

    private func maximumStackedTotal(in hierarchy: ExpandableHierarchy) -> Double {
        let nodes = showsExpandedHierarchy ? allNodes(in: hierarchy) : hierarchy.nodes
        return nodes.map { node in
            hierarchy.displayedSeries.reduce(0) {
                $0 + max(node.values[$1.key]?.value ?? 0, 0)
            }
        }.max() ?? 1
    }

    private func maximumSingleValue(in hierarchy: ExpandableHierarchy) -> Double {
        let nodes = showsExpandedHierarchy ? allNodes(in: hierarchy) : hierarchy.nodes
        return nodes.flatMap { node in
            hierarchy.displayedSeries.map { max(node.values[$0.key]?.value ?? 0, 0) }
        }.max() ?? 1
    }

    private func groupedBarWidth(
        value: Double,
        availableWidth: CGFloat,
        hierarchy: ExpandableHierarchy
    ) -> CGFloat {
        let fraction = min(
            max(value / max(maximumSingleValue(in: hierarchy), 1), 0),
            1
        )
        return availableWidth * CGFloat(fraction) * (hasAppeared ? 1 : 0)
    }

    private func seriesColor(
        _ series: ExpandableHierarchySeries,
        in hierarchy: ExpandableHierarchy
    ) -> Color {
        if paletteScheme.usesAPIColors,
           let apiColor = Color(apiHex: series.colorGraph) {
            return apiColor
        }
        return ChartPalette.color(
            for: series.name,
            in: hierarchy.displayedSeries.map(\.name),
            scheme: paletteScheme,
            fallback: indicator.accent.primary
        )
    }

    private func formatted(
        _ item: ExpandableHierarchyValue?,
        series: ExpandableHierarchySeries
    ) -> String {
        guard let item else { return "—" }
        if let label = item.valueLabel, !label.isEmpty {
            return label
        }
        let number = indicator.formattedNumber(item.value)
        guard let unit = series.unit?.trimmingCharacters(in: .whitespacesAndNewlines),
              !unit.isEmpty else {
            return number
        }
        return "\(number) \(unit)"
    }

    private func toggleExpansion(_ nodeID: ExpandableHierarchyNode.ID) {
        if expandedNodeIDs.contains(nodeID) {
            expandedNodeIDs.remove(nodeID)
        } else {
            expandedNodeIDs.insert(nodeID)
        }
    }
}

private struct HierarchyVisibleNode: Identifiable {
    let node: ExpandableHierarchyNode
    let depth: Int
    var isTotal = false

    var id: String {
        isTotal ? "hierarchy-visible-total" : node.id
    }
}
