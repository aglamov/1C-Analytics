import SwiftUI

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

            HStack(alignment: .top, spacing: 16) {
                chartSection(fillsAvailableHeight: true)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: lowerHeight,
                        maxHeight: lowerHeight,
                        alignment: .top
                    )

                ScrollView(.vertical) {
                    rowsSection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, minHeight: lowerHeight, maxHeight: lowerHeight, alignment: .topLeading)
                .scrollBounceBehavior(.basedOnSize)
            }

            Spacer(minLength: 0)
        }
    }

    private func compactDetailContent(availableSize: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            IndicatorHero(indicator: indicator)
            chartSection(fillsAvailableHeight: false, aspectRatio: compactChartAspectRatio(for: availableSize))
            rowsSection
        }
    }

    private func splitHeaderHeight(for availableSize: CGSize) -> CGFloat {
        min(156, max(132, availableSize.height * 0.13))
    }

    private func splitLowerSectionHeight(for availableSize: CGSize, headerHeight: CGFloat) -> CGFloat {
        let verticalPadding: CGFloat = 32
        let contentSpacing: CGFloat = 16
        let remainingHeight = availableSize.height - verticalPadding - headerHeight - contentSpacing

        return max(320, remainingHeight * 0.8)
    }

    private func compactChartAspectRatio(for availableSize: CGSize) -> CGFloat {
        guard horizontalSizeClass == .regular, availableSize.height > availableSize.width else {
            return 1.0
        }

        return 1.28
    }

    @ViewBuilder
    private func chartSection(fillsAvailableHeight: Bool, aspectRatio: CGFloat = 1.0) -> some View {
        if indicator.chartType == .geoMap {
            GeoMapIndicatorView(indicator: indicator)
                .frame(maxWidth: .infinity, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            let chart = AnalyticsChart(
                indicator: indicator,
                usesCardBackground: false,
                showsLegend: false,
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

    private var rowsSection: some View {
        let groups = detailGroups
        let maximumValue = groups
            .flatMap { group in
                group.rows.count > 1 ? group.rows.map(\.value) : [group.totalValue]
            }
            .max() ?? 0
        let totalValue = groups.reduce(0) { $0 + $1.totalValue }

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

                if indicator.showsAggregateValue {
                    Text(totalText(for: totalValue))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            LazyVStack(spacing: 0) {
                ForEach(groups) { group in
                    DetailGroupRowView(
                        group: group,
                        maxValue: maximumValue,
                        totalValue: totalValue,
                        indicator: indicator,
                        selectedRowID: selectedRowID,
                        animatesOnAppear: indicator.chartType != .geoMap,
                        selectionEnabled: indicator.chartType != .geoMap,
                        onSelect: selectRow
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
        .padding(16)
        .premiumPanel()
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

    private func totalText(for totalValue: Double) -> String {
        "Итого \(indicator.formattedNumber(totalValue))"
    }

    private func selectRow(_ rowID: IndicatorRow.ID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            selectedRowID = selectedRowID == rowID ? nil : rowID
        }
    }
}

private struct DetailGroupRowView: View {
    let group: IndicatorRowGroup
    let maxValue: Double
    let totalValue: Double
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
                Text(group.label)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

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

    private func shareText(for value: Double) -> String {
        guard totalValue > 0 else {
            return "0%"
        }

        return (value / totalValue).formatted(.percent.precision(.fractionLength(0)))
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
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Выбрать \(group.label) \(row.series ?? "Значение")")
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
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Выбрать \(group.label)")
        } else {
            singleValueRowContent
        }
    }

    private func groupedSeriesRowContent(_ row: IndicatorRow) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            valueHeader(
                title: row.series ?? "Значение",
                value: row.value,
                color: segmentColor(for: row)
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
            valueHeader(title: group.label, value: group.totalValue, color: groupColor)
            progressBar(value: group.totalValue, color: groupColor)
        }
    }

    private func valueHeader(title: String, value: Double, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)

                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(indicator.formattedNumber(value))
                    .font(.body.monospacedDigit().weight(.bold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())

                Text(shareText(for: value))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
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

    private func segmentColor(for row: IndicatorRow) -> Color {
        indicator.chartColor(for: row, scheme: chartPaletteScheme)
    }
}
