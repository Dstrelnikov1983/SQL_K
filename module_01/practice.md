# Модуль 1. Практическая работа «Сортировка и фильтрация в запросах»

> Курс «Углублённый SQL» · сквозной пример «Питание +» · PostgreSQL 16 (Yandex Managed Service for PostgreSQL)

## Цель

Научиться точно отбирать и упорядочивать строки: строить условия `WHERE` с учётом приоритета
логических операторов, применять `IN`, `BETWEEN`, `LIKE / ILIKE`, корректно работать с `NULL`,
сортировать по нескольким ключам и выражениям, ограничивать выборку (`LIMIT`, `FETCH FIRST … WITH TIES`)
и выводить данные постранично.

## Формат и время

| Часть | Кто выполняет | Время |
|---|---|---|
| Шаги 1–4: WHERE, логика, предикаты | преподаватель показывает → слушатели повторяют | 20 мин |
| Шаги 5–7: NULL | преподаватель показывает → слушатели повторяют | 15 мин |
| Шаги 8–10: ORDER BY, LIMIT/FETCH, пагинация | преподаватель показывает → слушатели повторяют | 15 мин |

Все запросы — в файле [`examples.sql`](examples.sql) (номера разделов совпадают с шагами).

## Подготовка

1. Подключитесь к учебной БД (DBeaver / pgAdmin / psql). Параметры — в [`common/README.md`](../common/README.md),
   SSL-сертификат `root.crt` — в корне репозитория.
2. Выполните первой командой:

```sql
SET search_path TO pitanie, public;
```

3. Проверьте подключение:

```sql
SELECT COUNT(*) FROM orders;      -- ожидается 4458
```

> Схема `pitanie` доступна только для чтения. В этом модуле мы ничего не создаём и не изменяем.

---

## Шаг 1. Базовая фильтрация WHERE

Отберите заказы декабря 2025 года. Обратите внимание на **полуоткрытый интервал** `>= начало AND < следующий период`.

```sql
SELECT order_id,
       order_number,
       order_date,
       status
FROM   orders
WHERE  order_date >= DATE '2025-12-01'
  AND  order_date <  DATE '2026-01-01'
ORDER  BY order_date, order_id
LIMIT  10;
```

**Ожидаемый результат:** первые строки — `ЗК-2025-04241 … 04247` от 2025-12-01, статус «Доставлен».

Теперь — позиции со скидкой выше политики компании (10 %):

```sql
SELECT COUNT(*) AS items_over_policy
FROM   order_items
WHERE  discount_pct > 10;
```

**Ожидаемый результат:** `4365` позиций из 17 576.

> **Подумайте.** Почему для дат лучше писать `>= '2025-12-01' AND < '2026-01-01'`, а не `BETWEEN '2025-12-01' AND '2025-12-31'`?
> (Ответ — в шаге 3.)

## Шаг 2. Приоритет логических операторов

Порядок вычисления: **`NOT` → `AND` → `OR`**. Нужно: заказы менеджера 10 по каналам «Дистрибуция» или «Тендер».

```sql
-- без скобок — логическая ошибка
SELECT COUNT(*) AS wrong_cnt
FROM   orders
WHERE  employee_id = 10
  AND  channel = 'Дистрибуция'
   OR  channel = 'Тендер';
```

```sql
-- со скобками / через IN — правильно
SELECT COUNT(*) AS right_cnt
FROM   orders
WHERE  employee_id = 10
  AND  channel IN ('Дистрибуция', 'Тендер');
```

**Ожидаемый результат:** `690` против `651`. Лишние 39 строк — тендерные заказы **других** менеджеров.

> **Типичная ошибка.** Смешивать `AND` и `OR` без скобок. Правило команды: если в условии есть `OR` — ставим скобки всегда.

## Шаг 3. IN и BETWEEN

```sql
SELECT COUNT(*) AS cnt_12_18
FROM   order_items
WHERE  discount_pct BETWEEN 12 AND 18;      -- границы ВКЛЮЧАЮТСЯ
```

**Ожидаемый результат:** `2624`.

Ловушка `BETWEEN` с `timestamp`: правая граница `'2025-07-28'` — это `2025-07-28 00:00:00`.

```sql
SELECT COUNT(*) AS between_cnt
FROM   equipment_downtime
WHERE  start_time BETWEEN '2025-07-01' AND '2025-07-28';    -- 13

SELECT COUNT(*) AS halfopen_cnt
FROM   equipment_downtime
WHERE  start_time >= '2025-07-01'
  AND  start_time <  '2025-07-29';                          -- 15
```

**Ожидаемый результат:** `13` и `15` — два простоя, начавшиеся днём 28 июля, «потерялись».

## Шаг 4. LIKE, ILIKE, регулярные выражения

| Шаблон | Значение |
|---|---|
| `%` | любая последовательность символов (в т. ч. пустая) |
| `_` | ровно один символ |
| `\%`, `\_` | буквальные `%` и `_` |
| `ILIKE` | как `LIKE`, но без учёта регистра (PostgreSQL) |
| `~`, `~*` | регулярное выражение POSIX (с учётом / без учёта регистра) |

```sql
SELECT sku, product_name
FROM   products
WHERE  sku LIKE 'KSM-00_'
ORDER  BY sku;                                -- 8 строк: KSM-001 … KSM-008
```

Сравните `LIKE` и `ILIKE` на комментариях к заказам (там встречаются «акция» и «Акция -10%»):

```sql
SELECT COUNT(*) FILTER (WHERE comment LIKE  '%акция%') AS like_cnt,
       COUNT(*) FILTER (WHERE comment ILIKE '%акция%') AS ilike_cnt
FROM   orders;
```

**Ожидаемый результат:** `234` и `452`.

Найдите «грязные» email клиентов — с пробелами по краям или не в нижнем регистре:

```sql
SELECT customer_id,
       customer_name,
       '[' || email || ']' AS email_visible
FROM   customers
WHERE  email LIKE ' %'
   OR  email LIKE '% '
   OR  email <> LOWER(email)
ORDER  BY customer_id;
```

**Ожидаемый результат:** 32 строки, например `[ZAKAZ.1@YANDEX.RU]`, `[ zakaz.5@company.ru ]`.
Квадратные скобки — приём, чтобы «увидеть» пробелы.

Телефоны строго в формате `+7XXXXXXXXXX`:

```sql
SELECT customer_id, phone
FROM   customers
WHERE  phone ~ '^\+7[0-9]{10}$'
ORDER  BY customer_id;
```

> **Подумайте.** Почему поиск `LIKE '%ромашк%'` не найдёт `ООО  "РОМАШКА"`, а `ILIKE` найдёт? Чем это грозит аналитике по клиентам?

## Шаг 5. NULL и трёхзначная логика

```sql
SELECT COUNT(*) AS eq_null FROM customers WHERE region_id = NULL;   -- 0 (!)
SELECT customer_id, customer_name FROM customers WHERE region_id IS NULL;   -- 3 строки: 19, 54, 67
```

```sql
SELECT NULL = NULL       AS eq,        -- NULL
       TRUE  AND NULL    AS t_and_n,   -- NULL
       FALSE AND NULL    AS f_and_n,   -- FALSE
       TRUE  OR  NULL    AS t_or_n;    -- TRUE
```

`WHERE` пропускает строку, только если условие = `TRUE`. `FALSE` и `NULL` (UNKNOWN) — отбрасываются.

```sql
SELECT COUNT(*)                                  AS total,      -- 73
       COUNT(*) FILTER (WHERE region_id = 1)     AS reg_1,      -- 13
       COUNT(*) FILTER (WHERE region_id <> 1)    AS not_reg_1,  -- 57
       COUNT(*) FILTER (WHERE region_id IS NULL) AS reg_null    -- 3
FROM   customers;
```

13 + 57 = 70 ≠ 73: три клиента без региона не попали ни в «=», ни в «<>».

## Шаг 6. IS DISTINCT FROM, COALESCE, NULLIF

```sql
SELECT COUNT(*) FILTER (WHERE quality_status <> 'Принято')               AS by_ne,        -- 86
       COUNT(*) FILTER (WHERE quality_status IS DISTINCT FROM 'Принято') AS by_distinct   -- 94
FROM   purchase_order_items;
```

8 позиций ещё не получены (`quality_status IS NULL`) — `<>` их «не видит».

```sql
SELECT customer_name,
       COALESCE(email, '(нет email)') AS email_or_stub
FROM   customers
WHERE  email IS NULL
LIMIT  5;

SELECT 100.0 * 5 / NULLIF(0, 0) AS safe_div;   -- NULL вместо ошибки деления на ноль
```

NULL «заражает» выражения: `'Поставщик: ' || supplier_name || ', тел. ' || phone` для поставщика 12 (телефон NULL) даёт `NULL`,
а `CONCAT(...)` — строку без телефона.

## Шаг 7. Ловушка NOT IN с NULL

```sql
SELECT COUNT(*) FROM customers WHERE region_id NOT IN (1, 2, NULL);   -- 0 (!)
SELECT COUNT(*) FROM customers WHERE region_id NOT IN (1, 2);         -- 51
```

`x NOT IN (1, 2, NULL)` ≡ `x <> 1 AND x <> 2 AND x <> NULL` → последнее слагаемое всегда `NULL` → всё условие никогда не `TRUE`.
В модуле 5 та же ловушка встретится с подзапросом `NOT IN (SELECT …)`, где NULL появляется незаметно.

## Шаг 8. ORDER BY: несколько ключей, выражения, NULL, COLLATE

```sql
SELECT customer_type, customer_name, credit_limit
FROM   customers
ORDER  BY customer_type ASC,
          credit_limit  DESC,
          customer_name
LIMIT  10;
```

Сортировка по выражению — позиции с наибольшей скидкой в рублях:

```sql
SELECT order_item_id,
       quantity,
       unit_price,
       discount_pct,
       ROUND(quantity * unit_price * discount_pct / 100, 2) AS discount_rub
FROM   order_items
ORDER  BY discount_rub DESC
LIMIT  5;
```

**Ожидаемый результат:** 1-я строка — позиция 9654, 88 200,00 руб.

NULL при сортировке: в PostgreSQL NULL считается «больше» всех значений:

```sql
SELECT supplier_name, rating FROM suppliers ORDER BY rating DESC;             -- «Специи и Ко» (NULL) ПЕРВЫЙ
SELECT supplier_name, rating FROM suppliers ORDER BY rating DESC NULLS LAST;  -- первым «Сахарный комбинат Воронеж» 4.8
```

`COLLATE` меняет правила сравнения строк:

```sql
SELECT customer_name FROM customers WHERE customer_id IN (1, 9, 69, 70, 71)
ORDER  BY customer_name COLLATE "C";          -- побайтово: «ооо "Свежесть"» уходит в конец
```

## Шаг 9. TOP ↔ LIMIT ↔ FETCH FIRST, WITH TIES

| T-SQL | PostgreSQL |
|---|---|
| `SELECT TOP (5) …` | `… LIMIT 5` или `… FETCH FIRST 5 ROWS ONLY` |
| `TOP (5) WITH TIES` | `FETCH FIRST 5 ROWS WITH TIES` (нужен `ORDER BY`) |
| `OFFSET 40 ROWS FETCH NEXT 20 ROWS ONLY` | так же, или `LIMIT 20 OFFSET 40` |
| `TOP (10) PERCENT` | нет прямого аналога (оконные функции, модуль 8) |

```sql
SELECT invoice_number, invoice_date, amount
FROM   invoices
ORDER  BY amount DESC
FETCH  FIRST 5 ROWS ONLY;
```

**Ожидаемый результат:** первая строка `СЧ-2025-02646 | 2025-04-10 | 1245137.26`.

```sql
SELECT COUNT(*) AS with_ties_cnt
FROM  (SELECT order_item_id
       FROM   order_items
       ORDER  BY discount_pct DESC
       FETCH  FIRST 3 ROWS WITH TIES) AS t;
```

**Ожидаемый результат:** `869` — все позиции со скидкой 25 %, а не 3.

## Шаг 10. Постраничный вывод

```sql
-- страница 3 по 20 строк
SELECT order_id, order_number, order_date
FROM   orders
ORDER  BY order_date DESC, order_id DESC     -- уникальный «добивающий» ключ обязателен
OFFSET 40 ROWS
FETCH  NEXT 20 ROWS ONLY;
```

**Ожидаемый результат:** начинается с `4418 | ЗК-2025-04418 | 2025-12-26`.

Keyset-пагинация («после последней увиденной строки»):

```sql
SELECT order_id, order_number, order_date
FROM   orders
WHERE  (order_date, order_id) < (DATE '2025-12-29', 4433)
ORDER  BY order_date DESC, order_id DESC
LIMIT  5;
```

**Ожидаемый результат:** `4432, 4431, 4430, 4429, 4428`.

Сравните планы (раздел 6.8 в `examples.sql`): `OFFSET 20000` читает 20 020 строк индекса, keyset — 20.
На учебной таблице разница ~1,7 мс против ~0,05 мс; на миллионах строк — секунды против миллисекунд.

---

## Типичные ошибки

| Ошибка | Симптом | Как правильно |
|---|---|---|
| `= NULL` / `<> NULL` | 0 строк | `IS NULL`, `IS NOT NULL`, `IS DISTINCT FROM` |
| `AND`/`OR` без скобок | «лишние» строки | скобки или `IN` |
| `BETWEEN` для `timestamp` | теряется последний день | `>= начало AND < конец` |
| `LIMIT` без `ORDER BY` | каждый раз разные строки | всегда `ORDER BY` + уникальный ключ |
| `NOT IN (…, NULL)` | 0 строк | убрать NULL / `NOT EXISTS` (модуль 5) |
| Сортировка «по алфавиту» с разным регистром | дубли «разбросаны» | `ILIKE`, `LOWER()`, `COLLATE` |

## Контрольные вопросы

1. Чем отличается результат `WHERE NOT (a = 1)` от «все строки, кроме a = 1», если в `a` есть NULL?
2. Когда `FETCH FIRST n ROWS WITH TIES` вернёт больше `n` строк?
3. Почему OFFSET-пагинация замедляется на дальних страницах и может «терять» строки при вставке новых данных?
4. Какой предикат вернёт клиентов, у которых `region_id` не равен 1, **включая** клиентов без региона?
