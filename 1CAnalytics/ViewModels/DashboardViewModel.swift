import Foundation

struct DashboardSynchronizationSession: Identifiable, Codable, Equatable, Sendable {
    enum Phase: String, Codable, Equatable, Sendable {
        case running
        case completed
    }

    struct Item: Identifiable, Codable, Equatable, Sendable {
        enum Kind: String, Codable, Equatable, Sendable { case standard, extended }
        enum Status: String, Codable, Equatable, Sendable {
            case pending
            case updating
            case succeeded
            case cached
            case failed
        }

        struct Chart: Identifiable, Codable, Equatable, Sendable {
            let id: String
            let title: String
            let type: String
            let valueCount: Int
            let source: String?
            var status: Status
            var timestamp: Date?
            var errorMessage: String?
        }

        let id: String
        let title: String
        let kind: Kind
        var status: Status
        var timestamp: Date?
        var errorMessage: String?
        var charts: [Chart] = []
    }

    let id: UUID
    let title: String
    let startedAt: Date
    var completedAt: Date?
    var phase: Phase
    var items: [Item]

    var completedCount: Int {
        items.filter { $0.status == .succeeded || $0.status == .cached || $0.status == .failed }.count
    }

    var totalCount: Int { items.count }
    var hasFailures: Bool { items.contains { $0.status == .failed || $0.status == .cached } }
}

enum DashboardSynchronizationStoragePolicy {
    static let legacyHistoryKey = "dashboard.synchronization-history.v1"

    static func discardLegacyHistory(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: legacyHistoryKey)
    }
}

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
    @Published private(set) var cacheErrorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var staleSectionIDs: Set<DashboardSection.ID> = []
    @Published private(set) var extendedSectionStates: [DashboardSection.ID: ExtendedSectionLoadState] = [:]
    @Published private(set) var synchronizationSession: DashboardSynchronizationSession?
    @Published var selectedIndicatorID: Indicator.ID?

    private let provider: any AnalyticsProvider
    private let cache: any DashboardCaching
    private let onAuthenticationRequired: () -> Void
    private var dashboardStorage: Dashboard?
    private var standardStaleSectionIDs: Set<DashboardSection.ID> = []
    private var extendedStaleSectionIDs: Set<DashboardSection.ID> = []
    private var isStandardShowingCachedData = false

    private struct ExtendedRefreshOutcome: Sendable {
        enum Failure: Sendable {
            case cancelled
            case message(String)
        }

        let sectionID: DashboardSection.ID
        let response: DashboardSection?
        let failure: Failure?
    }

    private struct ExtendedRefreshError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    convenience init(
        provider: any AnalyticsProvider,
        cache: any DashboardCaching = DashboardCacheFactory.makeCache(),
        onAuthenticationRequired: @escaping () -> Void = {}
    ) {
        self.init(
            provider: provider,
            cache: cache,
            legacyHistoryDefaults: .standard,
            onAuthenticationRequired: onAuthenticationRequired
        )
    }

    init(
        provider: any AnalyticsProvider,
        cache: any DashboardCaching,
        legacyHistoryDefaults: UserDefaults,
        onAuthenticationRequired: @escaping () -> Void = {}
    ) {
        self.provider = provider
        self.cache = cache
        self.onAuthenticationRequired = onAuthenticationRequired
        DashboardSynchronizationStoragePolicy.discardLegacyHistory(from: legacyHistoryDefaults)
    }

    var dashboard: Dashboard? { dashboardStorage }

    var selectedIndicator: Indicator? {
        guard let selectedIndicatorID else { return dashboard?.indicators.first }
        return dashboard?.indicators.first { $0.id == selectedIndicatorID }
    }

    func load() async {
        refreshErrorMessage = nil
        cacheErrorMessage = nil
        do {
            if let cached = try cache.loadDashboard() {
                showDashboard(cached, cached: true, stale: Set(cached.sections.map(\.id)))
            } else {
                state = .loading
            }
        } catch {
            cacheErrorMessage = Self.cacheReadMessage(for: error)
            state = .loading
        }
        await synchronizeDashboard(title: "Обновление при запуске")
    }

    func refresh() async {
        refreshErrorMessage = nil
        cacheErrorMessage = nil
        await synchronizeDashboard(title: "Ручное обновление дашборда")
    }

    func extendedState(for sectionID: DashboardSection.ID) -> ExtendedSectionLoadState {
        extendedSectionStates[sectionID] ?? .idle
    }

    func loadExtendedIndicators(for section: DashboardSection) async {
        guard section.hasExtended,
              let contract = AnalyticsAPIContract.section(matching: section.title) else { return }

        beginSession(
            title: "Ручное обновление второго уровня",
            items: [synchronizationItem(for: section)]
        )
        updateSessionItem(id: extendedTaskID(section.id), status: .updating)
        extendedSectionStates[section.id] = .loading
        isRefreshing = true
        defer {
            isRefreshing = false
            completeSession()
        }

        do {
            let response = try await provider.fetchExtendedSection(for: contract)
            storeExtendedResponse(response, in: section)
            extendedSectionStates[section.id] = .loaded
            extendedStaleSectionIDs.remove(section.id)
            updateSessionItem(
                id: extendedTaskID(section.id),
                status: .succeeded,
                timestamp: response.fetchedAt ?? Date(),
                indicators: response.indicators
            )
            updateFreshnessState()
            saveCurrentDashboard()
        } catch AnalyticsError.authenticationRequired {
            failExtended(section, error: AnalyticsError.authenticationRequired)
            if dashboard == nil { state = .failed(AnalyticsError.authenticationRequired.localizedDescription) }
            onAuthenticationRequired()
        } catch is CancellationError {
            extendedSectionStates[section.id] = section.extended == nil ? .idle : .loaded
        } catch {
            failExtended(section, error: error)
        }
    }

    private func synchronizeDashboard(title: String) async {
        guard !isRefreshing else { return }
        let cachedExtended = dashboardStorage?.sections.filter { $0.extended != nil } ?? []
        let standardItems = AnalyticsAPIContract.sections.map(standardSynchronizationItem)
        beginSession(title: title, items: standardItems + cachedExtended.map { synchronizationItem(for: $0) })
        isRefreshing = true
        defer {
            isRefreshing = false
            completeSession()
        }

        async let extendedRefresh: Void = refreshSavedExtendedSections(cachedExtended.map(\.id))

        do {
            let fresh = try await provider.fetchDashboard { event in
                self.handle(event)
            }
            mergeFinalDashboard(fresh)
            refreshErrorMessage = nil
        } catch AnalyticsError.authenticationRequired {
            refreshErrorMessage = AnalyticsError.authenticationRequired.localizedDescription
            state = .failed(AnalyticsError.authenticationRequired.localizedDescription)
            onAuthenticationRequired()
        } catch is CancellationError {
            return
        } catch {
            refreshErrorMessage = Self.offlineMessage(for: error)
            if let dashboardStorage {
                let receivedAnyStandardSection = synchronizationSession?.items.contains {
                    $0.kind == .standard && $0.status == .succeeded
                } == true
                if !receivedAnyStandardSection {
                    standardStaleSectionIDs = Set(dashboardStorage.sections.map(\.id))
                }
                isStandardShowingCachedData = true
            } else {
                state = .failed(error.localizedDescription)
            }
        }

        await extendedRefresh
        if case .loading = state, let dashboardStorage {
            state = .loaded(dashboardStorage)
        }
        updateFreshnessState()
    }

    private func handle(_ event: AnalyticsSectionFetchEvent) {
        switch event {
        case let .started(contract):
            updateSessionItem(id: standardTaskID(contract), status: .updating)
        case let .succeeded(contract, section):
            mergeSection(section)
            standardStaleSectionIDs.remove(section.id)
            updateSessionItem(
                id: standardTaskID(contract),
                status: .succeeded,
                timestamp: section.fetchedAt ?? Date(),
                indicators: section.indicators
            )
            saveCurrentDashboard()
        case let .failed(contract, message):
            let cachedSection = dashboardStorage?.sections.first {
                AnalyticsAPIContract.normalize($0.title) == AnalyticsAPIContract.normalize(contract.displayName)
            }
            if let cachedSection {
                standardStaleSectionIDs.insert(cachedSection.id)
                updateSessionItem(
                    id: standardTaskID(contract),
                    status: .cached,
                    timestamp: cachedSection.fetchedAt,
                    error: message,
                    indicators: cachedSection.indicators
                )
            } else {
                updateSessionItem(id: standardTaskID(contract), status: .failed, error: message)
            }
        }
        updateFreshnessState()
    }

    private func mergeSection(_ newSection: DashboardSection) {
        let dashboardFetchedAt = dashboardStorage?.fetchedAt
        var sections = dashboardStorage?.sections ?? []
        let matchingIndex = sections.firstIndex {
            $0.id == newSection.id || AnalyticsAPIContract.normalize($0.title) == AnalyticsAPIContract.normalize(newSection.title)
        }
        let oldExtended = matchingIndex.flatMap { sections[$0].extended }
        let merged = DashboardSection(
            id: newSection.id, title: newSection.title, indicators: newSection.indicators,
            fetchedAt: newSection.fetchedAt ?? Date(), hasExtended: newSection.hasExtended,
            extended: newSection.hasExtended ? oldExtended : nil
        )
        if let matchingIndex { sections[matchingIndex] = merged } else { sections.append(merged) }
        sections.sort { AnalyticsAPIContract.order(of: $0.title) < AnalyticsAPIContract.order(of: $1.title) }
        showDashboard(
            Dashboard(
                id: "analytics",
                title: "Аналитика",
                fetchedAt: dashboardFetchedAt ?? sections.compactMap(\.fetchedAt).max(),
                sections: sections
            ),
            cached: !standardStaleSectionIDs.isEmpty,
            stale: standardStaleSectionIDs,
            publishState: state != .loading
        )
    }

    private func mergeFinalDashboard(_ fresh: Dashboard) {
        let oldSections = dashboardStorage?.sections ?? []
        let sections = fresh.sections.map { section -> DashboardSection in
            let old = oldSections.first {
                $0.id == section.id || AnalyticsAPIContract.normalize($0.title) == AnalyticsAPIContract.normalize(section.title)
            }
            return DashboardSection(
                id: section.id, title: section.title, indicators: section.indicators,
                fetchedAt: section.fetchedAt, hasExtended: section.hasExtended,
                extended: section.hasExtended ? old?.extended : nil
            )
        }
        standardStaleSectionIDs.removeAll()
        showDashboard(Dashboard(id: fresh.id, title: fresh.title, fetchedAt: fresh.fetchedAt, sections: sections), cached: false, stale: [])
        saveCurrentDashboard()
    }

    private func refreshSavedExtendedSections(_ sectionIDs: [DashboardSection.ID]) async {
        let requests = sectionIDs.compactMap { sectionID -> (DashboardSection.ID, AnalyticsAPIContract.Section)? in
            guard let section = dashboardStorage?.sections.first(where: { $0.id == sectionID }) else {
                return nil
            }
            guard section.hasExtended,
                  let contract = AnalyticsAPIContract.section(matching: section.title) else {
                updateSessionItem(id: extendedTaskID(sectionID), status: .succeeded, timestamp: Date(), indicators: [])
                return nil
            }
            updateSessionItem(id: extendedTaskID(sectionID), status: .updating)
            extendedSectionStates[sectionID] = .loading
            return (sectionID, contract)
        }

        await withTaskGroup(of: ExtendedRefreshOutcome.self) { group in
            for (sectionID, contract) in requests {
                group.addTask { [provider] in
                    do {
                        let response = try await provider.fetchExtendedSection(for: contract)
                        return ExtendedRefreshOutcome(
                            sectionID: sectionID,
                            response: response,
                            failure: nil
                        )
                    } catch is CancellationError {
                        return ExtendedRefreshOutcome(
                            sectionID: sectionID,
                            response: nil,
                            failure: .cancelled
                        )
                    } catch {
                        return ExtendedRefreshOutcome(
                            sectionID: sectionID,
                            response: nil,
                            failure: .message(error.localizedDescription)
                        )
                    }
                }
            }

            for await outcome in group {
                guard let section = dashboardStorage?.sections.first(where: { $0.id == outcome.sectionID }) else {
                    continue
                }
                if let response = outcome.response {
                    storeExtendedResponse(response, in: section)
                    extendedSectionStates[outcome.sectionID] = .loaded
                    extendedStaleSectionIDs.remove(outcome.sectionID)
                    updateSessionItem(
                        id: extendedTaskID(outcome.sectionID),
                        status: .succeeded,
                        timestamp: response.fetchedAt ?? Date(),
                        indicators: response.indicators
                    )
                    saveCurrentDashboard()
                } else if case .cancelled = outcome.failure {
                    extendedSectionStates[outcome.sectionID] = section.extended == nil ? .idle : .loaded
                } else if case let .message(message) = outcome.failure {
                    failExtended(section, error: ExtendedRefreshError(message: message))
                }
            }
        }
    }

    private func storeExtendedResponse(_ response: DashboardSection, in parent: DashboardSection) {
        guard var dashboard = dashboardStorage,
              let index = dashboard.sections.firstIndex(where: { $0.id == parent.id }) else { return }
        let child = DashboardExtendedSection(
            id: extendedTaskID(parent.id),
            title: "\(parent.title) · 2 уровень",
            indicators: response.indicators,
            fetchedAt: response.fetchedAt ?? Date()
        )
        var sections = dashboard.sections
        let current = sections[index]
        sections[index] = DashboardSection(
            id: current.id, title: current.title, indicators: current.indicators,
            fetchedAt: current.fetchedAt, hasExtended: current.hasExtended, extended: child
        )
        dashboard = Dashboard(id: dashboard.id, title: dashboard.title, fetchedAt: dashboard.fetchedAt, sections: sections)
        showDashboard(dashboard, cached: isStandardShowingCachedData, stale: standardStaleSectionIDs)
    }

    private func failExtended(_ section: DashboardSection, error: Error) {
        let cachedChild = dashboardStorage?.sections.first(where: { $0.id == section.id })?.extended
        let hasCachedChild = cachedChild != nil
        extendedSectionStates[section.id] = .failed(error.localizedDescription)
        extendedStaleSectionIDs.insert(section.id)
        refreshErrorMessage = "Не удалось обновить второй уровень раздела «\(section.title)». \(error.localizedDescription)"
        updateSessionItem(
            id: extendedTaskID(section.id),
            status: hasCachedChild ? .cached : .failed,
            timestamp: section.extended?.fetchedAt,
            error: error.localizedDescription,
            indicators: cachedChild?.indicators
        )
        updateFreshnessState()
    }

    private func showDashboard(
        _ dashboard: Dashboard,
        cached: Bool,
        stale: Set<DashboardSection.ID>,
        publishState: Bool = true
    ) {
        dashboardStorage = dashboard
        isStandardShowingCachedData = cached
        standardStaleSectionIDs = stale
        if publishState {
            state = .loaded(dashboard)
        }
        if !dashboard.indicators.contains(where: { $0.id == selectedIndicatorID }) {
            selectedIndicatorID = dashboard.indicators.first?.id
        }
        for section in dashboard.sections where section.extended != nil {
            extendedSectionStates[section.id] = .loaded
        }
        updateFreshnessState()
    }

    private func updateFreshnessState() {
        staleSectionIDs = standardStaleSectionIDs.union(extendedStaleSectionIDs)
        isShowingCachedData = isStandardShowingCachedData || !staleSectionIDs.isEmpty
    }

    private func beginSession(title: String, items: [DashboardSynchronizationSession.Item]) {
        publishSession(DashboardSynchronizationSession(
            id: UUID(), title: title, startedAt: Date(), completedAt: nil,
            phase: .running, items: items
        ))
    }

    private func publishSession(_ session: DashboardSynchronizationSession) {
        synchronizationSession = session
    }

    private func chartItems(
        for indicators: [Indicator],
        status: DashboardSynchronizationSession.Item.Status,
        timestamp: Date?,
        error: String? = nil
    ) -> [DashboardSynchronizationSession.Item.Chart] {
        indicators.map { indicator in
            DashboardSynchronizationSession.Item.Chart(
                id: indicator.id,
                title: indicator.title,
                type: indicator.chartType.title,
                valueCount: max(indicator.rows.count, indicator.value == nil ? 0 : 1),
                source: indicator.source,
                status: status,
                timestamp: timestamp,
                errorMessage: error
            )
        }
    }

    private func standardSynchronizationItem(
        for contract: AnalyticsAPIContract.Section
    ) -> DashboardSynchronizationSession.Item {
        let cachedSection = dashboardStorage?.sections.first {
            AnalyticsAPIContract.normalize($0.title) == AnalyticsAPIContract.normalize(contract.displayName)
        }
        return DashboardSynchronizationSession.Item(
            id: standardTaskID(contract),
            title: contract.displayName,
            kind: .standard,
            status: .pending,
            timestamp: cachedSection?.fetchedAt,
            errorMessage: nil,
            charts: chartItems(
                for: cachedSection?.indicators ?? [],
                status: .pending,
                timestamp: cachedSection?.fetchedAt
            )
        )
    }

    private func completeSession() {
        guard var session = synchronizationSession else { return }
        for index in session.items.indices where session.items[index].status == .pending || session.items[index].status == .updating {
            let status: DashboardSynchronizationSession.Item.Status = dashboardStorage == nil ? .failed : .cached
            session.items[index].status = status
            session.items[index].timestamp = Date()
            session.items[index].errorMessage = session.items[index].errorMessage ?? refreshErrorMessage
            for chartIndex in session.items[index].charts.indices {
                session.items[index].charts[chartIndex].status = status
                session.items[index].charts[chartIndex].timestamp = session.items[index].timestamp
                session.items[index].charts[chartIndex].errorMessage = session.items[index].errorMessage
            }
        }
        session.phase = .completed
        session.completedAt = Date()
        publishSession(session)
    }

    private func updateSessionItem(
        id: String,
        status: DashboardSynchronizationSession.Item.Status,
        timestamp: Date? = nil,
        error: String? = nil,
        indicators: [Indicator]? = nil
    ) {
        guard var session = synchronizationSession,
              let index = session.items.firstIndex(where: { $0.id == id }) else { return }
        session.items[index].status = status
        session.items[index].timestamp = timestamp
        session.items[index].errorMessage = error
        if let indicators {
            session.items[index].charts = chartItems(
                for: indicators,
                status: status,
                timestamp: timestamp,
                error: error
            )
        } else {
            for chartIndex in session.items[index].charts.indices {
                session.items[index].charts[chartIndex].status = status
                session.items[index].charts[chartIndex].timestamp = timestamp
                session.items[index].charts[chartIndex].errorMessage = error
            }
        }
        publishSession(session)
    }

    private func synchronizationItem(for section: DashboardSection) -> DashboardSynchronizationSession.Item {
        DashboardSynchronizationSession.Item(
            id: extendedTaskID(section.id), title: "\(section.title) · 2 уровень", kind: .extended,
            status: .pending, timestamp: section.extended?.fetchedAt, errorMessage: nil,
            charts: chartItems(
                for: section.extended?.indicators ?? [],
                status: .pending,
                timestamp: section.extended?.fetchedAt
            )
        )
    }

    private func standardTaskID(_ section: AnalyticsAPIContract.Section) -> String { "standard:\(section.queryValue)" }
    private func extendedTaskID(_ sectionID: String) -> String { "extended:\(sectionID)" }

    private func saveCurrentDashboard() {
        guard let dashboardStorage else { return }
        do { try cache.save(dashboardStorage) }
        catch { cacheErrorMessage = Self.cacheWriteMessage(for: error) }
    }

    private static func offlineMessage(for error: Error) -> String {
        guard let urlError = error as? URLError else { return error.localizedDescription }
        return switch urlError.code {
        case .notConnectedToInternet: "Нет подключения к интернету. Показаны последние сохранённые данные."
        case .timedOut: "Сервер не успел ответить. Подождите немного и повторите обновление."
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost:
            "Не удалось связаться с сервером. Показаны последние сохранённые данные."
        default: urlError.localizedDescription
        }
    }

    private static func cacheReadMessage(for error: Error) -> String {
        "Не удалось прочитать сохранённые данные. \(error.localizedDescription)"
    }

    private static func cacheWriteMessage(for error: Error) -> String {
        "Данные обновлены, но сохранить их для офлайн-режима не удалось. \(error.localizedDescription)"
    }
}
