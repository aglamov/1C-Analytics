import SwiftUI
import UIKit
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
    @State private var currentSectionID: DashboardSection.ID?
    @State private var hasFirstSectionHeaderPassedTop = false
    @State private var refreshAnimationGeneration = 0
    @State private var sectionAnimationGenerations: [DashboardSection.ID: Int] = [:]
    @State private var errorNoticePresentationRequest = 0

    var body: some View {
        NavigationStack(path: $navigationPath) {
            content
                .navigationTitle(navigationTitle)
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
                        if let dashboard = viewModel.dashboard {
                            Button {
                                toggleAllSections(in: dashboard)
                            } label: {
                                Image(
                                    systemName: allSectionsAreCollapsed(in: dashboard)
                                        ? "rectangle.expand.vertical"
                                        : "rectangle.compress.vertical"
                                )
                            }
                            .accessibilityLabel(
                                allSectionsAreCollapsed(in: dashboard)
                                    ? "Развернуть все группы"
                                    : "Свернуть все группы"
                            )

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

                    if case let .loaded(dashboard) = viewModel.state {
                        ToolbarItem(placement: .bottomBar) {
                            HStack(spacing: 0) {
                                DashboardConnectionStatus(
                                    date: dashboard.fetchedAt,
                                    isCached: viewModel.isShowingCachedData,
                                    isRefreshing: viewModel.isRefreshing,
                                    hasError: viewModel.refreshErrorMessage != nil,
                                    onErrorTap: {
                                        errorNoticePresentationRequest &+= 1
                                    }
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
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
        .onChange(of: viewModel.dashboard?.fetchedAt) { oldDate, newDate in
            guard oldDate != nil, newDate != nil, oldDate != newDate else {
                return
            }
            refreshAnimationGeneration &+= 1
        }
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
                .coordinateSpace(name: DashboardScrollCoordinateSpace.name)
                .onPreferenceChange(DashboardSectionOffsetPreferenceKey.self) { offsets in
                    updateCurrentSection(using: offsets, in: dashboard)
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
                DashboardOfflineNotice(
                    date: dashboard.fetchedAt,
                    isCached: viewModel.isShowingCachedData,
                    errorMessage: viewModel.refreshErrorMessage,
                    presentationRequest: errorNoticePresentationRequest
                )
            }
            .background(Color(.systemBackground).ignoresSafeArea())
        }
    }

    private func dashboardSection(_ section: DashboardSection) -> some View {
        let isExpanded = debugSectionTitle.map { $0 == section.title }
            ?? !collapsedSectionIDs.contains(section.id)

        return Section {
            if isExpanded {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(layoutRows(for: displayedIndicators(in: section))) { row in
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(row.indicators) { indicator in
                                dashboardCard(indicator, in: section)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                            }

                            if isPad, row.indicators.count == 1 {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
                .padding(.top, 12)
                .transition(.opacity)
            }
        } header: {
            dashboardSectionHeader(section, isExpanded: isExpanded)
        }
    }

    private func dashboardSectionHeader(
        _ section: DashboardSection,
        isExpanded: Bool
    ) -> some View {
        Button {
            toggleSection(section.id)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.title2.weight(.bold))

                    Text(sectionStatusText(section))
                        .font(.caption)
                        .foregroundStyle(
                            viewModel.staleSectionIDs.contains(section.id) ? .orange : .secondary
                        )
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
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DashboardSectionOffsetPreferenceKey.self,
                    value: [
                        section.id: proxy.frame(
                            in: .named(DashboardScrollCoordinateSpace.name)
                        ).minY
                    ]
                )
            }
        }
        .accessibilityLabel(section.title)
        .accessibilityValue(isExpanded ? "Развернуто" : "Свернуто")
        .accessibilityAddTraits(.isHeader)
    }

    private func dashboardCard(
        _ indicator: Indicator,
        in section: DashboardSection
    ) -> some View {
        IndicatorDashboardCard(
            indicator: indicator,
            animationTrigger: chartAnimationTrigger(for: section.id)
        )
            .overlay(alignment: .topTrailing) {
                if isEditingLayout {
                    reorderHandle(for: indicator, in: section)
                } else if indicator.supportsDetail {
                    NavigationLink(value: DashboardRoute.indicator(indicator.id)) {
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(indicator.paletteColor(scheme: chartPaletteScheme))
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

    private func layoutRows(for indicators: [Indicator]) -> [DashboardIndicatorLayoutRow] {
        DashboardGridLayoutPolicy.rows(for: indicators, isPad: isPad).map {
            DashboardIndicatorLayoutRow(indicators: $0)
        }
    }

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var chartPaletteScheme: ChartPaletteScheme {
        ChartPaletteScheme(rawValue: chartPaletteSchemeRawValue) ?? .corporate
    }

    private var navigationTitle: String {
        guard let dashboard = viewModel.dashboard else {
            return "1С Аналитика"
        }

        let sectionID = currentSectionID ?? dashboard.sections.first?.id
        if sectionID == dashboard.sections.first?.id,
           !hasFirstSectionHeaderPassedTop {
            return "1С Аналитика"
        }

        return dashboard.sections.first(where: { $0.id == sectionID })?.title
            ?? dashboard.title
    }

    private func toggleSection(_ sectionID: DashboardSection.ID) {
        withAnimation(.easeInOut(duration: 0.22)) {
            if collapsedSectionIDs.contains(sectionID) {
                sectionAnimationGenerations[sectionID, default: 0] &+= 1
                collapsedSectionIDs.remove(sectionID)
            } else {
                collapsedSectionIDs.insert(sectionID)
            }
        }
    }

    private func allSectionsAreCollapsed(in dashboard: Dashboard) -> Bool {
        !dashboard.sections.isEmpty
            && dashboard.sections.allSatisfy { collapsedSectionIDs.contains($0.id) }
    }

    private func sectionStatusText(_ section: DashboardSection) -> String {
        let count = sectionCountText(section.indicators.count)
        guard let fetchedAt = section.fetchedAt else {
            return viewModel.staleSectionIDs.contains(section.id)
                ? "\(count) · сохранённые данные"
                : count
        }

        let timestamp = fetchedAt.formatted(date: .numeric, time: .shortened)
        return viewModel.staleSectionIDs.contains(section.id)
            ? "\(count) · сохранено \(timestamp)"
            : "\(count) · обновлено \(timestamp)"
    }

    private func toggleAllSections(in dashboard: Dashboard) {
        withAnimation(.easeInOut(duration: 0.24)) {
            if allSectionsAreCollapsed(in: dashboard) {
                for section in dashboard.sections {
                    sectionAnimationGenerations[section.id, default: 0] &+= 1
                }
                collapsedSectionIDs.removeAll()
            } else {
                collapsedSectionIDs = Set(dashboard.sections.map(\.id))
            }
        }
    }

    private func chartAnimationTrigger(for sectionID: DashboardSection.ID) -> String {
        let sectionGeneration = sectionAnimationGenerations[sectionID, default: 0]
        return "refresh:\(refreshAnimationGeneration)-section:\(sectionGeneration)"
    }

    private func updateCurrentSection(
        using offsets: [DashboardSection.ID: CGFloat],
        in dashboard: Dashboard
    ) {
        guard !dashboard.sections.isEmpty, !offsets.isEmpty else {
            return
        }

        let topEdge: CGFloat = 1
        if let firstSectionID = dashboard.sections.first?.id,
           let firstSectionOffset = offsets[firstSectionID] {
            let didPassTop = firstSectionOffset <= topEdge
            if hasFirstSectionHeaderPassedTop != didPassTop {
                hasFirstSectionHeaderPassedTop = didPassTop
            }
        }

        let indexedSections = dashboard.sections.enumerated()
        let latestPassedSection = indexedSections
            .compactMap { index, section -> (index: Int, offset: CGFloat)? in
                guard let offset = offsets[section.id], offset <= topEdge else {
                    return nil
                }
                return (index, offset)
            }
            .max { $0.offset < $1.offset }

        let nextSection = indexedSections
            .compactMap { index, section -> (index: Int, offset: CGFloat)? in
                guard let offset = offsets[section.id], offset > topEdge else {
                    return nil
                }
                return (index, offset)
            }
            .min { $0.offset < $1.offset }

        var currentIndex = latestPassedSection?.index ?? 0
        if let nextSection {
            currentIndex = max(currentIndex, nextSection.index - 1)
        } else if latestPassedSection == nil {
            currentIndex = dashboard.sections.count - 1
        }

        let newSectionID = dashboard.sections[currentIndex].id
        if currentSectionID != newSectionID {
            currentSectionID = newSectionID
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

    private func displayedIndicators(in section: DashboardSection) -> [Indicator] {
        let indicators = layoutStore.orderedIndicators(in: section)
        return indicators.filter { indicator in
            let matchesTitle = debugIndicatorTitle.map {
                indicator.title.localizedCaseInsensitiveContains($0)
            } ?? true
            let matchesSeries = debugMinimumSeriesCount.map {
                indicator.barDataShape.series.count >= $0
            } ?? true
            return matchesTitle && matchesSeries
        }
    }

    private var debugSectionTitle: String? {
#if DEBUG
        ProcessInfo.processInfo.environment["DASHBOARD_SCREENSHOT_SECTION"]
#else
        nil
#endif
    }

    private var debugIndicatorTitle: String? {
#if DEBUG
        ProcessInfo.processInfo.environment["DASHBOARD_SCREENSHOT_INDICATOR"]
#else
        nil
#endif
    }

    private var debugMinimumSeriesCount: Int? {
#if DEBUG
        ProcessInfo.processInfo.environment["DASHBOARD_SCREENSHOT_MIN_SERIES"].flatMap(Int.init)
#else
        nil
#endif
    }

    private var chartPaletteBinding: Binding<ChartPaletteScheme> {
        Binding {
            chartPaletteScheme
        } set: { newValue in
            chartPaletteSchemeRawValue = newValue.rawValue
        }
    }
}
