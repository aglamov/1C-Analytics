import Foundation

@MainActor
protocol AnalyticsProvider {
    func fetchDashboard() async throws -> Dashboard
    func fetchDashboard(
        onSectionReceived: @escaping @MainActor @Sendable (DashboardSection) -> Void
    ) async throws -> Dashboard
    func fetchExtendedSection(for section: AnalyticsAPIContract.Section) async throws -> DashboardSection
}

extension AnalyticsProvider {
    func fetchDashboard(
        onSectionReceived: @escaping @MainActor @Sendable (DashboardSection) -> Void
    ) async throws -> Dashboard {
        let dashboard = try await fetchDashboard()
        dashboard.sections.forEach(onSectionReceived)
        return dashboard
    }

    func fetchExtendedSection(for section: AnalyticsAPIContract.Section) async throws -> DashboardSection {
        throw AnalyticsError.invalidResponse
    }
}

enum AnalyticsProviderFactory {
    @MainActor
    static func makeProvider(configuration: AppConfiguration = .load()) -> any AnalyticsProvider {
        APIAnalyticsProvider(configuration: configuration)
    }
}

enum AnalyticsError: LocalizedError, Equatable, Sendable {
    case invalidResponse
    case authenticationRequired
    case httpFailure(statusCode: Int)
    case partialFailure(sections: [String])

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Сервис аналитики вернул неожиданный ответ."
        case .authenticationRequired:
            "Сессия завершена. Выполните вход повторно."
        case let .httpFailure(statusCode):
            "Сервис аналитики вернул ошибку (код \(statusCode))."
        case let .partialFailure(sections):
            "Не удалось обновить разделы: \(sections.joined(separator: ", ")). Уже полученные данные сохранены."
        }
    }
}

enum AnalyticsAPIContract {
    static let requestID = "test_analitycs_med"
    static let sections = [
        Section(queryValue: "Образование", displayName: "Образование"),
        Section(queryValue: "Финансы", displayName: "Финансы"),
        Section(queryValue: "Наука", displayName: "Наука"),
        Section(queryValue: "Приемная_кампания", displayName: "Приемная кампания"),
        Section(queryValue: "Международная_деятельность", displayName: "Международная деятельность"),
        Section(queryValue: "Кадры", displayName: "Кадры")
    ]

    struct Section: Sendable {
        let queryValue: String
        let displayName: String
    }

    static func order(of sectionTitle: String) -> Int {
        let normalizedTitle = normalize(sectionTitle)
        return sections.firstIndex {
            normalize($0.displayName) == normalizedTitle || normalize($0.queryValue) == normalizedTitle
        } ?? .max
    }

    static func section(matching sectionTitle: String) -> Section? {
        let normalizedTitle = normalize(sectionTitle)
        return sections.first {
            normalize($0.displayName) == normalizedTitle || normalize($0.queryValue) == normalizedTitle
        }
    }

    static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
