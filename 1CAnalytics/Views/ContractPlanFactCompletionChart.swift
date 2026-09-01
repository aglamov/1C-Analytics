import Charts
import SwiftUI

struct ContractPlanFactCompletionChart: View {
    let indicator: Indicator
    @State private var selectedPointID: ContractPlanFactCompletionPoint.ID?
    @Environment(\.chartPaletteScheme) private var chartPaletteScheme
    @Environment(\.dashboardContentScale) private var contentScale

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
        VStack(alignment: .leading, spacing: 14 * contentScale) {
            if overviewTitle != nil || overviewSubtitle != nil {
                VStack(alignment: .leading, spacing: 3 * contentScale) {
                    if let overviewTitle {
                        Text(overviewTitle)
                            .font(.title3.weight(.bold))
                    }
                    if let overviewSubtitle {
                        Text(overviewSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
                    if indicator.showGrid != false {
                        AxisGridLine()
                            .foregroundStyle(.secondary.opacity(0.16))
                    }
                    AxisTick()

                    AxisValueLabel {
                        if let ratio = value.as(Double.self) {
                            Text(ratio.formatted(.percent.precision(.fractionLength(0))))
                        }
                    }
                }
            }
            .chartXAxis {
                if indicator.showsXAxisLabels {
                    AxisMarks { value in
                        if indicator.showGrid != false {
                            AxisGridLine()
                                .foregroundStyle(.secondary.opacity(0.16))
                        }
                        AxisValueLabel()
                    }
                } else if indicator.showGrid != false {
                    AxisMarks { _ in
                        AxisGridLine()
                            .foregroundStyle(.secondary.opacity(0.16))
                    }
                }
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                chartTapOverlay(proxy: proxy)
            }
            .frame(height: 220 * contentScale)
            .accessibilityLabel("Выполнение плана по контрактам")

            if indicator.showsPlanFactPresentationLegend {
                HStack(spacing: 16 * contentScale) {
                    ForEach(periods) { period in
                        HStack(spacing: 6 * contentScale) {
                            Capsule()
                                .fill(barGradient(for: period))
                                .frame(width: 18 * contentScale, height: 8 * contentScale)

                            Text(period.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selectedPointID)
        .onDisappear {
            selectedPointID = nil
        }
    }

    private var overviewTitle: String? {
        indicator.overviewTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private var overviewSubtitle: String? {
        indicator.overviewSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private struct ContractPlanFactCompletionPoint: Identifiable {
    let category: String
    let period: ContractPlanFactPeriod
    let ratio: Double

    var id: String {
        "\(category)-\(period.rawValue)"
    }
}
