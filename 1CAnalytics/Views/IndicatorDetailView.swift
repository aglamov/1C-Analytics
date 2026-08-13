import Charts
import SwiftUI
import UIKit

struct IndicatorDetailView: View {
    let indicator: Indicator
    @State private var selectedRowID: IndicatorRow.ID?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dashboardContentScale) private var contentScale

    var body: some View {
        GeometryReader { proxy in
            let usesSplitLayout = horizontalSizeClass == .regular && proxy.size.width > proxy.size.height
            let horizontalPadding: CGFloat = horizontalSizeClass == .regular ? 20 : 16
            let verticalPadding: CGFloat = 16

            if usesSplitLayout {
                splitDetailContent(availableSize: proxy.size)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
            } else {
                ScrollView(.vertical) {
                    compactDetailContent(availableSize: proxy.size)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, verticalPadding)
                }
                .scrollBounceBehavior(.always)
            }
        }
        .background(AppBackground())
        .navigationTitle(indicator.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            selectedRowID = nil
        }
        .dashboardScaledTypography()
    }

    private func splitDetailContent(availableSize: CGSize) -> some View {
        let headerHeight = splitHeaderHeight(for: availableSize)
        let lowerHeight = splitLowerSectionHeight(for: availableSize, headerHeight: headerHeight)

        return VStack(alignment: .leading, spacing: 16 * contentScale) {
            IndicatorHero(indicator: indicator)
                .frame(maxWidth: .infinity, minHeight: headerHeight, maxHeight: headerHeight, alignment: .leading)

            if indicator.usesContractPlanFactPresentation {
                OverflowAwareScrollView {
                    contractPlanFactSection
                }
                .frame(maxWidth: .infinity, minHeight: lowerHeight, maxHeight: lowerHeight, alignment: .topLeading)
            } else if indicator.chartType == .expandableHierarchy {
                OverflowAwareScrollView {
                    expandableHierarchySection
                }
                .frame(maxWidth: .infinity, minHeight: lowerHeight, maxHeight: lowerHeight, alignment: .topLeading)
            } else {
                HStack(alignment: .top, spacing: 16 * contentScale) {
                    chartSection(fillsAvailableHeight: false)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: lowerHeight,
                            alignment: .top
                        )

                    OverflowAwareScrollView {
                        rowsSection
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, minHeight: lowerHeight, maxHeight: lowerHeight, alignment: .topLeading)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func compactDetailContent(availableSize: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 16 * contentScale) {
            IndicatorHero(indicator: indicator)

            if indicator.usesContractPlanFactPresentation {
                contractPlanFactSection
            } else if indicator.chartType == .expandableHierarchy {
                expandableHierarchySection
            } else {
                chartSection(fillsAvailableHeight: false, aspectRatio: compactChartAspectRatio(for: availableSize))
                rowsSection
            }
        }
    }

    private var contractPlanFactSection: some View {
        VStack(alignment: .leading, spacing: 16 * contentScale) {
            ContractPlanFactCompletionChart(indicator: indicator)
                .padding(16 * contentScale)
                .premiumPanel()

            ContractPlanFactView(indicator: indicator)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(16 * contentScale)
                .premiumPanel()
        }
    }

    private var expandableHierarchySection: some View {
        ExpandableHierarchyChartView(
            indicator: indicator,
            showsExpandedHierarchy: true
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16 * contentScale)
        .premiumPanel()
    }

    private func splitHeaderHeight(for availableSize: CGSize) -> CGFloat {
        min(156, max(132, availableSize.height * 0.13))
    }

    private func splitLowerSectionHeight(for availableSize: CGSize, headerHeight: CGFloat) -> CGFloat {
        let verticalPadding: CGFloat = 32
        let contentSpacing: CGFloat = 16
        let remainingHeight = availableSize.height - verticalPadding - headerHeight - contentSpacing

        return max(320, remainingHeight)
    }

    private func compactChartAspectRatio(for availableSize: CGSize) -> CGFloat {
        let availableWidth = max(availableSize.width - (horizontalSizeClass == .regular ? 72 : 64), 240)
        let desiredHeight = ChartHeightPolicy.detailHeight(
            for: indicator,
            availableWidth: availableWidth
        ) * contentScale
        return availableWidth / max(desiredHeight, 1)
    }

    @ViewBuilder
    private func chartSection(fillsAvailableHeight: Bool, aspectRatio: CGFloat = 1.0) -> some View {
        Group {
            if indicator.chartType == .geoMap {
                GeoMapIndicatorView(indicator: indicator)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if indicator.chartType == .oneValue {
                OneValueDashboardContent(indicator: indicator)
                    .frame(maxWidth: .infinity, minHeight: 150 * contentScale, alignment: .topLeading)
            } else if indicator.chartType == .linearProgress {
                LinearProgressIndicatorView(indicator: indicator)
                    .frame(maxWidth: .infinity, minHeight: 80 * contentScale)
            } else if indicator.chartType == .gauge {
                GaugeIndicatorView(indicator: indicator)
                    .frame(maxWidth: .infinity)
            } else {
                let chart = AnalyticsChart(
                    indicator: indicator,
                    usesCardBackground: false,
                    showsLegend: true,
                    selectedRowID: $selectedRowID
                )
                    .frame(maxWidth: .infinity)

                if fillsAvailableHeight {
                    chart
                        .frame(maxHeight: .infinity)
                } else {
                    chart
                        .aspectRatio(aspectRatio, contentMode: .fit)
                }
            }
        }
        .padding(16 * contentScale)
        .premiumPanel()
    }

    private var rowsSection: some View {
        let groups = detailGroups
        let hasMultipleParameters = DetailPresentationPolicy.hasMultipleParameters(in: groups)
        let maximumValue = groups
            .flatMap { group in
                group.rows.count > 1 ? group.rows.map(\.value) : [group.totalValue]
            }
            .max() ?? 0
        let aggregateTotal = DetailPresentationPolicy.aggregateTotal(for: groups)
        let seriesTotals = DetailPresentationPolicy.seriesTotals(for: groups)

        return VStack(alignment: .leading, spacing: 12 * contentScale) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Детализация")
                        .font(.title3.weight(.bold))

                    Text("В порядке значений на графике")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if indicator.showsAggregateValue, let aggregateTotal {
                    Text(totalText(for: aggregateTotal))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            LazyVStack(spacing: 0) {
                ForEach(groups) { group in
                    detailGroupRow(
                        group,
                        maximumValue: maximumValue,
                        aggregateTotal: aggregateTotal,
                        seriesTotals: seriesTotals,
                        hidesGroupTotal: hasMultipleParameters
                    )

                    if group.id != groups.last?.id {
                        Divider()
                            .padding(.leading, 2)
                    }
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(rowsBackgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.10), lineWidth: 1)
            }
        }
    }

    private var detailGroups: [IndicatorRowGroup] {
        let groups = indicator.rowGroups
        guard indicator.chartType == .geoMap else {
            return groups
        }

        return groups
            .enumerated()
            .sorted { left, right in
                if left.element.totalValue == right.element.totalValue {
                    return left.offset < right.offset
                }

                return left.element.totalValue > right.element.totalValue
            }
            .map(\.element)
    }

    private var rowsBackgroundColor: Color {
        colorScheme == .dark ? Color(.tertiarySystemGroupedBackground).opacity(0.44) : Color(.systemBackground).opacity(0.56)
    }

    private func detailGroupRow(
        _ group: IndicatorRowGroup,
        maximumValue: Double,
        aggregateTotal: Double?,
        seriesTotals: [String: Double],
        hidesGroupTotal: Bool
    ) -> some View {
        DetailGroupRowView(
            group: group,
            maxValue: maximumValue,
            aggregateTotal: aggregateTotal,
            seriesTotals: seriesTotals,
            hidesGroupTotal: hidesGroupTotal,
            indicator: indicator,
            selectedRowID: selectedRowID,
            animatesOnAppear: indicator.chartType != .geoMap,
            selectionEnabled: indicator.chartType != .geoMap,
            onSelect: selectRow
        )
    }

    private func totalText(for totalValue: Double) -> String {
        "Итого \(indicator.formattedNumber(totalValue))"
    }

    private func selectRow(_ rowID: IndicatorRow.ID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            selectedRowID = selectedRowID == rowID ? nil : rowID
        }
    }
}
