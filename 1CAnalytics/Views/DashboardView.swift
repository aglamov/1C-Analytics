import MapKit
import SwiftUI

struct DashboardView: View {
    @StateObject var viewModel: DashboardViewModel
    let onSignOut: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("chartPaletteScheme") private var chartPaletteSchemeRawValue = ChartPaletteScheme.corporate.rawValue
    @State private var collapsedSectionIDs: Set<DashboardSection.ID> = []

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(viewModel.dashboard?.title ?? "Аналитика")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            DashboardSettingsView(
                                chartPalette: chartPaletteBinding,
                                onSignOut: onSignOut
                            )
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Настройки")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        RefreshButton {
                            await viewModel.refresh()
                        }
                    }
                }
        }
        .environment(\.chartPaletteScheme, chartPaletteScheme)
        .task {
            if case .idle = viewModel.state {
                await viewModel.load()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Загружаем аналитику")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView {
                Label("Не удалось загрузить данные", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Повторить") {
                    Task {
                        await viewModel.refresh()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRefreshing)
            }
        case let .loaded(dashboard):
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(dashboard.sections) { section in
                                DisclosureGroup(isExpanded: sectionExpandedBinding(for: section.id)) {
                                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                                        ForEach(section.indicators) { indicator in
                                            IndicatorDashboardCard(indicator: indicator)
                                                .overlay(alignment: .topTrailing) {
                                                    if indicator.supportsDetail {
                                                        NavigationLink {
                                                            IndicatorDetailView(indicator: indicator)
                                                        } label: {
                                                            Image(systemName: "arrow.up.right")
                                                                .font(.caption.weight(.bold))
                                                                .foregroundStyle(indicator.graphColor)
                                                                .frame(width: 30, height: 30)
                                                                .background(
                                                                    Color(.systemBackground).opacity(0.94),
                                                                    in: RoundedRectangle(cornerRadius: 8)
                                                                )
                                                                .overlay {
                                                                    RoundedRectangle(cornerRadius: 8)
                                                                        .strokeBorder(
                                                                            Color.secondary.opacity(0.12),
                                                                            lineWidth: 1
                                                                        )
                                                                }
                                                        }
                                                        .buttonStyle(.plain)
                                                        .accessibilityLabel("Открыть детализацию")
                                                        .padding(14)
                                                    }
                                                }
                                        }
                                    }
                                    .padding(.top, 12)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(section.title)
                                            .font(.title2.weight(.bold))

                                        Text(sectionCountText(section.indicators.count))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .accessibilityAddTraits(.isHeader)
                                }
                                .tint(.primary)
                            }
                        }
                        .padding(.horizontal, horizontalSizeClass == .regular ? 20 : 16)
                        .padding(.vertical, 16)
                    }
                    .background(AppBackground())

                    DashboardConnectionBar(
                        date: dashboard.fetchedAt,
                        isCached: viewModel.isShowingCachedData,
                        isRefreshing: viewModel.isRefreshing
                    )
                    .padding(.bottom, geometry.safeAreaInsets.bottom)
                    .background(.bar)
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            [
                GridItem(.flexible(), spacing: 16, alignment: .top),
                GridItem(.flexible(), spacing: 16, alignment: .top)
            ]
        } else {
            [
                GridItem(.flexible(), spacing: 16, alignment: .top)
            ]
        }
    }

    private var chartPaletteScheme: ChartPaletteScheme {
        ChartPaletteScheme(rawValue: chartPaletteSchemeRawValue) ?? .corporate
    }

    private func sectionExpandedBinding(for sectionID: DashboardSection.ID) -> Binding<Bool> {
        Binding {
            !collapsedSectionIDs.contains(sectionID)
        } set: { isExpanded in
            withAnimation(.easeInOut(duration: 0.22)) {
                if isExpanded {
                    collapsedSectionIDs.remove(sectionID)
                } else {
                    collapsedSectionIDs.insert(sectionID)
                }
            }
        }
    }

    private func sectionCountText(_ count: Int) -> String {
        let lastTwoDigits = count % 100
        let lastDigit = count % 10
        let noun: String

        if lastDigit == 1, lastTwoDigits != 11 {
            noun = "показатель"
        } else if (2...4).contains(lastDigit), !(12...14).contains(lastTwoDigits) {
            noun = "показателя"
        } else {
            noun = "показателей"
        }

        return "\(count) \(noun)"
    }

    private var chartPaletteBinding: Binding<ChartPaletteScheme> {
        Binding {
            chartPaletteScheme
        } set: { newValue in
            chartPaletteSchemeRawValue = newValue.rawValue
        }
    }

}

private struct ChartPalettePicker: View {
    @Binding var selection: ChartPaletteScheme

    var body: some View {
        Picker("Тема графиков", selection: $selection) {
            ForEach(ChartPaletteScheme.allCases) { scheme in
                Text(scheme.title)
                    .tag(scheme)
                    .accessibilityLabel(scheme.accessibilityTitle)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Тема графиков")
    }
}

private struct DashboardSettingsView: View {
    @Binding var chartPalette: ChartPaletteScheme
    let onSignOut: () -> Void

    var body: some View {
        Form {
            Section("Оформление") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Тема графиков")
                        .font(.body.weight(.semibold))

                    ChartPalettePicker(selection: $chartPalette)
                }
                .padding(.vertical, 4)
            }

            Section("Предпросмотр") {
                ChartThemePreview(palette: chartPalette)
            }

            Section {
                Button(role: .destructive, action: onSignOut) {
                    Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ChartThemePreview: View {
    let palette: ChartPaletteScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(ChartPalette.colors(for: palette).first ?? previewIndicator.accent.primary)

                Text("Пример графика")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(palette.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            AnalyticsChart(
                indicator: previewIndicator,
                showsTitle: false,
                usesCardBackground: false,
                showsLegend: false
            )
            .frame(height: 180)
        }
        .padding(.vertical, 6)
        .environment(\.chartPaletteScheme, palette)
        .animation(.easeInOut(duration: 0.25), value: palette)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Предпросмотр темы \(palette.accessibilityTitle)")
    }

    private var previewIndicator: Indicator {
        Indicator(
            id: "theme-preview",
            title: "Пример",
            value: nil,
            unit: nil,
            chartType: .compactBar,
            source: nil,
            rows: [
                IndicatorRow(id: "plan", label: "План", value: 72, series: nil, sortOrder: 0),
                IndicatorRow(id: "fact", label: "Факт", value: 54, series: nil, sortOrder: 1),
                IndicatorRow(id: "forecast", label: "Прогноз", value: 83, series: nil, sortOrder: 2)
            ]
        )
    }
}

private struct IndicatorDashboardCard: View {
    let indicator: Indicator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardContent
        }
        .padding(18)
        .frame(
            maxWidth: .infinity,
            minHeight: indicator.chartType == .oneValue ? 164 : nil,
            alignment: .topLeading
        )
        .background(
            indicator.chartType == .oneValue ? indicator.graphColor.opacity(0.075) : .clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .premiumPanel()
        .overlay(alignment: .leading) {
            if indicator.chartType == .oneValue {
                Capsule()
                    .fill(indicator.graphColor)
                    .frame(width: 4)
                    .padding(.vertical, 14)
                    .offset(x: 6)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        if indicator.chartType == .oneValue {
            OneValueDashboardContent(indicator: indicator)
        } else {
            header
            visualization
        }
    }

    @ViewBuilder
    private var visualization: some View {
        switch indicator.chartType {
        case .oneValue:
            EmptyView()
        case .linearProgress:
            LinearProgressIndicatorView(indicator: indicator)
        case .gauge:
            GaugeIndicatorView(indicator: indicator)
                .frame(minHeight: 190, idealHeight: 220, maxHeight: 240)
        case .geoMap:
            GeoMapIndicatorView(indicator: indicator)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        case .compactBar:
            VStack(alignment: .leading, spacing: 12) {
                AnalyticsChart(
                    indicator: indicator,
                    showsTitle: false,
                    usesCardBackground: false,
                    showsLegend: indicator.showsLegend,
                    animatesOnAppear: false
                )
                    .frame(minHeight: 180, idealHeight: 220, maxHeight: 260)
                    .padding(.top, 2)

                CompactBarValues(indicator: indicator)
            }
        case .bar, .horizontalBar, .stackedBar, .donut:
            AnalyticsChart(
                indicator: indicator,
                showsTitle: false,
                usesCardBackground: false,
                showsLegend: indicator.showsLegend,
                animatesOnAppear: false
            )
                .frame(minHeight: 220, idealHeight: 260, maxHeight: 320)
                .padding(.top, 2)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(indicator.graphColor, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(indicator.title)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if indicator.showsAggregateValue {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(valueText)
                        .font(.system(.title, design: .default).weight(.semibold))
                        .foregroundStyle(indicator.valueColor)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)

                    Spacer(minLength: 8)
                }
            }

        }
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

private struct CompactBarValues: View {
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

                    Spacer(minLength: 4)

                    Text(row.value.formatted(.number.grouping(.automatic).precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color(apiHex: row.colorValue ?? indicator.colorValue) ?? .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct OneValueDashboardContent: View {
    let indicator: Indicator
    @ScaledMetric(relativeTo: .largeTitle) private var valueFontSize: CGFloat = 44

    var body: some View {
        ZStack(alignment: .trailing) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 92, weight: .bold))
                .foregroundStyle(indicator.graphColor.opacity(0.07))
                .offset(x: 8, y: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 13) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(
                            LinearGradient(
                                colors: [indicator.graphColor, indicator.graphColor.opacity(0.78)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 11)
                        )
                        .shadow(color: indicator.graphColor.opacity(0.22), radius: 8, x: 0, y: 4)

                    Text(indicator.title)
                        .font(.headline.weight(.bold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }

                Text(valueText)
                    .font(.system(size: valueFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(indicator.valueColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.58)
                    .lineLimit(1)
                    .allowsTightening(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var valueText: String {
        guard let value = indicator.value else {
            return "нет данных"
        }

        return "\(value.formatted(.number.grouping(.automatic))) \(indicator.unit ?? "")"
            .trimmingCharacters(in: .whitespaces)
    }
}

private struct LinearProgressIndicatorView: View {
    let indicator: Indicator

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(indicator.graphColor.opacity(0.18))

                Capsule()
                    .fill(indicator.graphColor)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 10)
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

    private var accessibilityValue: String {
        guard let value = indicator.value, let valueMax = indicator.valueMax else {
            return "Нет данных"
        }

        return "\(value.formatted(.number.grouping(.automatic))) из \(valueMax.formatted(.number.grouping(.automatic)))"
    }
}

private struct GaugeIndicatorView: View {
    let indicator: Indicator

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let lineWidth = max(14, size * 0.09)

            ZStack {
                Circle()
                    .trim(from: 0.125, to: 0.875)
                    .stroke(
                        indicator.graphColor.opacity(0.13),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))

                Circle()
                    .trim(from: 0.125, to: 0.125 + 0.75 * progress)
                    .stroke(
                        AngularGradient(
                            colors: [
                                indicator.graphColor.opacity(0.52),
                                indicator.graphColor
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))

                ForEach(0..<11, id: \.self) { tick in
                    Capsule()
                        .fill(tick <= Int(progress * 10) ? indicator.graphColor : Color.secondary.opacity(0.22))
                        .frame(width: 2, height: tick.isMultiple(of: 5) ? 9 : 5)
                        .offset(y: -(size * 0.38))
                        .rotationEffect(.degrees(-135 + Double(tick) * 27))
                }

                Capsule()
                    .fill(indicator.valueColor)
                    .frame(width: 4, height: size * 0.29)
                    .offset(y: -(size * 0.145))
                    .rotationEffect(.degrees(-135 + 270 * progress))
                    .shadow(color: .black.opacity(0.16), radius: 2, y: 1)

                Circle()
                    .fill(indicator.graphColor)
                    .frame(width: 15, height: 15)
                    .overlay {
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 5, height: 5)
                    }

                VStack(spacing: 4) {
                    Spacer()

                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(indicator.valueColor)
                        .monospacedDigit()

                    if let value = indicator.value, let valueMax = indicator.valueMax {
                        Text(
                            "\(value.formatted(.number.notation(.compactName))) из "
                                + valueMax.formatted(.number.notation(.compactName))
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, max(2, size * 0.02))
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 8)
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

    private var accessibilityValue: String {
        guard let value = indicator.value, let valueMax = indicator.valueMax else {
            return "Нет данных"
        }

        return "\(value.formatted(.number.grouping(.automatic))) из \(valueMax.formatted(.number.grouping(.automatic)))"
    }
}

struct GeoMapIndicatorView: View {
    let indicator: Indicator
    private let valuesByCountryKey: [String: Double]
    private let maximumValue: Double
    private let minimumValue: Double
    @State private var geometry = GeoMapGeometry.empty

    init(indicator: Indicator) {
        self.indicator = indicator
        self.maximumValue = indicator.rows.map(\.value).max() ?? 1
        self.minimumValue = indicator.rows.map(\.value).filter { $0 > 0 }.min() ?? 0
        self.valuesByCountryKey = indicator.rows.reduce(into: [:]) { values, row in
            let key = row.label.geoCountryKey
            values[key] = row.value

            if let isoCode = GeoCountryAliases.isoCodeByAPIName[key] {
                values[isoCode] = row.value
            }
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
                let plotRect = CGRect(origin: .zero, size: size)

                for shape in geometry.shapes {
                    let path = mapPath(for: shape, in: plotRect, bounds: geometry.bounds)
                    context.fill(path, with: .color(fillColor(for: shape)))
                    context.stroke(
                        path,
                        with: .color(Color.secondary.opacity(0.38)),
                        style: StrokeStyle(lineWidth: 0.55, lineJoin: .round)
                    )
                }
            }
            .aspectRatio(geometry.aspectRatio, contentMode: .fit)
            .padding(.horizontal, 4)
            .accessibilityHidden(true)

            mapLegend
        }
        .task {
            if geometry.shapes.isEmpty {
                geometry = GeoMapWorldGeometry.load()
            }
        }
        .accessibilityLabel("Карта распределения по странам")
    }

    private func value(for shape: GeoCountryShape) -> Double? {
        shape.lookupKeys.compactMap { valuesByCountryKey[$0] }.first
    }

    private func fillColor(for shape: GeoCountryShape) -> Color {
        guard let value = value(for: shape) else {
            return Color.secondary.opacity(0.075)
        }

        let intensity = sqrt(max(value, 0) / max(maximumValue, 1))
        return indicator.graphColor.opacity(0.20 + 0.76 * intensity)
    }

    private func mapPath(for shape: GeoCountryShape, in rect: CGRect, bounds: CGRect) -> Path {
        var path = Path()
        var previousPoint: CGPoint?

        for normalizedPoint in shape.points {
            let point = CGPoint(
                x: rect.minX + ((normalizedPoint.x - bounds.minX) / bounds.width) * rect.width,
                y: rect.minY + ((normalizedPoint.y - bounds.minY) / bounds.height) * rect.height
            )

            if let previousPoint,
               abs(point.x - previousPoint.x) <= rect.width * 0.5 {
                path.addLine(to: point)
            } else {
                if previousPoint != nil {
                    path.closeSubpath()
                }
                path.move(to: point)
            }

            previousPoint = point
        }

        path.closeSubpath()
        return path
    }

    private var mapLegend: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(indicator.unit ?? "чел.")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Text(minimumValue.formatted(.number.notation(.compactName)))
                LinearGradient(
                    colors: [
                        indicator.graphColor.opacity(0.18),
                        indicator.graphColor.opacity(0.92)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 72, height: 8)
                .clipShape(Capsule())
                Text(maximumValue.formatted(.number.notation(.compactName)))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.primary)
        }
        .padding(9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Шкала от \(minimumValue.formatted(.number.grouping(.automatic))) "
                + "до \(maximumValue.formatted(.number.grouping(.automatic)))"
        )
    }
}

private struct GeoCountryShape: Identifiable {
    let id: String
    let points: [CGPoint]
    let lookupKeys: [String]
}

private struct GeoMapGeometry {
    let shapes: [GeoCountryShape]
    let bounds: CGRect

    static let empty = GeoMapGeometry(
        shapes: [],
        bounds: CGRect(x: 0, y: 0, width: 1, height: 1)
    )

    var aspectRatio: CGFloat {
        guard !shapes.isEmpty, bounds.height > 0 else {
            return 2.07
        }

        return 2 * bounds.width / bounds.height
    }
}

@MainActor
private enum GeoMapWorldGeometry {
    private static var cachedGeometry: GeoMapGeometry?

    static func load() -> GeoMapGeometry {
        if let cachedGeometry {
            return cachedGeometry
        }

        guard let url = Bundle.main.url(
            forResource: "world-countries-110m",
            withExtension: "geojson"
        ),
        let data = try? Data(contentsOf: url),
        let objects = try? MKGeoJSONDecoder().decode(data) else {
            return .empty
        }

        var shapes: [GeoCountryShape] = []
        var minimumX = CGFloat.greatestFiniteMagnitude
        var minimumY = CGFloat.greatestFiniteMagnitude
        var maximumX = -CGFloat.greatestFiniteMagnitude
        var maximumY = -CGFloat.greatestFiniteMagnitude

        for (featureIndex, object) in objects.enumerated() {
            guard let feature = object as? MKGeoJSONFeature else {
                continue
            }

            let properties = feature.properties.flatMap {
                try? JSONDecoder().decode(GeoCountryProperties.self, from: $0)
            }
            let lookupKeys = [
                properties?.nameRU?.geoCountryKey,
                properties?.admin?.geoCountryKey,
                properties?.isoA3?.geoCountryKey
            ].compactMap(\.self)

            var polygonIndex = 0
            for geometry in feature.geometry {
                let polygons: [MKPolygon]

                if let polygon = geometry as? MKPolygon {
                    polygons = [polygon]
                } else if let multiPolygon = geometry as? MKMultiPolygon {
                    polygons = multiPolygon.polygons
                } else {
                    continue
                }

                for polygon in polygons {
                    let mapPoints = polygon.points()
                    let normalizedPoints = (0..<polygon.pointCount).map { pointIndex in
                        let coordinate = mapPoints[pointIndex].coordinate
                        let point = CGPoint(
                            x: (coordinate.longitude + 180) / 360,
                            y: (90 - coordinate.latitude) / 180
                        )

                        minimumX = min(minimumX, point.x)
                        minimumY = min(minimumY, point.y)
                        maximumX = max(maximumX, point.x)
                        maximumY = max(maximumY, point.y)
                        return point
                    }

                    shapes.append(
                        GeoCountryShape(
                            id: "\(featureIndex)-\(polygonIndex)",
                            points: normalizedPoints,
                            lookupKeys: lookupKeys
                        )
                    )
                    polygonIndex += 1
                }
            }
        }

        guard !shapes.isEmpty else {
            return .empty
        }

        let geometry = GeoMapGeometry(
            shapes: shapes,
            bounds: CGRect(
                x: minimumX,
                y: minimumY,
                width: maximumX - minimumX,
                height: maximumY - minimumY
            )
        )
        cachedGeometry = geometry
        return geometry
    }
}

private struct GeoCountryProperties: Decodable {
    let nameRU: String?
    let admin: String?
    let isoA3: String?

    private enum CodingKeys: String, CodingKey {
        case nameRU = "NAME_RU"
        case admin = "ADMIN"
        case isoA3 = "ISO_A3"
    }
}

private enum GeoCountryAliases {
    static let isoCodeByAPIName: [String: String] = [
        "АБХАЗИЯ".geoCountryKey: "ABH",
        "БАХРЕЙН".geoCountryKey: "BHR",
        "БЕЛАРУСЬ".geoCountryKey: "BLR",
        "БОЛИВИЯ, МНОГОНАЦИОНАЛЬНОЕ ГОСУДАРСТВО".geoCountryKey: "BOL",
        "БРУНЕЙ-ДАРУССАЛАМ".geoCountryKey: "BRN",
        "ВЕНЕСУЭЛА (БОЛИВАРИАНСКАЯ РЕСПУБЛИКА)".geoCountryKey: "VEN",
        "ГАИТИ".geoCountryKey: "HTI",
        "ГРЕНАДА".geoCountryKey: "GRD",
        "ДОМИНИКА".geoCountryKey: "DMA",
        "ИРАН (ИСЛАМСКАЯ РЕСПУБЛИКА)".geoCountryKey: "IRN",
        "КАБО-ВЕРДЕ".geoCountryKey: "CPV",
        "КИТАЙ".geoCountryKey: "CHN",
        "КОМОРЫ".geoCountryKey: "COM",
        "КОНГО".geoCountryKey: "COG",
        "КОНГО, ДЕМОКРАТИЧЕСКАЯ РЕСПУБЛИКА".geoCountryKey: "COD",
        "КОРЕЯ, НАРОДНО-ДЕМОКРАТИЧЕСКАЯ РЕСПУБЛИКА".geoCountryKey: "PRK",
        "КОРЕЯ, РЕСПУБЛИКА".geoCountryKey: "KOR",
        "ЛАОССКАЯ НАРОДНО-ДЕМОКРАТИЧЕСКАЯ РЕСПУБЛИКА".geoCountryKey: "LAO",
        "МАВРИКИЙ".geoCountryKey: "MUS",
        "МАЛЬТА".geoCountryKey: "MLT",
        "МОЛДОВА, РЕСПУБЛИКА".geoCountryKey: "MDA",
        "ПАЛЕСТИНА, ГОСУДАРСТВО".geoCountryKey: "PSX",
        "САН-ТОМЕ И ПРИНСИПИ".geoCountryKey: "STP",
        "СИНГАПУР".geoCountryKey: "SGP",
        "СИРИЙСКАЯ АРАБСКАЯ РЕСПУБЛИКА".geoCountryKey: "SYR",
        "СОЕДИНЕННОЕ КОРОЛЕВСТВО ВЕЛИКОБРИТАНИИ И СЕВЕРНОЙ ИРЛАНДИИ".geoCountryKey: "GBR",
        "СОЕДИНЕННЫЕ ШТАТЫ".geoCountryKey: "USA",
        "ТАЙВАНЬ (КИТАЙ)".geoCountryKey: "TWN",
        "ТАНЗАНИЯ, ОБЪЕДИНЕННАЯ РЕСПУБЛИКА".geoCountryKey: "TZA",
        "ТУРКМЕНИСТАН".geoCountryKey: "TKM",
        "ЭЛЬ-САЛЬВАДОР".geoCountryKey: "SLV",
        "ЮЖНАЯ АФРИКА".geoCountryKey: "ZAF"
    ]
}

private extension String {
    var geoCountryKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
            .uppercased()
            .replacingOccurrences(of: "Ё", with: "Е")
            .filter { $0.isLetter || $0.isNumber }
    }
}
