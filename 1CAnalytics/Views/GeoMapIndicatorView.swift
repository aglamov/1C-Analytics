import MapKit
import SwiftUI

struct GeoMapIndicatorView: View {
    let indicator: Indicator
    private let valuesByCountryKey: [String: Double]
    private let selectedCountryKeys: Set<String>
    private let maximumValue: Double
    @State private var geometry = GeoMapGeometry.empty
    @Environment(\.chartPaletteScheme) private var chartPaletteScheme

    init(indicator: Indicator, selectedRowID: IndicatorRow.ID? = nil) {
        self.indicator = indicator
        self.maximumValue = indicator.rows.map(\.value).max() ?? 1
        self.valuesByCountryKey = indicator.rows.reduce(into: [:]) { values, row in
            let key = row.label.geoCountryKey
            values[key] = row.value

            if let isoCode = GeoCountryAliases.isoCodeByAPIName[key] {
                values[isoCode] = row.value
            }
        }
        self.selectedCountryKeys = GeoMapPresentationPolicy.countryKeys(
            for: indicator.rows.first { $0.id == selectedRowID }
        )
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
                let plotRect = CGRect(origin: .zero, size: size)

                for shape in geometry.shapes {
                    let path = mapPath(for: shape, in: plotRect, bounds: geometry.bounds)
                    context.fill(path, with: .color(fillColor(for: shape)))
                    context.stroke(
                        path,
                        with: .color(strokeColor(for: shape)),
                        style: StrokeStyle(
                            lineWidth: isSelected(shape) ? 2.2 : 0.55,
                            lineJoin: .round
                        )
                    )
                }
            }
            .aspectRatio(geometry.aspectRatio, contentMode: .fit)
            .padding(.horizontal, 4)
            .accessibilityHidden(true)

            if indicator.showsLegend {
                mapLegend
            }
        }
        .task {
            if geometry.shapes.isEmpty {
                geometry = await GeoMapWorldGeometry.shared.load()
            }
        }
        .accessibilityLabel("Карта распределения по странам")
    }

    private func value(for shape: GeoCountryShape) -> Double? {
        shape.lookupKeys.compactMap { valuesByCountryKey[$0] }.first
    }

    private func fillColor(for shape: GeoCountryShape) -> Color {
        guard let value = value(for: shape) else {
            return Color.secondary.opacity(0.075)
        }

        let intensity = log1p(max(value, 0)) / max(log1p(max(maximumValue, 1)), 1)
        let opacity = 0.20 + 0.76 * intensity

        if isSelected(shape) {
            return paletteColor.opacity(1)
        }

        return paletteColor.opacity(selectedCountryKeys.isEmpty ? opacity : opacity * 0.42)
    }

    private func strokeColor(for shape: GeoCountryShape) -> Color {
        isSelected(shape)
            ? Color.primary.opacity(0.92)
            : Color.secondary.opacity(selectedCountryKeys.isEmpty ? 0.38 : 0.22)
    }

    private func isSelected(_ shape: GeoCountryShape) -> Bool {
        !selectedCountryKeys.isDisjoint(with: shape.lookupKeys)
    }

    private func mapPath(for shape: GeoCountryShape, in rect: CGRect, bounds: CGRect) -> Path {
        var path = Path()
        var previousPoint: CGPoint?

        for normalizedPoint in shape.points {
            let point = CGPoint(
                x: rect.minX + ((normalizedPoint.x - bounds.minX) / bounds.width) * rect.width,
                y: rect.minY + ((normalizedPoint.y - bounds.minY) / bounds.height) * rect.height
            )

            if let previousPoint,
               abs(point.x - previousPoint.x) <= rect.width * 0.5 {
                path.addLine(to: point)
            } else {
                if previousPoint != nil {
                    path.closeSubpath()
                }
                path.move(to: point)
            }

            previousPoint = point
        }

        path.closeSubpath()
        return path
    }

    private var mapLegend: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if let unit = indicator.displayUnit {
                Text(unit)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text(indicator.formattedNumber(0.0))
                LinearGradient(
                    colors: [
                        paletteColor.opacity(0.18),
                        paletteColor.opacity(0.92)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 72, height: 8)
                .clipShape(Capsule())
                Text(indicator.formattedNumber(maximumValue))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.primary)
        }
        .padding(9)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Шкала от 0 "
                + "до \(maximumValue.formatted(.number.grouping(.automatic)))"
        )
    }

    private var paletteColor: Color {
        indicator.paletteColor(scheme: chartPaletteScheme)
    }
}

private struct GeoCountryShape: Identifiable, Sendable {
    let id: String
    let points: [CGPoint]
    let lookupKeys: [String]
}

private struct GeoMapGeometry: Sendable {
    let shapes: [GeoCountryShape]
    let bounds: CGRect

    static let empty = GeoMapGeometry(
        shapes: [],
        bounds: CGRect(x: 0, y: 0, width: 1, height: 1)
    )

    var aspectRatio: CGFloat {
        guard !shapes.isEmpty, bounds.height > 0 else {
            return 2.07
        }

        return 2 * bounds.width / bounds.height
    }
}

private actor GeoMapWorldGeometry {
    static let shared = GeoMapWorldGeometry()

    private var cachedGeometry: GeoMapGeometry?

    func load() -> GeoMapGeometry {
        if let cachedGeometry {
            return cachedGeometry
        }

        guard let url = Bundle.main.url(
            forResource: "world-countries-110m",
            withExtension: "geojson"
        ),
        let data = try? Data(contentsOf: url),
        let objects = try? MKGeoJSONDecoder().decode(data) else {
            return .empty
        }

        var shapes: [GeoCountryShape] = []
        var minimumX = CGFloat.greatestFiniteMagnitude
        var minimumY = CGFloat.greatestFiniteMagnitude
        var maximumX = -CGFloat.greatestFiniteMagnitude
        var maximumY = -CGFloat.greatestFiniteMagnitude

        for (featureIndex, object) in objects.enumerated() {
            guard let feature = object as? MKGeoJSONFeature else {
                continue
            }

            let properties = feature.properties.flatMap {
                try? JSONDecoder().decode(GeoCountryProperties.self, from: $0)
            }
            guard GeoMapPresentationPolicy.shouldIncludeCountry(
                nameRU: properties?.nameRU,
                admin: properties?.admin,
                isoA3: properties?.isoA3
            ) else {
                continue
            }

            let lookupKeys = [
                properties?.nameRU?.geoCountryKey,
                properties?.admin?.geoCountryKey,
                properties?.isoA3?.geoCountryKey
            ].compactMap(\.self)

            var polygonIndex = 0
            for geometry in feature.geometry {
                let polygons: [MKPolygon]

                if let polygon = geometry as? MKPolygon {
                    polygons = [polygon]
                } else if let multiPolygon = geometry as? MKMultiPolygon {
                    polygons = multiPolygon.polygons
                } else {
                    continue
                }

                for polygon in polygons {
                    let mapPoints = polygon.points()
                    let normalizedPoints = (0..<polygon.pointCount).map { pointIndex in
                        let coordinate = mapPoints[pointIndex].coordinate
                        let point = CGPoint(
                            x: (coordinate.longitude + 180) / 360,
                            y: (90 - coordinate.latitude) / 180
                        )

                        minimumX = min(minimumX, point.x)
                        minimumY = min(minimumY, point.y)
                        maximumX = max(maximumX, point.x)
                        maximumY = max(maximumY, point.y)
                        return point
                    }

                    shapes.append(
                        GeoCountryShape(
                            id: "\(featureIndex)-\(polygonIndex)",
                            points: normalizedPoints,
                            lookupKeys: lookupKeys
                        )
                    )
                    polygonIndex += 1
                }
            }
        }

        guard !shapes.isEmpty else {
            return .empty
        }

        let geometry = GeoMapGeometry(
            shapes: shapes,
            bounds: CGRect(
                x: minimumX,
                y: minimumY,
                width: maximumX - minimumX,
                height: maximumY - minimumY
            )
        )
        cachedGeometry = geometry
        return geometry
    }
}

private struct GeoCountryProperties: Decodable {
    let nameRU: String?
    let admin: String?
    let isoA3: String?

    private enum CodingKeys: String, CodingKey {
        case nameRU = "NAME_RU"
        case admin = "ADMIN"
        case isoA3 = "ISO_A3"
    }
}

enum GeoMapPresentationPolicy {
    static func shouldIncludeCountry(
        nameRU: String?,
        admin: String?,
        isoA3: String?
    ) -> Bool {
        let keys = [nameRU, admin, isoA3]
            .compactMap(\.self)
            .map(\.geoCountryKey)

        return GeoCountryAliases.antarcticaKeys.isDisjoint(with: keys)
    }

    static func countryKeys(for row: IndicatorRow?) -> Set<String> {
        guard let row else {
            return []
        }

        let key = row.label.geoCountryKey
        return Set([key, GeoCountryAliases.isoCodeByAPIName[key]].compactMap(\.self))
    }
}

private enum GeoCountryAliases {
    static let antarcticaKeys: Set<String> = [
        "Антарктида".geoCountryKey,
        "Antarctica".geoCountryKey,
        "ATA".geoCountryKey
    ]

    static let isoCodeByAPIName: [String: String] = [
        "АБХАЗИЯ".geoCountryKey: "ABH",
        "БАХРЕЙН".geoCountryKey: "BHR",
        "БЕЛАРУСЬ".geoCountryKey: "BLR",
        "БОЛИВИЯ, МНОГОНАЦИОНАЛЬНОЕ ГОСУДАРСТВО".geoCountryKey: "BOL",
        "БРУНЕЙ-ДАРУССАЛАМ".geoCountryKey: "BRN",
        "ВЕНЕСУЭЛА (БОЛИВАРИАНСКАЯ РЕСПУБЛИКА)".geoCountryKey: "VEN",
        "ГАИТИ".geoCountryKey: "HTI",
        "ГРЕНАДА".geoCountryKey: "GRD",
        "ДОМИНИКА".geoCountryKey: "DMA",
        "ИРАН (ИСЛАМСКАЯ РЕСПУБЛИКА)".geoCountryKey: "IRN",
        "КАБО-ВЕРДЕ".geoCountryKey: "CPV",
        "КИТАЙ".geoCountryKey: "CHN",
        "КОМОРЫ".geoCountryKey: "COM",
        "КОНГО".geoCountryKey: "COG",
        "КОНГО, ДЕМОКРАТИЧЕСКАЯ РЕСПУБЛИКА".geoCountryKey: "COD",
        "КОРЕЯ, НАРОДНО-ДЕМОКРАТИЧЕСКАЯ РЕСПУБЛИКА".geoCountryKey: "PRK",
        "КОРЕЯ, РЕСПУБЛИКА".geoCountryKey: "KOR",
        "ЛАОССКАЯ НАРОДНО-ДЕМОКРАТИЧЕСКАЯ РЕСПУБЛИКА".geoCountryKey: "LAO",
        "МАВРИКИЙ".geoCountryKey: "MUS",
        "МАЛЬТА".geoCountryKey: "MLT",
        "МОЛДОВА, РЕСПУБЛИКА".geoCountryKey: "MDA",
        "ПАЛЕСТИНА, ГОСУДАРСТВО".geoCountryKey: "PSX",
        "САН-ТОМЕ И ПРИНСИПИ".geoCountryKey: "STP",
        "СИНГАПУР".geoCountryKey: "SGP",
        "СИРИЙСКАЯ АРАБСКАЯ РЕСПУБЛИКА".geoCountryKey: "SYR",
        "СОЕДИНЕННОЕ КОРОЛЕВСТВО ВЕЛИКОБРИТАНИИ И СЕВЕРНОЙ ИРЛАНДИИ".geoCountryKey: "GBR",
        "СОЕДИНЕННЫЕ ШТАТЫ".geoCountryKey: "USA",
        "ТАЙВАНЬ (КИТАЙ)".geoCountryKey: "TWN",
        "ТАНЗАНИЯ, ОБЪЕДИНЕННАЯ РЕСПУБЛИКА".geoCountryKey: "TZA",
        "ТУРКМЕНИСТАН".geoCountryKey: "TKM",
        "ЭЛЬ-САЛЬВАДОР".geoCountryKey: "SLV",
        "ЮЖНАЯ АФРИКА".geoCountryKey: "ZAF"
    ]
}

private extension String {
    var geoCountryKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
            .uppercased()
            .replacingOccurrences(of: "Ё", with: "Е")
            .filter { $0.isLetter || $0.isNumber }
    }
}
