import SwiftUI

struct DashboardView: View {
    @StateObject var viewModel: DashboardViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(viewModel.dashboard?.title ?? "Аналитика")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        RefreshButton {
                            await viewModel.refresh()
                        }
                    }
                }
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.load()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Загружаем аналитику")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView("Не удалось загрузить данные", systemImage: "wifi.exclamationmark", description: Text(message))
        case let .loaded(dashboard):
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DashboardSummaryHeader(dashboard: dashboard)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(dashboard.indicators) { indicator in
                            IndicatorDashboardCard(indicator: indicator)
                        }
                    }
                }
                .frame(maxWidth: 1180, alignment: .leading)
                .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 16)
                .padding(.vertical, 18)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                UpdatedAtBar(date: dashboard.updatedAt)
            }
        }
    }

    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            [
                GridItem(.adaptive(minimum: 430, maximum: 560), spacing: 14, alignment: .top)
            ]
        } else {
            [
                GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 14, alignment: .top)
            ]
        }
    }
}

private struct DashboardSummaryHeader: View {
    let dashboard: Dashboard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dashboard.title)
                        .font(.largeTitle.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text("\(dashboard.indicators.count) показателя")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Image(systemName: "chart.xyaxis.line")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct IndicatorDashboardCard: View {
    let indicator: Indicator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            AnalyticsChart(indicator: indicator, showsTitle: false, usesCardBackground: false)
                .frame(height: chartHeight)
                .padding(.top, 2)

            rowsPreview
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(indicator.title)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(indicator.chartType.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(valueText)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }

            if let source = indicator.source {
                Text(source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rowsPreview: some View {
        VStack(spacing: 0) {
            ForEach(sortedRows) { row in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)

                        if let series = row.series {
                            Text(series)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(row.value.formatted(.number.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.vertical, 8)

                if row.id != sortedRows.last?.id {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var sortedRows: [IndicatorRow] {
        indicator.rows.sortedByOrder()
    }

    private var valueText: String {
        guard let value = indicator.value else {
            return "нет данных"
        }

        return "\(value.formatted(.number.grouping(.automatic))) \(indicator.unit ?? "")"
    }

    private var chartHeight: CGFloat {
        switch indicator.chartType {
        case .donut:
            240
        case .horizontalBar:
            220
        case .bar, .stackedBar:
            230
        }
    }

    private var iconName: String {
        switch indicator.chartType {
        case .bar, .horizontalBar, .stackedBar:
            "chart.bar.fill"
        case .donut:
            "chart.pie.fill"
        }
    }

    private var tint: Color {
        switch indicator.chartType {
        case .bar:
            .blue
        case .horizontalBar:
            .teal
        case .stackedBar:
            .indigo
        case .donut:
            .orange
        }
    }
}

private extension Array where Element == IndicatorRow {
    func sortedByOrder() -> [IndicatorRow] {
        sorted {
            ($0.sortOrder ?? .max, $0.label) < ($1.sortOrder ?? .max, $1.label)
        }
    }
}
