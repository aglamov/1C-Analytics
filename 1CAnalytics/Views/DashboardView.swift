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
                VStack(alignment: .leading, spacing: 16) {
                    DashboardHeader(dashboard: dashboard)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(dashboard.indicators) { indicator in
                            IndicatorDashboardCard(indicator: indicator)
                                .overlay(alignment: .topTrailing) {
                                    NavigationLink {
                                        IndicatorDetailView(indicator: indicator)
                                    } label: {
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(indicator.accent.primary)
                                            .frame(width: 30, height: 30)
                                            .background(Color(.systemBackground).opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Открыть детализацию")
                                    .padding(14)
                                }
                        }
                    }
                }
                .frame(maxWidth: 1180, alignment: .leading)
                .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 16)
                .padding(.vertical, 18)
            }
            .background(AppBackground())
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

private struct DashboardHeader: View {
    let dashboard: Dashboard

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dashboard.title)
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text("\(dashboard.indicators.count) показателя")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Image(systemName: "chart.xyaxis.line")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(AppAccent.blue.primary, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumPanel()
    }
}

private struct IndicatorDashboardCard: View {
    let indicator: Indicator
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            AnalyticsChart(indicator: indicator, showsTitle: false, usesCardBackground: false, showsLegend: false)
                .frame(height: 250)
                .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
        .premiumPanel()
        .scaleEffect(isVisible ? 1 : 0.98)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                isVisible = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(indicator.accent.primary, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(indicator.title)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(valueText)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }

        }
    }

    private var valueText: String {
        guard let value = indicator.value else {
            return "нет данных"
        }

        return "\(value.formatted(.number.grouping(.automatic))) \(indicator.unit ?? "")"
    }

    private var iconName: String {
        switch indicator.chartType {
        case .bar, .horizontalBar, .stackedBar:
            "chart.bar.fill"
        case .donut:
            "chart.pie.fill"
        }
    }
}
