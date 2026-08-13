import Foundation
import SwiftData

@Model
final class DashboardCacheRecord {
    @Attribute(.unique) var identifier: String
    var payload: Data
    var savedAt: Date

    init(identifier: String, payload: Data, savedAt: Date) {
        self.identifier = identifier
        self.payload = payload
        self.savedAt = savedAt
    }
}

@MainActor
protocol DashboardCaching {
    func loadDashboard() throws -> Dashboard?
    func save(_ dashboard: Dashboard) throws
    func clearDashboard() throws
}

@MainActor
final class DashboardCache: DashboardCaching {
    private let modelContainer: ModelContainer
    private let credentialsStore: any AuthenticationCredentialsStoring
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        inMemory: Bool = false,
        credentialsStore: any AuthenticationCredentialsStoring = AuthenticationCredentialsStore.shared
    ) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        self.modelContainer = try ModelContainer(
            for: DashboardCacheRecord.self,
            configurations: configuration
        )
        self.credentialsStore = credentialsStore
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadDashboard() throws -> Dashboard? {
        guard let identifier = try currentRecordIdentifier else {
            return nil
        }
        var descriptor = FetchDescriptor<DashboardCacheRecord>(
            predicate: #Predicate { $0.identifier == identifier }
        )
        descriptor.fetchLimit = 1

        guard let record = try modelContainer.mainContext.fetch(descriptor).first else {
            return nil
        }

        return try decoder.decode(Dashboard.self, from: record.payload)
    }

    func save(_ dashboard: Dashboard) throws {
        guard let identifier = try currentRecordIdentifier else {
            return
        }

        let payload = try encoder.encode(dashboard)
        var descriptor = FetchDescriptor<DashboardCacheRecord>(
            predicate: #Predicate { $0.identifier == identifier }
        )
        descriptor.fetchLimit = 1

        if let record = try modelContainer.mainContext.fetch(descriptor).first {
            record.payload = payload
            record.savedAt = Date()
        } else {
            modelContainer.mainContext.insert(
                DashboardCacheRecord(identifier: identifier, payload: payload, savedAt: Date())
            )
        }

        try modelContainer.mainContext.save()
    }

    func clearDashboard() throws {
        guard let identifier = try currentRecordIdentifier else {
            return
        }
        let descriptor = FetchDescriptor<DashboardCacheRecord>(
            predicate: #Predicate { $0.identifier == identifier }
        )

        for record in try modelContainer.mainContext.fetch(descriptor) {
            modelContainer.mainContext.delete(record)
        }
        try modelContainer.mainContext.save()
    }

    private var currentRecordIdentifier: String? {
        get throws {
            try credentialsStore.load()?.username
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }
    }
}

@MainActor
final class EmptyDashboardCache: DashboardCaching {
    func loadDashboard() throws -> Dashboard? { nil }
    func save(_ dashboard: Dashboard) throws {}
    func clearDashboard() throws {}
}

enum DashboardCacheFactory {
    @MainActor
    static func makeCache() -> any DashboardCaching {
        do {
            return try DashboardCache()
        } catch {
            return UnavailableDashboardCache(underlyingError: error)
        }
    }
}

enum DashboardCacheError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message):
            "Локальное хранилище недоступно: \(message)"
        }
    }
}

@MainActor
private final class UnavailableDashboardCache: DashboardCaching {
    private let error: DashboardCacheError

    init(underlyingError: Error) {
        self.error = .unavailable(underlyingError.localizedDescription)
    }

    func loadDashboard() throws -> Dashboard? {
        throw error
    }

    func save(_ dashboard: Dashboard) throws {
        throw error
    }

    func clearDashboard() throws {
        throw error
    }
}
