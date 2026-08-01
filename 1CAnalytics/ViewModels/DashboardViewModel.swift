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
        let cachedDashboard = try? cache.loadDashboard()
        let receivedSections = DashboardSectionAccumulator()

        if let cachedDashboard {
            show(cachedDashboard, isCached: true)
        } else {
            state = .loading
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let dashboard = try await provider.fetchDashboard { section in
                receivedSections.append(section)
            }
            try? cache.save(dashboard)
            show(dashboard, isCached: false)
        } catch AnalyticsError.authenticationRequired {
            state = .failed(AnalyticsError.authenticationRequired.localizedDescription)
            onAuthenticationRequired()
        } catch {
            publishReceivedSections(receivedSections.sections)

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
            }
            try? cache.save(dashboard)
            show(dashboard, isCached: false)
        } catch AnalyticsError.authenticationRequired {
            state = .failed(AnalyticsError.authenticationRequired.localizedDescription)
            onAuthenticationRequired()
        } catch {
            publishReceivedSections(receivedSections.sections)

            if dashboard != nil {
                isShowingCachedData = receivedSections.sections.isEmpty
                    && dashboard == dashboardBeforeRefresh
                refreshErrorMessage = Self.offlineMessage(for: error)
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func publishReceivedSections(_ receivedSections: [DashboardSection]) {
        guard !receivedSections.isEmpty else {
            return
        }

        var sections = dashboard?.sections ?? []
        for section in receivedSections {
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
            fetchedAt: Date(),
            sections: sections
        )
        try? cache.save(partialDashboard)
        show(partialDashboard, isCached: false)
    }

    private func show(_ dashboard: Dashboard, isCached: Bool) {
        state = .loaded(dashboard)
        isShowingCachedData = isCached

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
}

@MainActor
private final class DashboardSectionAccumulator {
    private(set) var sections: [DashboardSection] = []

    func append(_ section: DashboardSection) {
        sections.append(section)
    }
}
