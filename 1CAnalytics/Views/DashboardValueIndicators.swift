import SwiftUI

struct ContractPlanFactView: View {
    let indicator: Indicator
    @Environment(\.chartPaletteScheme) private var chartPaletteScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(indicator.contractPlanFactCategories) { category in
                VStack(alignment: .leading, spacing: 12) {
                    Text(category.label)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .textCase(.uppercase)

                    ForEach(category.periods) { periodRows in
                        ContractPlanFactPeriodSummary(
                            indicator: indicator,
                            periodRows: periodRows,
                            planColor: planColor(for: periodRows),
                            paidColor: paidColor(for: periodRows)
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func planColor(for periodRows: ContractPlanFactPeriodRows) -> Color {
        periodRows.planRow.map(barColor(for:)) ?? indicator.paletteColor(scheme: chartPaletteScheme)
    }

    private func paidColor(for periodRows: ContractPlanFactPeriodRows) -> Color {
        guard let paidRow = periodRows.paidRow else {
            return ChartPalette.colors(for: chartPaletteScheme).dropFirst().first
                ?? indicator.paletteColor(scheme: chartPaletteScheme)
        }
        return barColor(for: paidRow)
    }

    private func barColor(for row: IndicatorRow) -> Color {
        let colors = ChartPalette.colors(for: chartPaletteScheme)
        guard !colors.isEmpty else {
            return indicator.paletteColor(scheme: chartPaletteScheme)
        }
        return colors[row.isContractPlanMetric ? 0 : min(1, colors.count - 1)]
    }
}

private struct ContractPlanFactPeriodSummary: View {
    let indicator: Indicator
    let periodRows: ContractPlanFactPeriodRows
    let planColor: Color
    let paidColor: Color
    @Environment(\.chartPaletteScheme) private var chartPaletteScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(periodRows.period.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(periodColor)

                Spacer(minLength: 8)

                if let completionRatio = periodRows.completionRatio {
                    Text(completionRatio.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(periodColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(periodColor.opacity(0.14), in: Capsule())
                }
            }

            HStack(alignment: .top, spacing: 10) {
                metric(
                    title: "План",
                    row: periodRows.planRow,
                    color: planColor
                )

                Divider()

                metric(
                    title: "Оплачено",
                    row: periodRows.paidRow,
                    color: paidColor
                )
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(planColor.opacity(0.16))

                    RoundedRectangle(cornerRadius: 6)
                        .fill(paidColor)
                        .frame(
                            width: geometry.size.width
                                * min(max(periodRows.completionRatio ?? 0, 0), 1)
                        )
                }
            }
            .frame(height: 10)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    periodColor.opacity(0.12),
                    periodColor.opacity(0.035)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(periodColor.opacity(0.24), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var periodColor: Color {
        periodRows.period.contractPlanFactColor(in: chartPaletteScheme)
    }

    private func metric(title: String, row: IndicatorRow?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(displayValue(for: row))
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(row.map(indicator.valueColor(for:)) ?? .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func displayValue(for row: IndicatorRow?) -> String {
        guard let row else {
            return "—"
        }
        return row.valueLabel ?? indicator.formattedNumber(row.value)
    }
}

extension ContractPlanFactPeriod {
    func contractPlanFactColor(in scheme: ChartPaletteScheme) -> Color {
        let colors = ChartPalette.colors(for: scheme)

        switch self {
        case .current:
            return colors.first ?? Color(red: 0.02, green: 0.55, blue: 0.45)
        case .previous:
            return colors.dropFirst().first ?? Color(red: 0.48, green: 0.35, blue: 0.72)
        }
    }
}

struct CompactBarValues: View {
    let indicator: Indicator
    @Environment(\.chartPaletteScheme) private var chartPaletteScheme

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 132), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(indicator.orderedRows) { row in
                HStack(spacing: 8) {
                    Circle()
                        .fill(indicator.chartColor(for: row, scheme: chartPaletteScheme))
                        .frame(width: 8, height: 8)

                    Text(row.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .subtleTextShadow()

                    Spacer(minLength: 4)

                    Text(row.valueLabel ?? indicator.formattedNumber(row.value))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .subtleTextShadow()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

}

struct OneValueDashboardContent: View {
    let indicator: Indicator
    var reservesDetailButtonSpace = false
    @ScaledMetric(relativeTo: .largeTitle) private var valueFontSize: CGFloat = 38
    @Environment(\.chartPaletteScheme) private var chartPaletteScheme

    var body: some View {
        ZStack(alignment: .trailing) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 92, weight: .bold))
                .foregroundStyle(paletteColor.opacity(0.07))
                .offset(x: 8, y: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    Text(indicator.title)
                        .font(.headline.weight(.bold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .subtleTextShadow()

                    Spacer(minLength: 0)
                }
                .padding(.trailing, reservesDetailButtonSpace && indicator.supportsDetail ? 42 : 0)

                if indicator.showsAggregateValue {
                    Text(valueText)
                        .font(.system(size: valueFontSize, weight: .bold, design: .rounded))
                        .foregroundStyle(indicator.valueColor)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.58)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .subtleTextShadow()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var valueText: String {
        if let valueLabel = indicator.rows.first?.valueLabel {
            return valueLabel
        }

        guard let value = indicator.value else {
            return "нет данных"
        }

        return indicator.formattedValueWithUnit(value)
    }

    private var paletteColor: Color {
        indicator.paletteColor(scheme: chartPaletteScheme)
    }
}

