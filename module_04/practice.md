# Модуль 4. Практическая работа «Группирование и агрегирование данных»

| Параметр | Значение |
|---|---|
| Цель | Освоить агрегатные функции, GROUP BY, HAVING, FILTER, ROLLUP / CUBE / GROUPING SETS и избежать типичных ошибок агрегации |
| Время | 60 минут (демонстрация преподавателя + повторение слушателями) |
| Формат | Преподаватель показывает шаг → слушатели повторяют → короткое обсуждение результатов |
| Файл с кодом | [`examples.sql`](examples.sql) — разделы 1–7 |

## Подготовка

```sql
SET search_path TO pitanie, public;
```

Формула выручки строки заказа (используется во всех шагах; отменённые заказы исключаем):

```sql
oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)
```

---

## Шаг 1. COUNT(*), COUNT(столбец), COUNT(DISTINCT)

```sql
SELECT COUNT(*)                  AS customers_total,
       COUNT(region_id)          AS with_region,
       COUNT(email)              AS with_email,
       COUNT(DISTINCT region_id) AS distinct_regions,
       COUNT(DISTINCT inn)       AS distinct_inn
FROM   customers;
```

**Ожидаемый результат:**

| customers_total | with_region | with_email | distinct_regions | distinct_inn |
|---|---|---|---|---|
| 73 | 70 | 52 | 12 | 69 |

> **Подумайте.** Клиентов 73, а различных ИНН — 69. О чём это говорит? (Подсказка: вернёмся к этому в шаге 6.)

---

## Шаг 2. Агрегаты и NULL

```sql
SELECT COUNT(*)                         AS suppliers,
       COUNT(rating)                    AS rated,
       ROUND(AVG(rating), 2)            AS avg_rating_ignore_null,
       ROUND(AVG(COALESCE(rating, 0)), 2) AS avg_coalesce_zero
FROM   suppliers;
```

**Ожидаемый результат:** `12 | 11 | 4.28 | 3.93`. `AVG` делит на число **не-NULL** значений (11). Подстановка 0 — это уже другое утверждение: «у нового поставщика рейтинг 0».

```sql
SELECT SUM(amount), COALESCE(SUM(amount), 0), COUNT(*)
FROM   payments
WHERE  payment_date > DATE '2030-01-01';
```

**Ожидаемый результат:** `NULL | 0 | 0`. SUM пустого набора — NULL, COUNT — 0.

---

## Шаг 3. Функции PostgreSQL: STRING_AGG, BOOL_AND, медиана

```sql
SELECT l.line_name,
       COUNT(DISTINCT b.product_id)                    AS products_cnt,
       STRING_AGG(DISTINCT p.sku, ', ' ORDER BY p.sku) AS skus
FROM   production_batches AS b
JOIN   production_lines   AS l ON l.line_id    = b.line_id
JOIN   products           AS p ON p.product_id = b.product_id
GROUP  BY l.line_id, l.line_name
ORDER  BY l.line_id;
```

**Ожидаемый результат:** 5 строк; на линиях выпускается 5, 7, 8, 9 и 6 SKU.

```sql
SELECT COUNT(*) FILTER (WHERE NOT all_in_policy) AS orders_with_violation
FROM  (SELECT order_id, BOOL_AND(discount_pct <= 10) AS all_in_policy
       FROM   order_items
       GROUP  BY order_id) AS t;
```

**Ожидаемый результат:** 1136 заказов из 4458 содержат хотя бы одну позицию со скидкой выше 10 %.

```sql
SELECT ROUND(AVG(amount), 2)                               AS avg_invoice,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount) AS median_invoice
FROM   invoices;
```

**Ожидаемый результат:** `193598.20 | 163852.09…` (у `PERCENTILE_CONT` тип `double precision` — оберните в `ROUND(…::numeric, 2)`).

> **Подумайте.** Почему средний счёт больше медианного? Какой показатель вы бы показали руководству как «типичный счёт»?

---

## Шаг 4. FILTER — условная агрегация

```sql
SELECT e.full_name,
       COUNT(*)                                     AS items,
       COUNT(*) FILTER (WHERE oi.discount_pct > 10) AS items_over_10,
       ROUND(AVG(oi.discount_pct), 2)               AS avg_discount
FROM   order_items AS oi
JOIN   orders      AS o ON o.order_id    = oi.order_id
JOIN   employees   AS e ON e.employee_id = o.employee_id
WHERE  o.status <> 'Отменён'
GROUP  BY e.employee_id, e.full_name
ORDER  BY items_over_10 DESC;
```

**Ожидаемый результат (первые строки):**

| full_name | items | items_over_10 | avg_discount |
|---|---|---|---|
| Соколов Игорь Андреевич | 4167 | 4167 | 18.01 |
| Попов Станислав Игоревич | 133 | 53 | 8.29 |
| Волков Денис Сергеевич | 893 | 0 | 2.84 |

`FILTER (WHERE …)` — стандарт SQL:2003, в PostgreSQL работает с любым агрегатом. Переносимый аналог — `SUM(CASE WHEN … THEN 1 ELSE 0 END)`.

---

## Шаг 5. GROUP BY по выражениям и нескольким столбцам

```sql
SELECT date_trunc('month', o.order_date)::date AS month,
       COUNT(DISTINCT o.order_id)              AS orders,
       ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100))) AS revenue
FROM   orders      AS o
JOIN   order_items AS oi ON oi.order_id = o.order_id
WHERE  o.status <> 'Отменён'
  AND  o.order_date >= DATE '2025-01-01'
GROUP  BY date_trunc('month', o.order_date)
ORDER  BY month;
```

**Ожидаемый результат:** 12 строк; минимум — июль 2025 (24,7 млн руб.), максимум — декабрь (44,7 млн).

> **Почему `COUNT(DISTINCT o.order_id)`?** После JOIN с `order_items` каждая строка — позиция, а не заказ. `COUNT(*)` посчитал бы позиции.

```sql
SELECT b.line_id,
       b.shift,
       SUM(b.produced_qty) AS produced,
       SUM(b.defect_qty)   AS defects,
       ROUND(100.0 * SUM(b.defect_qty) / SUM(b.produced_qty), 2) AS defect_pct
FROM   production_batches AS b
GROUP  BY b.line_id, b.shift
ORDER  BY b.line_id, b.shift;
```

**Ожидаемый результат:** 10 строк; выделяется **Линия 3, Ночь — 7.94 %** (в остальных ячейках 1,5–2,3 %).

---

## Шаг 6. WHERE vs HAVING и логический порядок выполнения

Логический порядок: `FROM/JOIN → WHERE → GROUP BY → HAVING → SELECT → DISTINCT → ORDER BY → LIMIT`.

```sql
SELECT e.full_name,
       ROUND(AVG(oi.discount_pct), 2) AS avg_discount
FROM   order_items AS oi
JOIN   orders      AS o ON o.order_id    = oi.order_id
JOIN   employees   AS e ON e.employee_id = o.employee_id
WHERE  o.status <> 'Отменён'          -- фильтр строк
GROUP  BY e.employee_id, e.full_name
HAVING AVG(oi.discount_pct) > 10;     -- фильтр групп
```

**Ожидаемый результат:** 1 строка — Соколов И. А., 18.01.

Выполните и **прочитайте сообщения об ошибках** (они ожидаемы):

```sql
-- агрегат в WHERE
SELECT o.employee_id, AVG(oi.discount_pct)
FROM   order_items AS oi JOIN orders AS o ON o.order_id = oi.order_id
WHERE  AVG(oi.discount_pct) > 10
GROUP  BY o.employee_id;
-- ERROR: aggregate functions are not allowed in WHERE

-- столбец не в GROUP BY
SELECT o.employee_id, o.customer_id, COUNT(*)
FROM   orders AS o
GROUP  BY o.employee_id;
-- ERROR: column "o.customer_id" must appear in the GROUP BY clause ...

-- псевдоним SELECT в HAVING
SELECT o.employee_id, COUNT(*) AS cnt
FROM   orders AS o
GROUP  BY o.employee_id
HAVING cnt > 100;
-- ERROR: column "cnt" does not exist
```

Дубли клиентов:

```sql
SELECT inn,
       COUNT(*) AS cards,
       STRING_AGG(customer_name, ' | ' ORDER BY customer_id) AS names
FROM   customers
GROUP  BY inn
HAVING COUNT(*) > 1;
```

**Ожидаемый результат:** 3 ИНН — «Ромашка» (3 карточки), «Колос» и «Свежесть» (по 2).

> **Подумайте.** Можно ли условие `HAVING inn LIKE '79%'` перенести в WHERE? А нужно ли? (Да — фильтр по столбцу группировки эффективнее в WHERE: меньше строк попадёт в группировку.)

---

## Шаг 7. ROLLUP и GROUPING()

```sql
SELECT CASE WHEN GROUPING(t.yr)  = 1 THEN 'ВСЕГО' ELSE t.yr::text END AS yr,
       CASE WHEN GROUPING(t.yr)  = 1 THEN ''
            WHEN GROUPING(t.qtr) = 1 THEN 'Итого за год'
            ELSE 'Q' || t.qtr END                                    AS qtr,
       ROUND(SUM(t.revenue) / 1e6, 2)                                AS revenue_mln
FROM  (SELECT EXTRACT(YEAR    FROM o.order_date)::int AS yr,
              EXTRACT(QUARTER FROM o.order_date)::int AS qtr,
              oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100) AS revenue
       FROM   orders AS o
       JOIN   order_items AS oi ON oi.order_id = o.order_id
       WHERE  o.status <> 'Отменён') AS t
GROUP  BY ROLLUP (t.yr, t.qtr)
ORDER  BY t.yr NULLS LAST, t.qtr NULLS LAST;
```

**Ожидаемый результат:**

| yr | qtr | revenue_mln |
|---|---|---|
| 2024 | Q1 | 94.97 |
| 2024 | Q2 | 86.42 |
| 2024 | Q3 | 98.22 |
| 2024 | Q4 | 104.41 |
| 2024 | Итого за год | 384.01 |
| 2025 | Q1 | 107.16 |
| … | … | … |
| 2025 | Итого за год | 445.11 |
| ВСЕГО | | 829.12 |

> **Почему GROUPING(), а не `IS NULL`?** NULL в строке подытога и NULL «в данных» (например, клиент без региона) неразличимы. `GROUPING(col) = 1` означает именно «это строка подытога по col».

---

## Шаг 8. CUBE и GROUPING SETS

```sql
SELECT CASE WHEN GROUPING(b.line_id) = 1 THEN 'Все линии' ELSE 'Линия ' || b.line_id END AS line,
       CASE WHEN GROUPING(b.shift)   = 1 THEN 'Обе смены' ELSE b.shift END              AS shift,
       ROUND(100.0 * SUM(b.defect_qty) / SUM(b.produced_qty), 2)                        AS defect_pct
FROM   production_batches AS b
GROUP  BY CUBE (b.line_id, b.shift)
ORDER  BY GROUPING(b.line_id), b.line_id, GROUPING(b.shift), b.shift;
```

**Ожидаемый результат:** 18 строк (10 + 5 + 2 + 1). Итог компании — 2.52 %, ночные смены в целом — 3.37 %, дневные — 1.74 %. Без разбивки по линиям «ночная проблема» выглядит общей, с разбивкой — видно, что это одна ячейка.

```sql
SELECT o.channel,
       c.customer_type,
       ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) / 1e6, 2) AS revenue_mln
FROM   orders AS o
JOIN   order_items AS oi ON oi.order_id   = o.order_id
JOIN   customers   AS c  ON c.customer_id = o.customer_id
WHERE  o.status <> 'Отменён'
  AND  o.order_date >= DATE '2025-01-01'
GROUP  BY GROUPING SETS ((o.channel), (c.customer_type), ());
```

**Ожидаемый результат:** 11 строк: 4 канала + 6 типов клиентов + общий итог 445.11 млн.

| Конструкция | Какие наборы группировки | Для (a, b) |
|---|---|---|
| `ROLLUP (a, b)` | иерархия «справа налево» | (a,b), (a), () |
| `CUBE (a, b)` | все комбинации | (a,b), (a), (b), () |
| `GROUPING SETS (...)` | ровно перечисленные | любые |

---

## Шаг 9. Типичные ошибки: среднее процентов и размножение строк

```sql
SELECT ROUND(AVG(100.0 * defect / produced), 2)      AS avg_of_pct,
       ROUND(100.0 * SUM(defect) / SUM(produced), 2) AS weighted_pct
FROM   (VALUES (10, 5), (1000, 10)) AS t (produced, defect);
```

**Ожидаемый результат:** `25.50 | 1.49`. Среднее процентов придаёт партии из 10 штук такой же вес, как партии из 1000.

На реальных данных: среднее по 10 ячейкам «линия × смена» — 2.391 %, взвешенный процент брака — 2.520 %.

Размножение строк (повтор модуля 3):

```sql
SELECT SUM(i.amount) AS invoiced_wrong
FROM   invoices  AS i
JOIN   orders    AS o ON o.order_id = i.order_id
LEFT   JOIN payments AS p ON p.invoice_id = i.invoice_id
WHERE  o.customer_id = 24;      -- 55 866 923.22 вместо 50 091 668.75
```

Правильный приём — **сначала агрегировать «многие»** (оплаты по счёту), потом соединять (пример 7.4 в `examples.sql`; долг клиента 1 — 6 907 600,45 руб.).

---

## Типичные ошибки (сводка)

| Ошибка | Симптом | Исправление |
|---|---|---|
| Агрегат в WHERE | `aggregate functions are not allowed in WHERE` | Условие на агрегат — в HAVING |
| Столбец не в GROUP BY | `must appear in the GROUP BY clause` | Добавить в GROUP BY или агрегировать; либо группировать по PK |
| `COUNT(*)` после JOIN с позициями | Считаются позиции, а не заказы | `COUNT(DISTINCT o.order_id)` |
| `AVG(процент)` | Искажённый итоговый процент | `SUM(часть) / SUM(целое)` |
| SUM «одного» после JOIN с «многими» | Завышенные суммы | Агрегировать «многие» в подзапросе, потом JOIN |
| Подытоги через `IS NULL` | Путаница с NULL в данных | `GROUPING(col)` |
| Целочисленное деление `SUM(a)/SUM(b)` | 0 вместо 0.025 | Умножить на `100.0` или привести к `numeric` |

## Вопросы для самопроверки
1. Чем отличаются `COUNT(*)`, `COUNT(email)` и `COUNT(DISTINCT email)`?
2. Почему `WHERE` выполняется до `GROUP BY`, а псевдоним из `SELECT` нельзя использовать в `HAVING`?
3. Сколько строк вернёт `GROUP BY CUBE (a, b, c)`, если у a, b, c по 2 значения? (27 = 3 × 3 × 3: для каждого столбца — 2 значения + «итог».)
4. Почему в отчёте по браку правильнее `SUM(defect_qty) / SUM(produced_qty)`, чем `AVG(defect_pct)`?
