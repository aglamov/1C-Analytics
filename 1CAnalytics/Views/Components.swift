import SwiftUI

enum AppAccent {
    case blue
    case green
    case violet
    case orange

    var primary: Color {
        switch self {
        case .blue:
            Color(red: 0.13, green: 0.30, blue: 0.48)
        case .green:
            Color(red: 0.13, green: 0.43, blue: 0.36)
        case .violet:
            Color(red: 0.35, green: 0.31, blue: 0.48)
        case .orange:
            Color(red: 0.58, green: 0.35, blue: 0.18)
        }
    }

    var secondary: Color {
        switch self {
        case .blue:
            Color(red: 0.34, green: 0.49, blue: 0.62)
        case .green:
            Color(red: 0.39, green: 0.56, blue: 0.49)
        case .violet:
            Color(red: 0.49, green: 0.45, blue: 0.61)
        case .orange:
            Color(red: 0.67, green: 0.50, blue: 0.31)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [primary, primary.opacity(0.82)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var softGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(.secondarySystemGroupedBackground).opacity(0.98),
                primary.opacity(0.06),
                Color(.systemBackground).opacity(0.90)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

enum ChartPaletteScheme: String, CaseIterable, Identifiable {
    case playful
    case stylish
    case corporate

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .playful:
            "Веселая"
        case .stylish:
            "Стильная"
        case .corporate:
            "Корп."
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .playful:
            "Веселая цветовая схема"
        case .stylish:
            "Стильная цветовая схема"
        case .corporate:
            "Корпоративная цветовая схема"
        }
    }
}

private struct ChartPaletteSchemeKey: EnvironmentKey {
    static let defaultValue: ChartPaletteScheme = .corporate
}

extension EnvironmentValues {
    var chartPaletteScheme: ChartPaletteScheme {
        get { self[ChartPaletteSchemeKey.self] }
        set { self[ChartPaletteSchemeKey.self] = newValue }
    }
}

enum ChartPalette {
    static func colors(for scheme: ChartPaletteScheme) -> [Color] {
        switch scheme {
        case .playful:
            [
                Color(red: 0.00, green: 0.48, blue: 1.00),
                Color(red: 0.00, green: 0.73, blue: 0.52),
                Color(red: 1.00, green: 0.58, blue: 0.12),
                Color(red: 0.58, green: 0.34, blue: 0.98),
                Color(red: 0.96, green: 0.27, blue: 0.51),
                Color(red: 0.13, green: 0.75, blue: 0.92),
                Color(red: 0.69, green: 0.78, blue: 0.14),
                Color(red: 1.00, green: 0.78, blue: 0.20)
            ]
        case .stylish:
            [
                Color(red: 0.18, green: 0.27, blue: 0.38),
                Color(red: 0.53, green: 0.43, blue: 0.32),
                Color(red: 0.31, green: 0.44, blue: 0.42),
                Color(red: 0.45, green: 0.37, blue: 0.48),
                Color(red: 0.66, green: 0.47, blue: 0.37),
                Color(red: 0.36, green: 0.45, blue: 0.57),
                Color(red: 0.48, green: 0.52, blue: 0.42),
                Color(red: 0.57, green: 0.44, blue: 0.45)
            ]
        case .corporate:
            [
                Color(red: 0.13, green: 0.30, blue: 0.48),
                Color(red: 0.13, green: 0.43, blue: 0.36),
                Color(red: 0.58, green: 0.35, blue: 0.18),
                Color(red: 0.35, green: 0.31, blue: 0.48),
                Color(red: 0.39, green: 0.49, blue: 0.62),
                Color(red: 0.67, green: 0.50, blue: 0.31),
                Color(red: 0.38, green: 0.43, blue: 0.36),
                Color(red: 0.52, green: 0.39, blue: 0.43)
            ]
        }
    }

    static func color(for key: String, in domain: [String], scheme: ChartPaletteScheme, fallback: Color) -> Color {
        let colors = colors(for: scheme)
        guard let index = domain.firstIndex(of: key), !colors.isEmpty else {
            return fallback
        }

        return colors[index % colors.count]
    }
}

extension Indicator {
    var chartColorDomain: [String] {
        switch chartType {
        case .stackedBar:
            orderedRows.uniqueValues { $0.series ?? "Значение" }
        case .bar, .horizontalBar, .donut:
            orderedRows.uniqueValues(\.label)
        }
    }

    func chartColor(for row: IndicatorRow, scheme: ChartPaletteScheme) -> Color {
        let key: String
        switch chartType {
        case .stackedBar:
            key = row.series ?? "Значение"
        case .bar, .horizontalBar, .donut:
            key = row.label
        }

        return ChartPalette.color(for: key, in: chartColorDomain, scheme: scheme, fallback: accent.primary)
    }

    func chartColor(forGroupLabel label: String, scheme: ChartPaletteScheme) -> Color {
        ChartPalette.color(for: label, in: orderedRows.uniqueValues(\.label), scheme: scheme, fallback: accent.primary)
    }
}

private extension Array where Element == IndicatorRow {
    func uniqueValues(_ transform: (IndicatorRow) -> String) -> [String] {
        reduce(into: [String]()) { values, row in
            let value = transform(row)
            if !values.contains(value) {
                values.append(value)
            }
        }
    }

    func uniqueValues(_ keyPath: KeyPath<IndicatorRow, String>) -> [String] {
        uniqueValues { $0[keyPath: keyPath] }
    }
}

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
            .background(backgroundShape)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: 1)
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

    private var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.07)
    }

    private var shadowColor: Color {
        if colorScheme == .dark {
            return .black.opacity(isElevated ? 0.28 : 0.16)
        }

        return .black.opacity(isElevated ? 0.08 : 0.04)
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
                    .background(indicator.accent.primary, in: RoundedRectangle(cornerRadius: 8))

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(indicator.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(valueText)
                    .font(.system(.largeTitle, design: .default).weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(.primary)
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
                    .background(indicator.accent.primary, in: RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 5) {
                    Text(indicator.title)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            if let value = indicator.value {
                Text("\(value.formatted(.number.grouping(.automatic))) \(indicator.unit ?? "")")
                    .font(.system(.largeTitle, design: .default).weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.75)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .premiumPanel()
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
