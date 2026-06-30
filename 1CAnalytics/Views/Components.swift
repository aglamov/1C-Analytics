import SwiftUI

enum AppAccent {
    case blue
    case green
    case violet
    case orange

    var primary: Color {
        switch self {
        case .blue:
            Color(red: 0.10, green: 0.36, blue: 0.95)
        case .green:
            Color(red: 0.02, green: 0.55, blue: 0.40)
        case .violet:
            Color(red: 0.45, green: 0.22, blue: 0.88)
        case .orange:
            Color(red: 0.88, green: 0.38, blue: 0.10)
        }
    }

    var secondary: Color {
        switch self {
        case .blue:
            Color(red: 0.08, green: 0.69, blue: 0.84)
        case .green:
            Color(red: 0.56, green: 0.74, blue: 0.18)
        case .violet:
            Color(red: 0.88, green: 0.28, blue: 0.61)
        case .orange:
            Color(red: 0.96, green: 0.69, blue: 0.18)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [primary, secondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var softGradient: LinearGradient {
        LinearGradient(
            colors: [
                primary.opacity(0.18),
                secondary.opacity(0.10),
                Color(.secondarySystemGroupedBackground).opacity(0.88)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)

            LinearGradient(
                colors: [
                    Color(red: 0.92, green: 0.97, blue: 1.00),
                    Color(red: 0.96, green: 0.94, blue: 1.00),
                    Color(red: 1.00, green: 0.97, blue: 0.91)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

struct PremiumPanelModifier: ViewModifier {
    var accent: AppAccent?
    var isElevated = true

    func body(content: Content) -> some View {
        content
            .background(backgroundShape)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: isElevated ? 18 : 8, x: 0, y: isElevated ? 10 : 4)
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

    private var shadowColor: Color {
        (accent?.primary ?? .black).opacity(isElevated ? 0.14 : 0.08)
    }
}

extension View {
    func premiumPanel(accent: AppAccent? = nil, isElevated: Bool = true) -> some View {
        modifier(PremiumPanelModifier(accent: accent, isElevated: isElevated))
    }
}

struct IndicatorCard: View {
    let indicator: Indicator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(indicator.accent.gradient, in: RoundedRectangle(cornerRadius: 8))

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(indicator.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(valueText)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(.primary)
            }

            Text(indicator.source ?? "Источник не указан")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)
        .premiumPanel(accent: indicator.accent)
    }

    private var valueText: String {
        guard let value = indicator.value else {
            return "нет данных"
        }

        return "\(value.formatted(.number.grouping(.automatic))) \(indicator.unit ?? "")"
    }

    private var iconName: String {
        switch indicator.chartType {
        case .bar, .horizontalBar, .stackedBar:
            "chart.bar.fill"
        case .donut:
            "chart.pie.fill"
        }
    }

}

struct IndicatorHero: View {
    let indicator: Indicator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(indicator.accent.gradient, in: RoundedRectangle(cornerRadius: 8))
                    .shadow(color: indicator.accent.primary.opacity(0.24), radius: 12, x: 0, y: 8)

                VStack(alignment: .leading, spacing: 5) {
                    Text(indicator.title)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            if let value = indicator.value {
                Text("\(value.formatted(.number.grouping(.automatic))) \(indicator.unit ?? "")")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.75)
            }

            if let source = indicator.source {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(indicator.accent.primary)

                    Text(source)
                        .lineLimit(2)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .premiumPanel(accent: indicator.accent)
    }

    private var iconName: String {
        switch indicator.chartType {
        case .bar, .horizontalBar, .stackedBar:
            "chart.bar.fill"
        case .donut:
            "chart.pie.fill"
        }
    }
}

struct UpdatedAtBar: View {
    let date: Date?

    var body: some View {
        HStack {
            Image(systemName: "clock")
            Text(dateText)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var dateText: String {
        guard let date else {
            return "Срез не указан"
        }

        return "Обновлено \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

struct RefreshButton: View {
    let action: () async -> Void
    @State private var isRefreshing = false

    var body: some View {
        Button {
            Task {
                isRefreshing = true
                await action()
                isRefreshing = false
            }
        } label: {
            Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
        }
        .disabled(isRefreshing)
        .accessibilityLabel("Обновить")
    }
}
