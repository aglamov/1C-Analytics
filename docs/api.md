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
https://sed2.rudn.ru/DGU_HTTP/hs/DGU_APP_Mobile_Client/analitycs
```

Endpoint подготовлен для мобильного клиента аналитики и используется без
дополнительных компонентов пути. Для каждой секции выполняется отдельный запрос:

```http
GET /DGU_HTTP/hs/DGU_APP_Mobile_Client/analitycs
    ?id=test_analitycs_med
    &section=<URL-encoded section>
Accept: application/json
```

`id` фиксирован. Одновременно запрашиваются:

1. `Образование`
2. `Финансы`
3. `Наука`
4. `Приемная_кампания`
5. `Международная_деятельность`
6. `Кадры`

Каждый запрос дополнительно получает заголовки `X-Auth-Token`,
`X-Auth-Timestamp`, `Login` и `X-Auth-Key`. Идентификатор содержит системный
`identifierForVendor` устройства в формате UUID.

Таймаут каждого запроса - 60 секунд. Успешные секции передаются во ViewModel и
сохраняются сразу по мере завершения. Если одна или несколько секций не
загрузились, уже полученные разделы остаются на экране и в кэше, а интерфейс
показывает перечень секций с ошибкой. Любой ответ `401/403` завершает сессию.

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
| `OneValue` | Заголовок и одно значение | KPI без графика и детализации |
| `LinearProgressIndicator` | Линейный progress bar | Текущее `value` относительно `valueMax` |
| `BarMarkCompact` | Вертикальный `BarMark` | Компактное сравнение с отдельным экраном детализации |
| `Gauge`, `GaugeIndicator`, `Speedometer`, `CircularProgressIndicator` | Круговой индикатор | Доля текущего `value` от `valueMax` |
| `GeoMap`, `WorldMap`, `Map`, `GeoChoropleth` | Контурный хороплет мира | Распределение значений по странам |
| `PercentDonut`, `DonutPercent`, `SectorMarkPercent` | `SectorMark` с процентами | Доли с процентными подписями |
| `LineMark`, `LineChart`, `Line` | `LineMark` | Линейная динамика по категориям |
| `AreaMark`, `AreaChart`, `Area` | `AreaMark` и `LineMark` | Динамика с заливкой области |
| `SplineLineMark`, `SmoothLineMark` | Сглаженный `LineMark` | Плавная линейная динамика |
| `SplineAreaMark`, `LayeredAreaMark`, `SmoothAreaMark` | Сглаженные `AreaMark` | Плавные наложенные области |
| `ForecastLineMark`, `PredictionLineMark` | Сплошной и пунктирный `LineMark` | Факт и прогноз с `forecastFromIndex` |

Неизвестный тип отображается как обычный `BarMark`, чтобы изменение серверного
контракта не делало всю секцию недоступной.

Новые поля цвета принимаются в hex-формате (`#RRGGBB` или `#RRGGBBAA`):

- `colorGraph` задаёт цвет графика; у строк `values` он может отличаться;
- `colorValue` задаёт цвет числового значения;
- если поле отсутствует или некорректно, используется встроенная палитра.

Для `LinearProgressIndicator` фон показывает весь диапазон `valueMax` приглушённым
`colorGraph`, а заполненная часть соответствует отношению `value / valueMax`.

Для `BarMarkCompact` элементы `subgroup` сохраняются даже при пустом `group` и
выводятся как самостоятельные столбцы с подписями из `subgroup.name`.
Поле `group` может быть строкой или числом (например, год `2026`); числовое
значение преобразуется в строковую подпись оси.

Для `Gauge` значение и максимум берутся из первой записи `values`. Заполнение
кольца равно `value / valueMax`.

Для `GeoMap` поле `group` содержит русское название страны, а `value` —
количество. Клиент сопоставляет названия с упрощёнными границами Natural Earth
и рисует контурный хороплет через SwiftUI `Canvas`: все страны из API
закрашиваются с насыщенностью, пропорциональной значению. Тайлы, дороги,
географические подписи и жесты карты не используются; контур мира всегда
целиком вписывается в доступную область карточки и экрана детализации.

Дополнительные настройки показателя:

- `showLegend` управляет легендой; по умолчанию она показана, кроме `GeoMap`;
- `showTotal` управляет выводом агрегированного значения; значение по умолчанию
  `true`, для `GeoMap` — `false`;
- `showDetails` управляет переходом к детализации и по умолчанию равен `true`
  для всех типов, включая `OneValue`, `LinearProgressIndicator` и `Gauge`;
- `showValueLabels` управляет числовыми подписями элементов графика и по
  умолчанию равен `true`;
- `showYAxisLabels` по умолчанию равен `false` и включает подписи шкалы Y для
  линейных, площадных, сглаженных и прогнозных графиков;
- `detailsOrientation` по умолчанию равен `vertical` и переключает легенду
  карточки между вертикальным списком и адаптивной сеткой `horizontal`;
  список на экране детализации всегда остаётся вертикальным;
- `useCompactNumbers` включает системное локализованное сокращение чисел;
- `valueSpacing` принимает значение `0...64` и управляет расстоянием между
  значениями, а для кольцевых диаграмм — угловым зазором;
- `forecastFromIndex` задаёт первую прогнозную точку; без него прогнозными
  считаются последние 25% точек с округлением количества вверх;
- `widthPercent`, `width` или `halfWidth` декодируются для совместимости с
  контрактом, но не влияют на раскладку дашборда: на iPhone карточки всегда
  выводятся по одной в строке, а на iPad — по две независимо от переданной ширины.

Поддерживаются алиасы:

- `show_total`, `displayTotal` для `showTotal`;
- `show_details`, `displayDetails` для `showDetails`;
- `showLabels`, `displayValueLabels` для `showValueLabels`;
- `showYAxis`, `showScale`, `displayYAxisLabels` для `showYAxisLabels`;
- `detailOrientation`, `detailsLayout` для `detailsOrientation`;
- `useAbbreviations`, `compactValues`, `abbreviateValues` для
  `useCompactNumbers`;
- `valueGap`, `itemSpacing` для `valueSpacing`.

Внутри элемента `values` поле `totalLabel` может переопределить вычисленную
сумму группы произвольной строкой. Его алиасы — `displayTotal` и `totalValue`.
Поле `group`, а также алиасы `name` и `title`, задают подпись категории.
Если графический показатель содержит несколько числовых элементов без этих
полей, клиент сохраняет каждый элемент как отдельную точку с порядковой
подписью. Это важно, например, для двух значений среднего балла ЕГЭ: они не
должны ошибочно сворачиваться в единственный итог.

Поле `valueLabel` задаёт собственный отображаемый текст отдельного значения,
не изменяя числовое `value`, которое используется для расчёта геометрии и долей.
Внутри `subgroup` поддерживаются алиасы `displayValue`, `displayLabel` и
`totalLabel`.

При `showValueLabels: false` подписи отдельных
сегментов и выбранного значения скрываются, но групповой итог остаётся видимым.
При `showValueLabels: true` числовые подписи выводятся для всех поддерживаемых
типов графиков, включая круговые, линейные и площадные диаграммы.

Для вертикальных гистограмм клиент всегда резервирует место над максимальным
столбцом. Это обязательный инвариант отображения: ограничение высоты или
обрезание карточки не должно скрывать числовые подписи.

Если одна категория содержит несколько `subgroup`, детализация выводит их
отдельными параметрами. Значения разных параметров не складываются: групповой и
общий итоги скрываются, а доля рассчитывается внутри соответствующего параметра.

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
          "type": "BarMarkHorizon"
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
    let sections: [DashboardSection]
}

struct DashboardSection: Identifiable, Decodable {
    let id: String
    let title: String
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
    case compactBar = "BarMarkCompact"
    case horizontalBar = "BarMarkHorizon"
    case stackedBar = "BarMarkStacking"
    case donut = "SectorMarkInnerRadius"
    case oneValue = "OneValue"
    case linearProgress = "LinearProgressIndicator"
    case gauge = "Gauge"
    case geoMap = "GeoMap"
}
```

Все элементы корневого массива `sections` сохраняются в исходном порядке и
выводятся отдельными блоками с заголовками. Старый кэш, содержащий только
`Dashboard.indicators`, преобразуется в один раздел при чтении.

Один запрос секции может вернуть `values` как массив или как одиночный объект.
Для вложенных серий принимаются оба ключа: `subgroup` и `values`. Числа могут
приходить JSON-числами либо строками с пробелами, неразрывными пробелами и
десятичной запятой.

Стабильный идентификатор карточки выбирается в порядке `id`, `identifier`,
индекс в секции. Повторы получают суффикс `#N`, поэтому SwiftUI не теряет
карточки с одинаковым серверным идентификатором.

Для показателей API может возвращать список `subgroup`. Поле `group` всегда
остаётся основной категорией оси, а каждая запись `subgroup` становится
отдельной серией в `IndicatorRow.series`. Эта форма данных типизирована как
`BarChartDataShape.multipleValuesPerGroup` и одинаково поддерживается
`BarMark` и `BarMarkHorizon`: значения одной основной группы располагаются
рядом, цвет и легенда определяются серией. Для `BarMarkStacking` те же серии
складываются внутри основной группы.

`fetchedAt` — локальное время успешного получения ответа, а не дата среза данных в 1С. Пока API не возвращает дату среза, интерфейс подписывает это значение как «Получено».

## Open Questions

- Будет ли API возвращать дату среза.
- Какие ошибки возвращаются при пустых данных, отсутствии доступа и недоступности 1С.
