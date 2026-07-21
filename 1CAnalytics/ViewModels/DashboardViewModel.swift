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

        if let cachedDashboard {
            show(cachedDashboard, isCached: true)
        } else {
            state = .loading
        }

        do {
            let dashboard = try await provider.fetchDashboard()
            try? cache.save(dashboard)
            show(dashboard, isCached: false)
        } catch AnalyticsError.authenticationRequired {
            state = .failed(AnalyticsError.authenticationRequired.localizedDescription)
            onAuthenticationRequired()
        } catch {
            if cachedDashboard == nil {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func refresh() async {
        refreshErrorMessage = nil

        do {
            let dashboard = try await provider.fetchDashboard()
            try? cache.save(dashboard)
            show(dashboard, isCached: false)
        } catch AnalyticsError.authenticationRequired {
            state = .failed(AnalyticsError.authenticationRequired.localizedDescription)
            onAuthenticationRequired()
        } catch {
            if dashboard != nil {
                refreshErrorMessage = error.localizedDescription
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func dismissRefreshError() {
        refreshErrorMessage = nil
    }

    private func show(_ dashboard: Dashboard, isCached: Bool) {
        state = .loaded(dashboard)
        isShowingCachedData = isCached

        if !dashboard.indicators.contains(where: { $0.id == selectedIndicatorID }) {
            selectedIndicatorID = dashboard.indicators.first?.id
        }
    }
}
