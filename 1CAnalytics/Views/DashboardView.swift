import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum DashboardBulkSectionAction: Equatable {
    case collapseAndScrollToTop
    case expandPreservingPosition
}

enum DashboardBulkSectionActionPolicy {
    static func action(
        sectionIDs: [DashboardSection.ID],
        collapsedSectionIDs: Set<DashboardSection.ID>
    ) -> DashboardBulkSectionAction {
        let allCollapsed = !sectionIDs.isEmpty
            && sectionIDs.allSatisfy(collapsedSectionIDs.contains)
        return allCollapsed ? .expandPreservingPosition : .collapseAndScrollToTop
    }
}

struct DashboardView: View {
    private static let feedTopAnchor = "dashboard-feed-top"

    @StateObject var viewModel: DashboardViewModel
    @StateObject private var layoutStore = DashboardLayoutStore()
    let onSignOut: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("chartPaletteScheme") private var chartPaletteSchemeRawValue = ChartPaletteScheme.corporate.rawValue
    @AppStorage("dashboardContentScale.v1") private var dashboardContentScale = 1.0
    @State private var collapsedSectionIDs: Set<DashboardSection.ID> = []
    @State private var expandedExtendedSectionIDs: Set<DashboardExtendedSection.ID> = []
    @State private var isEditingLayout = false
    @State private var draggedIndicator: DashboardDraggedIndicator?
    @State private var navigationPath: [DashboardRoute] = []
    @State private var indicatorIDToRestore: Indicator.ID?
    @State private var currentSectionID: DashboardSection.ID?
    @State private var hasFirstSectionHeaderPassedTop = false
    @State private var refreshAnimationGeneration = 0
    @State private var sectionAnimationGenerations: [DashboardSection.ID: Int] = [:]
    @State private var isShowingSynchronizationDetails = false
    @State private var scrollToTopRequest = 0

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
                                contentScale: contentScaleBinding,
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
        .environment(\.dashboardContentScale, CGFloat(normalizedContentScale))
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
                    VStack(alignment: .leading, spacing: 16) {
                        Color.clear
                            .frame(height: 0)
                            .id(Self.feedTopAnchor)

                        ForEach(dashboard.sections) { section in
                            dashboardSection(section)
                        }
                    }
                    .padding(.horizontal, horizontalSizeClass == .regular ? 20 : 16)
                    .padding(.top, 16)
                    .padding(.bottom, 92)
                }
                .coordinateSpace(name: DashboardScrollCoordinateSpace.name)
                .onPreferenceChange(DashboardSectionOffsetPreferenceKey.self) { offsets in
                    Task { @MainActor in
                        await Task.yield()
                        updateCurrentSection(using: offsets, in: dashboard)
                    }
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
                .onChange(of: scrollToTopRequest) { _, _ in
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.28)) {
                            scrollProxy.scrollTo(Self.feedTopAnchor, anchor: .top)
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let session = viewModel.synchronizationSession {
                    DashboardSynchronizationIndicator(
                        session: session,
                        isCached: viewModel.isShowingCachedData,
                        hasCacheError: viewModel.cacheErrorMessage != nil
                    ) {
                        isShowingSynchronizationDetails = true
                    }
                    .padding(.trailing, horizontalSizeClass == .regular ? 20 : 16)
                    .padding(.bottom, 8)
                }
            }
            .sheet(isPresented: synchronizationDetailsBinding(forPad: false)) {
                synchronizationDetails
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .popover(isPresented: synchronizationDetailsBinding(forPad: true), arrowEdge: .bottom) {
                synchronizationDetails
                    .frame(width: 430, height: 480)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
    }

    private func dashboardSection(_ section: DashboardSection) -> some View {
        let isExpanded = debugSectionTitle.map { $0 == section.title }
            ?? !collapsedSectionIDs.contains(section.id)

        return Section {
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(layoutRows(for: displayedIndicators(in: section))) { row in
                        DashboardSlotRowLayout(
                            slotCapacity: row.slotCapacity,
                            spans: row.items.map(\.width.slotSpan),
                            spacing: 16
                        ) {
                            ForEach(row.items) { item in
                                dashboardCard(item.indicator, in: section)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    extendedSectionControl(for: section)
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
        let style = DashboardSectionVisualStyle.style(for: section.title)
        return Button {
            toggleSection(section.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: style.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(style.tint)
                    .frame(width: 36, height: 36)
                    .background(style.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title)
                        .font(.headline)

                    sectionStatusLabel(section)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(minHeight: 58)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
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
                    layoutControls(for: indicator, in: section)
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

    private func layoutControls(
        for indicator: Indicator,
        in section: DashboardSection
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    layoutStore.toggleWidth(for: indicator)
                }
            } label: {
                Text(layoutStore.width(for: indicator).title)
                    .font(.caption.monospacedDigit().weight(.bold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ширина графика")
            .accessibilityValue(layoutStore.width(for: indicator).title)
            .accessibilityHint("Изменить на \(layoutStore.width(for: indicator).toggled.title)")

            Image(systemName: "line.3.horizontal")
            .font(.headline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
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
        }
        .padding(4)
        .background(Color(.systemBackground).opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        }
        .padding(12)
    }

    private func layoutRows(for indicators: [Indicator]) -> [DashboardIndicatorLayoutRow] {
        let items = indicators.map {
            DashboardIndicatorLayoutItem(indicator: $0, width: layoutStore.width(for: $0))
        }
        return DashboardGridLayoutPolicy.rows(
            for: items,
            slotCapacity: isRegularPadLayout ? 4 : 2
        )
    }

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var isRegularPadLayout: Bool {
        isPad && horizontalSizeClass == .regular
    }

    @ViewBuilder
    private func extendedSectionControl(for section: DashboardSection) -> some View {
        if section.hasExtended {
            if let extended = section.extended {
                extendedSectionGroup(extended, parent: section)
            } else {
                switch viewModel.extendedState(for: section.id) {
                case .loaded, .idle:
                    extendedSectionButton(section, errorMessage: nil)
                case .loading:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Загружаем \(section.title) · 2 уровень")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 52)
                    .frame(maxWidth: .infinity)
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                    .padding(.horizontal, 12)
                case let .failed(message):
                    extendedSectionButton(section, errorMessage: message)
                }
            }
        }
    }

    private func extendedSectionGroup(
        _ extended: DashboardExtendedSection,
        parent: DashboardSection
    ) -> some View {
        let isExpanded = expandedExtendedSectionIDs.contains(extended.id)
        let layoutSection = DashboardSection(
            id: extended.id,
            title: extended.title,
            indicators: extended.indicators,
            fetchedAt: extended.fetchedAt
        )
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    if isExpanded { expandedExtendedSectionIDs.remove(extended.id) }
                    else { expandedExtendedSectionIDs.insert(extended.id) }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .foregroundStyle(.secondary)
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(extended.title).font(.headline)
                        extendedStatusLabel(extended, parent: parent)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 52)
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(extended.title)
            .accessibilityValue(isExpanded ? "Развернуто" : "Свернуто")

            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(layoutRows(for: displayedIndicators(in: layoutSection))) { row in
                        DashboardSlotRowLayout(
                            slotCapacity: row.slotCapacity,
                            spans: row.items.map(\.width.slotSpan),
                            spacing: 16
                        ) {
                            ForEach(row.items) { item in
                                dashboardCard(item.indicator, in: layoutSection)
                            }
                        }
                    }
                }
                .padding(.leading, 12)
            }
        }
        .padding(.horizontal, 12)
    }

    private func extendedSectionButton(
        _ section: DashboardSection,
        errorMessage: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    await viewModel.loadExtendedIndicators(for: section)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text("\(section.title) · 2 уровень")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 52)
                .frame(maxWidth: .infinity)
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(isEditingLayout)
        }
        .padding(.horizontal, 12)
    }

    private func extendedStatusText(
        _ extended: DashboardExtendedSection,
        parent: DashboardSection
    ) -> String {
        let count = sectionCountText(extended.indicators.count)
        guard let fetchedAt = extended.fetchedAt else { return "\(count) · сохранённые данные" }
        let timestamp = fetchedAt.formatted(date: .numeric, time: .shortened)
        return viewModel.staleSectionIDs.contains(parent.id)
            ? "\(count) · сохранено \(timestamp)"
            : "\(count) · обновлено \(timestamp)"
    }

    private func extendedStatusLabel(
        _ extended: DashboardExtendedSection,
        parent: DashboardSection
    ) -> some View {
        let isStale = viewModel.staleSectionIDs.contains(parent.id)
        return HStack(spacing: 4) {
            if isStale {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .accessibilityHidden(true)
            }
            Text(extendedStatusText(extended, parent: parent))
        }
        .font(.caption)
        .foregroundStyle(isStale ? Color.orange : Color.secondary)
    }

    private func synchronizationDetailsBinding(forPad: Bool) -> Binding<Bool> {
        Binding {
            isShowingSynchronizationDetails && isPad == forPad
        } set: { value in
            if !value { isShowingSynchronizationDetails = false }
        }
    }

    private var synchronizationDetails: some View {
        DashboardSynchronizationDetailsView(
            sessions: viewModel.synchronizationHistory,
            networkError: viewModel.refreshErrorMessage,
            cacheError: viewModel.cacheErrorMessage
        )
    }

    private var chartPaletteScheme: ChartPaletteScheme {
        ChartPaletteScheme(rawValue: chartPaletteSchemeRawValue) ?? .corporate
    }

    private var normalizedContentScale: Double {
        DashboardContentScalePolicy.normalized(dashboardContentScale)
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

    private func sectionStatusLabel(_ section: DashboardSection) -> some View {
        let isStale = viewModel.staleSectionIDs.contains(section.id)
        return HStack(spacing: 4) {
            if isStale {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .accessibilityHidden(true)
            }
            Text(sectionStatusText(section))
        }
        .font(.caption)
        .foregroundStyle(isStale ? Color.orange : Color.secondary)
    }

    private func toggleAllSections(in dashboard: Dashboard) {
        let action = DashboardBulkSectionActionPolicy.action(
            sectionIDs: dashboard.sections.map(\.id),
            collapsedSectionIDs: collapsedSectionIDs
        )
        withAnimation(.easeInOut(duration: 0.24)) {
            switch action {
            case .expandPreservingPosition:
                for section in dashboard.sections {
                    sectionAnimationGenerations[section.id, default: 0] &+= 1
                }
                collapsedSectionIDs.removeAll()
            case .collapseAndScrollToTop:
                collapsedSectionIDs = Set(dashboard.sections.map(\.id))
            }
        }
        if action == .collapseAndScrollToTop {
            scrollToTopRequest &+= 1
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

    private var contentScaleBinding: Binding<Double> {
        Binding {
            normalizedContentScale
        } set: { newValue in
            dashboardContentScale = DashboardContentScalePolicy.normalized(newValue)
        }
    }
}
