# Модуль 6. Практическая работа «Операции над наборами и LATERAL»

| Параметр | Значение |
|---|---|
| Цель | Научиться объединять, пересекать и вычитать наборы строк (`UNION [ALL]`, `INTERSECT [ALL]`, `EXCEPT [ALL]`), соблюдать требования совместимости, управлять приоритетом операций и решать задачи top-N на группу с помощью `LATERAL` (аналог `CROSS/OUTER APPLY` в T-SQL) |
| Время | 35 минут (преподаватель показывает шаг, слушатели повторяют) |
| Формат | Демонстрация + повторение, индивидуально |
| Файл с кодом | `module_06/examples.sql` (разделы 1–6 соответствуют шагам) |

## Подготовка

1. Подключитесь к учебной БД (`<адрес_сервера>:6432`, база `db1`, SSL `verify-full`, `root.crt`).
2. Выполните:

```sql
SET search_path TO pitanie, public;
```

> Все запросы — только чтение. Для экспериментов с «игрушечными» наборами используем конструктор `VALUES` — создавать таблицы не нужно.

---

## Шаг 1. UNION и UNION ALL

```sql
-- регионы, где есть клиенты ИЛИ поставщики
SELECT region_id FROM customers WHERE region_id IS NOT NULL
UNION
SELECT region_id FROM suppliers
ORDER  BY region_id;
```

**Ожидаемый результат:** 12 строк (1 … 12).

```sql
SELECT COUNT(*) AS cnt
FROM  (SELECT region_id FROM customers WHERE region_id IS NOT NULL
       UNION ALL
       SELECT region_id FROM suppliers) AS t;
```

**Ожидаемый результат:** `82` (70 клиентов с регионом + 12 поставщиков).

| | `UNION` | `UNION ALL` |
|---|---|---|
| Дубликаты | удаляет (как `DISTINCT`) | сохраняет |
| Стоимость | сортировка или хэш всего результата | простое «склеивание» |
| Когда | нужен список уникальных значений | лента событий, суммирование, когда дублей не бывает по смыслу |

> **Подумайте.** Вы собираете ленту «счета + оплаты» и затем суммируете. Что произойдёт с суммой, если вместо `UNION ALL` написать `UNION`?

---

## Шаг 2. Совместимость наборов

Единый справочник контактов:

```sql
SELECT 'Сотрудник' AS contact_type, full_name AS name, phone FROM employees
UNION ALL
SELECT 'Клиент',    customer_name, phone FROM customers
UNION ALL
SELECT 'Поставщик', supplier_name, phone FROM suppliers
ORDER  BY contact_type, name
LIMIT  10;
```

**Ожидаемый результат:** 10 строк типа «Клиент», начиная с `АО "Альфа"`. Всего в наборе 35 + 73 + 12 = 120 строк.

Правила, которые проверим ошибками:

```sql
-- ОЖИДАЕМАЯ ОШИБКА: разное число столбцов
SELECT customer_id, customer_name FROM customers
UNION
SELECT supplier_id FROM suppliers;
-- ERROR: each UNION query must have the same number of columns

-- ОЖИДАЕМАЯ ОШИБКА: несовместимые типы
SELECT customer_id FROM customers
UNION
SELECT registration_date FROM customers;
-- ERROR: UNION types integer and date cannot be matched

-- ОЖИДАЕМАЯ ОШИБКА: ORDER BY в первой ветке без скобок
SELECT customer_name FROM customers ORDER BY customer_name
UNION ALL
SELECT supplier_name FROM suppliers;
-- ERROR: syntax error at or near "UNION"
```

Правильно — скобки:

```sql
(SELECT customer_name AS name FROM customers ORDER BY customer_name LIMIT 3)
UNION ALL
(SELECT supplier_name         FROM suppliers ORDER BY supplier_name LIMIT 3);
```

**Ожидаемый результат:** 6 строк: 3 клиента (АО "Альфа", АО "Берёзка", АО "Вайлдберриз-Поставка") и 3 поставщика.

**Чек-лист совместимости:**
1. Одинаковое число столбцов.
2. Совместимые типы по позиции (при необходимости — явное `::text`, `::numeric`).
3. Имена столбцов результата — из **первого** запроса.
4. `ORDER BY` / `LIMIT` — один раз в конце (или в скобках у ветки).

---

## Шаг 3. INTERSECT и EXCEPT

```sql
-- материалы, которые поставляют и АгроСнаб-М (3), и Специи и Ко (12)
SELECT poi.material_id
FROM   purchase_order_items poi JOIN purchase_orders po ON po.po_id = poi.po_id
WHERE  po.supplier_id = 3
INTERSECT
SELECT poi.material_id
FROM   purchase_order_items poi JOIN purchase_orders po ON po.po_id = poi.po_id
WHERE  po.supplier_id = 12
ORDER  BY 1;
```

**Ожидаемый результат:** 15, 16, 18, 24 (соль, ванилин, желатин, чеснок).

```sql
-- клиенты, покупавшие в 2024 г., но не в 2025 г.
SELECT customer_id FROM orders
WHERE  order_date <  DATE '2025-01-01' AND status <> 'Отменён'
EXCEPT
SELECT customer_id FROM orders
WHERE  order_date >= DATE '2025-01-01' AND status <> 'Отменён';
```

**Ожидаемый результат:** 0 строк.

> **Подумайте.** Пустой результат — это «ошибка в запросе» или «хорошая новость»? Как убедиться, что запрос правильный? (Поменяйте ветки местами, проверьте на паре «клиент — товар».)

```sql
SELECT COUNT(*) AS lost_pairs
FROM  (SELECT o.customer_id, oi.product_id
       FROM   orders o JOIN order_items oi ON oi.order_id = o.order_id
       WHERE  o.order_date <  DATE '2025-01-01' AND o.status <> 'Отменён'
       EXCEPT
       SELECT o.customer_id, oi.product_id
       FROM   orders o JOIN order_items oi ON oi.order_id = o.order_id
       WHERE  o.order_date >= DATE '2025-01-01' AND o.status <> 'Отменён') AS t;
```

**Ожидаемый результат:** `127` пар «клиент — товар» исчезли в 2025 г.

**Типичная ошибка:** ожидать, что `EXCEPT` симметричен. `A EXCEPT B` ≠ `B EXCEPT A`: пары «поставщик — материал» 2025 EXCEPT 2024 дают 4 строки (новый поставщик 12), а 2024 EXCEPT 2025 — 0.

---

## Шаг 4. ALL-варианты и NULL

```sql
SELECT x FROM (VALUES (1),(1),(1),(2),(NULL)) a(x)
INTERSECT ALL
SELECT x FROM (VALUES (1),(1),(3),(NULL)) b(x)
ORDER  BY x;
-- 1, 1, NULL

SELECT x FROM (VALUES (1),(1),(1),(2),(NULL)) a(x)
EXCEPT ALL
SELECT x FROM (VALUES (1),(1),(3),(NULL)) b(x)
ORDER  BY x;
-- 1, 2
```

| Операция | Сколько раз попадает значение (m раз слева, n раз справа) |
|---|---|
| `UNION ALL` | m + n |
| `UNION` | 1 |
| `INTERSECT ALL` | min(m, n) |
| `INTERSECT` | 1, если m > 0 и n > 0 |
| `EXCEPT ALL` | max(m − n, 0) |
| `EXCEPT` | 1, если m > 0 и n = 0 |

> **Важно.** В операциях над наборами `NULL` считается равным `NULL` (как в `DISTINCT`), поэтому `NULL` попал в `INTERSECT ALL`. А вот `NOT IN` с `NULL` в подзапросе даёт пустой результат (модуль 5).

---

## Шаг 5. Приоритет операций

```sql
SELECT x FROM (VALUES (1),(2)) a(x)
UNION
SELECT x FROM (VALUES (3)) b(x)
INTERSECT
SELECT x FROM (VALUES (1)) c(x)
ORDER  BY x;
```

**Ожидаемый результат:** `1, 2` — вычислено как `A UNION (B INTERSECT C)`.

Со скобками `(A UNION B) INTERSECT C` — результат `1`.

> **Правило.** `INTERSECT` связывает сильнее `UNION` и `EXCEPT`; `UNION` и `EXCEPT` — равного приоритета, слева направо. Если в запросе больше одной разной операции — **всегда ставьте скобки**.

---

## Шаг 6. LATERAL: аналог CROSS APPLY / OUTER APPLY

Без `LATERAL` подзапрос в `FROM` не видит соседние таблицы:

```sql
-- ОЖИДАЕМАЯ ОШИБКА
SELECT c.customer_name, t.order_number
FROM   customers AS c
CROSS  JOIN (SELECT o.order_number FROM orders o
             WHERE  o.customer_id = c.customer_id LIMIT 3) AS t;
-- ERROR: invalid reference to FROM-clause entry for table "c"
-- HINT:  To reference that table, you must mark this subquery with LATERAL.
```

С `LATERAL` — 3 крупнейших заказа (по сумме счёта) каждого клиента:

```sql
SELECT c.customer_name, t.order_number, t.order_date, t.amount
FROM   customers AS c
CROSS  JOIN LATERAL (
         SELECT o.order_number, o.order_date, i.amount
         FROM   orders   AS o
         JOIN   invoices AS i ON i.order_id = o.order_id
         WHERE  o.customer_id = c.customer_id
         ORDER  BY i.amount DESC
         LIMIT  3) AS t
ORDER  BY c.customer_name, t.amount DESC
LIMIT  9;
```

**Ожидаемый результат (начало):**

| customer_name | order_number | order_date | amount |
|---|---|---|---|
| АО "Альфа" | ЗК-2024-00094 | 2024-01-18 | 454 205.70 |
| АО "Альфа" | ЗК-2024-00096 | 2024-01-19 | 449 481.55 |
| АО "Альфа" | ЗК-2025-02210 | 2025-01-14 | 432 553.60 |

Всего — 216 строк по 72 клиентам: клиент без заказов «выпал», как при `CROSS APPLY`.

`OUTER APPLY` → `LEFT JOIN LATERAL ... ON TRUE`:

```sql
SELECT e.employee_id, e.full_name, lo.order_number, lo.order_date
FROM   employees AS e
LEFT   JOIN LATERAL (
         SELECT o.order_number, o.order_date
         FROM   orders AS o
         WHERE  o.employee_id = e.employee_id
         ORDER  BY o.order_date DESC, o.order_id DESC
         LIMIT  1) AS lo ON TRUE
WHERE  e.department = 'Продажи'
ORDER  BY e.employee_id;
```

**Ожидаемый результат:** 11 строк; у Громова (3) и Ершовой (9) — `NULL`; у Попова (60) последний заказ — 2024-06-28 (сотрудник уволен).

`LATERAL` с функциями, возвращающими набор:

```sql
-- брак по каждой смене каждой линии: массив → строки
SELECT l.line_id, sh.shift,
       (SELECT ROUND(100.0 * SUM(b.defect_qty) / SUM(b.produced_qty), 2)
        FROM   production_batches b
        WHERE  b.line_id = l.line_id AND b.shift = sh.shift) AS defect_pct
FROM   production_lines AS l
CROSS  JOIN LATERAL unnest(ARRAY['День', 'Ночь']) AS sh(shift)
ORDER  BY l.line_id, sh.shift;
```

**Ожидаемый результат:** 10 строк; Линия 3: День 1.62, **Ночь 7.94**; остальные — 1.55…2.34 без разницы между сменами.

Календарь месяцев (`generate_series`) + выручка месяца — см. `examples.sql`, пример 6.6 (12 строк, минимум — 2025-07: 24,7 млн руб.).

| T-SQL | PostgreSQL |
|---|---|
| `CROSS APPLY (SELECT TOP 3 ... ORDER BY ...)` | `CROSS JOIN LATERAL (SELECT ... ORDER BY ... LIMIT 3)` |
| `OUTER APPLY (...)` | `LEFT JOIN LATERAL (...) ON TRUE` |
| `CROSS APPLY STRING_SPLIT(...)` | `CROSS JOIN LATERAL unnest(string_to_array(...))` |
| `EXCEPT` / `INTERSECT` (без `ALL`) | `EXCEPT [ALL]` / `INTERSECT [ALL]` |

> **Подумайте.** Задачу «последний заказ клиента» мы решали коррелированным подзапросом с `MAX` (модуль 5). Чем вариант с `LATERAL ... LIMIT 1` лучше? (Можно вернуть сразу несколько столбцов; ровно одна строка даже при «ничьих»; можно вернуть top-3.)

---

## Итог практической работы

| Задача | Инструмент |
|---|---|
| Собрать события из разных таблиц в одну ленту | `UNION ALL` + столбец-признак типа |
| Уникальный список из нескольких источников | `UNION` |
| «И там, и там» | `INTERSECT` |
| «Здесь есть, там нет» | `EXCEPT` (или `NOT EXISTS`) |
| Top-N на группу, «последний элемент», несколько столбцов из связанной таблицы | `CROSS JOIN LATERAL` / `LEFT JOIN LATERAL ... ON TRUE` |
