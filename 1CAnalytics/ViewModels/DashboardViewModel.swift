import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(Dashboard)
        case failed(String)
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var isShowingCachedData = false
    @Published private(set) var refreshErrorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var staleSectionIDs: Set<DashboardSection.ID> = []
    @Published var selectedIndicatorID: Indicator.ID?

    private let provider: any AnalyticsProvider
    private let cache: any DashboardCaching
    private let onAuthenticationRequired: () -> Void

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
            show(
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
            show(dashboard, isCached: false, staleSectionIDs: [])
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
            show(dashboard, isCached: false, staleSectionIDs: [])
            refreshErrorMessage = nil
            saveToCache(dashboard)
        } catch AnalyticsError.authenticationRequired {
            state = .failed(AnalyticsError.authenticationRequired.localizedDescription)
            onAuthenticationRequired()
        } catch is CancellationError {
            return
        } catch {
            publishReceivedSections(receivedSections.sections, refreshFailed: true)

            if dashboard != nil {
                if receivedSections.sections.isEmpty, dashboard == dashboardBeforeRefresh {
                    isShowingCachedData = true
                    staleSectionIDs = Set(dashboard?.sections.map(\.id) ?? [])
                }
                refreshErrorMessage = Self.offlineMessage(for: error)
            } else {
                state = .failed(error.localizedDescription)
            }
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
                fetchedAt: section.fetchedAt ?? receivedAt
            )
        }
        var sections = dashboard?.sections ?? []
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
            fetchedAt: dashboard?.fetchedAt
                ?? normalizedReceivedSections.compactMap(\.fetchedAt).max(),
            sections: sections
        )
        let receivedIDs = Set(normalizedReceivedSections.map(\.id))
        let staleIDs = Set(sections.map(\.id)).subtracting(receivedIDs)
        show(
            partialDashboard,
            isCached: refreshFailed || !staleIDs.isEmpty,
            staleSectionIDs: staleIDs
        )
        saveToCache(partialDashboard)
    }

    private func show(
        _ dashboard: Dashboard,
        isCached: Bool,
        staleSectionIDs: Set<DashboardSection.ID>
    ) {
        state = .loaded(dashboard)
        isShowingCachedData = isCached
        self.staleSectionIDs = staleSectionIDs

        if !dashboard.indicators.contains(where: { $0.id == selectedIndicatorID }) {
            selectedIndicatorID = dashboard.indicators.first?.id
        }
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
