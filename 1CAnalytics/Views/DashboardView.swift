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
                                                                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
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
            .safeAreaInset(edge: .bottom) {
                DashboardConnectionBar(
                    date: dashboard.fetchedAt,
                    isCached: viewModel.isShowingCachedData,
                    isRefreshing: viewModel.isRefreshing
                )
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
    @State private var isVisible = false

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
        .scaleEffect(isVisible ? 1 : 0.98)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                isVisible = true
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
        case .compactBar:
            VStack(alignment: .leading, spacing: 12) {
                AnalyticsChart(indicator: indicator, showsTitle: false, usesCardBackground: false, showsLegend: false)
                    .frame(minHeight: 180, idealHeight: 220, maxHeight: 260)
                    .padding(.top, 2)

                CompactBarValues(indicator: indicator)
            }
        case .bar, .horizontalBar, .stackedBar, .donut:
            AnalyticsChart(indicator: indicator, showsTitle: false, usesCardBackground: false, showsLegend: false)
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
    @State private var hasAppeared = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(indicator.graphColor.opacity(0.18))

                Capsule()
                    .fill(indicator.graphColor)
                    .frame(width: proxy.size.width * (hasAppeared ? progress : 0))
            }
        }
        .frame(height: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(indicator.title)
        .accessibilityValue(accessibilityValue)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) {
                hasAppeared = true
            }
        }
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
