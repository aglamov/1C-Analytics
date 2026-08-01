import MapKit
import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @StateObject var viewModel: DashboardViewModel
    @StateObject private var layoutStore = DashboardLayoutStore()
    let onSignOut: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("chartPaletteScheme") private var chartPaletteSchemeRawValue = ChartPaletteScheme.corporate.rawValue
    @State private var collapsedSectionIDs: Set<DashboardSection.ID> = []
    @State private var isEditingLayout = false
    @State private var draggedIndicator: DashboardDraggedIndicator?
    @State private var navigationPath: [DashboardRoute] = []
    @State private var indicatorIDToRestore: Indicator.ID?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            content
                .navigationTitle(viewModel.dashboard?.title ?? "Аналитика")
                .navigationDestination(for: DashboardRoute.self) { route in
                    switch route {
                    case let .indicator(indicatorID):
                        if let indicator = viewModel.dashboard?.indicators.first(where: { $0.id == indicatorID }) {
                            IndicatorDetailView(indicator: indicator)
                        } else {
                            ContentUnavailableView(
                                "График недоступен",
                                systemImage: "chart.bar.xaxis"
                            )
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            DashboardSettingsView(
                                chartPalette: chartPaletteBinding,
                                layoutStore: layoutStore,
                                onSignOut: onSignOut
                            )
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Настройки")
                    }

                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if viewModel.dashboard != nil {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isEditingLayout.toggle()
                                    if !isEditingLayout {
                                        draggedIndicator = nil
                                    }
                                }
                            } label: {
                                Image(systemName: isEditingLayout ? "checkmark" : "arrow.up.arrow.down.square")
                            }
                            .accessibilityLabel(isEditingLayout ? "Завершить настройку" : "Изменить расположение")
                        }

                        RefreshButton {
                            await viewModel.refresh()
                        }
                        .disabled(isEditingLayout)
                    }
                }
        }
        .onChange(of: navigationPath) { oldPath, newPath in
            guard newPath.count < oldPath.count,
                  case let .indicator(indicatorID) = oldPath.last else {
                return
            }
            indicatorIDToRestore = indicatorID
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
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(dashboard.sections) { section in
                            dashboardSection(section)
                        }
                    }
                    .padding(.horizontal, horizontalSizeClass == .regular ? 20 : 16)
                    .padding(.vertical, 16)
                }
                .onChange(of: indicatorIDToRestore) { _, indicatorID in
                    guard let indicatorID else {
                        return
                    }

                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        scrollProxy.scrollTo(indicatorID, anchor: .center)
                    }
                    indicatorIDToRestore = nil
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DashboardConnectionBar(
                    date: dashboard.fetchedAt,
                    isCached: viewModel.isShowingCachedData,
                    isRefreshing: viewModel.isRefreshing
                )
            }
            .background(Color(.systemBackground).ignoresSafeArea())
        }
    }

    private func dashboardSection(_ section: DashboardSection) -> some View {
        let isExpanded = !collapsedSectionIDs.contains(section.id)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleSection(section.id)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title)
                            .font(.title2.weight(.bold))

                        Text(sectionCountText(section.indicators.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(section.title)
            .accessibilityValue(isExpanded ? "Развернуто" : "Свернуто")
            .accessibilityAddTraits(.isHeader)

            if isExpanded {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(layoutStore.orderedIndicators(in: section)) { indicator in
                        dashboardCard(indicator, in: section)
                    }
                }
                .padding(.top, 12)
                .transition(.opacity)
            }
        }
    }

    private func dashboardCard(
        _ indicator: Indicator,
        in section: DashboardSection
    ) -> some View {
        IndicatorDashboardCard(indicator: indicator)
            .overlay(alignment: .topTrailing) {
                if isEditingLayout {
                    reorderHandle(for: indicator, in: section)
                } else if indicator.supportsDetail {
                    NavigationLink(value: DashboardRoute.indicator(indicator.id)) {
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
            .id(indicator.id)
            .opacity(draggedIndicator?.indicatorID == indicator.id ? 0.68 : 1)
            .animation(.easeInOut(duration: 0.16), value: draggedIndicator?.indicatorID)
            .onDrop(
                of: [UTType.plainText],
                delegate: DashboardIndicatorDropDelegate(
                    section: section,
                    targetIndicatorID: indicator.id,
                    isEditing: isEditingLayout,
                    draggedIndicator: $draggedIndicator,
                    layoutStore: layoutStore
                )
            )
    }

    private func reorderHandle(
        for indicator: Indicator,
        in section: DashboardSection
    ) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.headline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
            .background(
                Color(.systemBackground).opacity(0.96),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .onDrag {
                draggedIndicator = DashboardDraggedIndicator(
                    sectionID: section.id,
                    indicatorID: indicator.id
                )
                return NSItemProvider(object: indicator.id as NSString)
            } preview: {
                Label(indicator.title, systemImage: "chart.bar.fill")
                    .font(.headline)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("Переместить \(indicator.title)")
            .padding(12)
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

    private func toggleSection(_ sectionID: DashboardSection.ID) {
        withAnimation(.easeInOut(duration: 0.22)) {
            if collapsedSectionIDs.contains(sectionID) {
                collapsedSectionIDs.remove(sectionID)
            } else {
                collapsedSectionIDs.insert(sectionID)
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

private enum DashboardRoute: Hashable {
    case indicator(Indicator.ID)
}

final class DashboardLayoutStore: ObservableObject {
    static let defaultStorageKey = "dashboardIndicatorOrder.v1"

    @Published private var orderBySection: [DashboardSection.ID: [Indicator.ID]]

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = DashboardLayoutStore.defaultStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey

        guard let data = defaults.data(forKey: storageKey),
              let storedOrder = try? JSONDecoder().decode(
                  [DashboardSection.ID: [Indicator.ID]].self,
                  from: data
              ) else {
            orderBySection = [:]
            return
        }

        orderBySection = storedOrder
    }

    func orderedIndicators(in section: DashboardSection) -> [Indicator] {
        let indicatorByID = Dictionary(
            uniqueKeysWithValues: section.indicators.map { ($0.id, $0) }
        )
        return Self.reconciledOrder(
            savedOrder: orderBySection[section.id] ?? [],
            availableIDs: section.indicators.map(\.id)
        ).compactMap { indicatorByID[$0] }
    }

    func moveIndicator(
        in section: DashboardSection,
        draggedID: Indicator.ID,
        over targetID: Indicator.ID
    ) {
        guard draggedID != targetID else {
            return
        }

        var order = Self.reconciledOrder(
            savedOrder: orderBySection[section.id] ?? [],
            availableIDs: section.indicators.map(\.id)
        )
        guard let sourceIndex = order.firstIndex(of: draggedID),
              let targetIndex = order.firstIndex(of: targetID) else {
            return
        }

        order.move(
            fromOffsets: IndexSet(integer: sourceIndex),
            toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        )
        orderBySection[section.id] = order
        persist()
    }

    static func reconciledOrder(
        savedOrder: [Indicator.ID],
        availableIDs: [Indicator.ID]
    ) -> [Indicator.ID] {
        let availableIDSet = Set(availableIDs)
        var seenIDs = Set<Indicator.ID>()
        let retainedIDs = savedOrder.filter {
            availableIDSet.contains($0) && seenIDs.insert($0).inserted
        }
        let newIDs = availableIDs.filter {
            seenIDs.insert($0).inserted
        }
        return retainedIDs + newIDs
    }

    var hasCustomLayout: Bool {
        !orderBySection.isEmpty
    }

    func reset() {
        orderBySection = [:]
        defaults.removeObject(forKey: storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(orderBySection) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}

private struct DashboardDraggedIndicator: Equatable {
    let sectionID: DashboardSection.ID
    let indicatorID: Indicator.ID
}

private struct DashboardIndicatorDropDelegate: DropDelegate {
    let section: DashboardSection
    let targetIndicatorID: Indicator.ID
    let isEditing: Bool
    @Binding var draggedIndicator: DashboardDraggedIndicator?
    let layoutStore: DashboardLayoutStore

    func validateDrop(info: DropInfo) -> Bool {
        isEditing
            && draggedIndicator?.sectionID == section.id
            && info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        guard isEditing,
              let draggedIndicator,
              draggedIndicator.sectionID == section.id else {
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            layoutStore.moveIndicator(
                in: section,
                draggedID: draggedIndicator.indicatorID,
                over: targetIndicatorID
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info) else {
            return false
        }
        draggedIndicator = nil
        return true
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
    @ObservedObject var layoutStore: DashboardLayoutStore
    let onSignOut: () -> Void
    @State private var showsLayoutResetConfirmation = false

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
                Button(role: .destructive) {
                    showsLayoutResetConfirmation = true
                } label: {
                    Label("Сбросить расположение графиков", systemImage: "arrow.counterclockwise")
                }
                .disabled(!layoutStore.hasCustomLayout)
            } header: {
                Text("Расположение")
            } footer: {
                Text("Графики вернутся к порядку, полученному от сервера.")
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
        .confirmationDialog(
            "Сбросить расположение графиков?",
            isPresented: $showsLayoutResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Сбросить", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    layoutStore.reset()
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Карточки во всех группах вернутся к исходному порядку.")
        }
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
        .premiumPanel(isElevated: false)
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
                .frame(height: chartHeight)
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
                    .frame(height: chartHeight)
                    .padding(.top, 2)

                if !indicator.prefersHorizontalGroupedBars {
                    CompactBarValues(indicator: indicator)
                }
            }
        case .bar, .horizontalBar, .stackedBar, .donut, .percentDonut,
             .line, .area, .splineLine, .splineArea, .forecastLine:
            AnalyticsChart(
                indicator: indicator,
                showsTitle: false,
                usesCardBackground: false,
                showsLegend: indicator.showsLegend,
                animatesOnAppear: false,
                showsLineAreaFill: true
            )
                .frame(height: chartHeight)
                .padding(.top, 2)
        }
    }

    private var chartHeight: CGFloat {
        let categoryCount = max(Set(indicator.orderedRows.map(\.label)).count, 1)

        if indicator.prefersHorizontalGroupedBars {
            return min(max(CGFloat(categoryCount) * 54 + 64, 240), 420)
        }

        switch indicator.chartType {
        case .horizontalBar:
            return min(max(CGFloat(categoryCount) * 42 + 52, 180), 340)
        case .bar, .stackedBar:
            return categoryCount > 6 ? 250 : 220
        case .compactBar:
            return categoryCount > 5 ? 220 : 190
        case .line, .area, .splineLine, .splineArea, .forecastLine:
            return categoryCount > 8 ? 250 : 220
        case .donut, .percentDonut:
            return 270
        case .gauge:
            return 220
        case .oneValue, .linearProgress, .geoMap:
            return 220
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

                Text(indicator.title)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            if indicator.showsAggregateValue {
                Text(valueText)
                    .font(.system(.title2, design: .default).weight(.semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        }
    }

    private var valueText: String {
        guard let value = indicator.value else {
            return "нет данных"
        }

        return "\(indicator.formattedNumber(value)) \(indicator.unit ?? "")"
    }

    private var iconName: String {
        switch indicator.chartType {
        case .bar, .compactBar, .horizontalBar, .stackedBar:
            "chart.bar.fill"
        case .donut, .percentDonut:
            "chart.pie.fill"
        case .line, .splineLine, .forecastLine:
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

                    Text(indicator.formattedNumber(row.value))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
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
    @ScaledMetric(relativeTo: .largeTitle) private var valueFontSize: CGFloat = 38

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

        return "\(indicator.formattedNumber(value)) \(indicator.unit ?? "")"
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

        return "\(indicator.formattedNumber(value)) из \(indicator.formattedNumber(valueMax))"
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

                VStack(spacing: 7) {
                    Spacer()

                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(indicator.valueColor)
                        .monospacedDigit()

                    if let value = indicator.value, let valueMax = indicator.valueMax {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            gaugeValue(
                                title: "Сейчас",
                                value: indicator.formattedNumber(value),
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
