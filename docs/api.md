# API Integration

## Authorization

Приложение открывает страницу входа без переопределения зарегистрированного redirect:

```text
https://id.rudn.ru/sign-in?client_id=ed75cd5e-b477-4f3e-84b6-074608eee315&response_type=code&state=<random-state>
```

После успешного входа PASSPORT.RUDN направляет браузер на зарегистрированный URL `https://sed.rudn.ru/DGU_DEMO/hs/DGU_APP_Mobile_Client/return_uri?code=...&state=...`. Встроенное окно перехватывает этот URL до загрузки `return_uri`, проверяет одноразовый `state`, извлекает `code`, отменяет навигацию и закрывается. Callback без ожидаемого `state` отклоняется. Затем выполняется:

```http
POST https://sed2.rudn.ru/DGU_HTTP/hs/DGU_APP_Mobile_Client/auth/code
Content-Type: application/json
Accept: application/json
X-Auth-Key: <device-identifier>
X-Auth-Timestamp: <unix-timestamp-seconds>

{"code_analitic":"<authorization-code>"}
```

Backend возвращает `token` и `username` в корне JSON либо внутри объекта `data`. Только ответ со статусом `2xx`, содержащий оба непустых значения, завершает вход. Значения сохраняются в Keychain (`WhenUnlockedThisDeviceOnly`). Ответы других классов или некорректный JSON отображаются как ошибка авторизации и не дают открыть дашборд.

Каждый последующий запрос к API получает заголовки из Keychain:

```http
X-Auth-Token: <sha1-signature>
Login: <username>
X-Auth-Key: <device-identifier>
X-Auth-Timestamp: <unix-timestamp-seconds>
```

Подпись формируется отдельно для каждого запроса как lowercase hex: `SHA1(X-Auth-Key + X-Auth-Timestamp + token)`. Компоненты объединяются без разделителей в указанном порядке. Timestamp передаётся в Unix-секундах.

## Base URL

```text
https://sed2.rudn.ru/DGU_HTTP/hs/DGU_APP_Mobile_Client/analitycs/
```

Endpoint подготовлен для мобильного клиента аналитики и используется без дополнительных компонентов пути.

Запрос `/analitycs/` дополнительно требует заголовки `X-Auth-Token`, `X-Auth-Timestamp`, `Login` и `X-Auth-Key`. Идентификатор содержит системный `identifierForVendor` устройства в формате UUID.

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
    let fetchedAt: Date?
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

`fetchedAt` — локальное время успешного получения ответа, а не дата среза данных в 1С. Пока API не возвращает дату среза, интерфейс подписывает это значение как «Получено».

## Open Questions

- Какие параметры фильтрации поддерживаются.
- Будет ли API возвращать дату среза.
- Какие ошибки возвращаются при пустых данных, отсутствии доступа и недоступности 1С.
