import Foundation

@MainActor
protocol AnalyticsProvider {
    func fetchDashboard() async throws -> Dashboard
}

enum AnalyticsProviderFactory {
    @MainActor
    static func makeProvider(configuration: AppConfiguration = .load()) -> any AnalyticsProvider {
        if configuration.useMockData {
            MockAnalyticsProvider()
        } else {
            APIAnalyticsProvider(configuration: configuration)
        }
    }
}

enum AnalyticsError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Сервис аналитики вернул неожиданный ответ."
        }
    }
}
