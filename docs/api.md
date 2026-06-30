# API Integration

## Base URL

```text
https://sed2.rudn.ru/DGU_HTTP/hs/DGU_APP_Mobile_Client/analitycs/
```

Endpoint подготовлен для мобильного клиента аналитики. На момент фиксации документации доступ с текущей машины не подтвердился: DNS не смог разрешить `sed2.rudn.ru`. Возможные причины: доступ только из внутренней сети, VPN или отдельной DNS-зоны.

## Client Responsibility

iOS/iPadOS-приложение должно работать через отдельный слой интеграции:

- `AnalyticsProvider` - протокол получения дашбордов и показателей;
- `MockAnalyticsProvider` - локальные данные для разработки интерфейса;
- `APIAnalyticsProvider` - HTTP-клиент подготовленного API;
- маппинг ответа API в независимые UI-модели.

UI не должен напрямую зависеть от JSON-структуры 1С. Это позволит менять контракт API без переписывания экранов.

## Chart View Types

API или модель показателя должны указывать тип визуализации. Поддерживаемые виды:

| Type | Swift Charts implementation | Use case |
| --- | --- | --- |
| `BarMark` | `BarMark` | Вертикальное сравнение категорий |
| `BarMarkHorizon` | `BarMark` с горизонтальной ориентацией осей | Сравнение категорий с длинными подписями |
| `BarMarkStacking` | `BarMark` с группировкой/stacking | Состав показателя внутри категории |
| `SectorMarkInnerRadius` | `SectorMark` с `innerRadius` | Кольцевая диаграмма долей |

## Expected Data Shape

Фактическая схема ответа должна быть подтверждена после доступа к API. Для клиента желательно привести ответ к такой внутренней модели:

```swift
struct Dashboard: Identifiable, Decodable {
    let id: String
    let title: String
    let updatedAt: Date?
    let indicators: [Indicator]
}

struct Indicator: Identifiable, Decodable {
    let id: String
    let title: String
    let value: Decimal?
    let unit: String?
    let chartType: ChartType
    let source: String?
    let rows: [IndicatorRow]
}

struct IndicatorRow: Identifiable, Decodable {
    let id: String
    let label: String
    let value: Decimal
    let series: String?
    let sortOrder: Int?
}

enum ChartType: String, Decodable {
    case bar = "BarMark"
    case horizontalBar = "BarMarkHorizon"
    case stackedBar = "BarMarkStacking"
    case donut = "SectorMarkInnerRadius"
}
```

## Open Questions

- Нужна ли авторизация для endpoint.
- Какие HTTP-методы и параметры поддерживаются.
- Возвращает ли API один дашборд или список дашбордов.
- В каком формате приходят даты и числовые значения.
- Какие ошибки возвращаются при пустых данных, отсутствии доступа и недоступности 1С.

