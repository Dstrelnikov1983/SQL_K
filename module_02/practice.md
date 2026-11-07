# Модуль 2. Практическая работа «Типы данных и встроенные функции»

> Курс «Углублённый SQL» · сквозной пример «Питание +» · PostgreSQL 16 (Yandex Managed Service for PostgreSQL)

## Цель

Научиться выбирать и преобразовывать типы данных, избегать типовых ловушек (целочисленное деление,
погрешность `float`, ведущие нули, локаль), применять математические, строковые функции, функции даты/времени
и выражение `CASE` для подготовки данных к анализу.

## Формат и время

| Часть | Содержание | Время |
|---|---|---|
| Шаги 1–3 | типы данных, преобразования, ловушки | 25 мин |
| Шаги 4–5 | математические функции, NULLIF | 15 мин |
| Шаги 6–8 | строковые функции, нормализация контактов и названий | 25 мин |
| Шаги 9–12 | дата и время, интервалы, to_char, generate_series | 25 мин |
| Шаг 13 | CASE, «светофоры» | 10 мин |

Преподаватель показывает шаг → слушатели повторяют у себя → обсуждаем вопрос «Подумайте».
Все запросы — в файле [`examples.sql`](examples.sql) (номера разделов совпадают).
Запросы, помеченные `-- ОЖИДАЕМАЯ ОШИБКА`, демонстрируют ошибку намеренно.

## Подготовка

```sql
SET search_path TO pitanie, public;
SET lc_time = 'ru_RU.UTF-8';          -- русские названия месяцев и дней в to_char (шаг 11)
SELECT version();                      -- PostgreSQL 16.x
```

> В DBeaver интервалы и массивы отображаются корректно. В некоторых клиентах (например, драйверах Python)
> `interval` выводится как «6200 days» — для точного текста используйте `::text`.

---

## Шаг 1. Какие типы хранятся в таблицах

```sql
SELECT column_name, data_type, numeric_precision, numeric_scale, is_nullable
FROM   information_schema.columns
WHERE  table_schema = 'pitanie'
  AND  table_name   = 'order_items'
ORDER  BY ordinal_position;
```

**Ожидаемый результат:** `quantity` — `integer`, `unit_price` — `numeric(10,2)`, `discount_pct` — `numeric(5,2)`.

Узнать тип любого выражения — `pg_typeof`:

```sql
SELECT pg_typeof(42), pg_typeof(42.0), pg_typeof(DATE '2025-12-31'), pg_typeof(now());
-- integer | numeric | date | timestamp with time zone
```

| Группа | Типы PostgreSQL | Где в «Питание +» |
|---|---|---|
| Целые | `smallint`, `integer`, `bigint` | количества, идентификаторы |
| Точные дробные | `numeric(p,s)` | деньги, скидки, рейтинг |
| Приближённые | `real`, `double precision` | (не используются — и правильно) |
| Строки | `char(n)`, `varchar(n)`, `text` | названия, ИНН, телефоны |
| Дата/время | `date`, `timestamp`, `timestamptz`, `interval` | даты заказов, простои |
| Логический | `boolean` | `products.is_active` |
| Прочие | `uuid`, `json/jsonb`, массивы | обзорно |

## Шаг 2. numeric против float

```sql
SELECT 0.1::float8 + 0.2::float8           AS float_sum,    -- 0.30000000000000004
       0.1::float8 + 0.2::float8 = 0.3     AS float_eq,     -- false
       0.1::numeric + 0.2::numeric = 0.3   AS numeric_eq;   -- true
```

```sql
SELECT 1234.5::numeric(5,2);   -- ОЖИДАЕМАЯ ОШИБКА: numeric field overflow (максимум 999.99)
```

> **Подумайте.** Почему деньги никогда не хранят во `float`? Что будет с суммой 4,5 тыс. счетов?

Строки: `char(n)` дополняет пробелами, `varchar(n)` ограничивает длину, явный `::varchar(5)` **молча обрезает**:

```sql
SELECT 'Слишком длинное значение'::varchar(5);   -- 'Слишк'
SELECT OCTET_LENGTH('АБВ');                      -- 6 байт (UTF-8: кириллица — 2 байта на символ)
```

Обзорно — `uuid`, `jsonb`, массивы:

```sql
SELECT gen_random_uuid()                                            AS new_uuid,
       '{"sku": "SYR-001", "price": 189}'::jsonb ->> 'sku'          AS json_sku,
       (ARRAY[7, 10, 14])[2]                                        AS second_elem,   -- 10
       string_to_array('День;Ночь', ';')                            AS shifts;
```

## Шаг 3. Преобразование типов и его ловушки

```sql
SELECT CAST('2025-03-01' AS date)   AS by_cast,      -- стандарт SQL
       '2025-03-01'::date           AS by_colons,    -- PostgreSQL
       '42'::integer + 1            AS str_to_int;   -- 43
```

Ошибки преобразования:

```sql
SELECT 'abc'::integer;          -- ОЖИДАЕМАЯ ОШИБКА: invalid input syntax for type integer
SELECT '2025-02-30'::date;      -- ОЖИДАЕМАЯ ОШИБКА: date/time field value out of range
SELECT 3000000000::integer;     -- ОЖИДАЕМАЯ ОШИБКА: integer out of range
```

ИНН — строка, а не число:

```sql
SELECT customer_id, inn, inn::bigint AS inn_as_number
FROM   customers
WHERE  inn LIKE '0%';
```

**Ожидаемый результат:** 5 клиентов; `0152338412` превращается в `152338412` — ИНН испорчен.

**Целочисленное деление** — главная ловушка модуля:

```sql
SELECT 7 / 2, 7 / 2.0, 7::numeric / 2, -7 / 2;     -- 3 | 3.5000 | 3.5000 | -3
```

```sql
SELECT batch_number,
       defect_qty,
       produced_qty,
       defect_qty / produced_qty                    AS wrong_share,    -- 0
       100 * defect_qty / produced_qty              AS wrong_pct_int,  -- 2
       ROUND(100.0 * defect_qty / produced_qty, 2)  AS right_pct       -- 2.06
FROM   production_batches
ORDER  BY batch_id
LIMIT  5;
```

**Ожидаемый результат (первая строка):** `П240101-1Д | 19 | 922 | 0 | 2 | 2.06`.

> **Подумайте.** Если в отчёте «доля брака» у всех партий 0 — какой тип у числителя и знаменателя?

**Округление** зависит от типа:

```sql
SELECT ROUND(2.5), ROUND(3.5), ROUND(2.5::float8), ROUND(3.5::float8), ROUND(-2.5);
-- 3 | 4 | 2 | 4 | -3      numeric — «от нуля», float8 — к ближайшему чётному
SELECT ROUND(2.567::float8, 1);            -- ОЖИДАЕМАЯ ОШИБКА: round(double precision, integer) не существует
SELECT ROUND(2.567::float8::numeric, 1);   -- 2.6
```

**Форматные функции** `to_char / to_number / to_date` зависят от `lc_numeric`:

```sql
SELECT to_char(1245137.26, 'FM999G999G990D00');      -- 1,245,137.26  (lc_numeric = en_US)
SET lc_numeric = 'ru_RU.UTF-8';
SELECT to_char(1245137.26, 'FM999G999G990D00'),      -- 1 245 137,26
       to_number('1 245 137,26', '9G999G999D99');    -- 1245137.26
RESET lc_numeric;
SELECT to_date('08.03.2025', 'DD.MM.YYYY'),          -- 2025-03-08
       to_date('240101', 'YYMMDD');                  -- 2024-01-01
```

## Шаг 4. Математические функции

```sql
SELECT ROUND(189.456, 2)      AS round_2,          -- 189.46
       ROUND(1622899.67, -3)  AS round_thousands,  -- 1623000
       TRUNC(189.456, 1)      AS trunc_1,          -- 189.4
       CEIL(2.1), FLOOR(-2.1), ABS(-15),           -- 3 | -3 | 15
       POWER(1.1, 3), MOD(17, 5), SIGN(-3.2);      -- 1.331 | 2 | -1
```

`GREATEST / LEAST` — максимум/минимум **внутри строки** (не путать с агрегатами `MAX/MIN`):

```sql
SELECT oi.order_item_id,
       ROUND(oi.unit_price * (1 - oi.discount_pct / 100), 2)                         AS net_price,
       p.standard_cost,
       GREATEST(ROUND(oi.unit_price * (1 - oi.discount_pct / 100), 2), p.standard_cost) AS floor_price
FROM   order_items AS oi
JOIN   products    AS p ON p.product_id = oi.product_id
WHERE  oi.product_id = 13
ORDER  BY oi.order_item_id
LIMIT  5;
```

**Ожидаемый результат:** `net_price` 165,22 / 174,11 / 177,66 — всё ниже себестоимости 205,00.

`CEIL` на практике — сколько коробок по 12 шт.:

```sql
SELECT quantity, CEIL(quantity / 12.0) AS boxes, quantity / 12 AS wrong_boxes
FROM   order_items ORDER BY order_item_id LIMIT 3;   -- 732 → 61/61; 595 → 50/49 (!)
```

`random()` и воспроизводимость:

```sql
SELECT setseed(0.42);
SELECT ROUND(random()::numeric, 6);       -- после setseed значение повторяется
```

## Шаг 5. Деление на ноль и NULLIF

В `material_writeoffs` 7 списаний с `quantity = 0`:

```sql
SELECT amount / quantity FROM material_writeoffs WHERE writeoff_id = 16;   -- ОЖИДАЕМАЯ ОШИБКА: division by zero

SELECT writeoff_id, quantity, amount,
       ROUND(amount / NULLIF(quantity, 0), 2) AS unit_cost
FROM   material_writeoffs
WHERE  writeoff_id IN (2, 16);
-- 2  | 77.20 | 25610.22 | 331.74
-- 16 | 0.00  | 0.00     | NULL
```

## Шаг 6. Строковые функции: длина, регистр, пробелы

```sql
SELECT customer_id,
       '[' || email || ']'          AS raw_email,
       LENGTH(email)                AS len_raw,
       LOWER(TRIM(email))           AS clean_email,
       LENGTH(LOWER(TRIM(email)))   AS len_clean
FROM   customers
WHERE  customer_id IN (1, 5, 12);
```

**Ожидаемый результат:** `[ zakaz.5@company.ru ]` — длина 20 → 18 после `TRIM`.

```sql
SELECT UPPER('ооо "Свежесть"'),          -- ООО "СВЕЖЕСТЬ"
       INITCAP('комаров илья петрович'), -- Комаров Илья Петрович
       TRIM(BOTH '"' FROM '"Колос"');    -- Колос
```

## Шаг 7. Разбор строк: SUBSTRING, SPLIT_PART, POSITION

Номер партии `П240101-1Д` = «П» + дата `YYMMDD` + «-» + линия + смена (Д/Н).

```sql
SELECT batch_number,
       SUBSTRING(batch_number FROM 2 FOR 6)  AS date_code,     -- 240101
       SPLIT_PART(batch_number, '-', 2)      AS line_shift,    -- 1Д
       RIGHT(batch_number, 1)                AS shift_letter,  -- Д
       POSITION('-' IN batch_number)         AS dash_pos       -- 8
FROM   production_batches
ORDER  BY batch_id
LIMIT  4;
```

## Шаг 8. Регулярные выражения: телефоны и названия

```sql
SELECT customer_id,
       phone,
       regexp_replace(phone, '\D', '', 'g')                      AS digits_only,
       '+7' || RIGHT(regexp_replace(phone, '\D', '', 'g'), 10)   AS phone_norm
FROM   customers
WHERE  customer_id IN (1, 2, 5, 6);
```

**Ожидаемый результат:** `8 (988) 214 52 93` → `+79882145293`; `+7 (986) 210-81-33` → `+79862108133`.

Нормализация названия для поиска дублей:

```sql
SELECT customer_id,
       customer_name,
       TRIM(regexp_replace(
                regexp_replace(UPPER(customer_name),
                               '\m(ООО|АО|ИП)\M|"|\(ДУБЛЬ\)', '', 'g'),
                '\s+', ' ', 'g')) AS name_norm
FROM   customers
WHERE  inn IN ('7924695572', '8423916122', '562810604315')
ORDER  BY inn, customer_id;
```

**Ожидаемый результат:** «ООО "Ромашка"», «Ромашка ООО», «ООО  "РОМАШКА"» → `РОМАШКА`;
но «ИП Иванов (Колос)» → `ИВАНОВ (КОЛОС)`, а «ООО "Колос" (дубль)» → `КОЛОС`.

> **Подумайте.** Почему нормализация названия не находит все дубли и чем ИНН надёжнее? А в каких случаях ИНН тоже подведёт?

Склейка строк и NULL:

```sql
SELECT supplier_name || ' / ' || phone              AS by_pipes,       -- NULL для поставщика 12
       CONCAT(supplier_name, ' / ', phone)           AS by_concat,
       CONCAT_WS(' / ', supplier_name, phone, inn)   AS by_concat_ws,
       format('%s (рейтинг %s)', supplier_name, COALESCE(rating::text, 'нет')) AS by_format
FROM   suppliers
WHERE  supplier_id IN (1, 12);
```

## Шаг 9. Дата и время: текущие значения, EXTRACT, date_trunc

```sql
SELECT CURRENT_DATE, NOW(), LOCALTIMESTAMP, current_setting('TimeZone');   -- Europe/Moscow
```

> Данные «Питание +» заканчиваются 31.12.2025. Для воспроизводимых отчётов используйте **фиксированную дату среза**
> (`DATE '2025-12-31'`), а не `CURRENT_DATE`.

```sql
SELECT order_date,
       EXTRACT(YEAR FROM order_date)    AS y,
       EXTRACT(QUARTER FROM order_date) AS q,
       EXTRACT(ISODOW FROM order_date)  AS iso_dow,    -- 3 (среда)
       date_part('week', order_date)    AS iso_week    -- 1 (!) — ISO-неделя 2026 года
FROM   orders
WHERE  order_id = 4458;                                -- 2025-12-31
```

```sql
SELECT start_time,
       date_trunc('month', start_time) AS month_start,   -- 2025-04-01 00:00:00
       date_trunc('week',  start_time) AS week_start     -- 2025-04-07 00:00:00 (понедельник)
FROM   equipment_downtime
WHERE  downtime_id = 148;
```

## Шаг 10. Арифметика дат и интервалы

```sql
-- date − date = integer (дни)
SELECT order_number, shipped_date - order_date AS lead_days
FROM   orders WHERE order_id IN (1, 2, 3);           -- 5, 1, 2

-- timestamp − timestamp = interval
SELECT downtime_id,
       (end_time - start_time)::text                              AS duration,
       ROUND(EXTRACT(EPOCH FROM end_time - start_time) / 3600, 2) AS hours
FROM   equipment_downtime
WHERE  end_time IS NOT NULL
ORDER  BY end_time - start_time DESC
LIMIT  3;
-- 148 | 14:52:00 | 14.87
```

```sql
SELECT DATE '2025-01-31' + INTERVAL '1 month'          AS jan31_plus_month,   -- 2025-02-28 00:00:00
       DATE '2025-12-31' + 30                          AS plus_30_days,       -- 2026-01-30
       AGE(DATE '2025-12-31', DATE '2009-01-01')::text AS line2_age;          -- 16 years 11 mons 30 days
```

Незакрытые простои — подставляем дату среза через `COALESCE`:

```sql
SELECT downtime_id, line_id, start_time,
       (COALESCE(end_time, TIMESTAMP '2026-01-01 00:00') - start_time)::text AS open_duration
FROM   equipment_downtime
WHERE  end_time IS NULL;
-- 12 | 3 | 2024-02-06 20:15:00 | 694 days 03:45:00
```

## Шаг 11. to_char на русском

```sql
SET lc_time = 'ru_RU.UTF-8';
SELECT to_char(DATE '2025-03-08', 'DD.MM.YYYY')              AS ru_numeric,   -- 08.03.2025
       to_char(DATE '2025-03-08', 'TMDay, DD TMMonth YYYY')  AS ru_long,      -- Суббота, 08 Марта 2025
       to_char(DATE '2025-03-08', 'TMMon YYYY')              AS ru_short,     -- Мар 2025
       to_char(DATE '2025-03-08', 'YYYY-"Q"Q')               AS year_quarter; -- 2025-Q1
```

Префикс `TM` (translation mode) берёт названия из `lc_time`; без него — английские (`Saturday`, `March`).
Без `FM` названия дополняются пробелами до фиксированной ширины.

## Шаг 12. generate_series — календарь

```sql
SELECT d::date                          AS day,
       to_char(d, 'TMDy')               AS dow,
       EXTRACT(ISODOW FROM d) IN (6, 7) AS is_weekend
FROM   generate_series(DATE '2025-12-01', DATE '2025-12-31', INTERVAL '1 day') AS d;
```

**Ожидаемый результат:** 31 строка, `2025-12-01 | Пн | false`, `2025-12-06 | Сб | true`.
Календарь пригодится в модулях 3–4: «дни без отгрузок», «месяцы без продаж» (LEFT JOIN к календарю).

## Шаг 13. CASE

```sql
SELECT batch_number, line_id, shift,
       ROUND(100.0 * defect_qty / NULLIF(produced_qty, 0), 2) AS defect_pct,
       CASE
           WHEN 100.0 * defect_qty / NULLIF(produced_qty, 0) >= 5 THEN 'красный'
           WHEN 100.0 * defect_qty / NULLIF(produced_qty, 0) >= 2 THEN 'жёлтый'
           ELSE 'зелёный'
       END AS traffic_light
FROM   production_batches
WHERE  production_date = DATE '2025-06-02'
ORDER  BY line_id, shift;
```

**Ожидаемый результат:** 10 партий; «красный» только у `П250602-3Н` (6,25 %).

> **Подумайте.** Порядок веток `WHEN` важен: что будет, если поставить условие `>= 2` первым?

---

## Типичные ошибки

| Ошибка | Симптом | Как правильно |
|---|---|---|
| `int / int` | доля = 0, проценты «ступеньками» | `100.0 * a / b`, `a::numeric / b` |
| Деньги во `float` | копейки «плывут», `=` не работает | `numeric(p,s)` |
| ИНН/телефон как число | потеря ведущих нулей, `+` | хранить как `varchar`/`text` |
| `ROUND(float8, n)` | функция не найдена | `ROUND(x::numeric, n)` |
| Деление на 0 | `division by zero` | `NULLIF(b, 0)` |
| `CURRENT_DATE` в отчёте | цифры меняются каждый день | фиксированная дата среза |
| `to_char` без `TM` | английские месяцы | `TMMonth`, `SET lc_time` |
| `'…' || NULL` | вся строка NULL | `CONCAT`, `CONCAT_WS`, `COALESCE` |

## Контрольные вопросы

1. Какой тип вернут выражения `DATE '2025-12-31' - DATE '2025-12-01'` и `TIMESTAMP '…' - TIMESTAMP '…'`?
2. Почему `ROUND(2.5)` и `ROUND(2.5::float8)` дают разные результаты?
3. Как получить длительность простоя в часах с двумя знаками после запятой?
4. Чем `CONCAT_WS` удобнее `||` при сборке адреса или контакта?
5. Почему `date_part('week', DATE '2025-12-31')` = 1?
