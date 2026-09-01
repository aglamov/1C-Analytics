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

enum DashboardSectionTextPolicy {
    static func graphCount(in section: DashboardSection) -> Int {
        section.indicators.count + (section.extended?.indicators.count ?? 0)
    }

    static func graphCountText(_ count: Int) -> String {
        let remainder100 = count % 100
        let noun: String
        if 11...14 ~= remainder100 {
            noun = "графиков"
        } else {
            switch count % 10 {
            case 1: noun = "график"
            case 2...4: noun = "графика"
            default: noun = "графиков"
            }
        }
        return "\(count) \(noun)"
    }
}

enum DashboardExtendedSectionPresentationPolicy {
    static func shouldCollapseAfterFailedLoad(hasCachedContent: Bool) -> Bool {
        !hasCachedContent
    }
}

struct DashboardView: View {
    private static let feedTopAnchor = "dashboard-feed-top"

    @StateObject var viewModel: DashboardViewModel
    @StateObject private var layoutStore = DashboardLayoutStore()
    let onSignOut: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("chartPaletteScheme") private var chartPaletteSchemeRawValue = ChartPaletteScheme.standard.rawValue
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

                    ToolbarItem(placement: .principal) {
                        if let section = navigationSection {
                            let style = DashboardSectionVisualStyle.style(for: section.title)
                            HStack(spacing: 7) {
                                Image(systemName: style.symbol)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(style.tint)
                                    .frame(width: 24, height: 24)
                                    .background(
                                        style.tint.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    )

                                Text(section.title)
                                    .font(.headline)
                                    .lineLimit(1)
                            }
                            .accessibilityElement(children: .combine)
                        }
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
            initialLoadingContent
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
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
    }

    private var initialLoadingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(AnalyticsAPIContract.sections) { section in
                    let style = DashboardSectionVisualStyle.style(for: section.displayName)
                    sectionHeaderLabel(
                        title: section.displayName,
                        subtitle: "Загрузка графиков…",
                        symbol: style.symbol,
                        tint: style.tint,
                        isExpanded: false,
                        isLoading: true,
                        isStale: false
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(section.displayName), загрузка графиков")
                }
            }
            .padding(.horizontal, horizontalSizeClass == .regular ? 20 : 16)
            .padding(.top, 16)
            .padding(.bottom, 92)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
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
                            spans: row.spans(expandingSingleItemToFill: isRegularPadLayout),
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
                .padding(.top, 2)
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
            sectionHeaderLabel(
                title: section.title,
                subtitle: DashboardSectionTextPolicy.graphCountText(
                    DashboardSectionTextPolicy.graphCount(in: section)
                ),
                symbol: style.symbol,
                tint: style.tint,
                isExpanded: isExpanded,
                isLoading: false,
                isStale: viewModel.staleSectionIDs.contains(section.id)
            )
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

    private func sectionHeaderLabel(
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        isExpanded: Bool,
        isLoading: Bool,
        isStale: Bool
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(
                    tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    if isStale {
                        Image(systemName: "externaldrive.badge.exclamationmark")
                            .accessibilityHidden(true)
                    }
                    Text(subtitle)
                }
                .font(.caption)
                .foregroundStyle(isStale ? Color.orange : Color.secondary)
            }

            Spacer(minLength: 12)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isExpanded ? 8 : 12)
        .frame(minHeight: isExpanded ? 58 : 66)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(isExpanded ? 0 : 0.11))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(isExpanded ? 0 : 0.12), lineWidth: 1)
        }
        .shadow(
            color: Color.black.opacity(isExpanded ? 0 : 0.07),
            radius: isExpanded ? 0 : 6,
            x: 0,
            y: isExpanded ? 0 : 3
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.22), value: isExpanded)
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
            extendedSectionGroup(parent: section)
        }
    }

    private func extendedSectionGroup(
        parent: DashboardSection
    ) -> some View {
        let extendedID = extendedSectionID(for: parent)
        let extended = parent.extended
        let state = viewModel.extendedState(for: parent.id)
        let isExpanded = expandedExtendedSectionIDs.contains(extendedID)
        let isLoading = state == .loading

        return VStack(alignment: .leading, spacing: 12) {
            Button {
                toggleExtendedSection(for: parent)
            } label: {
                extendedSectionHeaderLabel(
                    title: "\(parent.title) 2 уровень",
                    subtitle: extendedSectionSubtitle(parent: parent, state: state),
                    isExpanded: isExpanded,
                    isLoading: isLoading,
                    isStale: viewModel.staleSectionIDs.contains(parent.id)
                )
            }
            .buttonStyle(.plain)
            .disabled(isEditingLayout || isLoading)
            .accessibilityLabel("\(parent.title) 2 уровень")
            .accessibilityValue(isLoading ? "Загружается" : (isExpanded ? "Развернуто" : "Свернуто"))
            .accessibilityAddTraits(.isHeader)

            if isExpanded, let extended {
                let layoutSection = DashboardSection(
                    id: extended.id,
                    title: extended.title,
                    indicators: extended.indicators,
                    fetchedAt: extended.fetchedAt
                )
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(layoutRows(for: displayedIndicators(in: layoutSection))) { row in
                        DashboardSlotRowLayout(
                            slotCapacity: row.slotCapacity,
                            spans: row.spans(expandingSingleItemToFill: isRegularPadLayout),
                            spacing: 16
                        ) {
                            ForEach(row.items) { item in
                                dashboardCard(item.indicator, in: layoutSection)
                            }
                        }
                    }
                }
            }
        }
    }

    private func extendedSectionHeaderLabel(
        title: String,
        subtitle: String,
        isExpanded: Bool,
        isLoading: Bool,
        isStale: Bool
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    if isStale {
                        Image(systemName: "externaldrive.badge.exclamationmark")
                            .accessibilityHidden(true)
                    }
                    Text(subtitle)
                }
                .font(.caption)
                .foregroundStyle(isStale ? Color.orange : Color.secondary)
            }

            Spacer(minLength: 12)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func extendedSectionID(for section: DashboardSection) -> DashboardExtendedSection.ID {
        section.extended?.id ?? "extended:\(section.id)"
    }

    private func extendedSectionSubtitle(
        parent: DashboardSection,
        state: DashboardViewModel.ExtendedSectionLoadState
    ) -> String {
        switch state {
        case .loading:
            return "Загрузка графиков…"
        case .failed:
            return "Ошибка загрузки · нажмите, чтобы повторить"
        case .idle, .loaded:
            guard let count = parent.extended?.indicators.count else {
                return "Загрузить графики"
            }
            return DashboardSectionTextPolicy.graphCountText(count)
        }
    }

    private func toggleExtendedSection(for section: DashboardSection) {
        let extendedID = extendedSectionID(for: section)
        if expandedExtendedSectionIDs.contains(extendedID) {
            withAnimation(.easeInOut(duration: 0.22)) {
                _ = expandedExtendedSectionIDs.remove(extendedID)
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            _ = expandedExtendedSectionIDs.insert(extendedID)
            sectionAnimationGenerations[extendedID, default: 0] &+= 1
        }

        let state = viewModel.extendedState(for: section.id)
        let shouldReload: Bool
        if case .failed = state {
            shouldReload = true
        } else {
            shouldReload = false
        }
        guard section.extended == nil || shouldReload else {
            return
        }

        Task {
            await viewModel.loadExtendedIndicators(for: section)
            let hasCachedContent = viewModel.dashboard?.sections
                .first(where: { $0.id == section.id })?
                .extended != nil
            if case .failed = viewModel.extendedState(for: section.id),
               DashboardExtendedSectionPresentationPolicy.shouldCollapseAfterFailedLoad(
                   hasCachedContent: hasCachedContent
               ) {
                withAnimation(.easeInOut(duration: 0.22)) {
                    _ = expandedExtendedSectionIDs.remove(extendedID)
                }
            }
        }
    }

    private func synchronizationDetailsBinding(forPad: Bool) -> Binding<Bool> {
        Binding {
            isShowingSynchronizationDetails && isPad == forPad
        } set: { value in
            if !value { isShowingSynchronizationDetails = false }
        }
    }

    @ViewBuilder
    private var synchronizationDetails: some View {
        if let session = viewModel.synchronizationSession {
            DashboardSynchronizationDetailsView(
                session: session,
                networkError: viewModel.refreshErrorMessage,
                cacheError: viewModel.cacheErrorMessage
            )
        } else {
            ContentUnavailableView(
                "Нет текущего сеанса",
                systemImage: "arrow.triangle.2.circlepath",
                description: Text("Запустите обновление, чтобы увидеть его состояние.")
            )
        }
    }

    private var chartPaletteScheme: ChartPaletteScheme {
        ChartPaletteScheme(rawValue: chartPaletteSchemeRawValue) ?? .standard
    }

    private var normalizedContentScale: Double {
        DashboardContentScalePolicy.normalized(dashboardContentScale)
    }

    private var navigationTitle: String {
        navigationSection?.title ?? "1С Аналитика"
    }

    private var navigationSection: DashboardSection? {
        guard hasFirstSectionHeaderPassedTop,
              let dashboard = viewModel.dashboard,
              let sectionID = currentSectionID ?? dashboard.sections.first?.id else {
            return nil
        }
        return dashboard.sections.first(where: { $0.id == sectionID })
    }

    private func toggleSection(_ sectionID: DashboardSection.ID) {
        withAnimation(.easeInOut(duration: 0.22)) {
            if collapsedSectionIDs.contains(sectionID) {
                sectionAnimationGenerations[sectionID, default: 0] &+= 1
                collapsedSectionIDs.remove(sectionID)
            } else {
                collapsedSectionIDs.insert(sectionID)
                if let section = viewModel.dashboard?.sections.first(where: { $0.id == sectionID }) {
                    expandedExtendedSectionIDs.remove(extendedSectionID(for: section))
                }
            }
        }
    }

    private func allSectionsAreCollapsed(in dashboard: Dashboard) -> Bool {
        !dashboard.sections.isEmpty
            && dashboard.sections.allSatisfy { collapsedSectionIDs.contains($0.id) }
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
                expandedExtendedSectionIDs.removeAll()
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
