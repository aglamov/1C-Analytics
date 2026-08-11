import SwiftUI

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)

            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var gradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.06, green: 0.07, blue: 0.08),
                Color(red: 0.08, green: 0.09, blue: 0.10),
                Color(red: 0.07, green: 0.08, blue: 0.08)
            ]
        }

        return [
            Color(red: 0.95, green: 0.96, blue: 0.96),
            Color(red: 0.91, green: 0.93, blue: 0.94),
            Color(red: 0.96, green: 0.96, blue: 0.94)
        ]
    }
}

struct PremiumPanelModifier: ViewModifier {
    var accent: AppAccent?
    var isElevated = true
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                backgroundShape
                    .shadow(
                        color: isElevated ? .clear : directionalShadowColor,
                        radius: isElevated ? 0 : 2,
                        x: isElevated ? 0 : 6,
                        y: isElevated ? 0 : 6
                    )
                    .shadow(
                        color: shadowColor,
                        radius: isElevated ? 18 : 8,
                        x: isElevated ? 0 : 4,
                        y: isElevated ? 10 : 5
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(accent?.softGradient ?? LinearGradient(
                colors: [
                    Color(.secondarySystemGroupedBackground).opacity(0.96),
                    Color(.systemBackground).opacity(0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
    }

    private var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.07)
    }

    private var shadowColor: Color {
        if colorScheme == .dark {
            return .black.opacity(isElevated ? 0.28 : 0.30)
        }

        return .black.opacity(isElevated ? 0.08 : 0.12)
    }

    private var directionalShadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.42) : .black.opacity(0.16)
    }
}

extension View {
    func premiumPanel(accent: AppAccent? = nil, isElevated: Bool = true) -> some View {
        modifier(PremiumPanelModifier(accent: accent, isElevated: isElevated))
    }

    func subtleTextShadow() -> some View {
        modifier(SubtleTextShadowModifier())
    }
}

private struct SubtleTextShadowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.shadow(
            color: .black.opacity(colorScheme == .dark ? 0.28 : 0.14),
            radius: 2,
            x: 0,
            y: 1
        )
    }
}

struct IndicatorCard: View {
    let indicator: Indicator
    @Environment(\.chartPaletteScheme) private var chartPaletteScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(indicator.paletteColor(scheme: chartPaletteScheme), in: RoundedRectangle(cornerRadius: 8))

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(indicator.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if indicator.showsAggregateValue {
                    Text(valueText)
                        .font(.system(.largeTitle, design: .default).weight(.semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(indicator.valueColor)
                }
            }

        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)
        .premiumPanel()
    }

    private var valueText: String {
        guard let value = indicator.value else {
            return "нет данных"
        }

        return indicator.formattedValueWithUnit(value)
    }

    private var iconName: String {
        switch indicator.chartType {
        case .bar, .compactBar, .horizontalBar, .stackedBar:
            "chart.bar.fill"
        case .donut, .percentDonut:
            "chart.pie.fill"
        case .line, .splineLine, .forecastLine, .radar:
            "chart.xyaxis.line"
        case .area, .splineArea:
            "chart.xyaxis.line"
        case .oneValue:
            "waveform.path.ecg"
        case .linearProgress:
            "chart.xyaxis.line"
        case .gauge:
            "gauge.with.dots.needle.67percent"
        case .geoMap:
            "map.fill"
        case .expandableHierarchy:
            "chart.bar.doc.horizontal.fill"
        }
    }

}

struct IndicatorHero: View {
    let indicator: Indicator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(indicator.title)
                .font(.title2.weight(.bold))
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if indicator.showsAggregateValueInHeader,
               let value = indicator.value {
                Text(indicator.formattedValueWithUnit(value))
                    .font(.system(.largeTitle, design: .default).weight(.semibold))
                    .foregroundStyle(indicator.valueColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.75)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .premiumPanel()
    }

}
