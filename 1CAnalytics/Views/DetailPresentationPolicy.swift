import Foundation

enum DetailPresentationPolicy {
    static func hasMultipleParameters(in groups: [IndicatorRowGroup]) -> Bool {
        groups.contains { $0.rows.count > 1 }
    }

    static func aggregateTotal(for groups: [IndicatorRowGroup]) -> Double? {
        guard !hasMultipleParameters(in: groups) else {
            return nil
        }

        return groups.reduce(0) { $0 + $1.totalValue }
    }

    static func seriesTotals(for groups: [IndicatorRowGroup]) -> [String: Double] {
        groups
            .flatMap(\.rows)
            .reduce(into: [:]) { totals, row in
                guard let series = row.series else {
                    return
                }

                totals[series, default: 0] += row.value
            }
    }

    static func shareText(
        for value: Double,
        denominator: Double?,
        fractionDigits: Int = 0,
        locale: Locale = .current
    ) -> String {
        let share = denominator.map { $0 > 0 ? value / $0 : 0 } ?? 0
        return share.formatted(
            .percent
                .precision(.fractionLength(fractionDigits))
                .locale(locale)
        )
    }

    static func seriesTitle(_ title: String, aggregateValue: Double?) -> String {
        guard let aggregateValue,
              aggregateValue.isFinite,
              let separatorIndex = title.lastIndex(of: ":") else {
            return title
        }

        let prefix = title[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = title[title.index(after: separatorIndex)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let groupingCharacters: Set<Character> = [" ", " ", " ", ",", ".", "'", "_"]

        guard !prefix.isEmpty,
              !suffix.isEmpty,
              suffix.allSatisfy({ $0.isNumber || groupingCharacters.contains($0) }) else {
            return title
        }

        let digits = suffix.filter(\.isNumber)
        guard let displayedAggregate = Double(digits),
              abs(displayedAggregate - abs(aggregateValue)) < 0.5 else {
            return title
        }

        return prefix
    }
}
