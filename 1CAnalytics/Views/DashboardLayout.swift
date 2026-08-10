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

enum DashboardCardWidth: Int, Codable, CaseIterable, Sendable {
    case half = 50
    case full = 100

    init(percent: Double) {
        self = percent <= 50 ? .half : .full
    }

    var slotSpan: Int {
        self == .half ? 1 : 2
    }

    var title: String {
        "\(rawValue)%"
    }

    var toggled: DashboardCardWidth {
        self == .half ? .full : .half
    }
}

struct DashboardIndicatorLayoutItem: Identifiable {
    let indicator: Indicator
    let width: DashboardCardWidth

    var id: Indicator.ID { indicator.id }
}

struct DashboardIndicatorLayoutRow: Identifiable {
    let items: [DashboardIndicatorLayoutItem]
    let slotCapacity: Int

    var id: String {
        items.map(\.id).joined(separator: "|")
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

    static func rows(
        for items: [DashboardIndicatorLayoutItem],
        slotCapacity: Int
    ) -> [DashboardIndicatorLayoutRow] {
        let capacity = max(slotCapacity, 2)
        var rows: [DashboardIndicatorLayoutRow] = []
        var currentItems: [DashboardIndicatorLayoutItem] = []
        var usedSlots = 0

        for item in items {
            let span = min(item.width.slotSpan, capacity)
            if !currentItems.isEmpty, usedSlots + span > capacity {
                rows.append(DashboardIndicatorLayoutRow(items: currentItems, slotCapacity: capacity))
                currentItems = []
                usedSlots = 0
            }
            currentItems.append(item)
            usedSlots += span
        }

        if !currentItems.isEmpty {
            rows.append(DashboardIndicatorLayoutRow(items: currentItems, slotCapacity: capacity))
        }
        return rows
    }
}

struct DashboardSlotMetrics {
    let availableWidth: CGFloat
    let slotCapacity: Int
    let spacing: CGFloat

    private var capacity: Int {
        max(slotCapacity, 1)
    }

    var slotWidth: CGFloat {
        max(
            (availableWidth - spacing * CGFloat(capacity - 1)) / CGFloat(capacity),
            0
        )
    }

    func itemWidth(span: Int) -> CGFloat {
        let resolvedSpan = min(max(span, 1), capacity)
        return slotWidth * CGFloat(resolvedSpan)
            + spacing * CGFloat(resolvedSpan - 1)
    }

    func occupiedWidth(spans: [Int]) -> CGFloat {
        guard !spans.isEmpty else {
            return 0
        }

        return spans.reduce(0) { $0 + itemWidth(span: $1) }
            + spacing * CGFloat(spans.count - 1)
    }
}

struct DashboardSlotRowLayout: Layout {
    let slotCapacity: Int
    let spans: [Int]
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let availableWidth = max(proposal.width ?? 0, 0)
        let metrics = DashboardSlotMetrics(
            availableWidth: availableWidth,
            slotCapacity: slotCapacity,
            spacing: spacing
        )
        let height = zip(subviews, resolvedSpans(for: subviews.count))
            .map { subview, span in
                subview.sizeThatFits(
                    ProposedViewSize(width: metrics.itemWidth(span: span), height: nil)
                ).height
            }
            .max() ?? 0

        return CGSize(width: availableWidth, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let metrics = DashboardSlotMetrics(
            availableWidth: bounds.width,
            slotCapacity: slotCapacity,
            spacing: spacing
        )
        var x = bounds.minX

        for (subview, span) in zip(subviews, resolvedSpans(for: subviews.count)) {
            let width = metrics.itemWidth(span: span)
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }

    private func resolvedSpans(for count: Int) -> [Int] {
        (0..<count).map { index in
            index < spans.count ? spans[index] : 1
        }
    }
}

final class DashboardLayoutStore: ObservableObject {
    static let defaultStorageKey = "dashboardIndicatorLayout.v2"

    @Published private var storedLayout: StoredDashboardLayout

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = DashboardLayoutStore.defaultStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey

        storedLayout = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(StoredDashboardLayout.self, from: $0) }
            ?? StoredDashboardLayout()
    }

    func orderedIndicators(in section: DashboardSection) -> [Indicator] {
        let indicatorByID = Dictionary(
            uniqueKeysWithValues: section.indicators.map { ($0.id, $0) }
        )
        return Self.reconciledOrder(
            savedOrder: storedLayout.orderBySection[section.id] ?? [],
            availableIDs: section.indicators.map(\.id)
        ).compactMap { indicatorByID[$0] }
    }

    func width(for indicator: Indicator) -> DashboardCardWidth {
        storedLayout.widthByIndicatorID[indicator.id]
            ?? DashboardCardWidth(percent: indicator.resolvedWidthPercent)
    }

    func setWidth(_ width: DashboardCardWidth, for indicator: Indicator) {
        storedLayout.widthByIndicatorID[indicator.id] = width
        persist()
    }

    func toggleWidth(for indicator: Indicator) {
        setWidth(width(for: indicator).toggled, for: indicator)
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
            savedOrder: storedLayout.orderBySection[section.id] ?? [],
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
        storedLayout.orderBySection[section.id] = order
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
        !storedLayout.orderBySection.isEmpty || !storedLayout.widthByIndicatorID.isEmpty
    }

    func reset() {
        storedLayout = StoredDashboardLayout()
        defaults.removeObject(forKey: storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(storedLayout) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}

private struct StoredDashboardLayout: Codable {
    var orderBySection: [DashboardSection.ID: [Indicator.ID]] = [:]
    var widthByIndicatorID: [Indicator.ID: DashboardCardWidth] = [:]
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
