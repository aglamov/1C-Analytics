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

enum DashboardContentScalePolicy {
    static let range = 0.8...1.3
    static let step = 0.05

    static func normalized(_ value: Double) -> Double {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return (clamped / step).rounded() * step
    }

    static func scaledDynamicTypeSize(
        from current: DynamicTypeSize,
        scale: Double
    ) -> DynamicTypeSize {
        let sizes: [(DynamicTypeSize, Double)] = [
            (.xSmall, 14), (.small, 15), (.medium, 16), (.large, 17),
            (.xLarge, 19), (.xxLarge, 21), (.xxxLarge, 23),
            (.accessibility1, 28), (.accessibility2, 33), (.accessibility3, 40),
            (.accessibility4, 47), (.accessibility5, 53)
        ]
        let base = sizes.first(where: { $0.0 == current })?.1 ?? 17
        let target = base * normalized(scale)
        return sizes.min { abs($0.1 - target) < abs($1.1 - target) }?.0 ?? current
    }
}

private struct DashboardContentScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var chartPaletteScheme: ChartPaletteScheme {
        get { self[ChartPaletteSchemeKey.self] }
        set { self[ChartPaletteSchemeKey.self] = newValue }
    }

    var dashboardContentScale: CGFloat {
        get { self[DashboardContentScaleKey.self] }
        set {
            self[DashboardContentScaleKey.self] = CGFloat(
                DashboardContentScalePolicy.normalized(Double(newValue))
            )
        }
    }
}

private struct DashboardScaledTypographyModifier: ViewModifier {
    @Environment(\.dashboardContentScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.dynamicTypeSize(
            DashboardContentScalePolicy.scaledDynamicTypeSize(
                from: dynamicTypeSize,
                scale: Double(scale)
            )
        )
    }
}

extension View {
    func dashboardScaledTypography() -> some View {
        modifier(DashboardScaledTypographyModifier())
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
            return orderedRows.uniqueValues { $0.series ?? "Значение" }
        case .line, .area, .splineLine, .splineArea, .forecastLine:
            let series = orderedRows.uniqueValues { $0.series ?? "" }.filter { !$0.isEmpty }
            return series.isEmpty ? [title] : series
        case .bar where !barDataShape.series.isEmpty,
             .horizontalBar where !barDataShape.series.isEmpty:
            return barDataShape.series
        case .bar, .compactBar, .horizontalBar, .donut, .percentDonut:
            return orderedRows.uniqueValues(\.label)
        case .oneValue, .linearProgress, .gauge, .geoMap:
            return []
        }
    }

    func chartColor(for row: IndicatorRow, scheme: ChartPaletteScheme) -> Color {
        let key: String
        switch chartType {
        case .stackedBar:
            key = row.series ?? "Значение"
        case .line, .area, .splineLine, .splineArea, .forecastLine:
            key = row.series ?? title
        case .bar where !barDataShape.series.isEmpty,
             .horizontalBar where !barDataShape.series.isEmpty:
            key = row.series ?? "Значение"
        case .bar, .compactBar, .horizontalBar, .donut, .percentDonut:
            key = row.label
        case .oneValue, .linearProgress, .gauge, .geoMap:
            return accent.primary
        }

        return ChartPalette.color(for: key, in: chartColorDomain, scheme: scheme, fallback: accent.primary)
    }

    func chartColor(forGroupLabel label: String, scheme: ChartPaletteScheme) -> Color {
        return ChartPalette.color(
            for: label,
            in: orderedRows.uniqueValues(\.label),
            scheme: scheme,
            fallback: accent.primary
        )
    }

    func paletteColor(scheme: ChartPaletteScheme) -> Color {
        ChartPalette.colors(for: scheme).first ?? accent.primary
    }

    var graphColor: Color {
        Color(apiHex: colorGraph) ?? accent.primary
    }

    var valueColor: Color {
        Color(apiHex: colorValue) ?? .primary
    }

    func valueColor(for row: IndicatorRow) -> Color {
        apiValueColor(for: row) ?? .primary
    }

    func apiValueColor(for row: IndicatorRow) -> Color? {
        Color(apiHex: row.colorValue ?? colorValue)
    }
}

extension Array where Element == IndicatorRow {
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
