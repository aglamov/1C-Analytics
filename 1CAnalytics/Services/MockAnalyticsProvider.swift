import Foundation

final class MockAnalyticsProvider: AnalyticsProvider {
    func fetchDashboard() async throws -> Dashboard {
        Dashboard(
            id: "education",
            title: "Образование",
            updatedAt: Date(),
            indicators: [
                Indicator(
                    id: "students-total",
                    title: "Всего обучающихся",
                    value: 31_248,
                    unit: "чел.",
                    chartType: .bar,
                    source: "Регистр сведений (вуз). Обучение, срез последних",
                    rows: [
                        IndicatorRow(id: "bak", label: "БАК", value: 18_420, series: nil, sortOrder: 1),
                        IndicatorRow(id: "spec", label: "СПЕЦ", value: 4_180, series: nil, sortOrder: 2),
                        IndicatorRow(id: "mag", label: "МАГ", value: 5_360, series: nil, sortOrder: 3),
                        IndicatorRow(id: "asp", label: "АСП", value: 1_240, series: nil, sortOrder: 4),
                        IndicatorRow(id: "ord", label: "ОРД", value: 2_048, series: nil, sortOrder: 5)
                    ]
                ),
                Indicator(
                    id: "citizenship",
                    title: "РФ и ИГ",
                    value: 31_248,
                    unit: "чел.",
                    chartType: .stackedBar,
                    source: "Регистр сведений (вуз). Обучение, срез последних",
                    rows: [
                        IndicatorRow(id: "rf-bak", label: "БАК", value: 11_020, series: "РФ", sortOrder: 1),
                        IndicatorRow(id: "foreign-bak", label: "БАК", value: 7_400, series: "ИГ", sortOrder: 2),
                        IndicatorRow(id: "rf-spec", label: "СПЕЦ", value: 2_460, series: "РФ", sortOrder: 3),
                        IndicatorRow(id: "foreign-spec", label: "СПЕЦ", value: 1_720, series: "ИГ", sortOrder: 4),
                        IndicatorRow(id: "rf-mag", label: "МАГ", value: 3_280, series: "РФ", sortOrder: 5),
                        IndicatorRow(id: "foreign-mag", label: "МАГ", value: 2_080, series: "ИГ", sortOrder: 6)
                    ]
                ),
                Indicator(
                    id: "students-persons",
                    title: "Обучающиеся",
                    value: 29_774,
                    unit: "чел.",
                    chartType: .donut,
                    source: "Регистр сведений (вуз). Обучение, срез последних",
                    rows: [
                        IndicatorRow(id: "bak-part", label: "БАК", value: 59, series: nil, sortOrder: 1),
                        IndicatorRow(id: "spec-part", label: "СПЕЦ", value: 13, series: nil, sortOrder: 2),
                        IndicatorRow(id: "mag-part", label: "МАГ", value: 17, series: nil, sortOrder: 3),
                        IndicatorRow(id: "asp-part", label: "АСП", value: 4, series: nil, sortOrder: 4),
                        IndicatorRow(id: "ord-part", label: "ОРД", value: 7, series: nil, sortOrder: 5)
                    ]
                ),
                Indicator(
                    id: "full-time",
                    title: "Обучающиеся очно",
                    value: 24_510,
                    unit: "чел.",
                    chartType: .horizontalBar,
                    source: "Регистр сведений (вуз). Обучение, срез последних",
                    rows: [
                        IndicatorRow(id: "fulltime-bak", label: "Бакалавриат", value: 14_980, series: nil, sortOrder: 1),
                        IndicatorRow(id: "fulltime-spec", label: "Специалитет", value: 3_880, series: nil, sortOrder: 2),
                        IndicatorRow(id: "fulltime-mag", label: "Магистратура", value: 3_960, series: nil, sortOrder: 3),
                        IndicatorRow(id: "fulltime-asp", label: "Аспирантура", value: 720, series: nil, sortOrder: 4),
                        IndicatorRow(id: "fulltime-ord", label: "Ординатура", value: 970, series: nil, sortOrder: 5)
                    ]
                )
            ]
        )
    }
}

