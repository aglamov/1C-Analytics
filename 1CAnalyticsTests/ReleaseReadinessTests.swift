import XCTest
import UIKit
@testable import _C_Analytics

@MainActor
final class ReleaseReadinessTests: XCTestCase {
    func testFailedExtendedReloadKeepsCachedContentExpanded() {
        XCTAssertFalse(
            DashboardExtendedSectionPresentationPolicy.shouldCollapseAfterFailedLoad(
                hasCachedContent: true
            )
        )
        XCTAssertTrue(
            DashboardExtendedSectionPresentationPolicy.shouldCollapseAfterFailedLoad(
                hasCachedContent: false
            )
        )
    }

    func testSynchronizationProtocolStartsCollapsedForGroupsAndSubgroups() {
        XCTAssertFalse(
            DashboardSynchronizationItemPresentationPolicy.isInitiallyExpanded(for: .standard)
        )
        XCTAssertFalse(
            DashboardSynchronizationItemPresentationPolicy.isInitiallyExpanded(for: .extended)
        )
    }

    func testSignOutClearsDashboardBeforeCredentials() {
        let events = SignOutEventRecorder()
        let credentialsStore = StubAuthenticationCredentialsStore(events: events)
        let dashboardCache = SignOutDashboardCache(events: events)
        let viewModel = AuthenticationViewModel(
            credentialsStore: credentialsStore,
            dashboardCache: dashboardCache
        )

        viewModel.signOut()

        XCTAssertEqual(events.values, [.dashboardCleared, .credentialsCleared])
        XCTAssertEqual(viewModel.state, .signedOut)
    }

    func testSignOutStillClearsCredentialsWhenDashboardCleanupFails() {
        let events = SignOutEventRecorder()
        let credentialsStore = StubAuthenticationCredentialsStore(events: events)
        let dashboardCache = SignOutDashboardCache(events: events, shouldFail: true)
        let viewModel = AuthenticationViewModel(
            credentialsStore: credentialsStore,
            dashboardCache: dashboardCache
        )

        viewModel.signOut()

        XCTAssertEqual(events.values, [.dashboardCleared, .credentialsCleared])
        guard case let .failed(message) = viewModel.state else {
            return XCTFail("Ожидалась ошибка очистки локальных данных")
        }
        XCTAssertEqual(message, DashboardCacheError.unavailable("test").localizedDescription)
    }

    func testDashboardCacheClearRemovesCurrentUsersStoredDashboard() throws {
        let credentialsStore = StubAuthenticationCredentialsStore(events: SignOutEventRecorder())
        let cache = try DashboardCache(inMemory: true, credentialsStore: credentialsStore)
        let dashboard = Dashboard(
            id: "dashboard",
            title: "Дашборд",
            fetchedAt: Date(),
            indicators: []
        )

        try cache.save(dashboard)
        XCTAssertEqual(try cache.loadDashboard()?.id, dashboard.id)

        try cache.clearDashboard()

        XCTAssertNil(try cache.loadDashboard())
    }

    func testSelectedPaletteOverridesServerGraphColor() {
        let row = IndicatorRow(
            id: "row",
            label: "Показатель",
            value: 42,
            series: nil,
            sortOrder: 0,
            colorGraph: "#FF0000"
        )
        let indicator = Indicator(
            id: "indicator",
            title: "Показатель",
            value: nil,
            unit: nil,
            chartType: .bar,
            source: nil,
            colorGraph: "#FF0000",
            rows: [row]
        )

        let corporateColor = UIColor(indicator.chartColor(for: row, scheme: .corporate))
        let playfulColor = UIColor(indicator.chartColor(for: row, scheme: .playful))
        let standardColor = UIColor(indicator.chartColor(for: row, scheme: .standard))

        XCTAssertNotEqual(corporateColor, playfulColor)
        XCTAssertEqual(
            corporateColor,
            UIColor(ChartPalette.colors(for: .corporate)[0])
        )
        XCTAssertEqual(
            playfulColor,
            UIColor(ChartPalette.colors(for: .playful)[0])
        )
        XCTAssertEqual(standardColor, UIColor(red: 1, green: 0, blue: 0, alpha: 1))
    }

    func testDetailPercentagesUseAtMostThreeFractionDigits() {
        let locale = Locale(identifier: "en_US_POSIX")

        XCTAssertEqual(
            DetailPresentationPolicy.shareText(
                for: 1,
                denominator: 8,
                fractionDigits: 3,
                locale: locale
            ),
            "12.5%"
        )
        XCTAssertEqual(
            DetailPresentationPolicy.shareText(
                for: 0,
                denominator: nil,
                fractionDigits: 3,
                locale: locale
            ),
            "0%"
        )
    }

    func testGeoMapExcludesAntarcticaFromRenderedGeometry() {
        XCTAssertFalse(
            GeoMapPresentationPolicy.shouldIncludeCountry(
                nameRU: "Антарктида",
                admin: "Antarctica",
                isoA3: "ATA"
            )
        )
        XCTAssertTrue(
            GeoMapPresentationPolicy.shouldIncludeCountry(
                nameRU: "Китай",
                admin: "China",
                isoA3: "CHN"
            )
        )
    }

    func testGeoMapSelectionMatchesAPICountryAliasToISOCode() {
        let row = IndicatorRow(
            id: "china",
            label: "КИТАЙ",
            value: 1_757,
            series: nil,
            sortOrder: 0
        )

        XCTAssertTrue(GeoMapPresentationPolicy.countryKeys(for: row).contains("CHN"))
    }

    func testIPadDashboardAlwaysPlacesIndicatorsTwoPerRow() {
        let rows = DashboardGridLayoutPolicy.rows(for: [1, 2, 3, 4, 5], isPad: true)

        XCTAssertEqual(rows, [[1, 2], [3, 4], [5]])
    }

    func testSlotLayoutPacksMixedCardWidthsWithoutReordering() {
        let indicators = ["a", "b", "c", "d"].map { id in
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
        let items = [
            DashboardIndicatorLayoutItem(indicator: indicators[0], width: .half),
            DashboardIndicatorLayoutItem(indicator: indicators[1], width: .full),
            DashboardIndicatorLayoutItem(indicator: indicators[2], width: .half),
            DashboardIndicatorLayoutItem(indicator: indicators[3], width: .full)
        ]

        let compactRows = DashboardGridLayoutPolicy.rows(for: items, slotCapacity: 2)
        XCTAssertEqual(compactRows.map { $0.items.map(\.id) }, [["a"], ["b"], ["c"], ["d"]])

        let regularRows = DashboardGridLayoutPolicy.rows(for: items, slotCapacity: 4)
        XCTAssertEqual(regularRows.map { $0.items.map(\.id) }, [["a", "b", "c"], ["d"]])
    }

    func testSlotMetricsNeverExceedAvailableDashboardWidth() {
        let compact = DashboardSlotMetrics(
            availableWidth: 361,
            slotCapacity: 2,
            spacing: 16
        )
        XCTAssertEqual(compact.occupiedWidth(spans: [2]), 361, accuracy: 0.001)
        XCTAssertEqual(compact.occupiedWidth(spans: [1, 1]), 361, accuracy: 0.001)

        let regular = DashboardSlotMetrics(
            availableWidth: 744,
            slotCapacity: 4,
            spacing: 16
        )
        XCTAssertLessThanOrEqual(regular.occupiedWidth(spans: [1, 2]), 744)
        XCTAssertEqual(regular.occupiedWidth(spans: [2, 2]), 744, accuracy: 0.001)
    }

    func testDashboardScaleIsClampedAndRoundedToFivePercentSteps() {
        XCTAssertEqual(DashboardContentScalePolicy.normalized(0.5), 0.8, accuracy: 0.000_001)
        XCTAssertEqual(DashboardContentScalePolicy.normalized(1.07), 1.05, accuracy: 0.000_001)
        XCTAssertEqual(DashboardContentScalePolicy.normalized(1.08), 1.10, accuracy: 0.000_001)
        XCTAssertEqual(DashboardContentScalePolicy.normalized(1.8), 1.3, accuracy: 0.000_001)
    }

    func testIPhoneDashboardKeepsOneIndicatorPerRow() {
        let rows = DashboardGridLayoutPolicy.rows(for: [1, 2, 3], isPad: false)

        XCTAssertEqual(rows, [[1], [2], [3]])
    }

    func testBulkSectionActionScrollsOnlyWhenCollapsing() {
        let sectionIDs = ["education", "finance", "science"]

        XCTAssertEqual(
            DashboardBulkSectionActionPolicy.action(
                sectionIDs: sectionIDs,
                collapsedSectionIDs: []
            ),
            .collapseAndScrollToTop
        )
        XCTAssertEqual(
            DashboardBulkSectionActionPolicy.action(
                sectionIDs: sectionIDs,
                collapsedSectionIDs: Set(sectionIDs)
            ),
            .expandPreservingPosition
        )
        XCTAssertEqual(
            DashboardBulkSectionActionPolicy.action(
                sectionIDs: sectionIDs,
                collapsedSectionIDs: ["education"]
            ),
            .collapseAndScrollToTop
        )
    }

    func testDashboardSectionGraphCountUsesRussianPluralRules() {
        XCTAssertEqual(DashboardSectionTextPolicy.graphCountText(1), "1 график")
        XCTAssertEqual(DashboardSectionTextPolicy.graphCountText(2), "2 графика")
        XCTAssertEqual(DashboardSectionTextPolicy.graphCountText(4), "4 графика")
        XCTAssertEqual(DashboardSectionTextPolicy.graphCountText(5), "5 графиков")
        XCTAssertEqual(DashboardSectionTextPolicy.graphCountText(11), "11 графиков")
        XCTAssertEqual(DashboardSectionTextPolicy.graphCountText(21), "21 график")
    }

    func testDashboardSectionGraphCountIncludesLoadedExtendedCharts() {
        let primary = Indicator(
            id: "primary",
            title: "Основной",
            value: 1,
            unit: nil,
            chartType: .oneValue,
            source: nil,
            rows: []
        )
        let extended = Indicator(
            id: "extended",
            title: "Второй уровень",
            value: 2,
            unit: nil,
            chartType: .oneValue,
            source: nil,
            rows: []
        )
        let unloadedSection = DashboardSection(
            id: "section",
            title: "Раздел",
            indicators: [primary],
            hasExtended: true
        )
        let loadedSection = DashboardSection(
            id: "section",
            title: "Раздел",
            indicators: [primary],
            hasExtended: true,
            extended: DashboardExtendedSection(
                id: "extended:section",
                title: "Раздел · 2 уровень",
                indicators: [extended]
            )
        )

        XCTAssertEqual(DashboardSectionTextPolicy.graphCount(in: unloadedSection), 1)
        XCTAssertEqual(DashboardSectionTextPolicy.graphCount(in: loadedSection), 2)
    }

    func testIPadSingleChartRowExpandsToFullAvailableWidth() {
        let indicator = Indicator(
            id: "single",
            title: "Один график",
            value: 1,
            unit: nil,
            chartType: .oneValue,
            source: nil,
            rows: []
        )
        let row = DashboardIndicatorLayoutRow(
            items: [DashboardIndicatorLayoutItem(indicator: indicator, width: .full)],
            slotCapacity: 4
        )

        XCTAssertEqual(row.spans(expandingSingleItemToFill: true), [4])
        XCTAssertEqual(row.spans(expandingSingleItemToFill: false), [2])
    }

    func testLegacySynchronizationHistoryIsDiscarded() throws {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "sync-history-cleanup-tests-\(UUID().uuidString)")
        )
        defaults.set(Data("old-history".utf8), forKey: DashboardSynchronizationStoragePolicy.legacyHistoryKey)

        DashboardSynchronizationStoragePolicy.discardLegacyHistory(from: defaults)

        XCTAssertNil(defaults.object(forKey: DashboardSynchronizationStoragePolicy.legacyHistoryKey))
    }

    func testErrorNoticeCanBePresentedAgainForTheSameMessage() {
        let initialPresentation = DashboardOfflineNoticeTaskID(
            errorMessage: "Не удалось обновить данные",
            presentationRequest: 0
        )
        let repeatedPresentation = DashboardOfflineNoticeTaskID(
            errorMessage: "Не удалось обновить данные",
            presentationRequest: 1
        )

        XCTAssertNotEqual(initialPresentation, repeatedPresentation)
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

    func testTrendPointValueLabelsFollowContractPriority() {
        XCTAssertFalse(
            TrendPointValueLabelPolicy.isVisible(
                rowMatchesSelection: true,
                showValueLabels: false,
                alwaysShowPointValues: true
            )
        )
        XCTAssertFalse(
            TrendPointValueLabelPolicy.isVisible(
                rowMatchesSelection: false,
                showValueLabels: true,
                alwaysShowPointValues: false
            )
        )
        XCTAssertTrue(
            TrendPointValueLabelPolicy.isVisible(
                rowMatchesSelection: true,
                showValueLabels: nil,
                alwaysShowPointValues: false
            )
        )
        XCTAssertTrue(
            TrendPointValueLabelPolicy.isVisible(
                rowMatchesSelection: false,
                showValueLabels: true,
                alwaysShowPointValues: true
            )
        )
        XCTAssertTrue(
            TrendPointValueLabelPolicy.isVisible(
                rowMatchesSelection: false,
                showValueLabels: nil,
                alwaysShowPointValues: nil
            )
        )
    }

    func testSelectedValueLabelGrowsSlightlyButStaysCompact() {
        for usesContrastingForeground in [false, true] {
            let idle = ChartValueLabelLayoutPolicy.metrics(
                isSelected: false,
                usesContrastingForeground: usesContrastingForeground
            )
            let selected = ChartValueLabelLayoutPolicy.metrics(
                isSelected: true,
                usesContrastingForeground: usesContrastingForeground
            )

            XCTAssertGreaterThan(selected.horizontalPadding, idle.horizontalPadding)
            XCTAssertGreaterThan(selected.verticalPadding, idle.verticalPadding)
            XCTAssertLessThan(selected.maximumTextWidth, idle.maximumTextWidth)
            XCTAssertLessThanOrEqual(selected.maximumTextWidth, 96)
        }
    }

    func testOneValueAnimationMatchesCatalogTimingAndNumberPrecision() throws {
        XCTAssertEqual(OneValueAnimationPolicy.initialDelay, .milliseconds(80))
        XCTAssertEqual(OneValueAnimationPolicy.duration, 0.85, accuracy: 0.000_001)

        XCTAssertEqual(OneValueAnimationPolicy.fractionDigits(for: 247), 0)
        XCTAssertEqual(
            OneValueAnimationPolicy.fractionDigits(
                for: try XCTUnwrap(Decimal(string: "24.7"))
            ),
            1
        )
        XCTAssertEqual(
            OneValueAnimationPolicy.fractionDigits(
                for: try XCTUnwrap(Decimal(string: "24.75"))
            ),
            2
        )

        XCTAssertEqual(
            NSDecimalNumber(
                decimal: OneValueAnimationPolicy.roundedValue(123.7, fractionDigits: 0)
            ).doubleValue,
            124
        )
        XCTAssertEqual(
            NSDecimalNumber(
                decimal: OneValueAnimationPolicy.roundedValue(12.34, fractionDigits: 1)
            ).doubleValue,
            12.3,
            accuracy: 0.000_001
        )
    }

    func testSelectedTrendLabelStaysInsideChartAndRespectsPlacement() {
        let containerSize = CGSize(width: 320, height: 180)

        let topLeading = SelectedTrendLabelPositionPolicy.center(
            for: CGPoint(x: 0, y: 0),
            placement: .above,
            in: containerSize,
            contentScale: 1
        )
        XCTAssertEqual(topLeading, CGPoint(x: 64, y: 20))

        let bottomTrailing = SelectedTrendLabelPositionPolicy.center(
            for: CGPoint(x: 320, y: 180),
            placement: .below,
            in: containerSize,
            contentScale: 1
        )
        XCTAssertEqual(bottomTrailing, CGPoint(x: 256, y: 160))

        let centeredAbove = SelectedTrendLabelPositionPolicy.center(
            for: CGPoint(x: 160, y: 90),
            placement: .above,
            in: containerSize,
            contentScale: 1
        )
        XCTAssertEqual(centeredAbove, CGPoint(x: 160, y: 66))
    }

    func testSynchronizationTimestampHasStableCompactFormat() throws {
        let date = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-10T08:13:00Z")
        )

        XCTAssertEqual(
            DashboardSynchronizationTextPolicy.timestamp(
                for: date,
                timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0))
            ),
            "10.08.26, 08:13"
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

    func testSelectedDonutLabelDoesNotShrinkPlotArea() {
        let availableSize = CGSize(width: 148, height: 260)

        XCTAssertEqual(
            DonutPlotLayoutPolicy.plotSize(in: availableSize),
            availableSize
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

    func testChartsAlwaysFitAvailableWidth() {
        let compactWidth = ChartPresentationPolicy.contentWidth(
            availableWidth: 320
        )
        let denseWidth = ChartPresentationPolicy.contentWidth(
            availableWidth: 320
        )

        XCTAssertEqual(compactWidth, 320)
        XCTAssertEqual(denseWidth, 320)
        XCTAssertEqual(ChartPresentationPolicy.contentWidth(availableWidth: -20), 0)
    }

    func testChartsRenderOnlyWithFiniteNonZeroGeometry() {
        XCTAssertTrue(
            ChartRenderGeometryPolicy.canRender(in: CGSize(width: 320, height: 240))
        )
        XCTAssertFalse(
            ChartRenderGeometryPolicy.canRender(in: CGSize(width: 320, height: 0))
        )
        XCTAssertFalse(
            ChartRenderGeometryPolicy.canRender(in: CGSize(width: 0, height: 240))
        )
        XCTAssertFalse(
            ChartRenderGeometryPolicy.canRender(in: CGSize(width: CGFloat.infinity, height: 240))
        )
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
        XCTAssertEqual(threeSeriesHeight, 672)
    }

    func testHorizontalBarLabelFlagsStayIndependentWithoutDuplicatingValues() {
        XCTAssertTrue(
            HorizontalBarLabelPolicy.showsRowValue(
                showRowValues: true,
                showValueLabels: false
            )
        )
        XCTAssertTrue(
            HorizontalBarLabelPolicy.showsRowValue(
                showRowValues: false,
                showValueLabels: true
            )
        )
        XCTAssertFalse(
            HorizontalBarLabelPolicy.showsRowValue(
                showRowValues: false,
                showValueLabels: false
            )
        )
        XCTAssertTrue(
            HorizontalBarLabelPolicy.showsGroupTotal(
                rowCount: 2,
                showsAggregateValue: true
            )
        )
        XCTAssertFalse(
            HorizontalBarLabelPolicy.showsGroupTotal(
                rowCount: 2,
                showsAggregateValue: false
            )
        )
    }

    func testHorizontalBarTrackScaleSupportsPositiveNegativeAndMixedValues() {
        let positiveDomain = HorizontalBarTrackScale.domain(for: [40, 100])
        XCTAssertEqual(positiveDomain, 0...100)
        XCTAssertEqual(
            HorizontalBarTrackScale.segment(for: 40, in: positiveDomain),
            HorizontalBarTrackSegment(startFraction: 0, lengthFraction: 0.4)
        )

        let negativeDomain = HorizontalBarTrackScale.domain(for: [-100, -40])
        XCTAssertEqual(negativeDomain, -100...0)
        XCTAssertEqual(
            HorizontalBarTrackScale.segment(for: -40, in: negativeDomain),
            HorizontalBarTrackSegment(startFraction: 0.6, lengthFraction: 0.4)
        )

        let mixedDomain = HorizontalBarTrackScale.domain(for: [-25, 75])
        XCTAssertEqual(mixedDomain, -25...75)
        XCTAssertEqual(
            HorizontalBarTrackScale.segment(for: -25, in: mixedDomain),
            HorizontalBarTrackSegment(startFraction: 0, lengthFraction: 0.25)
        )
        XCTAssertEqual(
            HorizontalBarTrackScale.segment(for: 75, in: mixedDomain),
            HorizontalBarTrackSegment(startFraction: 0.25, lengthFraction: 0.75)
        )
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
        store.setWidth(.half, for: section.indicators[0])

        let restoredStore = DashboardLayoutStore(defaults: defaults, storageKey: storageKey)
        XCTAssertEqual(restoredStore.orderedIndicators(in: section).map(\.id), ["b", "a", "c"])
        XCTAssertEqual(restoredStore.width(for: section.indicators[0]), .half)

        restoredStore.reset()

        let resetStore = DashboardLayoutStore(defaults: defaults, storageKey: storageKey)
        XCTAssertFalse(resetStore.hasCustomLayout)
        XCTAssertEqual(resetStore.orderedIndicators(in: section).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(resetStore.width(for: section.indicators[0]), .full)
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

    func testFalseBackendResultRequiresAuthenticationDespiteSuccessfulHTTPStatus() {
        let data = Data(#"{"result":false}"#.utf8)

        XCTAssertThrowsError(try APIAnalyticsProvider.validatePayloadAuthentication(data)) { error in
            guard case AnalyticsError.authenticationRequired = error else {
                return XCTFail("Expected authenticationRequired, got \(error)")
            }
        }
    }

    func testAnalyticsPayloadIsNotRejectedAsAuthenticationResponse() {
        let data = Data(
            #"{"sections":[{"name":"Образование","values":[]}]}"#.utf8
        )

        XCTAssertNoThrow(try APIAnalyticsProvider.validatePayloadAuthentication(data))
    }

    func testAnalyticsRequestUsesOnlySectionAndSixtySecondTimeout() throws {
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

        XCTAssertNil(queryItems.first { $0.name == "id" })
        XCTAssertEqual(queryItems.first { $0.name == "section" }?.value, "Приемная_кампания")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.timeoutInterval, 60)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test-Authorization"), "attached")

        let extendedRequest = try provider.makeRequest(
            for: AnalyticsAPIContract.sections[3],
            isExtended: true
        )
        let extendedItems = try XCTUnwrap(
            URLComponents(url: extendedRequest.url!, resolvingAgainstBaseURL: false)?.queryItems
        )
        XCTAssertEqual(
            extendedItems.first { $0.name == "section" }?.value,
            "Приемная_кампания_Расширенный"
        )
        XCTAssertEqual(extendedRequest.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(extendedRequest.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
    }

    func testExtendedContractAndPlanFactProgressUseContractDefaults() throws {
        let data = Data(
            #"{"sections":[{"name":"Финансы","hasExtended":true,"values":[{"name":"План-Факт (контракт), тыс. руб","type":"PlanFactProgress","values":[{"group":"БАК","subgroup":[{"group":"Текущий год","subgroup":[{"name":"План","value":100},{"name":"Опл.","value":80}]}]}]}]}]}"#.utf8
        )

        let section = try XCTUnwrap(
            JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
                .toDashboard()
                .sections
                .first
        )
        let indicator = try XCTUnwrap(section.indicators.first)

        XCTAssertTrue(section.hasExtended)
        XCTAssertEqual(indicator.chartType, .horizontalBar)
        XCTAssertTrue(indicator.usesContractPlanFactPresentation)
        XCTAssertEqual(indicator.isExplicitPlanFactProgress, true)
        XCTAssertFalse(indicator.showsAggregateValue)
        XCTAssertFalse(indicator.showsLegend)
        XCTAssertFalse(indicator.showsAggregateValueInHeader)
        XCTAssertFalse(indicator.showsPlanFactPresentationLegend)
    }

    func testExplicitPlanFactProgressCanEnableTotalAndLegend() throws {
        let data = Data(
            #"{"sections":[{"name":"Финансы","values":[{"name":"Исполнение","type":"PlanFactProgress","showTotal":true,"showLegend":true,"values":[{"group":"БАК","subgroup":[{"group":"Текущий год","subgroup":[{"name":"План","value":100},{"name":"Опл.","value":80}]}]}]}]}]}"#.utf8
        )

        let indicator = try XCTUnwrap(
            JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
                .toDashboard()
                .indicators
                .first
        )

        XCTAssertTrue(indicator.usesContractPlanFactPresentation)
        XCTAssertTrue(indicator.showsAggregateValue)
        XCTAssertTrue(indicator.showsLegend)
        XCTAssertTrue(indicator.showsAggregateValueInHeader)
        XCTAssertTrue(indicator.showsPlanFactPresentationLegend)
    }

    func testTrendPointValueAliasesDecodeWithCanonicalPriority() throws {
        let data = Data(
            #"{"sections":[{"name":"Тренды","values":[{"name":"Канонический","type":"LineMark","alwaysShowPointValues":false,"showPointValues":true,"values":[{"group":"2025","value":1}]},{"name":"Первый алиас","type":"LineMark","showPointValues":false,"values":[{"group":"2025","value":1}]},{"name":"Второй алиас","type":"LineMark","displayPointValues":true,"values":[{"group":"2025","value":1}]},{"name":"По умолчанию","type":"LineMark","values":[{"group":"2025","value":1}]}]}]}"#.utf8
        )

        let indicators = try JSONDecoder()
            .decode(AnalyticsAPIResponse.self, from: data)
            .toDashboard()
            .indicators

        XCTAssertEqual(indicators.map(\.alwaysShowPointValues), [false, false, true, nil])
    }

    func testRadarContractDecodesAliasesSeriesAndDefaults() throws {
        let aliases = ["RadarMark", "RadarChart", "SpiderMark", "SpiderChart", "Spider", "WebChart"]

        for alias in aliases {
            let data = Data(
                """
                {
                  "sections": [{
                    "name": "Стратегия",
                    "values": [{
                      "name": "Профиль направлений",
                      "type": "\(alias)",
                      "values": [
                        {"group":"Продажи","subgroup":[{"name":"План","value":80},{"name":"Факт","value":72,"lineStyle":"dashed"}]},
                        {"group":"Маржа","subgroup":[{"name":"План","value":65},{"name":"Факт","value":58}]},
                        {"group":"Качество","subgroup":[{"name":"План","value":90},{"name":"Факт","value":84}]}
                      ]
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

            XCTAssertEqual(indicator.chartType, .radar)
            XCTAssertFalse(indicator.showsAggregateValue)
            XCTAssertTrue(indicator.showsLegend)
            XCTAssertEqual(indicator.rowGroups.map(\.label), ["Продажи", "Маржа", "Качество"])
            XCTAssertEqual(indicator.barDataShape.series, ["План", "Факт"])
            XCTAssertEqual(
                indicator.rows.first { $0.series == "Факт" }?.lineStyle,
                .dashed
            )
        }
    }

    func testDenseRadarMovesSmallValueLabelsAwayFromCenter() {
        XCTAssertEqual(
            RadarPresentationPolicy.labelRadiusFraction(valueFraction: 0.001, axisCount: 9),
            0.62,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            RadarPresentationPolicy.labelRadiusFraction(valueFraction: 0.72, axisCount: 9),
            0.72,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            RadarPresentationPolicy.labelRadiusFraction(valueFraction: 0.10, axisCount: 5),
            0.34,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            RadarPresentationPolicy.labelRadiusFraction(valueFraction: 1, axisCount: 5),
            0.84,
            accuracy: 0.000_001
        )
    }

    func testExpandableHierarchyDecodesRecursiveNodesAndTotalSeries() throws {
        let data = Data(
            #"""
            {
              "sections": [{
                "name": "Образование",
                "values": [{
                  "name": "Всего обучающихся РФ и ИГ",
                  "type": "ExpandableTableMark",
                  "barMode": "stacked",
                  "totalSeries": "total",
                  "series": [
                    {"key":"total","name":"Всего"},
                    {"key":"rf","name":"РФ","unit":"чел."},
                    {"key":"foreign","name":"ИГ"}
                  ],
                  "nodes": [{
                    "id":"bachelor",
                    "label":"Бакалавриат",
                    "values": {
                      "total":19368,
                      "rf":{"value":16155,"valueLabel":"16 155 чел."},
                      "foreign":3213
                    },
                    "children":[
                      {"label":"Профиль 1","values":{"total":1200,"rf":1110,"foreign":90}},
                      {"label":"Профиль 2","values":{"total":900,"rf":850,"foreign":50}}
                    ]
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
        let hierarchy = try XCTUnwrap(indicator.hierarchy)
        let root = try XCTUnwrap(hierarchy.nodes.first)

        XCTAssertEqual(indicator.chartType, .expandableHierarchy)
        XCTAssertTrue(indicator.rows.isEmpty)
        XCTAssertFalse(indicator.showsAggregateValueInHeader)
        XCTAssertEqual(hierarchy.barMode, .stacked)
        XCTAssertEqual(hierarchy.displayedSeries.map(\.key), ["rf", "foreign"])
        XCTAssertEqual(hierarchy.displayedTotal(for: root), 19_368)
        XCTAssertEqual(root.values["rf"]?.valueLabel, "16 155 чел.")
        XCTAssertEqual(root.children.count, 2)
        XCTAssertNotEqual(root.children[0].id, root.children[1].id)
        XCTAssertTrue(root.children.allSatisfy { $0.id.hasPrefix(root.id) })

        let roundTrip = try JSONDecoder().decode(
            Indicator.self,
            from: JSONEncoder().encode(indicator)
        )
        XCTAssertEqual(roundTrip, indicator)
    }

    func testExpandableHierarchyTotalModesAndSingleSeries() {
        let first = ExpandableHierarchySeries(
            key: "first",
            name: "Первый",
            colorGraph: nil,
            colorValue: nil,
            unit: nil
        )
        let second = ExpandableHierarchySeries(
            key: "second",
            name: "Второй",
            colorGraph: nil,
            colorValue: nil,
            unit: nil
        )
        let node = ExpandableHierarchyNode(
            id: "node",
            label: "Узел",
            values: [
                "first": ExpandableHierarchyValue(value: 10, valueLabel: nil),
                "second": ExpandableHierarchyValue(value: 4, valueLabel: nil)
            ],
            children: []
        )

        let automatic = ExpandableHierarchy(
            barMode: .stacked,
            series: [first, second],
            nodes: [node],
            totalSeries: nil
        )
        XCTAssertEqual(automatic.displayedTotal(for: node), 14)

        let hidden = ExpandableHierarchy(
            barMode: .grouped,
            series: [first, second],
            nodes: [node],
            totalSeries: ""
        )
        XCTAssertNil(hidden.displayedTotal(for: node))

        let single = ExpandableHierarchy(
            barMode: .single,
            series: [first, second],
            nodes: [node],
            totalSeries: nil
        )
        XCTAssertEqual(single.displayedSeries.map(\.key), ["first"])
        XCTAssertEqual(single.displayedTotal(for: node), 10)
    }

    func testExpandableHierarchyWithoutBarModeUsesSafeStackedFallback() throws {
        let data = Data(
            #"{"sections":[{"name":"Test","values":[{"name":"Broken","type":"ExpandableTableMark","series":[],"nodes":[]}]}]}"#.utf8
        )

        let section = try XCTUnwrap(
            JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
                .toDashboard()
                .sections
                .first
        )
        XCTAssertEqual(section.indicators.first?.chartType, .expandableHierarchy)
        XCTAssertEqual(section.indicators.first?.hierarchy?.barMode, .stacked)
        XCTAssertNil(section.indicatorDecodeFailureCount)
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

    func testExplicitContractPlanFactBuildsCurrentThenPreviousYearPresentation() throws {
        let data = Data(
            #"{"sections":[{"name":"Финансы","values":[{"name":"План-Факт (контракт), тыс. руб","values":[{"group":"БАК","subgroup":[{"name":"Прошлый год","values":[{"name":"План","value":412755},{"name":"Опл.","value":893538}]},{"name":"Текущий год","subgroup":[{"name":"Опл.","value":400192},{"name":"План","value":483360}]}]}],"type":"PlanFactProgress"}]}]}"#.utf8
        )

        let indicator = try XCTUnwrap(
            JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
                .toDashboard()
                .indicators
                .first
        )

        XCTAssertTrue(indicator.usesContractPlanFactPresentation)
        XCTAssertEqual(indicator.isExplicitPlanFactProgress, true)
        XCTAssertFalse(indicator.showsAggregateValueInHeader)
        XCTAssertFalse(indicator.showsPlanFactPresentationLegend)
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

    func testEnrollmentByCitizenshipKeepsServerStackingType() throws {
        let data = Data(
            #"{"sections":[{"name":"Образование","values":[{"name":"Всего обучающихся РФ и ИГ","values":[{"group":"БАК","subgroup":[{"name":"РФ","value":18347},{"name":"ИГ","value":3604}]},{"group":"СПЕЦ","subgroup":[{"name":"РФ","value":5120},{"name":"ИГ","value":920}]},{"group":"МАГ","subgroup":[{"name":"РФ","value":3480},{"name":"ИГ","value":740}]},{"group":"АСП","subgroup":[{"name":"РФ","value":995},{"name":"ИГ","value":115}]}],"type":"BarMarkStacking"}]}]}"#.utf8
        )

        let indicator = try XCTUnwrap(
            JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
                .toDashboard()
                .indicators
                .first
        )

        XCTAssertEqual(indicator.chartType, .stackedBar)
        XCTAssertNil(indicator.unit)
        XCTAssertTrue(indicator.usesStackedCompositionPresentation)
        XCTAssertFalse(indicator.usesCitizenshipCompositionPresentation)
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

    func testStackedPlanFactKeepsTotalAndValueLabelFlagsIndependent() throws {
        let data = Data(
            #"{"sections":[{"name":"Финансы","values":[{"name":"Структура доходов (План/Факт)","type":"BarMarkStacking","showTotal":false,"values":[{"group":"2026","subgroup":[{"name":"План","value":70},{"name":"Факт","value":30}]}]}]}]}"#.utf8
        )

        let indicator = try XCTUnwrap(
            JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
                .toDashboard()
                .indicators
                .first
        )

        XCTAssertFalse(indicator.showsAggregateValue)
        XCTAssertFalse(indicator.showsHorizontalCategoryTotals)
        XCTAssertNil(indicator.showValueLabels)
        XCTAssertTrue(indicator.showsValueLabels)
        XCTAssertTrue(
            ChartValueLabelPolicy.isVisible(
                rowMatchesSelection: false,
                hasSelection: false,
                contractPreference: indicator.showValueLabels,
                defaultLabelsEnabled: indicator.showsValueLabels
            )
        )
    }

    func testDonutKeepsTotalAndSectorValueLabelFlagsIndependent() throws {
        let data = Data(
            #"{"sections":[{"name":"Наука","values":[{"name":"Финансирование","type":"SectorMarkInnerRadius","showTotal":false,"values":[{"group":"2024","value":4000},{"group":"2025","value":6600},{"group":"2026","value":3714}]}]}]}"#.utf8
        )

        let indicator = try XCTUnwrap(
            JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
                .toDashboard()
                .indicators
                .first
        )

        XCTAssertEqual(indicator.chartType, .donut)
        XCTAssertFalse(indicator.showsAggregateValue)
        XCTAssertNil(indicator.showValueLabels)
        XCTAssertTrue(indicator.showsValueLabels)
    }

    func testSingleLegendItemIsHiddenUnlessContractExplicitlyEnablesIt() {
        func indicator(showLegend: Bool?, series: [String]) -> Indicator {
            Indicator(
                id: "single-legend",
                title: "Доходы",
                value: nil,
                unit: nil,
                chartType: .bar,
                source: nil,
                showLegend: showLegend,
                rows: series.enumerated().map { index, name in
                    IndicatorRow(
                        id: "row-\(index)",
                        label: "202\(index + 5)",
                        value: Double(index + 1),
                        series: name,
                        sortOrder: index
                    )
                }
            )
        }

        let implicitSingle = AnalyticsChart(
            indicator: indicator(showLegend: nil, series: ["Факт", "Факт"])
        )
        XCTAssertFalse(implicitSingle.displaysLegend)

        let explicitSingle = AnalyticsChart(
            indicator: indicator(showLegend: true, series: ["Факт", "Факт"])
        )
        XCTAssertTrue(explicitSingle.displaysLegend)

        let explicitHidden = AnalyticsChart(
            indicator: indicator(showLegend: false, series: ["План", "Факт"])
        )
        XCTAssertFalse(explicitHidden.displaysLegend)

        let implicitMultiple = AnalyticsChart(
            indicator: indicator(showLegend: nil, series: ["План", "Факт"])
        )
        XCTAssertTrue(implicitMultiple.displaysLegend)
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

            XCTAssertEqual(indicator.chartType.barOrientation, .vertical, chartType.rawValue)
        }
    }

    func testBarContractTypeAloneDeterminesOrientation() throws {
        let data = Data(
            #"{"sections":[{"name":"Test","values":[{"name":"Всего обучающихся РФ и ИГ","type":"BarMark","values":[{"group":"2024","value":1000000},{"group":"2025","value":900000}]},{"name":"Всего обучающихся РФ и ИГ","type":"BarMarkHorizon","values":[{"group":"2024","value":1000000},{"group":"2025","value":900000}]},{"name":"Всего обучающихся РФ и ИГ","type":"BarMarkStacking","values":[{"group":"2024","subgroup":[{"name":"РФ","value":800000},{"name":"ИГ","value":200000}]}]}]}]}"#.utf8
        )

        let indicators = try JSONDecoder()
            .decode(AnalyticsAPIResponse.self, from: data)
            .toDashboard()
            .indicators

        XCTAssertEqual(indicators.map(\.chartType), [.bar, .horizontalBar, .stackedBar])
        XCTAssertEqual(
            indicators.map { $0.chartType.barOrientation },
            [.vertical, .horizontal, .horizontal]
        )
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
        XCTAssertEqual(temporalIndicator.chartType, .bar)
        XCTAssertEqual(temporalIndicator.chartType.barOrientation, .vertical)
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
        let chartTypes: [(backend: String, expected: ChartType)] = [
            ("BarMark", .bar),
            ("BarMarkHorizon", .horizontalBar),
            ("OneValue", .oneValue)
        ]
        for contract in chartTypes {
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
                      "type": "\(contract.backend)"
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
            XCTAssertEqual(indicator.chartType, contract.expected)
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
                    "type": "BarMark",
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

    func testUnknownChartTypeUsesSafePresentationAndReplacesCachedShape() throws {
        let data = Data(
            #"{"sections":[{"name":"Test","values":[{"name":"Valid","type":"OneValue","value":7},{"name":"Broken","type":"UnknownChart","values":[]}]}]}"#.utf8
        )

        let section = try XCTUnwrap(
            JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
                .toDashboard()
                .sections
                .first
        )

        XCTAssertEqual(section.indicators.map(\.title), ["Valid", "Broken"])
        XCTAssertEqual(section.indicators.map(\.chartType), [.oneValue, .bar])
        XCTAssertNil(section.indicatorDecodeFailureCount)
    }

    func testMalformedOptionalNumericValueDoesNotRejectItsChart() throws {
        let data = Data(
            #"{"sections":[{"name":"Test","values":[{"name":"Valid","type":"OneValue","value":7},{"name":"Broken","type":"BarMark","values":[{"group":"A","value":"not-a-number"}]}]}]}"#.utf8
        )

        let section = try XCTUnwrap(
            JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
                .toDashboard()
                .sections
                .first
        )

        XCTAssertEqual(section.indicators.map(\.title), ["Valid", "Broken"])
        XCTAssertNil(section.indicatorDecodeFailureCount)
    }

    func testMalformedFlexibleArrayIsRejectedInsteadOfBecomingEmpty() {
        let data = Data(#"{"sections":{"name":"Test","values":"broken"}}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(AnalyticsAPIResponse.self, from: data))
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

    func testDashboardSectionDecodesOldPayloadWithoutExtendedGroup() throws {
        let data = Data(
            #"{"id":"cached","title":"Cached","fetchedAt":null,"sections":[{"id":"science","title":"Наука","indicators":[],"fetchedAt":null,"hasExtended":true}]}"#.utf8
        )

        let dashboard = try JSONDecoder().decode(Dashboard.self, from: data)

        XCTAssertNil(dashboard.sections.first?.extended)
    }

    func testDashboardRoundTripPreservesExtendedGroupSeparately() throws {
        let child = DashboardExtendedSection(
            id: "extended:science",
            title: "Наука · 2 уровень",
            indicators: [],
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        let dashboard = Dashboard(
            id: "cached",
            title: "Cached",
            fetchedAt: nil,
            sections: [
                DashboardSection(
                    id: "science", title: "Наука", indicators: [],
                    hasExtended: true, extended: child
                )
            ]
        )

        let decoded = try JSONDecoder().decode(Dashboard.self, from: JSONEncoder().encode(dashboard))

        XCTAssertEqual(decoded.sections.first?.extended, child)
    }

    func testCrossingAndHorizontalRowValueFieldsDecode() throws {
        let data = Data(
            #"{"sections":[{"name":"Наука","values":[{"name":"Динамика","type":"LineMark","showRowValues":false,"highlightCrossing":true,"highlightSeriesIndex":0,"referenceSeriesIndex":1,"values":[{"group":"2025","subgroup":[{"name":"Факт","value":5},{"name":"Норма","value":8}]}]}]}]}"#.utf8
        )

        let indicator = try XCTUnwrap(JSONDecoder().decode(AnalyticsAPIResponse.self, from: data).toDashboard().indicators.first)

        XCTAssertEqual(indicator.showRowValues, false)
        XCTAssertEqual(indicator.highlightCrossing, true)
        XCTAssertEqual(indicator.highlightSeriesIndex, 0)
        XCTAssertEqual(indicator.referenceSeriesIndex, 1)
    }

    func testCrossingHighlightUsesDisplayedCurveAndIgnoresIncompleteConfiguration() {
        let rows = [
            IndicatorRow(id: "fact-0", label: "2024", value: 8, series: "Факт", sortOrder: 0),
            IndicatorRow(id: "norm-0", label: "2024", value: 4, series: "Норма", sortOrder: 0),
            IndicatorRow(id: "fact-1", label: "2025", value: 2, series: "Факт", sortOrder: 1),
            IndicatorRow(id: "norm-1", label: "2025", value: 4, series: "Норма", sortOrder: 1),
            IndicatorRow(id: "fact-2", label: "2026", value: 8, series: "Факт", sortOrder: 2),
            IndicatorRow(id: "norm-2", label: "2026", value: 4, series: "Норма", sortOrder: 2)
        ]
        let configured = Indicator(
            id: "trend",
            title: "Динамика",
            value: nil,
            unit: nil,
            chartType: .line,
            source: nil,
            highlightCrossing: true,
            highlightSeriesIndex: 0,
            referenceSeriesIndex: 1,
            rows: rows
        )
        let chart = AnalyticsChart(indicator: configured)

        XCTAssertEqual(chart.crossingIntersectionPoints(smooth: true).count, 2)
        XCTAssertTrue(chart.isCrossingHighlighted(rows[2]))
        XCTAssertFalse(chart.isCrossingHighlighted(rows[3]))

        let incomplete = Indicator(
            id: "incomplete",
            title: "Динамика",
            value: nil,
            unit: nil,
            chartType: .line,
            source: nil,
            highlightCrossing: true,
            highlightSeriesIndex: 0,
            rows: rows
        )
        XCTAssertTrue(AnalyticsChart(indicator: incomplete).crossingHighlightSegments(smooth: false).isEmpty)
    }

    func testCrossingHighlightKeepsLargeSeriesRenderMarkCountBounded() {
        let rows = (0..<400).flatMap { index in
            [
                IndicatorRow(
                    id: "fact-\(index)",
                    label: String(index),
                    value: index.isMultiple(of: 2) ? 2 : 8,
                    series: "Факт",
                    sortOrder: index
                ),
                IndicatorRow(
                    id: "norm-\(index)",
                    label: String(index),
                    value: 5,
                    series: "Норма",
                    sortOrder: index
                )
            ]
        }
        let indicator = Indicator(
            id: "large-trend",
            title: "Большая динамика",
            value: nil,
            unit: nil,
            chartType: .splineLine,
            source: nil,
            highlightCrossing: true,
            highlightSeriesIndex: 0,
            referenceSeriesIndex: 1,
            rows: rows
        )
        let chart = AnalyticsChart(indicator: indicator)
        let pointCount = chart.crossingHighlightSegments(smooth: true)
            .reduce(0) { $0 + $1.points.count }

        XCTAssertLessThanOrEqual(pointCount, 1_600)
        XCTAssertEqual(chart.crossingConfiguration?.highlightedRowIDs.count, 200)
    }

    func testDashboardSectionSystemSymbolsExist() {
        let titles = AnalyticsAPIContract.sections.map(\.displayName)

        for title in titles {
            let symbol = DashboardSectionVisualStyle.style(for: title).symbol
            XCTAssertNotNil(UIImage(systemName: symbol), "Missing SF Symbol: \(symbol)")
        }
    }

    func testInvalidRadarStaysRadarAndDuplicateHierarchyIDsAreMadeUnique() throws {
        let radar = Data(
            #"{"sections":[{"name":"Наука","values":[{"name":"Radar","type":"RadarMark","values":[{"group":"A","value":1},{"group":"B","value":-1}]}]}]}"#.utf8
        )
        let radarSection = try XCTUnwrap(
            JSONDecoder().decode(AnalyticsAPIResponse.self, from: radar)
                .toDashboard()
                .sections
                .first
        )
        XCTAssertEqual(radarSection.indicators.first?.chartType, .radar)
        XCTAssertNil(radarSection.indicatorDecodeFailureCount)

        let hierarchy = Data(
            #"{"sections":[{"name":"Наука","values":[{"name":"Tree","type":"ExpandableTableMark","barMode":"single","series":[{"key":"value","name":"Значение"}],"nodes":[{"id":"same","label":"A","values":{"value":1}},{"id":"same","label":"B","values":{"value":2}}]}]}]}"#.utf8
        )
        let hierarchySection = try XCTUnwrap(
            JSONDecoder().decode(AnalyticsAPIResponse.self, from: hierarchy)
                .toDashboard()
                .sections
                .first
        )
        let tree = try XCTUnwrap(hierarchySection.indicators.first)
        XCTAssertEqual(tree.chartType, .expandableHierarchy)
        XCTAssertEqual(tree.hierarchy?.nodes.map(\.id), ["node/same", "node/same#2"])
        XCTAssertNil(hierarchySection.indicatorDecodeFailureCount)
    }

    func testExpandableHierarchyRecoversMissingLabelsValuesAndNullMetrics() throws {
        let data = Data(
            #"{"sections":[{"name":"Test","values":[{"name":"Tree","type":"ExpandableTableMark","series":[{"key":"value","name":"Значение"}],"nodes":[{"id":"first","values":{"value":null}},{"children":[]}]}]}]}"#.utf8
        )

        let section = try XCTUnwrap(
            JSONDecoder().decode(AnalyticsAPIResponse.self, from: data)
                .toDashboard()
                .sections
                .first
        )
        let indicator = try XCTUnwrap(section.indicators.first)

        XCTAssertNil(section.indicatorDecodeFailureCount)
        XCTAssertEqual(indicator.hierarchy?.barMode, .stacked)
        XCTAssertEqual(indicator.hierarchy?.nodes.map(\.label), ["first", "Узел"])
        XCTAssertEqual(indicator.hierarchy?.nodes.first?.values["value"]?.value, 0)
        XCTAssertEqual(indicator.hierarchy?.nodes.last?.values, [:])
    }

    func testUpdatedChartContractAliasesAndOptionsDecode() throws {
        let data = Data(
            #"{"sections":[{"name":"Контракт","values":[{"name":"Плитка","type":"Treemap","show_percentages_in_details":false,"max_groups":7,"maxTiles":3,"tileLayout":"grid","colorGraph":"0x123456","values":[{"group":"A","value":10}]},{"name":"План-факт","type":"PlanFactByPeriod","useOverviewStyle":true,"showGrid":false,"overviewTitle":"Исполнение","overviewSubtitle":"За период","values":[{"group":"БАК","subgroup":[{"group":"Текущий год","subgroup":[{"name":"План","value":100},{"name":"Факт","value":75}]}]}]},{"name":"Иерархия","type":"ExpandableTableMark","barMode":"single","overviewType":"tile","maxItems":4,"series":[{"key":"value","name":"Значение"}],"nodes":[{"label":"Без явного id","values":{"value":5}}]}]}]}"#.utf8
        )

        let indicators = try JSONDecoder()
            .decode(AnalyticsAPIResponse.self, from: data)
            .toDashboard()
            .indicators

        XCTAssertEqual(indicators.count, 3)
        XCTAssertEqual(indicators[0].chartType, .tile)
        XCTAssertFalse(indicators[0].showsPercentagesInDetails)
        XCTAssertEqual(indicators[0].maxGroups, 7)
        XCTAssertEqual(indicators[0].resolvedMaximumTiles, 3)
        XCTAssertEqual(indicators[0].resolvedTileLayout, .grid)
        XCTAssertFalse(indicators[0].showsLegend)
        XCTAssertEqual(indicators[0].colorGraph, "0x123456")

        XCTAssertEqual(indicators[1].chartType, .horizontalBar)
        XCTAssertTrue(indicators[1].usesContractPlanFactPresentation)
        XCTAssertEqual(indicators[1].useOverviewStyle, true)
        XCTAssertEqual(indicators[1].showGrid, false)
        XCTAssertEqual(indicators[1].overviewTitle, "Исполнение")
        XCTAssertEqual(indicators[1].overviewSubtitle, "За период")

        XCTAssertEqual(indicators[2].chartType, .expandableHierarchy)
        XCTAssertEqual(indicators[2].resolvedExpandableOverviewType, .tile)
        XCTAssertEqual(indicators[2].maxGroups, 4)
        XCTAssertEqual(indicators[2].hierarchy?.nodes.first?.label, "Без явного id")
        XCTAssertFalse(indicators[2].showsLegend)
    }

    func testCardGroupLimitAggregatesRemainderAndTilePercentagesSumExactly() {
        let indicator = Indicator(
            id: "limited",
            title: "Ограничение",
            value: nil,
            unit: nil,
            chartType: .bar,
            source: nil,
            useCompactNumbers: true,
            maxGroups: 2,
            rows: [
                IndicatorRow(id: "a", label: "A", value: 10, series: nil, sortOrder: 0),
                IndicatorRow(id: "b", label: "B", value: 20, series: nil, sortOrder: 1),
                IndicatorRow(id: "c", label: "C", value: 30, series: nil, sortOrder: 2),
                IndicatorRow(id: "d", label: "D", value: 40, series: nil, sortOrder: 3)
            ]
        )

        let card = indicator.cardPresentationIndicator
        XCTAssertEqual(card.rowGroups.map(\.label), ["A", "B", "Прочие"])
        XCTAssertEqual(card.rowGroups.last?.rows.first?.value, 70)
        XCTAssertEqual(indicator.formattedNumber(1_000.0), "1K")

        let percentages = TilePercentagePolicy.percentages(for: [1, 1, 1])
        XCTAssertEqual(percentages.reduce(0, +), 1, accuracy: 0.000_001)
        XCTAssertEqual(percentages, [0.334, 0.333, 0.333])
    }

    func testTileLimitIncludesRemainderAndKeepsOriginalCategories() {
        let indicator = Indicator(
            id: "tile-limit",
            title: "Плитка",
            value: nil,
            unit: nil,
            chartType: .tile,
            source: nil,
            maxTiles: 3,
            rows: [
                IndicatorRow(id: "a", label: "A", value: 100, series: nil, sortOrder: 0),
                IndicatorRow(id: "b", label: "B", value: 80, series: nil, sortOrder: 1),
                IndicatorRow(id: "c", label: "C", value: 60, series: nil, sortOrder: 2),
                IndicatorRow(id: "d", label: "D", value: 40, series: nil, sortOrder: 3),
                IndicatorRow(id: "e", label: "E", value: 20, series: nil, sortOrder: 4),
                IndicatorRow(id: "zero", label: "Zero", value: 0, series: nil, sortOrder: 5),
                IndicatorRow(id: "negative", label: "Negative", value: -10, series: nil, sortOrder: 6)
            ]
        )

        let cardItems = TilePresentationPolicy.items(for: indicator, appliesLimit: true)
        XCTAssertEqual(cardItems.map(\.title), ["A", "B", "Прочее"])
        XCTAssertEqual(cardItems.count, 3)
        XCTAssertEqual(cardItems.last?.value, 120)
        XCTAssertEqual(cardItems.last?.sourceRowIDs, Set(["c", "d", "e"]))
        XCTAssertTrue(cardItems.last?.isRemainder == true)

        let fullItems = TilePresentationPolicy.items(for: indicator, appliesLimit: false)
        XCTAssertEqual(fullItems.map(\.title), ["A", "B", "C", "D", "E"])
        XCTAssertEqual(indicator.rowGroups.count, 7)
    }

    func testTileDefaultsAndLimitRangeDecode() throws {
        let data = Data(
            #"{"sections":[{"name":"Tiles","values":[{"name":"Default","type":"TileMark","values":[{"group":"A","value":1}]},{"name":"Too small","type":"TileMark","maxTiles":1,"values":[{"group":"A","value":1}]},{"name":"Minimum","type":"TileMark","maxTiles":2,"values":[{"group":"A","value":1}]},{"name":"Maximum","type":"TileMark","maxTiles":20,"values":[{"group":"A","value":1}]},{"name":"Too large","type":"TileMark","maxTiles":21,"values":[{"group":"A","value":1}]}]}]}"#.utf8
        )

        let indicators = try JSONDecoder()
            .decode(AnalyticsAPIResponse.self, from: data)
            .toDashboard()
            .indicators

        XCTAssertEqual(indicators.map(\.maxTiles), [nil, nil, 2, 20, nil])
        XCTAssertEqual(indicators.map(\.resolvedMaximumTiles), [8, 8, 2, 20, 8])
        XCTAssertEqual(indicators.map(\.resolvedTileLayout), [.mosaic, .mosaic, .mosaic, .mosaic, .mosaic])
    }

    func testSquarifiedTileLayoutFillsAreaWithoutOverlap() {
        let values = [50.0, 30.0, 15.0, 5.0]
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 240)
        let frames = TileMosaicLayout.frames(for: values, in: bounds, spacing: 0)

        XCTAssertEqual(frames.count, values.count)
        XCTAssertTrue(frames.allSatisfy { $0.width > 0 && $0.height > 0 && bounds.contains($0) })
        XCTAssertEqual(
            frames.reduce(0) { $0 + $1.width * $1.height },
            bounds.width * bounds.height,
            accuracy: 0.01
        )

        for leftIndex in frames.indices {
            for rightIndex in frames.indices where rightIndex > leftIndex {
                let intersection = frames[leftIndex].intersection(frames[rightIndex])
                XCTAssertEqual(intersection.width * intersection.height, 0, accuracy: 0.001)
            }
        }

        let totalValue = values.reduce(0, +)
        let totalArea = bounds.width * bounds.height
        for index in frames.indices {
            let expectedArea = totalArea * CGFloat(values[index] / totalValue)
            XCTAssertEqual(frames[index].width * frames[index].height, expectedArea, accuracy: 0.01)
        }
    }

    func testTileGridAndProgressiveLabelVisibility() {
        XCTAssertEqual(TileGridLayout.columnCount(availableWidth: 390, contentScale: 1), 2)
        XCTAssertEqual(TileGridLayout.columnCount(availableWidth: 600, contentScale: 1), 3)
        XCTAssertEqual(TileGridLayout.columnCount(availableWidth: 900, contentScale: 1), 4)

        XCTAssertEqual(
            TileLabelVisibilityPolicy.visibility(
                for: CGSize(width: 80, height: 80),
                contentScale: 1,
                showValueLabels: true
            ),
            TileLabelVisibility(showsTitle: true, showsValue: true, showsPercentage: true)
        )
        XCTAssertEqual(
            TileLabelVisibilityPolicy.visibility(
                for: CGSize(width: 48, height: 44),
                contentScale: 1,
                showValueLabels: true
            ),
            TileLabelVisibility(showsTitle: true, showsValue: true, showsPercentage: false)
        )
        XCTAssertEqual(
            TileLabelVisibilityPolicy.visibility(
                for: CGSize(width: 30, height: 24),
                contentScale: 1,
                showValueLabels: true
            ),
            TileLabelVisibility(showsTitle: true, showsValue: false, showsPercentage: false)
        )
        XCTAssertEqual(
            TileLabelVisibilityPolicy.visibility(
                for: CGSize(width: 80, height: 80),
                contentScale: 1,
                showValueLabels: false
            ),
            TileLabelVisibility(showsTitle: true, showsValue: false, showsPercentage: false)
        )
    }

    func testPasswordExpirySkipIsRestrictedToRUDNIdentityHost() throws {
        XCTAssertTrue(
            RUDNPasswordExpiryWarningPolicy.canInject(
                on: try XCTUnwrap(URL(string: "https://id.rudn.ru/login"))
            )
        )
        XCTAssertFalse(
            RUDNPasswordExpiryWarningPolicy.canInject(
                on: try XCTUnwrap(URL(string: "https://id.rudn.ru.example.com/login"))
            )
        )
        XCTAssertTrue(RUDNPasswordExpiryWarningPolicy.script.contains("Срок действия пароля истекает"))
        XCTAssertTrue(RUDNPasswordExpiryWarningPolicy.script.contains("Пропустить"))
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
        XCTAssertTrue(viewModel.isShowingCachedData)
        XCTAssertEqual(viewModel.dashboard?.fetchedAt, .distantPast)
        XCTAssertEqual(viewModel.staleSectionIDs, [cachedSection.id])
        XCTAssertNotNil(viewModel.dashboard?.sections.first(where: { $0.id == freshSection.id })?.fetchedAt)
        XCTAssertEqual(
            viewModel.refreshErrorMessage,
            "Не удалось обновить разделы: Кадры. Уже полученные данные сохранены."
        )
    }

    func testPartiallyDecodedSectionUpdatesValidChartsAndKeepsCachedInvalidChart() async {
        let cachedValid = Indicator(
            id: "science-valid",
            title: "Valid",
            value: 1,
            unit: nil,
            chartType: .oneValue,
            source: nil,
            rows: []
        )
        let cachedInvalid = Indicator(
            id: "science-changed",
            title: "Changed contract",
            value: 2,
            unit: nil,
            chartType: .oneValue,
            source: nil,
            rows: []
        )
        let freshValid = Indicator(
            id: cachedValid.id,
            title: cachedValid.title,
            value: 10,
            unit: nil,
            chartType: .oneValue,
            source: nil,
            rows: []
        )
        let cached = Dashboard(
            id: "analytics",
            title: "Аналитика",
            fetchedAt: .distantPast,
            sections: [
                DashboardSection(
                    id: "science",
                    title: "Наука",
                    indicators: [cachedValid, cachedInvalid]
                )
            ]
        )
        let fresh = Dashboard(
            id: "analytics",
            title: "Аналитика",
            fetchedAt: Date(),
            sections: [
                DashboardSection(
                    id: "science",
                    title: "Наука",
                    indicators: [freshValid],
                    indicatorDecodeFailureCount: 1
                )
            ]
        )
        let viewModel = DashboardViewModel(
            provider: StaticDashboardProvider(dashboard: fresh),
            cache: StubDashboardCache(dashboard: cached)
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.dashboard?.indicators.map(\.id), [freshValid.id, cachedInvalid.id])
        XCTAssertEqual(viewModel.dashboard?.indicators.first?.value, freshValid.value)
        XCTAssertTrue(viewModel.isShowingCachedData)
        XCTAssertTrue(viewModel.refreshErrorMessage?.contains("1 график") == true)
    }

    func testFreshChartWithChangedTypeReplacesCachedChart() async {
        let chartID = "science-changing-chart"
        let cachedChart = Indicator(
            id: chartID,
            title: "Changing chart",
            value: 2,
            unit: nil,
            chartType: .oneValue,
            source: nil,
            rows: []
        )
        let freshChart = Indicator(
            id: chartID,
            title: "Changing chart",
            value: 10,
            unit: nil,
            chartType: .bar,
            source: nil,
            rows: [
                IndicatorRow(
                    id: "fresh-row",
                    label: "Fresh",
                    value: 10,
                    series: nil,
                    sortOrder: 0
                )
            ]
        )
        let cached = Dashboard(
            id: "analytics",
            title: "Аналитика",
            fetchedAt: .distantPast,
            sections: [
                DashboardSection(
                    id: "science",
                    title: "Наука",
                    indicators: [cachedChart]
                )
            ]
        )
        let fresh = Dashboard(
            id: "analytics",
            title: "Аналитика",
            fetchedAt: Date(),
            sections: [
                DashboardSection(
                    id: "science",
                    title: "Наука",
                    indicators: [freshChart]
                )
            ]
        )
        let viewModel = DashboardViewModel(
            provider: StaticDashboardProvider(dashboard: fresh),
            cache: StubDashboardCache(dashboard: cached)
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.dashboard?.indicators, [freshChart])
        XCTAssertFalse(viewModel.isShowingCachedData)
        XCTAssertNil(viewModel.refreshErrorMessage)
    }

    func testProgressiveLoadingPublishesSectionBeforeRequestCompletes() async {
        let firstSection = DashboardSection(
            id: "образование",
            title: "Образование",
            indicators: []
        )
        let secondSection = DashboardSection(
            id: "финансы",
            title: "Финансы",
            indicators: []
        )
        let finalDashboard = Dashboard(
            id: "analytics",
            title: "Аналитика",
            fetchedAt: Date(),
            sections: [firstSection, secondSection]
        )
        let provider = PausingProgressiveProvider(
            firstSection: firstSection,
            finalDashboard: finalDashboard
        )
        let viewModel = DashboardViewModel(
            provider: provider,
            cache: StubDashboardCache(dashboard: nil)
        )

        let loadTask = Task { await viewModel.load() }
        while !provider.isPaused {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.dashboard?.sections.map(\.title), ["Образование"])
        XCTAssertEqual(viewModel.state, .loading)
        XCTAssertTrue(viewModel.isRefreshing)

        provider.finish()
        await loadTask.value

        XCTAssertEqual(viewModel.dashboard?.sections.map(\.title), ["Образование", "Финансы"])
        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testCachedExtendedSectionsRefreshInParallel() async {
        let cachedSections = AnalyticsAPIContract.sections.prefix(2).map { contract in
            DashboardSection(
                id: contract.id,
                title: contract.displayName,
                indicators: [],
                hasExtended: true,
                extended: DashboardExtendedSection(
                    id: "extended:\(contract.id)",
                    title: "\(contract.displayName) · 2 уровень",
                    indicators: []
                )
            )
        }
        let cached = Dashboard(
            id: "cached",
            title: "Аналитика",
            fetchedAt: .distantPast,
            sections: cachedSections
        )
        let provider = ParallelExtendedDashboardProvider(dashboard: cached)
        let viewModel = DashboardViewModel(
            provider: provider,
            cache: StubDashboardCache(dashboard: cached)
        )

        await viewModel.load()

        XCTAssertEqual(provider.extendedRequestCount, 2)
        XCTAssertEqual(provider.maximumConcurrentExtendedRequests, 2)
        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testCacheWriteFailureIsVisibleAfterSuccessfulRefresh() async {
        let dashboard = Dashboard(id: "fresh", title: "Fresh", fetchedAt: Date(), indicators: [])
        let viewModel = DashboardViewModel(
            provider: StaticDashboardProvider(dashboard: dashboard),
            cache: FailingWriteDashboardCache()
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.dashboard, dashboard)
        XCTAssertTrue(viewModel.cacheErrorMessage?.contains("сохранить") == true)
    }

    func testExtendedIndicatorsAreCachedSeparatelyAndRefreshWithDashboard() async throws {
        let baseIndicator = Indicator(
            id: "финансы-base",
            title: "Основной",
            value: nil,
            unit: nil,
            chartType: .bar,
            source: nil,
            rows: []
        )
        let extendedIndicator = Indicator(
            id: "финансы-extended-extra",
            title: "Дополнительный",
            value: nil,
            unit: nil,
            chartType: .bar,
            source: nil,
            rows: []
        )
        let baseSection = DashboardSection(
            id: "финансы",
            title: "Финансы",
            indicators: [baseIndicator],
            hasExtended: true
        )
        let baseDashboard = Dashboard(
            id: "analytics",
            title: "Аналитика",
            fetchedAt: Date(),
            sections: [baseSection]
        )
        let provider = ExtendedDashboardProvider(
            dashboard: baseDashboard,
            extendedSection: DashboardSection(
                id: "финансы",
                title: "Финансы",
                indicators: [extendedIndicator]
            )
        )
        let cache = RecordingDashboardCache()
        let historyDefaults = try XCTUnwrap(UserDefaults(suiteName: "sync-history-tests-\(UUID().uuidString)"))
        historyDefaults.set(Data("legacy".utf8), forKey: DashboardSynchronizationStoragePolicy.legacyHistoryKey)
        let viewModel = DashboardViewModel(
            provider: provider,
            cache: cache,
            legacyHistoryDefaults: historyDefaults
        )
        XCTAssertNil(historyDefaults.object(forKey: DashboardSynchronizationStoragePolicy.legacyHistoryKey))

        await viewModel.load()
        XCTAssertEqual(viewModel.dashboard?.indicators.map(\.id), [baseIndicator.id])

        let visibleSection = try XCTUnwrap(viewModel.dashboard?.sections.first)
        await viewModel.loadExtendedIndicators(for: visibleSection)
        XCTAssertEqual(
            viewModel.dashboard?.indicators.map(\.id),
            [baseIndicator.id, extendedIndicator.id]
        )
        XCTAssertEqual(viewModel.extendedState(for: baseSection.id), .loaded)
        XCTAssertEqual(viewModel.dashboard?.sections.first?.indicators.map(\.id), [baseIndicator.id])
        XCTAssertEqual(viewModel.dashboard?.sections.first?.extended?.indicators.map(\.id), [extendedIndicator.id])
        XCTAssertTrue(cache.savedDashboards.contains { $0.sections.first?.extended?.indicators.map(\.id) == [extendedIndicator.id] })
        XCTAssertEqual(viewModel.synchronizationSession?.title, "Ручное обновление второго уровня")
        XCTAssertEqual(viewModel.synchronizationSession?.items.first?.charts.map(\.title), [extendedIndicator.title])
        XCTAssertEqual(viewModel.synchronizationSession?.items.first?.charts.first?.status, .succeeded)
        XCTAssertNil(historyDefaults.object(forKey: DashboardSynchronizationStoragePolicy.legacyHistoryKey))

        await viewModel.refresh()
        XCTAssertEqual(provider.extendedRequestCount, 2)
        XCTAssertEqual(
            viewModel.dashboard?.indicators.map(\.id),
            [baseIndicator.id, extendedIndicator.id]
        )
        XCTAssertEqual(viewModel.dashboard?.sections.first?.indicators.map(\.id), [baseIndicator.id])
        XCTAssertEqual(viewModel.dashboard?.sections.first?.extended?.indicators.map(\.id), [extendedIndicator.id])
        XCTAssertEqual(viewModel.synchronizationSession?.title, "Ручное обновление дашборда")
        XCTAssertEqual(
            viewModel.synchronizationSession?.items.first(where: { $0.kind == .extended })?.charts.map(\.title),
            [extendedIndicator.title]
        )
        XCTAssertNil(historyDefaults.object(forKey: DashboardSynchronizationStoragePolicy.legacyHistoryKey))
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
private final class SignOutEventRecorder {
    enum Event: Equatable {
        case dashboardCleared
        case credentialsCleared
    }

    private(set) var values: [Event] = []

    func append(_ event: Event) {
        values.append(event)
    }
}

@MainActor
private final class StubAuthenticationCredentialsStore: AuthenticationCredentialsStoring {
    private let events: SignOutEventRecorder

    init(events: SignOutEventRecorder) {
        self.events = events
    }

    func load() throws -> AuthenticationCredentials? {
        AuthenticationCredentials(token: "token", username: "user")
    }

    func clear() throws {
        events.append(.credentialsCleared)
    }
}

@MainActor
private final class SignOutDashboardCache: DashboardCaching {
    private let events: SignOutEventRecorder
    private let shouldFail: Bool

    init(events: SignOutEventRecorder, shouldFail: Bool = false) {
        self.events = events
        self.shouldFail = shouldFail
    }

    func loadDashboard() throws -> Dashboard? { nil }
    func save(_ dashboard: Dashboard) throws {}

    func clearDashboard() throws {
        events.append(.dashboardCleared)
        if shouldFail {
            throw DashboardCacheError.unavailable("test")
        }
    }
}

@MainActor
private struct PartiallyFailingProvider: AnalyticsProvider {
    let section: DashboardSection

    func fetchDashboard() async throws -> Dashboard {
        throw AnalyticsError.partialFailure(sections: ["Кадры"])
    }

    func fetchDashboard(
        onEvent: @escaping @MainActor @Sendable (AnalyticsSectionFetchEvent) -> Void
    ) async throws -> Dashboard {
        let contract = AnalyticsAPIContract.sections[0]
        onEvent(.started(contract))
        onEvent(.succeeded(contract, section))
        let failed = AnalyticsAPIContract.sections[5]
        onEvent(.started(failed))
        onEvent(.failed(failed, "Ошибка"))
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
    func clearDashboard() throws {}
}

@MainActor
private final class PausingProgressiveProvider: AnalyticsProvider {
    let firstSection: DashboardSection
    let finalDashboard: Dashboard
    private var continuation: CheckedContinuation<Void, Never>?

    init(firstSection: DashboardSection, finalDashboard: Dashboard) {
        self.firstSection = firstSection
        self.finalDashboard = finalDashboard
    }

    var isPaused: Bool { continuation != nil }

    func fetchDashboard() async throws -> Dashboard {
        finalDashboard
    }

    func fetchDashboard(
        onEvent: @escaping @MainActor @Sendable (AnalyticsSectionFetchEvent) -> Void
    ) async throws -> Dashboard {
        let first = AnalyticsAPIContract.sections[0]
        onEvent(.started(first))
        onEvent(.succeeded(first, firstSection))
        await withCheckedContinuation { continuation = $0 }
        if let second = AnalyticsAPIContract.section(matching: "Финансы"),
           let section = finalDashboard.sections.first(where: { $0.title == "Финансы" }) {
            onEvent(.started(second))
            onEvent(.succeeded(second, section))
        }
        return finalDashboard
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private struct StaticDashboardProvider: AnalyticsProvider {
    let dashboard: Dashboard

    func fetchDashboard() async throws -> Dashboard {
        dashboard
    }
}

@MainActor
private final class ExtendedDashboardProvider: AnalyticsProvider {
    let dashboard: Dashboard
    let extendedSection: DashboardSection
    private(set) var extendedRequestCount = 0

    init(dashboard: Dashboard, extendedSection: DashboardSection) {
        self.dashboard = dashboard
        self.extendedSection = extendedSection
    }

    func fetchDashboard() async throws -> Dashboard {
        dashboard
    }

    func fetchExtendedSection(for section: AnalyticsAPIContract.Section) async throws -> DashboardSection {
        extendedRequestCount += 1
        return extendedSection
    }
}

@MainActor
private final class ParallelExtendedDashboardProvider: AnalyticsProvider {
    let dashboard: Dashboard
    private(set) var extendedRequestCount = 0
    private(set) var maximumConcurrentExtendedRequests = 0
    private var activeExtendedRequests = 0

    init(dashboard: Dashboard) {
        self.dashboard = dashboard
    }

    func fetchDashboard() async throws -> Dashboard {
        dashboard
    }

    func fetchExtendedSection(for section: AnalyticsAPIContract.Section) async throws -> DashboardSection {
        extendedRequestCount += 1
        activeExtendedRequests += 1
        maximumConcurrentExtendedRequests = max(
            maximumConcurrentExtendedRequests,
            activeExtendedRequests
        )
        defer { activeExtendedRequests -= 1 }
        try await Task.sleep(for: .milliseconds(50))

        return DashboardSection(
            id: section.id,
            title: section.displayName,
            indicators: []
        )
    }
}

@MainActor
private final class RecordingDashboardCache: DashboardCaching {
    private(set) var savedDashboards: [Dashboard] = []

    func loadDashboard() throws -> Dashboard? { nil }

    func save(_ dashboard: Dashboard) throws {
        savedDashboards.append(dashboard)
    }

    func clearDashboard() throws {}
}

@MainActor
private struct FailingWriteDashboardCache: DashboardCaching {
    func loadDashboard() throws -> Dashboard? { nil }

    func save(_ dashboard: Dashboard) throws {
        throw DashboardCacheError.unavailable("test")
    }

    func clearDashboard() throws {}
}
