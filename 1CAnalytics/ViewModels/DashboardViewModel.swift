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
    @Published var selectedIndicatorID: Indicator.ID?

    private let provider: any AnalyticsProvider

    init(provider: any AnalyticsProvider) {
        self.provider = provider
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
        state = .loading

        do {
            let dashboard = try await provider.fetchDashboard()
            state = .loaded(dashboard)
            selectedIndicatorID = dashboard.indicators.first?.id
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refresh() async {
        await load()
    }
}
