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
}

@MainActor
final class DashboardCache: DashboardCaching {
    private let modelContainer: ModelContainer
    private let credentialsStore: AuthenticationCredentialsStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        inMemory: Bool = false,
        credentialsStore: AuthenticationCredentialsStore = .shared
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
}

enum DashboardCacheFactory {
    @MainActor
    static func makeCache() -> any DashboardCaching {
        (try? DashboardCache()) ?? EmptyDashboardCache()
    }
}
