import SwiftUI

struct DetailGroupRowView: View {
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
        DetailPresentationPolicy.shareText(
            for: value,
            denominator: denominator,
            fractionDigits: 3
        )
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

                if indicator.showsPercentagesInDetails {
                    Text(shareText(for: value, denominator: shareDenominator))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
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
