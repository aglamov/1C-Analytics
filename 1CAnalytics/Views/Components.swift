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
    case corporate

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .playful:
            "Веселая"
        case .corporate:
            "Корп."
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .playful:
            "Веселая цветовая схема"
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

extension Color {
    init?(apiHex value: String?) {
        guard var value = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !value.isEmpty else {
            return nil
        }

        if value.hasPrefix("#") {
            value.removeFirst()
        } else if value.hasPrefix("0x") {
            value.removeFirst(2)
        }

        guard value.count == 6 || value.count == 8,
              let hex = UInt64(value, radix: 16) else {
            return nil
        }

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        if value.count == 8 {
            red = Double((hex >> 24) & 0xff) / 255
            green = Double((hex >> 16) & 0xff) / 255
            blue = Double((hex >> 8) & 0xff) / 255
            alpha = Double(hex & 0xff) / 255
        } else {
            red = Double((hex >> 16) & 0xff) / 255
            green = Double((hex >> 8) & 0xff) / 255
            blue = Double(hex & 0xff) / 255
            alpha = 1
        }

        self.init(red: red, green: green, blue: blue, opacity: alpha)
    }
}

extension Indicator {
    var chartColorDomain: [String] {
        switch chartType {
        case .stackedBar:
            orderedRows.uniqueValues { $0.series ?? "Значение" }
        case .bar where !barDataShape.series.isEmpty,
             .horizontalBar where !barDataShape.series.isEmpty:
            barDataShape.series
        case .bar, .compactBar, .horizontalBar, .donut:
            orderedRows.uniqueValues(\.label)
        case .oneValue, .linearProgress, .gauge, .geoMap:
            []
        }
    }

    func chartColor(for row: IndicatorRow, scheme: ChartPaletteScheme) -> Color {
        if let apiColor = Color(apiHex: row.colorGraph ?? colorGraph) {
            return apiColor
        }

        let key: String
        switch chartType {
        case .stackedBar:
            key = row.series ?? "Значение"
        case .bar where !barDataShape.series.isEmpty,
             .horizontalBar where !barDataShape.series.isEmpty:
            key = row.series ?? "Значение"
        case .bar, .compactBar, .horizontalBar, .donut:
            key = row.label
        case .oneValue, .linearProgress, .gauge, .geoMap:
            return accent.primary
        }

        return ChartPalette.color(for: key, in: chartColorDomain, scheme: scheme, fallback: accent.primary)
    }

    func chartColor(forGroupLabel label: String, scheme: ChartPaletteScheme) -> Color {
        if let rowColor = orderedRows.first(where: { $0.label == label })?.colorGraph,
           let apiColor = Color(apiHex: rowColor) {
            return apiColor
        }
        if let apiColor = Color(apiHex: colorGraph) {
            return apiColor
        }

        return ChartPalette.color(
            for: label,
            in: orderedRows.uniqueValues(\.label),
            scheme: scheme,
            fallback: accent.primary
        )
    }

    var graphColor: Color {
        Color(apiHex: colorGraph) ?? accent.primary
    }

    var valueColor: Color {
        Color(apiHex: colorValue) ?? .primary
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
                    .background(indicator.graphColor, in: RoundedRectangle(cornerRadius: 8))

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(indicator.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

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

        return "\(value.formatted(.number.grouping(.automatic))) \(indicator.unit ?? "")"
    }

    private var iconName: String {
        switch indicator.chartType {
        case .bar, .compactBar, .horizontalBar, .stackedBar:
            "chart.bar.fill"
        case .donut:
            "chart.pie.fill"
        case .oneValue:
            "waveform.path.ecg"
        case .linearProgress:
            "chart.xyaxis.line"
        case .gauge:
            "gauge.with.dots.needle.67percent"
        case .geoMap:
            "map.fill"
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
                    .background(indicator.graphColor, in: RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 5) {
                    Text(indicator.title)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            if indicator.showsAggregateValue, let value = indicator.value {
                Text("\(value.formatted(.number.grouping(.automatic))) \(indicator.unit ?? "")")
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

    private var iconName: String {
        switch indicator.chartType {
        case .bar, .compactBar, .horizontalBar, .stackedBar:
            "chart.bar.fill"
        case .donut:
            "chart.pie.fill"
        case .oneValue:
            "waveform.path.ecg"
        case .linearProgress:
            "chart.xyaxis.line"
        case .gauge:
            "gauge.with.dots.needle.67percent"
        case .geoMap:
            "map.fill"
        }
    }
}

struct DashboardConnectionBar: View {
    let date: Date?
    var isCached = false
    var isRefreshing = false

    var body: some View {
        HStack(spacing: 8) {
            if isCached {
                cachedContent
            } else {
                currentContent
            }

            Spacer(minLength: 8)

            Color.clear
                .frame(width: 16, height: 16)
                .overlay {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Обновление данных")
                    }
                }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        .frame(minHeight: 44)
        .animation(.easeInOut(duration: 0.2), value: isRefreshing)
    }

    private var currentContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text(dateText)
        }
    }

    private var cachedContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "icloud.slash.fill")
                .foregroundStyle(.orange)

            Text(cachedDateText)
        }
    }

    private var dateText: String {
        guard let date else {
            return "Срез не указан"
        }

        return "Данные актуальны на \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var cachedDateText: String {
        guard let date else {
            return "Дата последнего обновления неизвестна"
        }

        return "Последнее обновление: \(date.formatted(date: .abbreviated, time: .shortened))"
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
