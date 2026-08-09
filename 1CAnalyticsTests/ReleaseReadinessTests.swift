import XCTest
@testable import _C_Analytics

@MainActor
final class ReleaseReadinessTests: XCTestCase {
    func testIPadDashboardAlwaysPlacesIndicatorsTwoPerRow() {
        let rows = DashboardGridLayoutPolicy.rows(for: [1, 2, 3, 4, 5], isPad: true)

        XCTAssertEqual(rows, [[1, 2], [3, 4], [5]])
    }

    func testIPhoneDashboardKeepsOneIndicatorPerRow() {
        let rows = DashboardGridLayoutPolicy.rows(for: [1, 2, 3], isPad: false)

        XCTAssertEqual(rows, [[1], [2], [3]])
    }

    func testGroupedBarSelectionResolvesEverySeriesSlot() {
        let bounds: ClosedRange<CGFloat> = 20...120
        let domain = ["План", "Факт"]

        XCTAssertEqual(
            BarSelectionResolver.positionKey(at: 40, in: bounds, domain: domain),
            "План"
        )
        XCTAssertEqual(
            BarSelectionResolver.positionKey(at: 100, in: bounds, domain: domain),
            "Факт"
        )
    }

    func testBarSelectionRejectsTapsOutsideCategory() {
        let bounds: ClosedRange<CGFloat> = 20...120

        XCTAssertNil(
            BarSelectionResolver.positionKey(at: 10, in: bounds, domain: ["План", "Факт"])
        )
    }

    func testContractValueLabelPreferenceTakesPriority() {
        XCTAssertFalse(
            ChartValueLabelPolicy.isVisible(
                rowMatchesSelection: true,
                hasSelection: true,
                contractPreference: false,
                defaultLabelsEnabled: true
            )
        )
        XCTAssertTrue(
            ChartValueLabelPolicy.isVisible(
                rowMatchesSelection: false,
                hasSelection: false,
                contractPreference: true,
                defaultLabelsEnabled: false
            )
        )
        XCTAssertFalse(
            ChartValueLabelPolicy.isVisible(
                rowMatchesSelection: false,
                hasSelection: true,
                contractPreference: true,
                defaultLabelsEnabled: true
            )
        )
    }

    func testMissingContractValueLabelPreferenceKeepsPresentationDefaults() {
        XCTAssertTrue(
            ChartValueLabelPolicy.isVisible(
                rowMatchesSelection: true,
                hasSelection: true,
                contractPreference: nil,
                defaultLabelsEnabled: false
            )
        )
        XCTAssertFalse(
            ChartValueLabelPolicy.isVisible(
                rowMatchesSelection: false,
                hasSelection: false,
                contractPreference: nil,
                defaultLabelsEnabled: false
            )
        )
    }

    func testVerticalBarsReservePlotSpaceForValueLabels() {
        let domain = VerticalBarValueLabelScale.domain(for: [40, 100, 75])

        XCTAssertEqual(domain.lowerBound, 0)
        XCTAssertEqual(domain.upperBound, 122, accuracy: 0.0001)
        XCTAssertGreaterThan(domain.upperBound, 100)
    }

    func testVerticalBarLabelScaleHandlesEmptyAndNegativeData() {
        XCTAssertEqual(VerticalBarValueLabelScale.domain(for: []), 0...1)

        let mixedDomain = VerticalBarValueLabelScale.domain(for: [-20, 80])
        XCTAssertEqual(mixedDomain.lowerBound, -20)
        XCTAssertEqual(mixedDomain.upperBound, 102, accuracy: 0.0001)
    }

    func testVerticalBarLabelScaleIgnoresNonFiniteValues() {
        let domain = VerticalBarValueLabelScale.domain(for: [.nan, .infinity, 50])

        XCTAssertEqual(domain.lowerBound, 0)
        XCTAssertEqual(domain.upperBound, 61, accuracy: 0.0001)
    }

    func testSmallDonutLabelsMoveOutside() {
        XCTAssertTrue(
            DonutLabelPlacementPolicy.shouldPlaceOutside(
                share: 0.04,
                labelCharacterCount: 6,
                radius: 90
            )
        )
        XCTAssertTrue(
            DonutLabelPlacementPolicy.shouldPlaceOutside(
                share: 0.10,
                labelCharacterCount: 4,
                radius: 90
            )
        )
        XCTAssertFalse(
            DonutLabelPlacementPolicy.shouldPlaceOutside(
                share: 0.45,
                labelCharacterCount: 4,
                radius: 90
            )
        )

    }

    func testSelectedTinyDonutSliceHasAStableLabelAngle() throws {
        let rows = [
            IndicatorRow(id: "large", label: "Большой", value: 999, series: nil, sortOrder: 0),
            IndicatorRow(id: "tiny", label: "Маленький", value: 1, series: nil, sortOrder: 1),
            IndicatorRow(id: "zero", label: "Нулевой", value: 0, series: nil, sortOrder: 2)
        ]

        let tinyAngle = try XCTUnwrap(
            DonutSelectionGeometryPolicy.middleAngle(for: "tiny", in: rows)
        )
        let zeroAngle = try XCTUnwrap(
            DonutSelectionGeometryPolicy.middleAngle(for: "zero", in: rows)
        )

        XCTAssertTrue(tinyAngle.isFinite)
        XCTAssertTrue(zeroAngle.isFinite)
        XCTAssertNotEqual(tinyAngle, zeroAngle)
        XCTAssertNil(DonutSelectionGeometryPolicy.middleAngle(for: "missing", in: rows))
    }

    func testPhoneChartsFitAvailableWidthWhileIPadCanScrollDenseContent() {
        let compactWidth = ChartPresentationPolicy.contentWidth(
            availableWidth: 320,
            categoryCount: 8,
            seriesCount: 2,
            longestValueCharacterCount: 8,
            style: .groupedBar,
            allowsHorizontalOverflow: false
        )
        let denseWidth = ChartPresentationPolicy.contentWidth(
            availableWidth: 320,
            categoryCount: 8,
            seriesCount: 2,
            longestValueCharacterCount: 8,
            style: .groupedBar
        )

        XCTAssertEqual(compactWidth, 320)
        XCTAssertGreaterThan(denseWidth, 600)
    }

    func testStackedBarLabelsOnlyAppearWhenSegmentCanContainThem() {
        XCTAssertTrue(
            StackedBarLabelPolicy.isReadable(
                value: 35,
                groupTotal: 100,
                labelCharacterCount: 4
            )
        )
        XCTAssertFalse(
            StackedBarLabelPolicy.isReadable(
                value: 5,
                groupTotal: 100,
                labelCharacterCount: 6
            )
        )
    }

    func testTrendScaleReservesSpaceWithoutFlatteningLineAgainstZero() {
        let lineDomain = TrendValueLabelScale.domain(for: [100, 110], includesZero: false)
        let areaDomain = TrendValueLabelScale.domain(for: [100, 110], includesZero: true)

        XCTAssertGreaterThan(lineDomain.lowerBound, 90)
        XCTAssertLessThan(lineDomain.lowerBound, 100)
        XCTAssertGreaterThan(lineDomain.upperBound, 110)
        XCTAssertLessThan(areaDomain.lowerBound, 0)
        XCTAssertGreaterThan(areaDomain.upperBound, 110)
    }

    func testTrendLabelsFollowValueOrderAtEveryCategory() {
        let rows = [
            IndicatorRow(id: "upper", label: "2026", value: 92, series: "Текущий", sortOrder: 0),
            IndicatorRow(id: "middle", label: "2026", value: 88, series: "Средний", sortOrder: 1),
            IndicatorRow(id: "lower", label: "2026", value: 84, series: "Прошлый", sortOrder: 2)
        ]

        XCTAssertEqual(TrendLabelPlacementPolicy.placement(for: rows[0], in: rows), .above)
        XCTAssertEqual(TrendLabelPlacementPolicy.placement(for: rows[1], in: rows), .below)
        XCTAssertEqual(TrendLabelPlacementPolicy.placement(for: rows[2], in: rows), .below)
    }

    func testEqualTrendValuesArePlacedOnOppositeSides() {
        let rows = [
            IndicatorRow(id: "first", label: "2025", value: 88, series: "A", sortOrder: 0),
            IndicatorRow(id: "second", label: "2025", value: 88, series: "B", sortOrder: 1)
        ]

        XCTAssertEqual(TrendLabelPlacementPolicy.placement(for: rows[0], in: rows), .above)
        XCTAssertEqual(TrendLabelPlacementPolicy.placement(for: rows[1], in: rows), .below)
    }

    func testHorizontalChartHeightAccountsForEverySeries() {
        let singleSeriesHeight = ChartHeightPolicy.horizontalBarHeight(
            categoryCount: 4,
            seriesCount: 1
        )
        let threeSeriesHeight = ChartHeightPolicy.horizontalBarHeight(
            categoryCount: 4,
            seriesCount: 3
        )

        XCTAssertGreaterThan(threeSeriesHeight, singleSeriesHeight)
        XCTAssertEqual(singleSeriesHeight, 240)
        XCTAssertEqual(threeSeriesHeight, 424)
    }

    func testDetailPresentationKeepsMultipleParametersSeparate() {
        let groups = [
            IndicatorRowGroup(
                label: "БАК",
                rows: [
                    IndicatorRow(id: "bak-rf", label: "БАК", value: 16_151, series: "РФ", sortOrder: 0),
                    IndicatorRow(id: "bak-foreign", label: "БАК", value: 3_214, series: "ИГ", sortOrder: 1)
                ]
            ),
            IndicatorRowGroup(
                label: "СПЕЦ",
                rows: [
                    IndicatorRow(id: "spec-rf", label: "СПЕЦ", value: 5_109, series: "РФ", sortOrder: 2),
                    IndicatorRow(id: "spec-foreign", label: "СПЕЦ", value: 2_300, series: "ИГ", sortOrder: 3)
                ]
            )
        ]

        XCTAssertTrue(DetailPresentationPolicy.hasMultipleParameters(in: groups))
        XCTAssertNil(DetailPresentationPolicy.aggregateTotal(for: groups))
        XCTAssertEqual(
            DetailPresentationPolicy.seriesTotals(for: groups),
            ["РФ": 21_260, "ИГ": 5_514]
        )
    }

    func testDetailSeriesTitleHidesMatchingAggregateSuffix() {
        XCTAssertEqual(
            DetailPresentationPolicy.seriesTitle("Всего: 37 093", aggregateValue: 37_093),
            "Всего"
        )
        XCTAssertEqual(
            DetailPresentationPolicy.seriesTitle("Очно: 31 542", aggregateValue: 31_542),
            "Очно"
        )
        XCTAssertEqual(
            DetailPresentationPolicy.seriesTitle("План: 2024", aggregateValue: 100),
            "План: 2024"
        )
        XCTAssertEqual(
            DetailPresentationPolicy.seriesTitle("Текущий год: План", aggregateValue: 100),
            "Текущий год: План"
        )
    }

    func testLegendSelectionMatchesEveryRowInSelectedSeries() {
        XCTAssertTrue(
            ChartSelectionPolicy.matches(
                rowID: "previous-fact",
                rowSeriesKey: "Факт",
                selectedRowID: "current-fact",
                selectedSeriesKey: "Факт"
            )
        )
        XCTAssertTrue(
            ChartSelectionPolicy.matches(
                rowID: "current-fact",
                rowSeriesKey: "Факт",
                selectedRowID: "current-fact",
                selectedSeriesKey: "Факт"
            )
        )
        XCTAssertFalse(
            ChartSelectionPolicy.matches(
                rowID: "previous-plan",
                rowSeriesKey: "План",
                selectedRowID: "current-fact",
                selectedSeriesKey: "Факт"
            )
        )
    }

    func testDirectRowSelectionDoesNotHighlightSeriesLegend() {
        XCTAssertFalse(
            LegendSelectionPolicy.isSelected(
                usesSeriesLegend: true,
                rowMatchesSelection: true,
                selectedSeriesKey: nil
            )
        )
        XCTAssertTrue(
            LegendSelectionPolicy.isSelected(
                usesSeriesLegend: true,
                rowMatchesSelection: true,
                selectedSeriesKey: "Всего: 37 093"
            )
        )
        XCTAssertTrue(
            LegendSelectionPolicy.isSelected(
                usesSeriesLegend: false,
                rowMatchesSelection: true,
                selectedSeriesKey: nil
            )
        )
    }

    func testDirectChartSelectionMatchesOnlyTappedRow() {
        XCTAssertTrue(
            ChartSelectionPolicy.matches(
                rowID: "current-fact",
                rowSeriesKey: "Факт",
                selectedRowID: "current-fact",
                selectedSeriesKey: nil
            )
        )
        XCTAssertFalse(
            ChartSelectionPolicy.matches(
                rowID: "previous-fact",
                rowSeriesKey: "Факт",
                selectedRowID: "current-fact",
                selectedSeriesKey: nil
            )
        )
    }

    func testDashboardLayoutReconcilesSavedOrderWithFreshIndicators() {
        XCTAssertEqual(
            DashboardLayoutStore.reconciledOrder(
                savedOrder: ["section-c", "removed", "section-a", "section-c"],
                availableIDs: ["section-a", "section-b", "section-c", "section-new"]
            ),
            ["section-c", "section-a", "section-b", "section-new"]
        )
    }

    func testDashboardLayoutPersistsReorderedIndicators() throws {
        let suiteName = "DashboardLayoutStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let storageKey = "testDashboardOrder"
        let section = DashboardSection(
            id: "education",
            title: "Образование",
            indicators: ["a", "b", "c"].map { id in
                Indicator(
                    id: id,
                    title: id,
                    value: nil,
                    unit: nil,
                    chartType: .oneValue,
                    source: nil,
                    rows: []
                )
            }
        )

        let store = DashboardLayoutStore(defaults: defaults, storageKey: storageKey)
        store.moveIndicator(in: section, draggedID: "a", over: "b")

        let restoredStore = DashboardLayoutStore(defaults: defaults, storageKey: storageKey)
        XCTAssertEqual(restoredStore.orderedIndicators(in: section).map(\.id), ["b", "a", "c"])

        restoredStore.reset()

        let resetStore = DashboardLayoutStore(defaults: defaults, storageKey: storageKey)
        XCTAssertFalse(resetStore.hasCustomLayout)
        XCTAssertEqual(resetStore.orderedIndicators(in: section).map(\.id), ["a", "b", "c"])
    }

    func testAuthorizationURLContainsFreshState() throws {
        let url = try OAuthFlow.makeAuthorizationURL(
            baseURL: try XCTUnwrap(URL(string: "https://id.example/sign-in?state=stale")),
            clientID: "client-id",
            state: "fresh-state"
        )
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        XCTAssertEqual(items.filter { $0.name == "state" }.map(\.value), ["fresh-state"])
        XCTAssertEqual(items.first { $0.name == "client_id" }?.value, "client-id")
        XCTAssertEqual(items.first { $0.name == "response_type" }?.value, "code")
    }

    func testCallbackRejectsMismatchedState() throws {
        let callback = try XCTUnwrap(URL(string: "https://service.example/callback?code=abc&state=attacker"))

        XCTAssertThrowsError(try OAuthFlow.authorizationCode(from: callback, expectedState: "expected")) { error in
            guard case AuthenticationError.invalidState = error else {
                return XCTFail("Expected invalidState, got \(error)")
            }
        }
    }

    func testCallbackReturnsCodeForMatchingState() throws {
        let callback = try XCTUnwrap(URL(string: "https://service.example/callback?code=abc&state=expected"))

        XCTAssertEqual(try OAuthFlow.authorizationCode(from: callback, expectedState: "expected"), "abc")
    }

    func testUnauthorizedResponseRequiresAuthentication() throws {
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: try XCTUnwrap(URL(string: "https://service.example/analytics")),
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )
        )

        XCTAssertThrowsError(try APIAnalyticsProvider.validate(response)) { error in
            guard case AnalyticsError.authenticationRequired = error else {
                return XCTFail("Expected authenticationRequired, got \(error)")
            }
        }
    }

    func testAnalyticsRequestUsesFixedIDSectionAndSixtySecondTimeout() throws {
        let configuration = AppConfiguration(
            analyticsBaseURL: try XCTUnwrap(
                URL(string: "https://service.example/DGU_APP_Mobile_Client/analitycs/")
            ),
            analyticsAPIKey: nil,
            authenticationURL: try XCTUnwrap(URL(string: "https://id.example/sign-in")),
            authenticationClientID: "client-id",
            authenticationCallbackURL: try XCTUnwrap(URL(string: "https://service.example/callback")),
            authorizationCodeExchangeURL: try XCTUnwrap(URL(string: "https://service.example/auth/code"))
        )
        let provider = APIAnalyticsProvider(
            configuration: configuration,
            credentialsStore: StubRequestAuthorizer()
        )

        let request = try provider.makeRequest(for: AnalyticsAPIContract.sections[3])
        let queryItems = try XCTUnwrap(
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
        )

        XCTAssertEqual(queryItems.first { $0.name == "id" }?.value, "test_analitycs_med")
        XCTAssertEqual(queryItems.first { $0.name == "section" }?.value, "Приемная_кампания")
        XCTAssertEqual(request.timeoutInterval, 60)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test-Authorization"), "attached")
    }

    func testResponseMappingUsesFetchTimeAndCalculatesSubgroupSummary() throws {
        let data = Data(
            #"{"sections":[{"name":"Образование","values":[{"name":"Контингент","values":[{"group":"БАК","subgroup":[{"name":"РФ","value":10},{"name":"ИГ","value":2}]}],"type":"BarMarkStacking"}]}]}"#.utf8
        )

        let dashboard = try JSONDecoder().decode(AnalyticsAPIResponse.self, from: data).toDashboard()

        XCTAssertNotNil(dashboard.fetchedAt)
        XCTAssertEqual(dashboard.indicators.first?.value, 12)
        XCTAssertEqual(dashboard.indicators.first?.rows.count, 2)
        XCTAssertEqual(dashboard.indicators.first?.showsAggregateValue, true)
    }

    func testVerticalAndHorizontalBarsKeepMultipleValuesInsideMainGroups() throws {
        for chartType in ["BarMark", "BarMarkHorizon"] {
            let data = Data(
                """
                {
                  "sections": [{
                    "name": "Образование",
                    "values": [{
                      "name": "План-факт по уровням",
                      "values": [
                        {
                          "group": "БАК",
                          "subgroup": [
                            {"name": "План прошлый год", "value": 412755},
                            {"name": "Опл. прошлый год", "value": 899359},
                            {"name": "План текущий год", "value": 483360},
                            {"name": "Опл. текущий год", "value": 242167}
                          ]
                        },
                        {
                          "group": "СПЕЦ",
                          "subgroup": [
                            {"name": "План прошлый год", "value": 209445},
                            {"name": "Опл. прошлый год", "value": 457850},
                            {"name": "План текущий год", "value": 234387},
                            {"name": "Опл. текущий год", "value": 124083}
                          ]
                        }
                      ],
                      "type": "\(chartType)"
                    }]
                  }]
                }
                """.utf8
            )

            let indicator = try XCTUnwrap(
                JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
                    .toDashboard()
                    .indicators
                    .first
            )

            XCTAssertEqual(indicator.rowGroups.map(\.label), ["БАК", "СПЕЦ"])
            XCTAssertEqual(indicator.rowGroups.map { $0.rows.count }, [4, 4])
            XCTAssertEqual(
                indicator.barDataShape,
                .multipleValuesPerGroup(
                    series: [
                        "План прошлый год",
                        "Опл. прошлый год",
                        "План текущий год",
                        "Опл. текущий год"
                    ]
                )
            )
        }
    }

    func testContractPlanFactBuildsCurrentThenPreviousYearPresentation() throws {
        let data = Data(
            #"{"sections":[{"name":"Финансы","values":[{"name":"План-Факт (контракт), тыс. руб","values":[{"group":"БАК","subgroup":[{"name":"Прошлый год","values":[{"name":"План","value":412755},{"name":"Опл.","value":893538}]},{"name":"Текущий год","subgroup":[{"name":"Опл.","value":400192},{"name":"План","value":483360}]}]}],"type":"BarMark"}]}]}"#.utf8
        )

        let indicator = try XCTUnwrap(
            JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
                .toDashboard()
                .indicators
                .first
        )

        XCTAssertTrue(indicator.usesContractPlanFactPresentation)
        XCTAssertEqual(indicator.contractPlanFactCategories.map(\.label), ["БАК"])
        XCTAssertEqual(
            indicator.contractPlanFactCategories[0].periods.map(\.period),
            [.current, .previous]
        )
        XCTAssertEqual(
            indicator.contractPlanFactCategories[0].periods[0].rows.map(\.contractPlanFactMetricLabel),
            ["План", "Опл."]
        )
        XCTAssertEqual(
            indicator.contractPlanFactCategories[0].periods[0].rows.map(\.value),
            [483_360, 400_192]
        )
        XCTAssertEqual(
            indicator.contractPlanFactCategories[0].periods[1].rows.map(\.value),
            [412_755, 893_538]
        )
        XCTAssertEqual(
            try XCTUnwrap(indicator.contractPlanFactCategories[0].periods[0].completionRatio),
            400_192.0 / 483_360.0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(indicator.contractPlanFactCategories[0].periods[1].completionRatio),
            893_538.0 / 412_755.0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(indicator.contractPlanFactCategories[0].maximumValue, 893_538)
    }

    func testEnrollmentByCitizenshipOverridesStaleServerTypeWithHorizontalBar() throws {
        let data = Data(
            #"{"sections":[{"name":"Образование","values":[{"name":"Всего обучающихся РФ и ИГ","values":[{"group":"БАК","subgroup":[{"name":"РФ","value":18347},{"name":"ИГ","value":3604}]},{"group":"СПЕЦ","subgroup":[{"name":"РФ","value":5120},{"name":"ИГ","value":920}]},{"group":"МАГ","subgroup":[{"name":"РФ","value":3480},{"name":"ИГ","value":740}]},{"group":"АСП","subgroup":[{"name":"РФ","value":995},{"name":"ИГ","value":115}]}],"type":"BarMarkStacking"}]}]}"#.utf8
        )

        let indicator = try XCTUnwrap(
            JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
                .toDashboard()
                .indicators
                .first
        )

        XCTAssertEqual(indicator.chartType, .horizontalBar)
        XCTAssertNil(indicator.unit)
        XCTAssertFalse(indicator.usesStackedCompositionPresentation)
        XCTAssertTrue(indicator.usesCitizenshipCompositionPresentation)
        XCTAssertEqual(
            indicator.barDataShape,
            .multipleValuesPerGroup(series: ["РФ", "ИГ"])
        )
        XCTAssertEqual(indicator.rowGroups.map(\.totalValue), [21_951, 6_040, 4_220, 1_110])
    }

    func testGroupedValuesUseContractDefaultSummaryValue() throws {
        let data = Data(
            #"""
            {
              "sections": [{
                "name": "Финансы",
                "values": [{
                  "name": "План-факт",
                  "values": [
                    {"group": "План", "value": 120},
                    {"group": "Факт", "value": 80}
                  ],
                  "type": "BarMarkCompact"
                }]
              }]
            }
            """#.utf8
        )

        let indicator = try XCTUnwrap(
            JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
                .toDashboard()
                .indicators
                .first
        )

        XCTAssertEqual(indicator.value, 200)
        XCTAssertTrue(indicator.showsAggregateValue)
    }

    func testPlanFactTitlesFollowShowTotalContractDefault() {
        for title in ["План-факт", "План‑факт доходов", "План факт"] {
            let indicator = Indicator(
                id: title,
                title: title,
                value: nil,
                unit: nil,
                chartType: .bar,
                source: nil,
                rows: []
            )

            XCTAssertTrue(indicator.showsAggregateValue, title)
        }
    }

    func testPlanFactBarsUseVerticalPresentation() {
        let rows = [
            IndicatorRow(
                id: "current-plan",
                label: "Текущий год",
                value: 23_197_090,
                series: "План",
                sortOrder: 0
            ),
            IndicatorRow(
                id: "current-fact",
                label: "Текущий год",
                value: 14_737_476,
                series: "Факт",
                sortOrder: 1
            ),
            IndicatorRow(
                id: "previous-plan",
                label: "Прошлый год",
                value: 21_823_210,
                series: "План",
                sortOrder: 2
            ),
            IndicatorRow(
                id: "previous-fact",
                label: "Прошлый год",
                value: 21_767_084,
                series: "Факт",
                sortOrder: 3
            )
        ]

        for chartType in [ChartType.bar, .compactBar] {
            let indicator = Indicator(
                id: "plan-fact-income",
                title: "План-Факт доходов, тыс. руб",
                value: nil,
                unit: nil,
                chartType: chartType,
                source: nil,
                rows: rows
            )

            XCTAssertFalse(indicator.prefersHorizontalGroupedBars, chartType.rawValue)
        }
    }

    func testPresentationRulesKeepMixedPersonnelUnitsSeparate() {
        let indicator = Indicator(
            id: "personnel-share",
            title: "Доля АУП и УВП, % ССЧ",
            value: 4_663.1,
            unit: "чел.",
            chartType: .horizontalBar,
            source: nil,
            rows: [
                IndicatorRow(id: "total", label: "2026", value: 3_494.1, series: "Общая численность", sortOrder: 0),
                IndicatorRow(id: "aup", label: "2026", value: 762.1, series: "Численность АУП", sortOrder: 1),
                IndicatorRow(id: "aup-share", label: "2026", value: 21.8, series: "Процент АУП", sortOrder: 2)
            ]
        )

        XCTAssertTrue(indicator.usesMixedUnitPersonnelPresentation)
        XCTAssertTrue(indicator.showsAggregateValue)
    }

    func testAcademicTitleIndicatorKeepsEveryDonutCategory() {
        let rows = (0..<7).map {
            IndicatorRow(id: "title-\($0)", label: "Звание \($0)", value: Double($0 + 1), series: nil, sortOrder: $0)
        }
        let indicator = Indicator(
            id: "academic-titles",
            title: "ППС с учеными званиями, чел",
            value: 28,
            unit: "чел.",
            chartType: .donut,
            source: nil,
            rows: rows
        )

        XCTAssertEqual(indicator.chartType, .donut)
        XCTAssertEqual(indicator.orderedRows, rows)
    }

    func testPresentationRulesRecognizeZeroAndTemporalCharts() {
        let zeroIndicator = Indicator(
            id: "zero-plan-fact",
            title: "План-Факт (контракт), тыс. руб",
            value: nil,
            unit: nil,
            chartType: .bar,
            source: nil,
            rows: [
                IndicatorRow(id: "plan", label: "БАК", value: 0, series: "План", sortOrder: 0),
                IndicatorRow(id: "fact", label: "БАК", value: 0, series: "Факт", sortOrder: 1)
            ]
        )
        let temporalIndicator = Indicator(
            id: "research",
            title: "Внешнее финансирование НИОКР",
            value: 1_858,
            unit: "млн руб.",
            chartType: .bar,
            source: nil,
            rows: [
                IndicatorRow(id: "2024", label: "2024", value: 728, series: nil, sortOrder: 0),
                IndicatorRow(id: "2025", label: "2025", value: 666, series: nil, sortOrder: 1),
                IndicatorRow(id: "2026", label: "2026", value: 464, series: nil, sortOrder: 2)
            ]
        )

        XCTAssertTrue(zeroIndicator.hasOnlyZeroValues)
        XCTAssertTrue(temporalIndicator.prefersTrendPresentation)
    }

    func testTitleDoesNotProvideImplicitUnitWhenServerOmitsIt() {
        let indicator = Indicator(
            id: "share",
            title: "Доля НПР до 39 лет, %",
            value: 30,
            unit: nil,
            chartType: .oneValue,
            source: nil,
            rows: []
        )

        XCTAssertNil(indicator.displayUnit)
    }

    func testResponseMappingSupportsNewCompactIndicatorTypesAndColors() throws {
        let data = Data(
            #"""
            {
              "sections": [{
                "name": "Финансы",
                "values": [
                  {
                    "name": "Остаток",
                    "value": 4077837,
                    "colorGraph": "#C8752D",
                    "colorValue": "#111111",
                    "type": "OneValue"
                  },
                  {
                    "name": "Факт доходов",
                    "values": [{"value": 13450484, "valueMax": 23901704, "colorGraph": "#168AF2", "colorValue": "#15B889"}],
                    "type": "LinearProgressIndicator"
                  },
                  {
                    "name": "План-факт",
                    "values": [
                      {"group": "План 2025", "value": 21823210, "colorGraph": "#168AF2", "colorValue": "#333333"},
                      {"group": "Факт 2025", "value": 13450484, "colorGraph": "#66B547", "colorValue": "#444444"}
                    ],
                    "type": "BarMarkCompact"
                  }
                ]
              }]
            }
            """#.utf8
        )

        let dashboard = try JSONDecoder().decode(AnalyticsAPIResponse.self, from: data).toDashboard()

        XCTAssertEqual(dashboard.indicators.map(\.chartType), [.oneValue, .linearProgress, .compactBar])
        XCTAssertEqual(dashboard.indicators[0].value, 4_077_837)
        XCTAssertEqual(dashboard.indicators[0].colorGraph, "#C8752D")
        XCTAssertEqual(dashboard.indicators[0].colorValue, "#111111")
        XCTAssertEqual(dashboard.indicators[1].valueMax, 23_901_704)
        XCTAssertEqual(dashboard.indicators[1].unit, nil)
        XCTAssertEqual(dashboard.indicators[2].rows.map(\.colorGraph), ["#168AF2", "#66B547"])
        XCTAssertTrue(dashboard.indicators[2].supportsDetail)
    }

    func testResponseMappingPreservesAllSectionsInServerOrder() throws {
        let data = Data(
            #"""
            {
              "sections": [
                {
                  "name": "Образование",
                  "values": [{"name": "Обучающиеся", "value": 100, "type": "OneValue"}]
                },
                {
                  "name": "Финансы",
                  "values": [{"name": "Доходы", "value": 200, "type": "OneValue"}]
                }
              ]
            }
            """#.utf8
        )

        let dashboard = try JSONDecoder().decode(AnalyticsAPIResponse.self, from: data).toDashboard()

        XCTAssertEqual(dashboard.title, "Аналитика")
        XCTAssertEqual(dashboard.sections.map(\.title), ["Образование", "Финансы"])
        XCTAssertEqual(dashboard.sections.map { $0.indicators.count }, [1, 1])
        XCTAssertEqual(dashboard.indicators.map(\.title), ["Обучающиеся", "Доходы"])
        XCTAssertEqual(Set(dashboard.indicators.map(\.id)).count, 2)
    }

    func testCompactBarKeepsSubgroupsFromAnEmptyGroup() throws {
        let data = Data(
            #"""
            {
              "sections": [{
                "name": "Финансы",
                "values": [{
                  "name": "План-факт доходов",
                  "values": [{
                    "group": "",
                    "subgroup": [
                      {"name": "План 2025", "value": 21823210, "colorGraph": "#168AF2"},
                      {"name": "Факт 2025", "value": 21767084, "colorGraph": "#66B547"},
                      {"name": "План 2026", "value": 23901704, "colorGraph": "#168AF2"},
                      {"name": "Факт 2026", "value": 13450484, "colorGraph": "#66B547"}
                    ]
                  }],
                  "type": "BarMarkCompact"
                }]
              }]
            }
            """#.utf8
        )

        let dashboard = try JSONDecoder().decode(AnalyticsAPIResponse.self, from: data).toDashboard()
        let indicator = try XCTUnwrap(dashboard.indicators.first)

        XCTAssertEqual(indicator.rows.map(\.label), ["План 2025", "Факт 2025", "План 2026", "Факт 2026"])
        XCTAssertEqual(indicator.rows.map(\.value), [21_823_210, 21_767_084, 23_901_704, 13_450_484])
        XCTAssertEqual(indicator.rows.map(\.colorGraph), ["#168AF2", "#66B547", "#168AF2", "#66B547"])
    }

    func testRegularBarsKeepPlanFactSubgroupsFromAnEmptyGroup() throws {
        for chartType in ["BarMark", "BarMarkHorizon", "OneValue"] {
            let data = Data(
                """
                {
                  "sections": [{
                    "name": "Финансы",
                    "values": [{
                      "name": "План-Факт (контракт), тыс. руб",
                      "values": [{
                        "name": "Контракт",
                        "group": "",
                        "subgroup": [
                          {"name": "План", "value": 23901704, "colorGraph": "#168AF2"},
                          {"name": "Факт", "value": 13450484, "colorGraph": "#66B547"}
                        ]
                      }],
                      "type": "\(chartType)"
                    }]
                  }]
                }
                """.utf8
            )

            let indicator = try XCTUnwrap(
                JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
                    .toDashboard()
                    .indicators
                    .first
            )

            XCTAssertEqual(indicator.rows.map(\.label), ["Контракт", "Контракт"])
            XCTAssertEqual(indicator.rows.map(\.series), ["План", "Факт"])
            XCTAssertEqual(indicator.rows.map(\.value), [23_901_704, 13_450_484])
            XCTAssertEqual(indicator.rowGroups.map(\.label), ["Контракт"])
            XCTAssertEqual(indicator.chartType, .horizontalBar)
            XCTAssertEqual(indicator.value, 37_352_188)
            XCTAssertTrue(indicator.showsAggregateValue)
        }
    }

    func testAverageUnifiedStateExamScoreKeepsTwoUnlabelledValues() throws {
        let data = Data(
            #"{"sections":[{"name":"Образование","values":[{"name":"Средний балл ЕГЭ","values":[{"value":86.4},{"value":88.1}],"type":"OneValue"}]}]}"#.utf8
        )

        let indicator = try XCTUnwrap(
            JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
                .toDashboard()
                .indicators
                .first
        )

        XCTAssertEqual(indicator.chartType, .bar)
        XCTAssertEqual(indicator.rows.map(\.label), ["1", "2"])
        XCTAssertEqual(indicator.rows.map(\.value), [86.4, 88.1])
        XCTAssertEqual(indicator.value, Decimal(string: "174.5"))
    }

    func testCompactBarAcceptsNumericGroupsFromScienceSection() throws {
        let data = Data(
            #"""
            {
              "sections": [{
                "name": "Наука",
                "values": [{
                  "name": "Объем внешнего финансирования НИОКР, млн. руб.",
                  "values": [
                    {"group": 2024, "value": 728},
                    {"group": 2025, "value": 666},
                    {"group": 2026, "value": 462}
                  ],
                  "type": "BarMarkCompact"
                }]
              }]
            }
            """#.utf8
        )

        let dashboard = try JSONDecoder().decode(AnalyticsAPIResponse.self, from: data).toDashboard()
        let indicator = try XCTUnwrap(dashboard.indicators.first)

        XCTAssertEqual(indicator.rows.map(\.label), ["2024", "2025", "2026"])
        XCTAssertEqual(indicator.rows.map(\.value), [728, 666, 462])
        XCTAssertEqual(indicator.value, 1_856)
        XCTAssertTrue(indicator.showsAggregateValue)
    }

    func testResponseMappingSupportsGaugeGeoMapAndServerDisplayOptions() throws {
        let data = Data(
            #"""
            {
              "sections": [
                {
                  "name": "Финансы",
                  "values": [{
                    "name": "Факт доходов, тыс. руб",
                    "values": [{
                      "value": 13591215,
                      "valueMax": 24009730,
                      "colorGraph": "#0089fe",
                      "colorValue": "#6ba547"
                    }],
                    "widthPercent": 50,
                    "type": "Gauge"
                  }]
                },
                {
                  "name": "Международная деятельность",
                  "values": [{
                    "name": "ИГ по регионам мира, чел",
                    "values": [
                      {"group": "КИТАЙ", "value": 1757},
                      {"group": "ТУРКМЕНИСТАН", "value": 1009}
                    ],
                    "showLegend": false,
                    "showTotal": false,
                    "type": "GeoMap"
                  }]
                }
              ]
            }
            """#.utf8
        )

        let dashboard = try JSONDecoder().decode(AnalyticsAPIResponse.self, from: data).toDashboard()
        let gauge = dashboard.sections[0].indicators[0]
        let geoMap = dashboard.sections[1].indicators[0]

        XCTAssertEqual(gauge.chartType, .gauge)
        XCTAssertEqual(gauge.value, 13_591_215)
        XCTAssertEqual(gauge.valueMax, 24_009_730)
        XCTAssertEqual(gauge.widthPercent, 50)
        XCTAssertTrue(gauge.supportsDetail)

        XCTAssertEqual(geoMap.chartType, .geoMap)
        XCTAssertEqual(geoMap.rows.map(\.label), ["КИТАЙ", "ТУРКМЕНИСТАН"])
        XCTAssertEqual(geoMap.value, 2_766)
        XCTAssertFalse(geoMap.showsLegend)
        XCTAssertFalse(geoMap.showsAggregateValue)
        XCTAssertTrue(geoMap.supportsDetail)
    }

    func testChartCatalogContractAddsNewChartsWithoutChangingLegacyDefaults() throws {
        let data = Data(
            #"""
            {
              "sections": [{
                "name": "Каталог",
                "values": [
                  {
                    "name": "Линия",
                    "type": "LineChart",
                    "show_total": false,
                    "show_details": false,
                    "useAbbreviations": true,
                    "valueGap": 80,
                    "lineStyle": "dashed",
                    "values": [
                      {"group": "Янв", "value": 10},
                      {"group": "Фев", "value": 14}
                    ]
                  },
                  {
                    "name": "Область",
                    "type": "Area",
                    "barLayout": "compact",
                    "values": [{"group": "Янв", "value": 8}]
                  },
                  {
                    "name": "Сглаженные линии",
                    "type": "SmoothLineMark",
                    "values": [{
                      "group": "Янв",
                      "subgroup": [
                        {"name": "Создано", "value": 12},
                        {"name": "Закрыто", "value": 9, "dashed": true}
                      ]
                    }]
                  },
                  {
                    "name": "Сглаженная область",
                    "type": "LayeredAreaMark",
                    "values": [{"group": "Янв", "value": 7}]
                  },
                  {
                    "name": "Прогноз",
                    "type": "PredictionLineMark",
                    "forecastFromIndex": 2,
                    "values": [
                      {"group": "1", "value": 2},
                      {"group": "2", "value": 4},
                      {"group": "3", "value": 6}
                    ]
                  },
                  {
                    "name": "Доли",
                    "type": "SectorMarkPercent",
                    "itemSpacing": -5,
                    "values": [
                      {"group": "Web", "value": 60},
                      {"group": "Email", "value": 40}
                    ]
                  }
                ]
              }]
            }
            """#.utf8
        )

        let indicators = try JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
            .toDashboard()
            .indicators

        XCTAssertEqual(
            indicators.map(\.chartType),
            [.line, .area, .splineLine, .splineArea, .forecastLine, .percentDonut]
        )

        let line = indicators[0]
        XCTAssertFalse(line.showsAggregateValue)
        XCTAssertFalse(line.supportsDetail)
        XCTAssertEqual(line.useCompactNumbers, true)
        XCTAssertEqual(line.valueSpacing, 64)
        XCTAssertEqual(line.lineStyle, .dashed)

        XCTAssertEqual(indicators[1].barLayout, .compact)
        XCTAssertEqual(indicators[2].rows.map(\.lineStyle), [nil, .dashed])
        XCTAssertEqual(indicators[4].forecastFromIndex, 2)
        XCTAssertEqual(indicators[5].valueSpacing, 0)

        XCTAssertTrue(line.showsLegend)
        XCTAssertTrue(indicators[1].showsAggregateValue)
    }

    func testExpandedChartCatalogContractMapsValueLabelsGroupTotalsAndDetailsOrientation() throws {
        let data = Data(
            #"""
            {
              "sections": [{
                "name": "Образование",
                "values": [{
                  "name": "Контингент",
                  "type": "BarMarkStacking",
                  "showValueLabels": false,
                  "detailsOrientation": "horizontal",
                  "values": [{
                    "group": "БАК",
                    "totalLabel": "16161/3220",
                    "subgroup": [
                      {"name": "РФ", "value": 16161},
                      {"name": "ИГ", "value": 3220}
                    ]
                  }]
                }, {
                  "name": "Алиас подписей",
                  "type": "BarMark",
                  "showLabels": false,
                  "values": [{"group": "2026", "value": 1}]
                }]
              }]
            }
            """#.utf8
        )

        let indicators = try JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
            .toDashboard()
            .indicators
        let stacked = try XCTUnwrap(indicators.first)

        XCTAssertFalse(stacked.showsValueLabels)
        XCTAssertEqual(stacked.detailsOrientation, .horizontal)
        XCTAssertEqual(stacked.rowGroups.first?.totalLabel, "16161/3220")
        XCTAssertEqual(stacked.rowGroups.first?.totalValue, 19_381)
        XCTAssertFalse(indicators[1].showsValueLabels)
    }

    func testLatestChartContractMapsAliasesCategoryTitlesAndCustomValueLabels() throws {
        let data = Data(
            #"""
            {
              "sections": [{
                "name": "Контракт",
                "values": [{
                  "name": "Алиасы",
                  "type": "LineMark",
                  "displayValueLabels": false,
                  "showScale": true,
                  "detailsLayout": "horizontal",
                  "abbreviateValues": true,
                  "values": [{
                    "name": "Янв",
                    "displayTotal": "10/20",
                    "subgroup": [
                      {"name": "План", "value": 10, "displayValue": "десять"},
                      {"name": "Факт", "value": 20, "totalLabel": "двадцать"}
                    ]
                  }, {
                    "title": "Фев",
                    "value": 30,
                    "valueLabel": "тридцать"
                  }, {
                    "group": "Мар",
                    "totalValue": "итог марта",
                    "value": 40,
                    "displayLabel": "сорок"
                  }]
                }]
              }]
            }
            """#.utf8
        )

        let indicator = try XCTUnwrap(
            JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
                .toDashboard()
                .indicators
                .first
        )

        XCTAssertFalse(indicator.showsValueLabels)
        XCTAssertTrue(indicator.showsYAxisLabels)
        XCTAssertEqual(indicator.resolvedDetailsOrientation, .horizontal)
        XCTAssertEqual(indicator.useCompactNumbers, true)
        XCTAssertEqual(indicator.rows.map(\.label), ["Янв", "Янв", "Фев", "Мар"])
        XCTAssertEqual(indicator.rows.map(\.valueLabel), ["десять", "двадцать", "тридцать", "сорок"])
        XCTAssertEqual(indicator.rowGroups.map(\.totalLabel), ["10/20", nil, "итог марта"])
    }

    func testLatestChartContractAppliesDefaultsAndScalarDetails() throws {
        let data = Data(
            #"""
            {
              "sections": [{
                "name": "Контракт",
                "values": [{
                  "name": "Линия",
                  "type": "LineMark",
                  "values": [{"group": "Янв", "value": 10}]
                }, {
                  "name": "Карта",
                  "type": "GeoMap",
                  "values": [{"group": "RU", "value": 20}]
                }, {
                  "name": "Индикатор",
                  "type": "Gauge",
                  "values": {"value": 30, "valueMax": 100, "valueLabel": "30 из 100"}
                }]
              }]
            }
            """#.utf8
        )

        let indicators = try JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
            .toDashboard()
            .indicators
        let line = indicators[0]
        let map = indicators[1]
        let gauge = indicators[2]

        XCTAssertTrue(line.showsAggregateValue)
        XCTAssertTrue(line.supportsDetail)
        XCTAssertTrue(line.showsValueLabels)
        XCTAssertFalse(line.showsYAxisLabels)
        XCTAssertTrue(line.showsLegend)
        XCTAssertEqual(line.resolvedDetailsOrientation, .vertical)
        XCTAssertEqual(line.resolvedWidthPercent, 100)

        XCTAssertFalse(map.showsAggregateValue)
        XCTAssertFalse(map.showsLegend)
        XCTAssertTrue(map.supportsDetail)

        XCTAssertTrue(gauge.supportsDetail)
        XCTAssertEqual(gauge.rows.map(\.valueLabel), ["30 из 100"])
    }

    func testLatestChartContractSupportsRemainingDisplayAliases() throws {
        let aliases = [
            ("showYAxis", "detailOrientation"),
            ("displayYAxisLabels", "detailsLayout")
        ]

        for (yAxisAlias, orientationAlias) in aliases {
            let data = Data(
                """
                {
                  "sections": [{
                    "name": "Контракт",
                    "values": [{
                      "name": "График",
                      "type": "AreaMark",
                      "\(yAxisAlias)": true,
                      "\(orientationAlias)": "horizontal",
                      "values": [{"group": "A", "value": 1}]
                    }]
                  }]
                }
                """.utf8
            )

            let indicator = try XCTUnwrap(
                JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
                    .toDashboard()
                    .indicators
                    .first
            )
            XCTAssertTrue(indicator.showsYAxisLabels, yAxisAlias)
            XCTAssertEqual(indicator.resolvedDetailsOrientation, .horizontal, orientationAlias)
        }
    }

    func testForecastDefaultsToLastQuarterRoundedUp() {
        XCTAssertEqual(ForecastPresentationPolicy.startIndex(pointCount: 6, explicitIndex: nil), 4)
        XCTAssertEqual(ForecastPresentationPolicy.startIndex(pointCount: 8, explicitIndex: nil), 6)
        XCTAssertEqual(ForecastPresentationPolicy.startIndex(pointCount: 1, explicitIndex: nil), 0)
        XCTAssertEqual(ForecastPresentationPolicy.startIndex(pointCount: 6, explicitIndex: 2), 2)
        XCTAssertNil(ForecastPresentationPolicy.startIndex(pointCount: 0, explicitIndex: nil))
    }

    func testAndroidContractAliasesFlexibleNumbersNestedValuesAndStableIDs() throws {
        let data = Data(
            #"""
            {
              "sections": [{
                "name": "Финансы",
                "values": [
                  {
                    "id": "stable-chart",
                    "name": "Исполнение",
                    "type": "GaugeIndicator",
                    "width": "70",
                    "values": {
                      "value": "1 234,5",
                      "valueMax": "2 000"
                    }
                  },
                  {
                    "id": "stable-chart",
                    "name": "География",
                    "type": "WorldMap",
                    "halfWidth": "true",
                    "values": [{"group": "РОССИЯ", "value": "1 000"}]
                  },
                  {
                    "identifier": "fallback-identifier",
                    "name": "Новый серверный тип",
                    "type": "UnknownChart",
                    "values": {"group": 2026, "value": "12,5"}
                  },
                  {
                    "name": "Вложенные серии",
                    "type": "BarMarkCompact",
                    "values": {
                      "group": "",
                      "values": [
                        {"name": "План", "value": "1 200"},
                        {"name": "Факт", "value": 950}
                      ]
                    }
                  }
                ]
              }]
            }
            """#.utf8
        )

        let indicators = try JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
            .toDashboard()
            .indicators

        XCTAssertEqual(indicators.map(\.chartType), [.gauge, .geoMap, .bar, .compactBar])
        XCTAssertEqual(indicators[0].value, Decimal(string: "1234.5"))
        XCTAssertEqual(indicators[0].valueMax, 2_000)
        XCTAssertEqual(indicators[0].widthPercent, 100)
        XCTAssertEqual(indicators[1].widthPercent, 50)
        XCTAssertEqual(indicators[1].rows.first?.value, 1_000)
        XCTAssertEqual(indicators[2].rows.first?.label, "2026")
        XCTAssertEqual(indicators[2].rows.first?.value, 12.5)
        XCTAssertEqual(indicators[3].rows.map(\.label), ["План", "Факт"])
        XCTAssertEqual(indicators[3].rows.map(\.value), [1_200, 950])
        XCTAssertEqual(Set(indicators.map(\.id)).count, indicators.count)
        XCTAssertTrue(indicators[0].id.hasSuffix("-stable-chart"))
        XCTAssertTrue(indicators[1].id.hasSuffix("-stable-chart#2"))
        XCTAssertTrue(indicators[2].id.hasSuffix("-fallback-identifier"))
        XCTAssertTrue(indicators[3].id.hasSuffix("-3"))
    }

    func testSectionCanContainSingleIndicatorObject() throws {
        let data = Data(
            #"""
            {
              "sections": {
                "name": "Кадры",
                "values": {
                  "name": "Сотрудники",
                  "type": "OneValue",
                  "value": "12 345"
                }
              }
            }
            """#.utf8
        )

        let dashboard = try JSONDecoder().decode(AnalyticsAPIResponse.self, from: data).toDashboard()

        XCTAssertEqual(dashboard.sections.map(\.title), ["Кадры"])
        XCTAssertEqual(dashboard.indicators.first?.chartType, .oneValue)
        XCTAssertEqual(dashboard.indicators.first?.value, 12_345)
    }

    func testDashboardDecodesLegacyCachedTimestamp() throws {
        let data = Data(
            #"{"id":"cached","title":"Cached","updatedAt":"2026-07-21T10:00:00Z","indicators":[]}"#.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let dashboard = try decoder.decode(Dashboard.self, from: data)

        XCTAssertNotNil(dashboard.fetchedAt)
        XCTAssertEqual(dashboard.sections.first?.title, "Cached")
    }

    func testAuthenticationFailureReplacesCachedDashboardAndNotifiesRoot() async {
        var didRequireAuthentication = false
        let cached = Dashboard(id: "cached", title: "Cached", fetchedAt: .distantPast, indicators: [])
        let viewModel = DashboardViewModel(
            provider: AuthenticationFailingProvider(),
            cache: StubDashboardCache(dashboard: cached),
            onAuthenticationRequired: { didRequireAuthentication = true }
        )

        await viewModel.load()

        XCTAssertTrue(didRequireAuthentication)
        guard case .failed = viewModel.state else {
            return XCTFail("Cached data must be hidden after an authorization failure")
        }
    }

    func testNetworkFailureKeepsCachedDashboardAndShowsOfflineStatus() async {
        let cached = Dashboard(id: "cached", title: "Cached", fetchedAt: .distantPast, indicators: [])
        let viewModel = DashboardViewModel(
            provider: NetworkFailingProvider(code: .timedOut),
            cache: StubDashboardCache(dashboard: cached)
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.dashboard, cached)
        XCTAssertTrue(viewModel.isShowingCachedData)
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertEqual(
            viewModel.refreshErrorMessage,
            "Сервер не успел ответить. Подождите немного и повторите обновление."
        )
    }

    func testFailedRefreshSwitchesLoadedDashboardToOfflineStatus() async {
        let dashboard = Dashboard(id: "fresh", title: "Fresh", fetchedAt: Date(), indicators: [])
        let viewModel = DashboardViewModel(
            provider: SucceedingThenFailingProvider(dashboard: dashboard),
            cache: StubDashboardCache(dashboard: nil)
        )

        await viewModel.load()
        XCTAssertFalse(viewModel.isShowingCachedData)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.dashboard, dashboard)
        XCTAssertTrue(viewModel.isShowingCachedData)
        XCTAssertNotNil(viewModel.refreshErrorMessage)
    }

    func testPartialRefreshPublishesFreshSectionAndKeepsOtherCachedSections() async {
        let cachedSection = DashboardSection(
            id: "финансы",
            title: "Финансы",
            indicators: []
        )
        let freshSection = DashboardSection(
            id: "образование",
            title: "Образование",
            indicators: []
        )
        let cached = Dashboard(
            id: "cached",
            title: "Cached",
            fetchedAt: .distantPast,
            sections: [cachedSection]
        )
        let viewModel = DashboardViewModel(
            provider: PartiallyFailingProvider(section: freshSection),
            cache: StubDashboardCache(dashboard: cached)
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.dashboard?.sections.map(\.title), ["Образование", "Финансы"])
        XCTAssertFalse(viewModel.isShowingCachedData)
        XCTAssertEqual(
            viewModel.refreshErrorMessage,
            "Не удалось обновить разделы: Кадры. Уже полученные данные сохранены."
        )
    }
}

@MainActor
private struct StubRequestAuthorizer: AuthenticationRequestAuthorizing {
    func addAuthentication(to request: inout URLRequest) throws {
        request.setValue("attached", forHTTPHeaderField: "X-Test-Authorization")
    }
}

@MainActor
private struct AuthenticationFailingProvider: AnalyticsProvider {
    func fetchDashboard() async throws -> Dashboard {
        throw AnalyticsError.authenticationRequired
    }
}

@MainActor
private struct NetworkFailingProvider: AnalyticsProvider {
    let code: URLError.Code

    func fetchDashboard() async throws -> Dashboard {
        throw URLError(code)
    }
}

@MainActor
private final class SucceedingThenFailingProvider: AnalyticsProvider {
    private let dashboard: Dashboard
    private var requestCount = 0

    init(dashboard: Dashboard) {
        self.dashboard = dashboard
    }

    func fetchDashboard() async throws -> Dashboard {
        requestCount += 1
        if requestCount == 1 {
            return dashboard
        }

        throw URLError(.networkConnectionLost)
    }
}

@MainActor
private struct PartiallyFailingProvider: AnalyticsProvider {
    let section: DashboardSection

    func fetchDashboard() async throws -> Dashboard {
        throw AnalyticsError.partialFailure(sections: ["Кадры"])
    }

    func fetchDashboard(
        onSectionReceived: @escaping @MainActor @Sendable (DashboardSection) -> Void
    ) async throws -> Dashboard {
        onSectionReceived(section)
        throw AnalyticsError.partialFailure(sections: ["Кадры"])
    }
}

@MainActor
private final class StubDashboardCache: DashboardCaching {
    private let dashboard: Dashboard?

    init(dashboard: Dashboard?) {
        self.dashboard = dashboard
    }

    func loadDashboard() throws -> Dashboard? { dashboard }
    func save(_ dashboard: Dashboard) throws {}
}
