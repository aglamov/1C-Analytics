import SwiftUI

struct LinearProgressIndicatorView: View {
    let indicator: Indicator
    @Environment(\.chartPaletteScheme) private var chartPaletteScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Выполнено")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(currentValueText)
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(indicator.valueColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 8)

                Text(progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(paletteColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(paletteColor.opacity(0.11), in: Capsule())
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(paletteColor.opacity(0.18))

                    Capsule()
                        .fill(paletteColor)
                        .frame(width: proxy.size.width * progress)
                        .overlay {
                            LinearGradient(
                                colors: [.white.opacity(0.18), .clear, .black.opacity(0.14)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .clipShape(Capsule())
                        }
                }
            }
            .frame(height: 10)

            HStack {
                Text("0")
                Spacer()
                Text("Цель: \(maximumValueText)")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(indicator.title)
        .accessibilityValue(accessibilityValue)
    }

    private var progress: Double {
        guard let valueMax = indicator.valueMax, valueMax > 0, let value = indicator.value else {
            return 0
        }

        return min(max(NSDecimalNumber(decimal: value).doubleValue / valueMax, 0), 1)
    }

    private var paletteColor: Color {
        indicator.paletteColor(scheme: chartPaletteScheme)
    }

    private var currentValueText: String {
        if let valueLabel = indicator.rows.first?.valueLabel {
            return valueLabel
        }

        guard let value = indicator.value else {
            return "Нет данных"
        }

        return indicator.formattedNumber(value)
    }

    private var maximumValueText: String {
        guard let valueMax = indicator.valueMax else {
            return "—"
        }

        return indicator.formattedNumber(valueMax)
    }

    private var accessibilityValue: String {
        guard let value = indicator.value, let valueMax = indicator.valueMax else {
            return "Нет данных"
        }

        return "\(indicator.formattedNumber(value)) из \(indicator.formattedNumber(valueMax))"
    }
}

struct GaugeIndicatorView: View {
    let indicator: Indicator
    var animationTrigger = ""
    @State private var displayedProgress = 0.0
    @State private var hasAppeared = false
    @State private var isVisible = false
    @Environment(\.chartPaletteScheme) private var chartPaletteScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let lineWidth = max(14, size * 0.09)

            ZStack {
                Circle()
                    .trim(from: 0.125, to: 0.875)
                    .stroke(
                        paletteColor.opacity(0.13),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))

                Circle()
                    .trim(from: 0.125, to: 0.125 + 0.75 * displayedProgress)
                    .stroke(
                        AngularGradient(
                            colors: [
                                paletteColor.opacity(0.52),
                                paletteColor
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))

                ForEach(0..<11, id: \.self) { tick in
                    Capsule()
                        .fill(tick <= Int(displayedProgress * 10) ? paletteColor : Color.secondary.opacity(0.22))
                        .frame(width: 2, height: tick.isMultiple(of: 5) ? 9 : 5)
                        .offset(y: -(size * 0.38))
                        .rotationEffect(.degrees(-135 + Double(tick) * 27))
                }

                Capsule()
                    .fill(indicator.valueColor)
                    .frame(width: 4, height: size * 0.29)
                    .offset(y: -(size * 0.145))
                    .rotationEffect(.degrees(-135 + 270 * displayedProgress))

                Circle()
                    .fill(paletteColor)
                    .frame(width: 15, height: 15)
                    .overlay {
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 5, height: 5)
                    }

                VStack(spacing: 7) {
                    Spacer()

                    Text(displayedProgress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(indicator.valueColor)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: displayedProgress))

                    if let value = indicator.value, let valueMax = indicator.valueMax {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            gaugeValue(
                                title: "Сейчас",
                                value: indicator.rows.first?.valueLabel ?? indicator.formattedNumber(value),
                                alignment: .leading
                            )

                            Spacer(minLength: 8)

                            gaugeValue(
                                title: "Цель",
                                value: indicator.formattedNumber(valueMax),
                                alignment: .trailing
                            )
                        }
                    }
                }
                .padding(.horizontal, max(14, size * 0.09))
                .padding(.bottom, max(2, size * 0.015))
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 8)
        .onAppear {
            isVisible = true
            animateIfNeeded()
        }
        .onDisappear {
            isVisible = false
        }
        .onChange(of: animationTrigger) { _, _ in
            prepareReplayAnimation()
        }
        .onChange(of: accessibilityReduceMotion) { _, reduceMotion in
            if reduceMotion {
                showFinalStateWithoutAnimation()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(indicator.title)
        .accessibilityValue(accessibilityValue)
    }

    private var progress: Double {
        guard let valueMax = indicator.valueMax, valueMax > 0, let value = indicator.value else {
            return 0
        }

        return min(max(NSDecimalNumber(decimal: value).doubleValue / valueMax, 0), 1)
    }

    private var paletteColor: Color {
        indicator.paletteColor(scheme: chartPaletteScheme)
    }

    private func animateIfNeeded() {
        guard !hasAppeared else {
            return
        }
        guard !accessibilityReduceMotion else {
            showFinalStateWithoutAnimation()
            return
        }

        withAnimation(.easeOut(duration: 0.85)) {
            displayedProgress = progress
            hasAppeared = true
        }
    }

    private func prepareReplayAnimation() {
        guard !accessibilityReduceMotion else {
            showFinalStateWithoutAnimation()
            return
        }

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            displayedProgress = 0
            hasAppeared = false
        }

        guard isVisible else {
            return
        }

        Task { @MainActor in
            await Task.yield()
            guard isVisible else {
                return
            }
            animateIfNeeded()
        }
    }

    private func showFinalStateWithoutAnimation() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            displayedProgress = progress
            hasAppeared = true
        }
    }

    private func gaugeValue(
        title: String,
        value: String,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var accessibilityValue: String {
        guard let value = indicator.value, let valueMax = indicator.valueMax else {
            return "Нет данных"
        }

        return "\(indicator.formattedNumber(value)) из \(indicator.formattedNumber(valueMax))"
    }
}

