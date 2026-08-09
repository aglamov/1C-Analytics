import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum DashboardScrollCoordinateSpace {
    static let name = "dashboard-scroll"
}

struct DashboardSectionOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: [DashboardSection.ID: CGFloat] = [:]

    static func reduce(
        value: inout [DashboardSection.ID: CGFloat],
        nextValue: () -> [DashboardSection.ID: CGFloat]
    ) {
        value.merge(nextValue()) { _, newValue in newValue }
    }
}

enum DashboardRoute: Hashable {
    case indicator(Indicator.ID)
}

struct DashboardIndicatorLayoutRow: Identifiable {
    let indicators: [Indicator]

    var id: String {
        indicators.map(\.id).joined(separator: "|")
    }
}

enum DashboardGridLayoutPolicy {
    static func rows<Element>(for elements: [Element], isPad: Bool) -> [[Element]] {
        let itemsPerRow = isPad ? 2 : 1

        return stride(from: 0, to: elements.count, by: itemsPerRow).map { startIndex in
            let endIndex = min(startIndex + itemsPerRow, elements.count)
            return Array(elements[startIndex..<endIndex])
        }
    }
}

final class DashboardLayoutStore: ObservableObject {
    static let defaultStorageKey = "dashboardIndicatorOrder.v1"

    @Published private var orderBySection: [DashboardSection.ID: [Indicator.ID]]

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = DashboardLayoutStore.defaultStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey

        guard let data = defaults.data(forKey: storageKey),
              let storedOrder = try? JSONDecoder().decode(
                  [DashboardSection.ID: [Indicator.ID]].self,
                  from: data
              ) else {
            orderBySection = [:]
            return
        }

        orderBySection = storedOrder
    }

    func orderedIndicators(in section: DashboardSection) -> [Indicator] {
        let indicatorByID = Dictionary(
            uniqueKeysWithValues: section.indicators.map { ($0.id, $0) }
        )
        return Self.reconciledOrder(
            savedOrder: orderBySection[section.id] ?? [],
            availableIDs: section.indicators.map(\.id)
        ).compactMap { indicatorByID[$0] }
    }

    func moveIndicator(
        in section: DashboardSection,
        draggedID: Indicator.ID,
        over targetID: Indicator.ID
    ) {
        guard draggedID != targetID else {
            return
        }

        var order = Self.reconciledOrder(
            savedOrder: orderBySection[section.id] ?? [],
            availableIDs: section.indicators.map(\.id)
        )
        guard let sourceIndex = order.firstIndex(of: draggedID),
              let targetIndex = order.firstIndex(of: targetID) else {
            return
        }

        order.move(
            fromOffsets: IndexSet(integer: sourceIndex),
            toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        )
        orderBySection[section.id] = order
        persist()
    }

    static func reconciledOrder(
        savedOrder: [Indicator.ID],
        availableIDs: [Indicator.ID]
    ) -> [Indicator.ID] {
        let availableIDSet = Set(availableIDs)
        var seenIDs = Set<Indicator.ID>()
        let retainedIDs = savedOrder.filter {
            availableIDSet.contains($0) && seenIDs.insert($0).inserted
        }
        let newIDs = availableIDs.filter {
            seenIDs.insert($0).inserted
        }
        return retainedIDs + newIDs
    }

    var hasCustomLayout: Bool {
        !orderBySection.isEmpty
    }

    func reset() {
        orderBySection = [:]
        defaults.removeObject(forKey: storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(orderBySection) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}

struct DashboardDraggedIndicator: Equatable {
    let sectionID: DashboardSection.ID
    let indicatorID: Indicator.ID
}

struct DashboardIndicatorDropDelegate: DropDelegate {
    let section: DashboardSection
    let targetIndicatorID: Indicator.ID
    let isEditing: Bool
    @Binding var draggedIndicator: DashboardDraggedIndicator?
    let layoutStore: DashboardLayoutStore

    func validateDrop(info: DropInfo) -> Bool {
        isEditing
            && draggedIndicator?.sectionID == section.id
            && info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        guard isEditing,
              let draggedIndicator,
              draggedIndicator.sectionID == section.id else {
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            layoutStore.moveIndicator(
                in: section,
                draggedID: draggedIndicator.indicatorID,
                over: targetIndicatorID
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info) else {
            return false
        }
        draggedIndicator = nil
        return true
    }
}

