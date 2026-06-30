import Charts
import SwiftUI

struct AnalyticsChart: View {
    let indicator: Indicator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(indicator.chartType.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            switch indicator.chartType {
            case .bar:
                verticalBars
            case .horizontalBar:
                horizontalBars
            case .stackedBar:
                stackedBars
            case .donut:
                donut
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var verticalBars: some View {
        Chart(indicator.rows) { row in
            BarMark(
                x: .value("Группа", row.label),
                y: .value("Значение", row.value)
            )
            .foregroundStyle(by: .value("Группа", row.label))
        }
        .chartLegend(.hidden)
    }

    private var horizontalBars: some View {
        Chart(indicator.rows) { row in
            BarMark(
                x: .value("Значение", row.value),
                y: .value("Группа", row.label)
            )
            .foregroundStyle(.teal)
        }
    }

    private var stackedBars: some View {
        Chart(indicator.rows) { row in
            BarMark(
                x: .value("Группа", row.label),
                y: .value("Значение", row.value)
            )
            .foregroundStyle(by: .value("Серия", row.series ?? "Значение"))
            .position(by: .value("Серия", row.series ?? "Значение"))
        }
    }

    private var donut: some View {
        Chart(indicator.rows) { row in
            SectorMark(
                angle: .value("Доля", row.value),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(5)
            .foregroundStyle(by: .value("Группа", row.label))
        }
    }
}

