import Foundation

@MainActor
protocol AnalyticsProvider: Sendable {
    func fetchDashboard() async throws -> Dashboard
    func fetchDashboard(
        onEvent: @escaping @MainActor @Sendable (AnalyticsSectionFetchEvent) -> Void
    ) async throws -> Dashboard
    func fetchExtendedSection(for section: AnalyticsSectionDescriptor) async throws -> DashboardSection
}

extension AnalyticsProvider {
    func fetchDashboard(
        onEvent: @escaping @MainActor @Sendable (AnalyticsSectionFetchEvent) -> Void
    ) async throws -> Dashboard {
        let dashboard = try await fetchDashboard()
        guard let catalog = dashboard.catalog else { throw AnalyticsError.invalidCatalog }
        try AnalyticsSectionDescriptor.validate(catalog)
        onEvent(.catalog(catalog))
        for descriptor in catalog {
            onEvent(.started(descriptor))
            if let section = dashboard.sections.first(where: { $0.id == descriptor.id }) {
                onEvent(.succeeded(descriptor, section))
            }
        }
        return dashboard
    }

    func fetchExtendedSection(for section: AnalyticsSectionDescriptor) async throws -> DashboardSection {
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
    case invalidCatalog
    case invalidResponse
    case authenticationRequired
    case httpFailure(statusCode: Int)
    case partialFailure(sections: [String])

    var errorDescription: String? {
        switch self {
        case .invalidCatalog:
            "Сервис вернул некорректный каталог разделов. Предыдущий каталог сохранён."
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
    static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

struct AnalyticsSectionDescriptor: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let parameter: String
    let name: String

    let androidIcon: String?
    let iosIcon: String?
    let color: String?

    private enum CodingKeys: String, CodingKey {
        case id, parameter, name, androidIcon, color
        case iosIcon = "IosIcon"
    }

    init(id: String, parameter: String, name: String, androidIcon: String? = nil,
         iosIcon: String? = nil, color: String? = nil) {
        self.id = id
        self.parameter = parameter
        self.name = name
        self.androidIcon = androidIcon
        self.iosIcon = iosIcon
        self.color = color
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        parameter = try container.decode(String.self, forKey: .parameter)
        name = try container.decode(String.self, forKey: .name)
        // Optional presentation metadata must not invalidate an otherwise valid catalog.
        androidIcon = try? container.decode(String.self, forKey: .androidIcon)
        iosIcon = try? container.decode(String.self, forKey: .iosIcon)
        color = try? container.decode(String.self, forKey: .color)
    }

    static func validate(_ sections: [Self]) throws {
        var ids = Set<String>()
        for section in sections {
            guard !section.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !section.parameter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  ids.insert(section.id).inserted else { throw AnalyticsError.invalidCatalog }
        }
    }
}

enum AnalyticsSectionFetchEvent: Sendable {
    case catalog([AnalyticsSectionDescriptor])
    case started(AnalyticsSectionDescriptor)
    case succeeded(AnalyticsSectionDescriptor, DashboardSection)
    case failed(AnalyticsSectionDescriptor, String)
}
