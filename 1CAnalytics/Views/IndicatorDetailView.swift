import SwiftUI

struct IndicatorDetailView: View {
    let indicator: Indicator
    @State private var selectedRowID: IndicatorRow.ID?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { proxy in
            let usesSplitLayout = horizontalSizeClass == .regular && proxy.size.width > proxy.size.height

            ScrollView {
                detailContent(usesSplitLayout: usesSplitLayout)
                    .padding(.horizontal, horizontalSizeClass == .regular ? 20 : 16)
                    .padding(.vertical, 16)
            }
        }
        .background(AppBackground())
        .navigationTitle(indicator.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            selectedRowID = nil
        }
    }

    @ViewBuilder
    private func detailContent(usesSplitLayout: Bool) -> some View {
        if usesSplitLayout {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    IndicatorHero(indicator: indicator)
                    chartSection(usesSplitLayout: usesSplitLayout)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                rowsSection
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                IndicatorHero(indicator: indicator)
                chartSection(usesSplitLayout: usesSplitLayout)
                rowsSection
            }
        }
    }

    private func chartSection(usesSplitLayout: Bool) -> some View {
        AnalyticsChart(indicator: indicator, showsLegend: false, selectedRowID: $selectedRowID)
            .frame(maxWidth: .infinity)
            .aspectRatio(usesSplitLayout ? 1.15 : 1.0, contentMode: .fit)
    }

    private var rowsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Детализация")
                        .font(.title3.weight(.bold))

                    Text("Ранжирование групп по значению")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(totalText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(indicator.accent.primary)
            }

            VStack(spacing: 10) {
                ForEach(rankedGroups) { group in
                    DetailGroupRowView(
                        group: group,
                        maxValue: maxValue,
                        totalValue: totalValue,
                        accent: indicator.accent,
                        selectedRowID: selectedRowID,
                        onSelect: selectRow
                    )
                }
            }
        }
        .padding(16)
        .premiumPanel(accent: indicator.accent)
    }

    private var rankedGroups: [IndicatorRowGroup] {
        Dictionary(grouping: indicator.orderedRows, by: \.label)
            .map { label, rows in
                IndicatorRowGroup(label: label, rows: rows.sortedByOrder())
            }
            .sorted {
                if $0.totalValue == $1.totalValue {
                    return $0.label < $1.label
                }

                return $0.totalValue > $1.totalValue
            }
    }

    private var maxValue: Double {
        rankedGroups.map(\.totalValue).max() ?? 0
    }

    private var totalValue: Double {
        rankedGroups.reduce(0) { $0 + $1.totalValue }
    }

    private var totalText: String {
        "Итого \(totalValue.formatted(.number.precision(.fractionLength(0))))"
    }

    private func selectRow(_ rowID: IndicatorRow.ID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            selectedRowID = selectedRowID == rowID ? nil : rowID
        }
    }
}

private struct IndicatorRowGroup: Identifiable {
    let label: String
    let rows: [IndicatorRow]

    var id: String {
        label
    }

    var totalValue: Double {
        rows.reduce(0) { $0 + $1.value }
    }

    var selectedFallbackRowID: IndicatorRow.ID? {
        rows.first?.id
    }
}

private struct DetailGroupRowView: View {
    let group: IndicatorRowGroup
    let maxValue: Double
    let totalValue: Double
    let accent: AppAccent
    let selectedRowID: IndicatorRow.ID?
    let onSelect: (IndicatorRow.ID) -> Void
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.label)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isSelected ? accent.primary : .primary)
                        .lineLimit(1)

                    if group.rows.count > 1 {
                        Text(seriesSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(group.totalValue.formatted(.number.precision(.fractionLength(0))))
                        .font((isSelected ? Font.title3 : Font.body).monospacedDigit().weight(.bold))
                        .foregroundStyle(isSelected ? accent.primary : .primary)
                        .contentTransition(.numericText())

                    Text(shareText)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemGroupedBackground))

                    HStack(spacing: 2) {
                        ForEach(group.rows) { row in
                            Button {
                                onSelect(row.id)
                            } label: {
                                segmentView(for: row)
                            }
                            .buttonStyle(.plain)
                            .frame(width: segmentWidth(for: row, availableWidth: proxy.size.width))
                            .accessibilityLabel("Выбрать \(group.label) \(row.series ?? "")")
                        }
                    }
                    .frame(width: proxy.size.width * progress, alignment: .leading)
                    .clipShape(Capsule())
                }
            }
            .frame(height: group.rows.count > 1 ? 28 : 10)
        }
        .padding(14)
        .background(isSelected ? accent.primary.opacity(0.12) : .white.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? accent.primary.opacity(0.35) : .clear, lineWidth: 1)
        }
        .scaleEffect(isSelected ? 1.015 : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isSelected)
        .onAppear {
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

    private var progress: Double {
        guard maxValue > 0, hasAppeared else {
            return 0
        }

        return group.totalValue / maxValue
    }

    private var shareText: String {
        guard totalValue > 0 else {
            return "0%"
        }

        return (group.totalValue / totalValue).formatted(.percent.precision(.fractionLength(0)))
    }

    private var seriesSummary: String {
        group.rows
            .map { row in
                "\(row.series ?? "Значение") \(row.value.formatted(.number.notation(.compactName).precision(.fractionLength(0))))"
            }
            .joined(separator: " / ")
    }

    private func segmentWidth(for row: IndicatorRow, availableWidth: CGFloat) -> CGFloat {
        guard group.totalValue > 0 else {
            return 0
        }

        return availableWidth * progress * (row.value / group.totalValue)
    }

    private func segmentView(for row: IndicatorRow) -> some View {
        let isSegmentSelected = selectedRowID == row.id

        return ZStack {
            Rectangle()
                .fill(segmentColor(for: row).opacity(isSegmentSelected ? 1 : 0.86))

            if group.rows.count > 1 {
                HStack(spacing: 4) {
                    Text(row.series ?? "Значение")
                        .lineLimit(1)

                    Text(row.value.formatted(.number.notation(.compactName).precision(.fractionLength(0))))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 5)
            }
        }
        .overlay {
            if isSegmentSelected {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white.opacity(0.85), lineWidth: 1.5)
                    .padding(1)
            }
        }
    }

    private func segmentColor(for row: IndicatorRow) -> Color {
        let rows = group.rows
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else {
            return accent.primary
        }

        return index.isMultiple(of: 2) ? accent.primary : accent.secondary
    }
}
