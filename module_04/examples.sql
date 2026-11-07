-- =====================================================================
-- Курс «Углублённый SQL». Модуль 4. Группирование и агрегирование данных
-- Практические примеры преподавателя (сквозной пример «Питание +»)
-- СУБД: PostgreSQL 16 (Yandex Managed Service for PostgreSQL)
-- Все запросы только читают данные схемы pitanie.
-- =====================================================================

SET search_path TO pitanie, public;

-- =====================================================================
-- 1. АГРЕГАТНЫЕ ФУНКЦИИ И NULL
-- =====================================================================

-- 1.1. COUNT(*) vs COUNT(столбец) vs COUNT(DISTINCT столбец)
-- Ожидаемо: 73 | 70 | 52 | 12 | 69
SELECT COUNT(*)                  AS customers_total,    -- все строки
       COUNT(region_id)          AS with_region,        -- без NULL
       COUNT(email)              AS with_email,
       COUNT(DISTINCT region_id) AS distinct_regions,
       COUNT(DISTINCT inn)       AS distinct_inn        -- меньше, чем клиентов: дубли!
FROM   customers;

-- 1.2. Неотгруженные заказы: COUNT(shipped_date) не считает NULL
-- Ожидаемо: 4458 | 4242 | 216
SELECT COUNT(*)            AS orders_total,
       COUNT(shipped_date) AS shipped,
       COUNT(*) - COUNT(shipped_date) AS not_shipped
FROM   orders;

-- 1.3. AVG игнорирует NULL: средний рейтинг поставщиков
-- Ожидаемо: 12 | 11 | 4.28 | 3.93 | 3.93 (у ООО "Специи и Ко" рейтинга нет)
SELECT COUNT(*)                       AS suppliers,
       COUNT(rating)                  AS rated,
       ROUND(AVG(rating), 2)          AS avg_rating_ignore_null,
       ROUND(SUM(rating) / COUNT(*), 2) AS avg_if_null_is_zero,
       ROUND(AVG(COALESCE(rating, 0)), 2) AS avg_coalesce_zero
FROM   suppliers;

-- 1.4. SUM по пустому набору — NULL, а не 0
-- Ожидаемо: NULL | 0 | 0
SELECT SUM(amount)              AS sum_empty,
       COALESCE(SUM(amount), 0) AS sum_empty_fixed,
       COUNT(*)                 AS cnt_empty
FROM   payments
WHERE  payment_date > DATE '2030-01-01';

-- 1.5. MIN / MAX работают с числами, датами и строками
SELECT MIN(order_date)    AS first_order,
       MAX(order_date)    AS last_order,
       MIN(order_number)  AS min_number,
       MAX(discount_pct)  AS max_discount
FROM   orders AS o
JOIN   order_items AS oi ON oi.order_id = o.order_id;

-- =====================================================================
-- 2. ФУНКЦИИ PostgreSQL: STRING_AGG, ARRAY_AGG, BOOL_AND/OR, ПЕРЦЕНТИЛИ
-- =====================================================================

-- 2.1. STRING_AGG / ARRAY_AGG: список продуктов каждой линии
-- Ожидаемо: 5 строк; число SKU по линиям 5, 7, 8, 9, 6
SELECT l.line_name,
       COUNT(DISTINCT b.product_id)                       AS products_cnt,
       STRING_AGG(DISTINCT p.sku, ', ' ORDER BY p.sku)    AS skus,
       ARRAY_AGG(DISTINCT b.shift)                        AS shifts
FROM   production_batches AS b
JOIN   production_lines   AS l ON l.line_id    = b.line_id
JOIN   products           AS p ON p.product_id = b.product_id
GROUP  BY l.line_id, l.line_name
ORDER  BY l.line_id;

-- 2.2. BOOL_AND / BOOL_OR: «все ли позиции заказа в рамках политики скидок?»
-- Ожидаемо: 4458 | 3322 | 1136 (подзапрос в FROM — подробно в модулях 5 и 9)
SELECT COUNT(*)                                  AS orders_cnt,
       COUNT(*) FILTER (WHERE all_in_policy)     AS orders_all_ok,
       COUNT(*) FILTER (WHERE NOT all_in_policy) AS orders_with_violation
FROM  (SELECT oi.order_id,
              BOOL_AND(oi.discount_pct <= 10) AS all_in_policy
       FROM   order_items AS oi
       GROUP  BY oi.order_id) AS t;

-- 2.3. Медиана и мода (упорядоченные агрегаты WITHIN GROUP)
-- Ожидаемо: среднее 192 542,67 > медиана 163 830,5 — распределение скошено вправо;
-- мода — «Банковский перевод». (Здесь счета с несколькими оплатами повторяются — для иллюстрации)
SELECT ROUND(AVG(i.amount), 2)                                        AS avg_invoice,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY i.amount)          AS median_invoice,
       PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY i.amount)          AS p90_invoice,
       MODE() WITHIN GROUP (ORDER BY p.payment_method)                AS popular_method
FROM   invoices AS i
JOIN   payments AS p ON p.invoice_id = i.invoice_id;

-- =====================================================================
-- 3. FILTER (WHERE …) — УСЛОВНАЯ АГРЕГАЦИЯ (особенность PostgreSQL)
-- =====================================================================

-- 3.1. Позиции и скидки сверх политики по менеджерам в одной строке
-- Ожидаемо: 9 строк; Соколов — 4167 из 4167 позиций сверх 10 %, средняя 18.01; Попов — 53
SELECT e.full_name,
       COUNT(*)                                      AS items,
       COUNT(*) FILTER (WHERE oi.discount_pct > 10)  AS items_over_10,
       ROUND(AVG(oi.discount_pct), 2)                AS avg_discount
FROM   order_items AS oi
JOIN   orders      AS o ON o.order_id    = oi.order_id
JOIN   employees   AS e ON e.employee_id = o.employee_id
WHERE  o.status <> 'Отменён'
GROUP  BY e.employee_id, e.full_name
ORDER  BY items_over_10 DESC, e.full_name;

-- 3.2. То же через CASE (переносимо в любую СУБД)
SELECT o.channel,
       SUM(CASE WHEN o.order_date <  DATE '2025-01-01' THEN 1 ELSE 0 END) AS orders_2024,
       SUM(CASE WHEN o.order_date >= DATE '2025-01-01' THEN 1 ELSE 0 END) AS orders_2025,
       COUNT(*) FILTER (WHERE o.order_date >= DATE '2025-01-01')          AS orders_2025_filter
FROM   orders AS o
WHERE  o.status <> 'Отменён'
GROUP  BY o.channel
ORDER  BY o.channel;

-- =====================================================================
-- 4. GROUP BY ПО НЕСКОЛЬКИМ СТОЛБЦАМ И ВЫРАЖЕНИЯМ
-- =====================================================================

-- 4.1. Выручка по месяцам (date_trunc) — 2025 г.
-- Ожидаемо: 12 строк; минимум — июль (24,7 млн), максимум — декабрь (44,7 млн)
SELECT date_trunc('month', o.order_date)::date                                   AS month,
       COUNT(DISTINCT o.order_id)                                                AS orders,
       ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)), 0)  AS revenue
FROM   orders      AS o
JOIN   order_items AS oi ON oi.order_id = o.order_id
WHERE  o.status <> 'Отменён'
  AND  o.order_date >= DATE '2025-01-01'
GROUP  BY date_trunc('month', o.order_date)
ORDER  BY month;

-- 4.2. Несколько столбцов: брак по линии и смене
-- Ожидаемо: 10 строк; Линия 3 / Ночь — 7.94 % при 1.5–2.3 % в остальных ячейках
SELECT b.line_id,
       b.shift,
       COUNT(*)                                                    AS batches,
       SUM(b.produced_qty)                                         AS produced,
       SUM(b.defect_qty)                                           AS defects,
       ROUND(100.0 * SUM(b.defect_qty) / SUM(b.produced_qty), 2)   AS defect_pct
FROM   production_batches AS b
GROUP  BY b.line_id, b.shift
ORDER  BY b.line_id, b.shift;

-- 4.3. Группировка по выражению CASE и по номеру/псевдониму столбца (PG)
SELECT CASE
           WHEN credit_limit >= 10000000 THEN '1. Крупный (≥ 10 млн)'
           WHEN credit_limit >= 1000000  THEN '2. Средний (1–10 млн)'
           ELSE                               '3. Малый (< 1 млн)'
       END            AS limit_group,
       COUNT(*)       AS customers
FROM   customers
GROUP  BY limit_group           -- PostgreSQL допускает псевдоним из SELECT
ORDER  BY 1;

-- =====================================================================
-- 5. HAVING vs WHERE и ЛОГИЧЕСКИЙ ПОРЯДОК ВЫПОЛНЕНИЯ
--    FROM/JOIN → WHERE → GROUP BY → HAVING → SELECT → DISTINCT → ORDER BY → LIMIT
-- =====================================================================

-- 5.1. WHERE фильтрует строки ДО группировки, HAVING — группы ПОСЛЕ
-- Ожидаемо: 1 строка — Соколов И. А., 18.01, 4167
SELECT e.full_name,
       ROUND(AVG(oi.discount_pct), 2) AS avg_discount,
       COUNT(*)                       AS items
FROM   order_items AS oi
JOIN   orders      AS o ON o.order_id    = oi.order_id
JOIN   employees   AS e ON e.employee_id = o.employee_id
WHERE  o.status <> 'Отменён'                 -- строки
GROUP  BY e.employee_id, e.full_name
HAVING AVG(oi.discount_pct) > 10             -- группы
ORDER  BY avg_discount DESC;

-- 5.2. ОЖИДАЕМАЯ ОШИБКА: агрегат в WHERE запрещён
SELECT o.employee_id, AVG(oi.discount_pct)
FROM   order_items AS oi
JOIN   orders      AS o ON o.order_id = oi.order_id
WHERE  AVG(oi.discount_pct) > 10
GROUP  BY o.employee_id;
-- ERROR: aggregate functions are not allowed in WHERE

-- 5.3. ОЖИДАЕМАЯ ОШИБКА: столбец не в GROUP BY и не в агрегате
SELECT o.employee_id, o.customer_id, COUNT(*)
FROM   orders AS o
GROUP  BY o.employee_id;
-- ERROR: column "o.customer_id" must appear in the GROUP BY clause or be used in an aggregate function

-- 5.4. Исключение: функциональная зависимость от первичного ключа (PG 9.1+)
-- Ожидаемо: 5 строк, лидер — ООО "Лента-Сервис" (146 заказов)
--      Группируем по PK customers — можно выводить любые столбцы этой таблицы
SELECT c.customer_id,
       c.customer_name,          -- не в GROUP BY, но зависит от PK
       c.credit_limit,
       COUNT(o.order_id) AS orders
FROM   customers AS c
LEFT   JOIN orders AS o ON o.customer_id = c.customer_id
GROUP  BY c.customer_id
ORDER  BY orders DESC
LIMIT  5;

-- 5.5. ОЖИДАЕМАЯ ОШИБКА: псевдоним из SELECT нельзя использовать в HAVING / WHERE
SELECT o.employee_id, COUNT(*) AS cnt
FROM   orders AS o
GROUP  BY o.employee_id
HAVING cnt > 100;
-- ERROR: column "cnt" does not exist

-- 5.6. Дубли клиентов: GROUP BY + HAVING COUNT(*) > 1
-- Ожидаемо: 3 ИНН (Ромашка — 3 карточки, Колос и Свежесть — по 2)
SELECT inn,
       COUNT(*)                                         AS cards,
       STRING_AGG(customer_name, ' | ' ORDER BY customer_id) AS names
FROM   customers
GROUP  BY inn
HAVING COUNT(*) > 1
ORDER  BY cards DESC;

-- =====================================================================
-- 6. ROLLUP, CUBE, GROUPING SETS, GROUPING()
-- =====================================================================

-- 6.1. ROLLUP (год, квартал): строки по кварталам + итог года + общий итог
SELECT EXTRACT(YEAR    FROM o.order_date) AS yr,
       EXTRACT(QUARTER FROM o.order_date) AS qtr,
       ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) / 1e6, 2) AS revenue_mln
FROM   orders      AS o
JOIN   order_items AS oi ON oi.order_id = o.order_id
WHERE  o.status <> 'Отменён'
GROUP  BY ROLLUP (EXTRACT(YEAR FROM o.order_date), EXTRACT(QUARTER FROM o.order_date))
ORDER  BY yr NULLS LAST, qtr NULLS LAST;
-- 8 кварталов + 2 итога по годам + 1 общий = 11 строк

-- 6.2. GROUPING() и подписи «Итого»
SELECT CASE WHEN GROUPING(t.yr)  = 1 THEN 'ВСЕГО'
            ELSE t.yr::text END                              AS yr,
       CASE WHEN GROUPING(t.yr)  = 1 THEN ''
            WHEN GROUPING(t.qtr) = 1 THEN 'Итого за год'
            ELSE 'Q' || t.qtr END                            AS qtr,
       ROUND(SUM(t.revenue) / 1e6, 2)                        AS revenue_mln,
       GROUPING(t.yr, t.qtr)                                 AS grouping_bits
FROM  (SELECT EXTRACT(YEAR    FROM o.order_date)::int AS yr,
              EXTRACT(QUARTER FROM o.order_date)::int AS qtr,
              oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100) AS revenue
       FROM   orders      AS o
       JOIN   order_items AS oi ON oi.order_id = o.order_id
       WHERE  o.status <> 'Отменён') AS t
GROUP  BY ROLLUP (t.yr, t.qtr)
ORDER  BY t.yr NULLS LAST, t.qtr NULLS LAST;

-- 6.3. CUBE (линия, смена): все комбинации подитогов — брак
SELECT CASE WHEN GROUPING(b.line_id) = 1 THEN 'Все линии' ELSE 'Линия ' || b.line_id END AS line,
       CASE WHEN GROUPING(b.shift)   = 1 THEN 'Обе смены' ELSE b.shift END              AS shift,
       SUM(b.produced_qty)                                                              AS produced,
       ROUND(100.0 * SUM(b.defect_qty) / SUM(b.produced_qty), 2)                        AS defect_pct
FROM   production_batches AS b
GROUP  BY CUBE (b.line_id, b.shift)
ORDER  BY GROUPING(b.line_id), b.line_id, GROUPING(b.shift), b.shift;
-- 5×2 + 5 (по линиям) + 2 (по сменам) + 1 = 18 строк

-- 6.4. GROUPING SETS: «отчёт из нескольких отчётов» за один проход
-- Ожидаемо: 11 строк = 4 канала + 6 типов клиентов + 1 итог (445,11 млн)
--      выручка 2025 по каналу, по типу клиента и общий итог
SELECT o.channel,
       c.customer_type,
       ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) / 1e6, 2) AS revenue_mln,
       GROUPING(o.channel, c.customer_type)                                           AS lvl
FROM   orders      AS o
JOIN   order_items AS oi ON oi.order_id    = o.order_id
JOIN   customers   AS c  ON c.customer_id  = o.customer_id
WHERE  o.status <> 'Отменён'
  AND  o.order_date >= DATE '2025-01-01'
GROUP  BY GROUPING SETS ((o.channel), (c.customer_type), ())
ORDER  BY lvl, revenue_mln DESC;

-- 6.5. Эквивалентность: ROLLUP(a, b) = GROUPING SETS ((a, b), (a), ())
-- Ожидаемо: 16 строк = 10 + 5 + 1; итог брака 197 033 шт.
SELECT b.line_id, b.shift, SUM(b.defect_qty) AS defects
FROM   production_batches AS b
GROUP  BY GROUPING SETS ((b.line_id, b.shift), (b.line_id), ())
ORDER  BY b.line_id NULLS LAST, b.shift NULLS LAST;

-- =====================================================================
-- 7. ТИПИЧНЫЕ ОШИБКИ АНАЛИТИКА
-- =====================================================================

-- 7.1. Среднее от процентов ≠ взвешенный процент
--      а) Наглядно на двух «партиях»: маленькая с 50 % брака и большая с 1 %
SELECT ROUND(AVG(100.0 * defect / produced), 2)        AS avg_of_pct,     -- 25.50
       ROUND(100.0 * SUM(defect) / SUM(produced), 2)   AS weighted_pct    -- 1.49
FROM   (VALUES (10, 5), (1000, 10)) AS t (produced, defect);

--      б) На данных: «средний процент брака компании» как среднее по 10 ячейкам
--         «линия × смена» и как SUM(брак) / SUM(выпуск)
SELECT ROUND(AVG(t.defect_pct), 3)                          AS avg_of_cell_pct,  -- 2.391
       ROUND(100.0 * SUM(t.defects) / SUM(t.produced), 3)   AS weighted_pct      -- 2.520
FROM  (SELECT b.line_id,
              b.shift,
              SUM(b.defect_qty)                                    AS defects,
              SUM(b.produced_qty)                                  AS produced,
              100.0 * SUM(b.defect_qty) / SUM(b.produced_qty)      AS defect_pct
       FROM   production_batches AS b
       GROUP  BY b.line_id, b.shift) AS t;

-- 7.2. Средняя скидка: простое среднее по позициям vs взвешенное по сумме
-- Ожидаемо: у Павлова 5.23 vs 6.42 — крупные позиции получают бо́льшие скидки
SELECT e.full_name,
       ROUND(AVG(oi.discount_pct), 2)                                           AS avg_discount_simple,
       ROUND(100.0 * SUM(oi.quantity * oi.unit_price * oi.discount_pct / 100)
                   / SUM(oi.quantity * oi.unit_price), 2)                       AS avg_discount_weighted
FROM   order_items AS oi
JOIN   orders      AS o ON o.order_id    = oi.order_id
JOIN   employees   AS e ON e.employee_id = o.employee_id
WHERE  o.status <> 'Отменён'
GROUP  BY e.employee_id, e.full_name
ORDER  BY avg_discount_weighted DESC
LIMIT  4;

-- 7.3. Размножение строк при агрегации после JOIN (вспоминаем модуль 3):
--      сумма счетов по клиенту, если присоединить оплаты, — завышена
--      (у ООО "Лента-Сервис" 149 оплат на 131 оплаченный счёт)
SELECT c.customer_name,
       SUM(i.amount)                        AS invoiced_wrong,
       (SELECT SUM(i2.amount)
        FROM   invoices AS i2
        JOIN   orders   AS o2 ON o2.order_id = i2.order_id
        WHERE  o2.customer_id = c.customer_id) AS invoiced_right
FROM   customers AS c
JOIN   orders    AS o ON o.customer_id = c.customer_id
JOIN   invoices  AS i ON i.order_id    = o.order_id
LEFT   JOIN payments AS p ON p.invoice_id = i.invoice_id
WHERE  c.customer_id = 24
GROUP  BY c.customer_id, c.customer_name;
-- Ожидаемо: invoiced_wrong 55 866 923,22 vs invoiced_right 50 091 668,75

-- 7.4. Правильно: сначала агрегировать «многие» (оплаты по счёту), потом соединять.
--      Долг клиента 1 (ООО "Торговый дом Вектор") vs кредитный лимит
SELECT c.customer_name,
       c.credit_limit,
       SUM(i.amount)                               AS invoiced,
       SUM(COALESCE(pay.paid, 0))                  AS paid,
       SUM(i.amount - COALESCE(pay.paid, 0))       AS debt
FROM   customers AS c
JOIN   orders    AS o ON o.customer_id = c.customer_id
JOIN   invoices  AS i ON i.order_id    = o.order_id
LEFT   JOIN (SELECT invoice_id, SUM(amount) AS paid
             FROM   payments
             GROUP  BY invoice_id) AS pay ON pay.invoice_id = i.invoice_id
WHERE  c.customer_id = 1
GROUP  BY c.customer_id, c.customer_name, c.credit_limit;
-- Ожидаемо: 14 716 047,93 | 7 808 447,48 | долг 6 907 600,45 при лимите 3 000 000
