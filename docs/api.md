# API Integration

## Base URL

```text
https://sed2.rudn.ru/DGU_HTTP/hs/DGU_APP_Mobile_Client/analitycs/
```

Endpoint подготовлен для мобильного клиента аналитики. Текущий API использует ключ как последний компонент пути. Ключ хранится локально в `Config/Secrets.xcconfig` через `ANALYTICS_PATH_TOKEN` и не коммитится в git.

## Client Responsibility

iOS/iPadOS-приложение должно работать через отдельный слой интеграции:

- `AnalyticsProvider` - протокол получения дашбордов и показателей;
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

## API Response Shape

Фактический ответ API:

```json
{
  "sections": [
    {
      "name": "Образование",
      "values": [
        {
          "name": "Всего обучающихся",
          "values": [
            { "group": "БАК/СПЕЦ/МАГ", "value": 35472 },
            { "group": "АСП", "value": 3547 },
            { "group": "ОРД", "value": 2184 },
            { "group": "", "value": 41203 }
          ],
          "type": "SectorMarkInnerRadius"
        },
        {
          "name": "Всего обучающихся РФ и ИГ",
          "values": [
            {
              "group": "БАК",
              "subgroup": [
                { "name": "РФ, чел", "value": 18347 },
                { "name": "ИГ, чел", "value": 3604 }
              ]
            }
          ],
          "type": "BarMarkStacking"
        }
      ]
    }
  ]
}
```

Внутри приложения ответ приводится к независимой UI-модели:

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

Для составных показателей API может возвращать список `subgroup`. Каждая запись
`subgroup` становится отдельной серией в `IndicatorRow.series`, а `group`
остаётся общей категорией для stacking.

## Open Questions

- Нужно ли будет заменить path-token на header-token.
- Какие параметры фильтрации поддерживаются.
- Будет ли API возвращать дату среза.
- Какие ошибки возвращаются при пустых данных, отсутствии доступа и недоступности 1С.
