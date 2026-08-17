import SwiftUI

struct ContractPlanFactView: View {
    let indicator: Indicator
    @Environment(\.chartPaletteScheme) private var chartPaletteScheme
    @Environment(\.dashboardContentScale) private var contentScale

    var body: some View {
        VStack(alignment: .leading, spacing: 22 * contentScale) {
            ForEach(indicator.contractPlanFactCategories) { category in
                VStack(alignment: .leading, spacing: 12 * contentScale) {
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
    @Environment(\.dashboardContentScale) private var contentScale

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * contentScale) {
            HStack(alignment: .center, spacing: 8 * contentScale) {
                Text(periodRows.period.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(periodColor)

                Spacer(minLength: 8)

                if let completionRatio = periodRows.completionRatio {
                    Text(completionRatio.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(periodColor)
                        .padding(.horizontal, 8 * contentScale)
                        .padding(.vertical, 4 * contentScale)
                        .background(periodColor.opacity(0.14), in: Capsule())
                }
            }

            HStack(alignment: .top, spacing: 10 * contentScale) {
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
            .frame(height: 10 * contentScale)
        }
        .padding(12 * contentScale)
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
        VStack(alignment: .leading, spacing: 3 * contentScale) {
            HStack(spacing: 5 * contentScale) {
                Circle()
                    .fill(color)
                    .frame(width: 6 * contentScale, height: 6 * contentScale)

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

struct OneValueDashboardContent: View {
    let indicator: Indicator
    var reservesDetailButtonSpace = false
    @ScaledMetric(relativeTo: .largeTitle) private var valueFontSize: CGFloat = 38
    @Environment(\.chartPaletteScheme) private var chartPaletteScheme
    @Environment(\.dashboardContentScale) private var contentScale

    var body: some View {
        ZStack(alignment: .trailing) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 92 * contentScale, weight: .bold))
                .foregroundStyle(paletteColor.opacity(0.07))
                .offset(x: 8, y: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text(indicator.title)
                        .font(.headline.weight(.bold))
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .subtleTextShadow()

                    Spacer(minLength: 0)
                }
                .padding(.trailing, reservesDetailButtonSpace && indicator.supportsDetail ? 42 : 0)

                Spacer(minLength: 4 * contentScale)

                if indicator.showsAggregateValue {
                    OneValueCountUpText(
                        animationKey: indicator.id,
                        value: indicator.value,
                        customText: indicator.rows.first?.valueLabel,
                        formatter: indicator.formattedValueWithUnit
                    )
                        .font(.system(size: valueFontSize * contentScale, weight: .bold, design: .rounded))
                        .foregroundStyle(indicator.valueColor)
                        .monospacedDigit()
                        .minimumScaleFactor(0.58)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .subtleTextShadow()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var paletteColor: Color {
        indicator.paletteColor(scheme: chartPaletteScheme)
    }
}

enum OneValueAnimationPolicy {
    static let initialDelay: Duration = .milliseconds(80)
    static let duration = 0.85

    static func fractionDigits(for value: Decimal) -> Int {
        let string = NSDecimalNumber(decimal: value).stringValue
        guard let separator = string.firstIndex(of: ".") else {
            return 0
        }

        return min(string.distance(from: string.index(after: separator), to: string.endIndex), 2)
    }

    static func roundedValue(_ value: Double, fractionDigits: Int) -> Decimal {
        let scale = pow(10, Double(max(fractionDigits, 0)))
        return Decimal((value * scale).rounded() / scale)
    }
}

@MainActor
private enum OneValueFirstAppearanceRegistry {
    private static var animatedKeys = Set<String>()

    static func contains(_ key: String) -> Bool {
        animatedKeys.contains(key)
    }

    static func claim(_ key: String) -> Bool {
        animatedKeys.insert(key).inserted
    }
}

private enum OneValueAnimationPhase {
    case unresolved
    case waiting
    case finished
}

private struct OneValueCountUpText: View {
    let animationKey: String
    let value: Decimal?
    let customText: String?
    let formatter: (Decimal) -> String

    @State private var phase = OneValueAnimationPhase.unresolved
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        displayedText
            .task {
                await runFirstAppearanceAnimationIfNeeded()
            }
            .onChange(of: accessibilityReduceMotion) { _, reduceMotion in
                if reduceMotion {
                    showFinalStateWithoutAnimation()
                }
            }
            .accessibilityLabel(finalText)
    }

    @ViewBuilder
    private var displayedText: some View {
        if let customText {
            Text(customText)
        } else if let targetValue, let value {
            OneValueInterpolatingNumberText(
                value: displaysFinalValue ? targetValue : 0,
                fractionDigits: OneValueAnimationPolicy.fractionDigits(for: value),
                formatter: formatter
            )
        } else {
            Text("нет данных")
        }
    }

    private var targetValue: Double? {
        guard let value else {
            return nil
        }

        let result = NSDecimalNumber(decimal: value).doubleValue
        return result.isFinite ? result : nil
    }

    private var displaysFinalValue: Bool {
        switch phase {
        case .finished:
            return true
        case .waiting:
            return false
        case .unresolved:
            return OneValueFirstAppearanceRegistry.contains(animationKey)
        }
    }

    private var finalText: String {
        if let customText {
            return customText
        }
        if let value {
            return formatter(value)
        }
        return "нет данных"
    }

    @MainActor
    private func runFirstAppearanceAnimationIfNeeded() async {
        let isFirstAppearance = OneValueFirstAppearanceRegistry.claim(animationKey)

        guard customText == nil, targetValue != nil else {
            showFinalStateWithoutAnimation()
            return
        }
        guard !accessibilityReduceMotion else {
            showFinalStateWithoutAnimation()
            return
        }
        guard isFirstAppearance else {
            showFinalStateWithoutAnimation()
            return
        }

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            phase = .waiting
        }

        do {
            try await Task.sleep(for: OneValueAnimationPolicy.initialDelay)
        } catch {
            return
        }

        withAnimation(.easeOut(duration: OneValueAnimationPolicy.duration)) {
            phase = .finished
        }
    }

    private func showFinalStateWithoutAnimation() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            phase = .finished
        }
    }
}

private struct OneValueInterpolatingNumberText: View, @preconcurrency Animatable {
    var value: Double
    let fractionDigits: Int
    let formatter: (Decimal) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(
            formatter(
                OneValueAnimationPolicy.roundedValue(
                    value,
                    fractionDigits: fractionDigits
                )
            )
        )
    }
}
