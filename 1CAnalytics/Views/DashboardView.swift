import SwiftUI

struct DashboardView: View {
    @StateObject var viewModel: DashboardViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("chartPaletteScheme") private var chartPaletteSchemeRawValue = ChartPaletteScheme.corporate.rawValue

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
        .environment(\.chartPaletteScheme, chartPaletteScheme)
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
                    ChartPalettePicker(selection: chartPaletteBinding)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
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
                                            .background(Color(.systemBackground).opacity(0.94), in: RoundedRectangle(cornerRadius: 8))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
                                            }
                                        }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Открыть детализацию")
                                    .padding(14)
                                }
                        }
                    }
                }
                .padding(.horizontal, horizontalSizeClass == .regular ? 20 : 16)
                .padding(.vertical, 16)
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
                GridItem(.flexible(), spacing: 16, alignment: .top),
                GridItem(.flexible(), spacing: 16, alignment: .top)
            ]
        } else {
            [
                GridItem(.flexible(), spacing: 16, alignment: .top)
            ]
        }
    }

    private var chartPaletteScheme: ChartPaletteScheme {
        ChartPaletteScheme(rawValue: chartPaletteSchemeRawValue) ?? .corporate
    }

    private var chartPaletteBinding: Binding<ChartPaletteScheme> {
        Binding {
            chartPaletteScheme
        } set: { newValue in
            chartPaletteSchemeRawValue = newValue.rawValue
        }
    }
}

private struct ChartPalettePicker: View {
    @Binding var selection: ChartPaletteScheme

    var body: some View {
        Picker("Цвета графиков", selection: $selection) {
            ForEach(ChartPaletteScheme.allCases) { scheme in
                Text(scheme.title)
                    .tag(scheme)
                    .accessibilityLabel(scheme.accessibilityTitle)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Цветовая схема графиков")
    }
}

private struct IndicatorDashboardCard: View {
    let indicator: Indicator
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            AnalyticsChart(indicator: indicator, showsTitle: false, usesCardBackground: false, showsLegend: false)
                .frame(minHeight: 220, idealHeight: 260, maxHeight: 320)
                .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
                    .font(.system(.title, design: .default).weight(.semibold))
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
