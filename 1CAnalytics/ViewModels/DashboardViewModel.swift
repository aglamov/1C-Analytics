import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(Dashboard)
        case failed(String)
    }

    enum ExtendedSectionLoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var isShowingCachedData = false
    @Published private(set) var refreshErrorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var staleSectionIDs: Set<DashboardSection.ID> = []
    @Published private(set) var extendedSectionStates: [DashboardSection.ID: ExtendedSectionLoadState] = [:]
    @Published var selectedIndicatorID: Indicator.ID?

    private let provider: any AnalyticsProvider
    private let cache: any DashboardCaching
    private let onAuthenticationRequired: () -> Void
    private var standardDashboard: Dashboard?
    private var expandedSectionIDs: Set<DashboardSection.ID> = []
    private var extendedIndicatorsBySectionID: [DashboardSection.ID: [Indicator]] = [:]
    private var standardStaleSectionIDs: Set<DashboardSection.ID> = []
    private var extendedStaleSectionIDs: Set<DashboardSection.ID> = []
    private var isStandardShowingCachedData = false

    init(
        provider: any AnalyticsProvider,
        cache: any DashboardCaching = DashboardCacheFactory.makeCache(),
        onAuthenticationRequired: @escaping () -> Void = {}
    ) {
        self.provider = provider
        self.cache = cache
        self.onAuthenticationRequired = onAuthenticationRequired
    }

    var dashboard: Dashboard? {
        if case let .loaded(dashboard) = state {
            dashboard
        } else {
            nil
        }
    }

    var selectedIndicator: Indicator? {
        guard let selectedIndicatorID else {
            return dashboard?.indicators.first
        }

        return dashboard?.indicators.first { $0.id == selectedIndicatorID }
    }

    func load() async {
        refreshErrorMessage = nil
        let cachedDashboard: Dashboard?
        do {
            cachedDashboard = try cache.loadDashboard()
        } catch {
            cachedDashboard = nil
            refreshErrorMessage = Self.cacheReadMessage(for: error)
        }
        let receivedSections = DashboardSectionAccumulator()

        if let cachedDashboard {
            showStandardDashboard(
                cachedDashboard,
                isCached: true,
                staleSectionIDs: Set(cachedDashboard.sections.map(\.id))
            )
        } else {
            state = .loading
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let dashboard = try await provider.fetchDashboard { section in
                receivedSections.append(section)
                self.publishReceivedSections(receivedSections.sections)
            }
            showStandardDashboard(dashboard, isCached: false, staleSectionIDs: [])
            refreshErrorMessage = nil
            saveToCache(dashboard)
        } catch AnalyticsError.authenticationRequired {
            state = .failed(AnalyticsError.authenticationRequired.localizedDescription)
            onAuthenticationRequired()
        } catch is CancellationError {
            return
        } catch {
            publishReceivedSections(receivedSections.sections, refreshFailed: true)

            if dashboard == nil {
                state = .failed(error.localizedDescription)
            } else {
                refreshErrorMessage = Self.offlineMessage(for: error)
            }
        }
    }

    func refresh() async {
        refreshErrorMessage = nil
        isRefreshing = true
        defer { isRefreshing = false }

        let dashboardBeforeRefresh = dashboard
        let receivedSections = DashboardSectionAccumulator()
        do {
            let dashboard = try await provider.fetchDashboard { section in
                receivedSections.append(section)
                self.publishReceivedSections(receivedSections.sections)
            }
            showStandardDashboard(dashboard, isCached: false, staleSectionIDs: [])
            refreshErrorMessage = nil
            saveToCache(dashboard)
            await refreshActivatedExtendedSections()
        } catch AnalyticsError.authenticationRequired {
            state = .failed(AnalyticsError.authenticationRequired.localizedDescription)
            onAuthenticationRequired()
        } catch is CancellationError {
            return
        } catch {
            publishReceivedSections(receivedSections.sections, refreshFailed: true)

            if dashboard != nil {
                if receivedSections.sections.isEmpty, dashboard == dashboardBeforeRefresh {
                    isStandardShowingCachedData = true
                    standardStaleSectionIDs = Set(dashboard?.sections.map(\.id) ?? [])
                    updateFreshnessState()
                }
                refreshErrorMessage = Self.offlineMessage(for: error)
                await refreshActivatedExtendedSections()
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func extendedState(for sectionID: DashboardSection.ID) -> ExtendedSectionLoadState {
        extendedSectionStates[sectionID] ?? .idle
    }

    func loadExtendedIndicators(for section: DashboardSection) async {
        guard section.hasExtended,
              let contract = AnalyticsAPIContract.section(matching: section.title) else {
            return
        }

        extendedSectionStates[section.id] = .loading

        do {
            let extendedSection = try await provider.fetchExtendedSection(for: contract)
            extendedIndicatorsBySectionID[section.id] = extendedSection.indicators
            expandedSectionIDs.insert(section.id)
            extendedSectionStates[section.id] = .loaded
            extendedStaleSectionIDs.remove(section.id)
            updateFreshnessState()
            renderDashboard()
        } catch AnalyticsError.authenticationRequired {
            state = .failed(AnalyticsError.authenticationRequired.localizedDescription)
            onAuthenticationRequired()
        } catch is CancellationError {
            extendedSectionStates[section.id] = .idle
        } catch {
            extendedSectionStates[section.id] = .failed(error.localizedDescription)
        }
    }

    private func publishReceivedSections(
        _ receivedSections: [DashboardSection],
        refreshFailed: Bool = false
    ) {
        guard !receivedSections.isEmpty else {
            return
        }

        let receivedAt = Date()
        let normalizedReceivedSections = receivedSections.map { section in
            DashboardSection(
                id: section.id,
                title: section.title,
                indicators: section.indicators,
                fetchedAt: section.fetchedAt ?? receivedAt,
                hasExtended: section.hasExtended
            )
        }
        var sections = standardDashboard?.sections ?? []
        for section in normalizedReceivedSections {
            if let index = sections.firstIndex(where: {
                $0.id == section.id
                    || AnalyticsAPIContract.normalize($0.title) == AnalyticsAPIContract.normalize(section.title)
            }) {
                sections[index] = section
            } else {
                sections.append(section)
            }
        }
        sections.sort {
            let lhsOrder = AnalyticsAPIContract.order(of: $0.title)
            let rhsOrder = AnalyticsAPIContract.order(of: $1.title)
            if lhsOrder == rhsOrder {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return lhsOrder < rhsOrder
        }

        let partialDashboard = Dashboard(
            id: "analytics",
            title: "Аналитика",
            fetchedAt: standardDashboard?.fetchedAt
                ?? normalizedReceivedSections.compactMap(\.fetchedAt).max(),
            sections: sections
        )
        let receivedIDs = Set(normalizedReceivedSections.map(\.id))
        let staleIDs = Set(sections.map(\.id)).subtracting(receivedIDs)
        showStandardDashboard(
            partialDashboard,
            isCached: refreshFailed || !staleIDs.isEmpty,
            staleSectionIDs: staleIDs
        )
        saveToCache(partialDashboard)
    }

    private func showStandardDashboard(
        _ dashboard: Dashboard,
        isCached: Bool,
        staleSectionIDs: Set<DashboardSection.ID>
    ) {
        standardDashboard = dashboard
        reconcileExtendedSections(with: dashboard)
        isStandardShowingCachedData = isCached
        standardStaleSectionIDs = staleSectionIDs
        updateFreshnessState()
        renderDashboard()
    }

    private func renderDashboard() {
        guard let standardDashboard else {
            return
        }

        let sections = standardDashboard.sections.map { section in
            let extendedIndicators = expandedSectionIDs.contains(section.id)
                ? (extendedIndicatorsBySectionID[section.id] ?? [])
                : []
            return DashboardSection(
                id: section.id,
                title: section.title,
                indicators: section.indicators + extendedIndicators,
                fetchedAt: section.fetchedAt,
                hasExtended: section.hasExtended
            )
        }
        let renderedDashboard = Dashboard(
            id: standardDashboard.id,
            title: standardDashboard.title,
            fetchedAt: standardDashboard.fetchedAt,
            sections: sections
        )
        state = .loaded(renderedDashboard)

        if !renderedDashboard.indicators.contains(where: { $0.id == selectedIndicatorID }) {
            selectedIndicatorID = renderedDashboard.indicators.first?.id
        }
    }

    private func reconcileExtendedSections(with dashboard: Dashboard) {
        let supportedIDs = Set(dashboard.sections.filter(\.hasExtended).map(\.id))
        let trackedIDs = expandedSectionIDs
            .union(extendedIndicatorsBySectionID.keys)
            .union(extendedSectionStates.keys)
        for sectionID in trackedIDs.subtracting(supportedIDs) {
            expandedSectionIDs.remove(sectionID)
            extendedIndicatorsBySectionID.removeValue(forKey: sectionID)
            extendedSectionStates.removeValue(forKey: sectionID)
            extendedStaleSectionIDs.remove(sectionID)
        }
        updateFreshnessState()
    }

    private func refreshActivatedExtendedSections() async {
        guard let standardDashboard else {
            return
        }

        for section in standardDashboard.sections where expandedSectionIDs.contains(section.id) {
            guard section.hasExtended,
                  let contract = AnalyticsAPIContract.section(matching: section.title) else {
                continue
            }

            extendedSectionStates[section.id] = .loading
            do {
                let refreshedSection = try await provider.fetchExtendedSection(for: contract)
                extendedIndicatorsBySectionID[section.id] = refreshedSection.indicators
                extendedSectionStates[section.id] = .loaded
                extendedStaleSectionIDs.remove(section.id)
                updateFreshnessState()
                renderDashboard()
            } catch AnalyticsError.authenticationRequired {
                state = .failed(AnalyticsError.authenticationRequired.localizedDescription)
                onAuthenticationRequired()
                return
            } catch is CancellationError {
                extendedSectionStates[section.id] = .loaded
                return
            } catch {
                extendedSectionStates[section.id] = .failed(error.localizedDescription)
                extendedStaleSectionIDs.insert(section.id)
                updateFreshnessState()
                refreshErrorMessage = "Не удалось обновить дополнительный уровень раздела «\(section.title)»."
            }
        }
    }

    private func updateFreshnessState() {
        staleSectionIDs = standardStaleSectionIDs.union(extendedStaleSectionIDs)
        isShowingCachedData = isStandardShowingCachedData || !extendedStaleSectionIDs.isEmpty
    }

    private static func offlineMessage(for error: Error) -> String {
        guard let urlError = error as? URLError else {
            return error.localizedDescription
        }

        switch urlError.code {
        case .notConnectedToInternet:
            return "Нет подключения к интернету. Показаны последние сохранённые данные."
        case .timedOut:
            return "Сервер не успел ответить. Подождите немного и повторите обновление."
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost:
            return "Не удалось связаться с сервером. Показаны последние сохранённые данные."
        default:
            return urlError.localizedDescription
        }
    }

    private func saveToCache(_ dashboard: Dashboard) {
        do {
            try cache.save(dashboard)
        } catch {
            refreshErrorMessage = Self.cacheWriteMessage(for: error)
        }
    }

    private static func cacheReadMessage(for error: Error) -> String {
        "Не удалось прочитать сохранённые данные. \(error.localizedDescription)"
    }

    private static func cacheWriteMessage(for error: Error) -> String {
        "Данные обновлены, но сохранить их для офлайн-режима не удалось. \(error.localizedDescription)"
    }
}

@MainActor
private final class DashboardSectionAccumulator {
    private(set) var sections: [DashboardSection] = []

    func append(_ section: DashboardSection) {
        sections.append(section)
    }
}
