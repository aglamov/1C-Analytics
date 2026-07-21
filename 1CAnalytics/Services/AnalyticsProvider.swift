import Foundation

@MainActor
protocol AnalyticsProvider {
    func fetchDashboard() async throws -> Dashboard
}

enum AnalyticsProviderFactory {
    @MainActor
    static func makeProvider(configuration: AppConfiguration = .load()) -> any AnalyticsProvider {
        APIAnalyticsProvider(configuration: configuration)
    }
}

enum AnalyticsError: LocalizedError {
    case invalidResponse
    case authenticationRequired
    case httpFailure(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Сервис аналитики вернул неожиданный ответ."
        case .authenticationRequired:
            "Сессия завершена. Выполните вход повторно."
        case let .httpFailure(statusCode):
            "Сервис аналитики вернул ошибку (код \(statusCode))."
        }
    }
}
