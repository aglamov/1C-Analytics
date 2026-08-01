import XCTest
@testable import _C_Analytics

@MainActor
final class ReleaseReadinessTests: XCTestCase {
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

    func testGroupedValuesDoNotPopulateMissingSummaryValue() throws {
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

        XCTAssertNil(indicator.value)
        XCTAssertFalse(indicator.showsAggregateValue)
    }

    func testPlanFactTitlesNeverShowMisleadingAggregateValue() {
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

            XCTAssertFalse(indicator.showsAggregateValue, title)
        }
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
        XCTAssertFalse(gauge.supportsDetail)

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

        XCTAssertFalse(line.showsLegend)
        XCTAssertTrue(indicators[1].showsAggregateValue)
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
