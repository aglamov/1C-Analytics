import SwiftUI

private struct ChartPalettePicker: View {
    @Binding var selection: ChartPaletteScheme

    var body: some View {
        Picker("Тема графиков", selection: $selection) {
            ForEach(ChartPaletteScheme.allCases) { scheme in
                Text(scheme.title)
                    .tag(scheme)
                    .accessibilityLabel(scheme.accessibilityTitle)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Тема графиков")
    }
}

struct DashboardSettingsView: View {
    @Binding var chartPalette: ChartPaletteScheme
    @Binding var contentScale: Double
    @ObservedObject var layoutStore: DashboardLayoutStore
    let onSignOut: () -> Void
    @State private var showsLayoutResetConfirmation = false

    var body: some View {
        Form {
            Section("Оформление") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Тема графиков")
                        .font(.body.weight(.semibold))

                    ChartPalettePicker(selection: $chartPalette)
                }
                .padding(.vertical, 4)
            }


            Section("Масштаб графиков") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Размер содержимого")
                        Spacer()
                        Text("\(Int((contentScale * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: $contentScale,
                        in: DashboardContentScalePolicy.range,
                        step: DashboardContentScalePolicy.step
                    )
                    .accessibilityLabel("Масштаб графиков")
                    .accessibilityValue("\(Int((contentScale * 100).rounded())) процентов")
                }
                .padding(.vertical, 4)
            }

            Section("Предпросмотр") {
                ChartThemePreview(palette: chartPalette, contentScale: contentScale)
            }

            Section {
                Button(role: .destructive) {
                    showsLayoutResetConfirmation = true
                } label: {
                    Label("Сбросить расположение графиков", systemImage: "arrow.counterclockwise")
                }
                .disabled(!layoutStore.hasCustomLayout)
            } header: {
                Text("Расположение")
            } footer: {
                Text("Графики вернутся к порядку и размерам, полученным от сервера.")
            }

            Section {
                Button(role: .destructive, action: onSignOut) {
                    Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Сбросить расположение графиков?",
            isPresented: $showsLayoutResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Сбросить", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    layoutStore.reset()
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Карточки во всех группах вернутся к исходному порядку.")
        }
    }
}

private struct ChartThemePreview: View {
    let palette: ChartPaletteScheme
    let contentScale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(ChartPalette.colors(for: palette).first ?? previewIndicator.accent.primary)

                Text("Пример графика")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(palette.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            AnalyticsChart(
                indicator: previewIndicator,
                usesCardBackground: false,
                showsLegend: false
            )
            .frame(height: 180 * CGFloat(contentScale))
        }
        .padding(.vertical, 6)
        .environment(\.chartPaletteScheme, palette)
        .environment(\.dashboardContentScale, CGFloat(contentScale))
        .dashboardScaledTypography()
        .animation(.easeInOut(duration: 0.25), value: palette)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Предпросмотр темы \(palette.accessibilityTitle)")
    }

    private var previewIndicator: Indicator {
        Indicator(
            id: "theme-preview",
            title: "Пример",
            value: nil,
            unit: nil,
            chartType: .compactBar,
            source: nil,
            rows: [
                IndicatorRow(id: "plan", label: "План", value: 72, series: nil, sortOrder: 0),
                IndicatorRow(id: "fact", label: "Факт", value: 54, series: nil, sortOrder: 1),
                IndicatorRow(id: "forecast", label: "Прогноз", value: 83, series: nil, sortOrder: 2)
            ]
        )
    }
}
