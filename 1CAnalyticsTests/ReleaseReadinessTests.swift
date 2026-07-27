import XCTest
@testable import _C_Analytics

@MainActor
final class ReleaseReadinessTests: XCTestCase {
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

    func testResponseMappingUsesFetchTimeAndMapsSubgroupsWithoutInventingSummary() throws {
        let data = Data(
            #"{"sections":[{"name":"Образование","values":[{"name":"Контингент","values":[{"group":"БАК","subgroup":[{"name":"РФ","value":10},{"name":"ИГ","value":2}]}],"type":"BarMarkStacking"}]}]}"#.utf8
        )

        let dashboard = try JSONDecoder().decode(AnalyticsAPIResponse.self, from: data).toDashboard()

        XCTAssertNotNil(dashboard.fetchedAt)
        XCTAssertNil(dashboard.indicators.first?.value)
        XCTAssertEqual(dashboard.indicators.first?.rows.count, 2)
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
private final class StubDashboardCache: DashboardCaching {
    private let dashboard: Dashboard?

    init(dashboard: Dashboard?) {
        self.dashboard = dashboard
    }

    func loadDashboard() throws -> Dashboard? { dashboard }
    func save(_ dashboard: Dashboard) throws {}
}
