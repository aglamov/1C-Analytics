import SwiftUI

struct IndicatorCard: View {
    let indicator: Indicator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8))

                Spacer()

                Text(indicator.chartType.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(indicator.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(valueText)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(.primary)
            }

            Text(indicator.source ?? "Источник не указан")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
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

struct IndicatorHero: View {
    let indicator: Indicator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(indicator.title)
                .font(.title2.weight(.bold))

            if let value = indicator.value {
                Text("\(value.formatted(.number.grouping(.automatic))) \(indicator.unit ?? "")")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
            }

            if let source = indicator.source {
                Text(source)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct UpdatedAtBar: View {
    let date: Date?

    var body: some View {
        HStack {
            Image(systemName: "clock")
            Text(dateText)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var dateText: String {
        guard let date else {
            return "Срез не указан"
        }

        return "Обновлено \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

struct RefreshButton: View {
    let action: () async -> Void
    @State private var isRefreshing = false

    var body: some View {
        Button {
            Task {
                isRefreshing = true
                await action()
                isRefreshing = false
            }
        } label: {
            Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
        }
        .disabled(isRefreshing)
        .accessibilityLabel("Обновить")
    }
}

