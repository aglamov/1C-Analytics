import SwiftUI

struct DashboardView: View {
    @StateObject var viewModel: DashboardViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.load()
            }
        }
    }

    private var compactLayout: some View {
        NavigationStack {
            contentList
                .navigationTitle(viewModel.dashboard?.title ?? "Аналитика")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        RefreshButton {
                            await viewModel.refresh()
                        }
                    }
                }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            indicatorSidebar
                .navigationTitle("Дашборды")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        RefreshButton {
                            await viewModel.refresh()
                        }
                    }
                }
        } detail: {
            if let indicator = viewModel.selectedIndicator {
                IndicatorDetailView(indicator: indicator)
                    .navigationTitle(indicator.title)
            } else {
                ContentUnavailableView("Нет показателя", systemImage: "chart.bar.doc.horizontal")
            }
        }
    }

    @ViewBuilder
    private var contentList: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Загружаем аналитику")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView("Не удалось загрузить данные", systemImage: "wifi.exclamationmark", description: Text(message))
        case let .loaded(dashboard):
            ScrollView {
                LazyVGrid(columns: compactColumns, spacing: 12) {
                    ForEach(dashboard.indicators) { indicator in
                        NavigationLink {
                            IndicatorDetailView(indicator: indicator)
                        } label: {
                            IndicatorCard(indicator: indicator)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                UpdatedAtBar(date: dashboard.updatedAt)
            }
        }
    }

    @ViewBuilder
    private var indicatorSidebar: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Загружаем")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView("Нет данных", systemImage: "wifi.exclamationmark", description: Text(message))
        case let .loaded(dashboard):
            List(dashboard.indicators, selection: $viewModel.selectedIndicatorID) { indicator in
                VStack(alignment: .leading, spacing: 6) {
                    Text(indicator.title)
                        .font(.headline)
                    Text(indicator.chartType.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(indicator.id)
            }
            .safeAreaInset(edge: .bottom) {
                UpdatedAtBar(date: dashboard.updatedAt)
            }
        }
    }

    private var compactColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 12)]
    }
}

