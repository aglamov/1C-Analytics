import SwiftUI

struct IndicatorDetailView: View {
    let indicator: Indicator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                IndicatorHero(indicator: indicator)
                AnalyticsChart(indicator: indicator)
                    .frame(height: 280)
                rowsSection
            }
            .padding()
            .frame(maxWidth: 920, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var rowsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Детализация")
                .font(.headline)

            ForEach(indicator.rows.sortedByOrder()) { row in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.label)
                            .font(.body.weight(.medium))

                        if let series = row.series {
                            Text(series)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text(row.value.formatted(.number.precision(.fractionLength(0))))
                        .font(.body.monospacedDigit().weight(.semibold))
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            }
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

