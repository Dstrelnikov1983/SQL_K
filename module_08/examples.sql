-- =====================================================================
-- Курс «Углублённый SQL» · Модуль 8 «Использование оконных функций»
-- Практические примеры преподавателя (PostgreSQL 16)
-- =====================================================================
-- Модуль только читает данные: работаем прямо со схемой pitanie.
SET search_path TO pitanie, public;

-- Выручка строки (без отменённых заказов):
--   oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)


-- =====================================================================
-- 1. ВВЕДЕНИЕ: окно vs GROUP BY
-- =====================================================================

-- 1.1 GROUP BY «схлопывает» строки: одна строка на линию
SELECT line_id,
       round(avg(100.0 * defect_qty / produced_qty), 2) AS avg_defect_pct
FROM   production_batches
GROUP  BY line_id
ORDER  BY line_id;

-- 1.2 Оконная функция сохраняет КАЖДУЮ строку и добавляет к ней агрегат «окна»
SELECT batch_id,
       line_id,
       production_date,
       shift,
       round(100.0 * defect_qty / produced_qty, 2)                         AS defect_pct,
       round(avg(100.0 * defect_qty / produced_qty) OVER (PARTITION BY line_id), 2)
                                                                            AS line_avg_pct
FROM   production_batches
WHERE  production_date = DATE '2025-06-02'
ORDER  BY line_id, shift;

-- 1.3 OVER () — окно = весь результат: доля строки от общего итога
SELECT r.region_name,
       count(*)                                             AS returns_cnt,
       sum(count(*)) OVER ()                                AS total_returns,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1)   AS share_pct
FROM   returns   AS rt
JOIN   orders    AS o ON o.order_id    = rt.order_id
JOIN   customers AS c ON c.customer_id = o.customer_id
LEFT   JOIN regions AS r ON r.region_id = c.region_id
GROUP  BY r.region_name
ORDER  BY returns_cnt DESC
LIMIT  5;
-- Окно считается ПОСЛЕ GROUP BY: sum(count(*)) OVER () — сумма групповых count.

-- 1.4 Логический порядок: FROM -> WHERE -> GROUP BY -> HAVING -> ОКНА -> SELECT -> DISTINCT -> ORDER BY -> LIMIT
--     Поэтому оконную функцию нельзя использовать в WHERE:
-- ОЖИДАЕМАЯ ОШИБКА: window functions are not allowed in WHERE
SELECT batch_id, line_id, defect_qty
FROM   production_batches
WHERE  row_number() OVER (PARTITION BY line_id ORDER BY defect_qty DESC) <= 3;

--     Решение — подзапрос или CTE: сначала вычислить, потом фильтровать
WITH ranked AS (
    SELECT batch_id, line_id, production_date, shift, defect_qty,
           row_number() OVER (PARTITION BY line_id ORDER BY defect_qty DESC, batch_id) AS rn
    FROM   production_batches
)
SELECT line_id, rn, batch_id, production_date, shift, defect_qty
FROM   ranked
WHERE  rn <= 3
ORDER  BY line_id, rn;


-- =====================================================================
-- 2. ФУНКЦИИ РАНЖИРОВАНИЯ
-- =====================================================================

-- 2.1 ROW_NUMBER, RANK, DENSE_RANK на одинаковых значениях
--     (сырьё по сроку годности: много одинаковых сроков — 365, 730, 1095 дн.)
SELECT material_name,
       shelf_life_days,
       row_number() OVER (ORDER BY shelf_life_days DESC) AS rn,
       rank()       OVER (ORDER BY shelf_life_days DESC) AS rnk,
       dense_rank() OVER (ORDER BY shelf_life_days DESC) AS drnk
FROM   raw_materials
ORDER  BY shelf_life_days DESC, material_name
LIMIT  10;
-- rn среди «пиров» (одинаковый срок) выдаётся в произвольном порядке!
-- Для воспроизводимости добавляйте второй ключ: ORDER BY shelf_life_days DESC, material_id

-- 2.2 Ранжирование по агрегату: средняя цена сахара у поставщиков в 2025 г.
SELECT s.supplier_name,
       round(avg(poi.unit_price), 2)                           AS avg_price,
       dense_rank() OVER (ORDER BY avg(poi.unit_price))        AS price_rank
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id       = poi.po_id
JOIN   suppliers            AS s  ON s.supplier_id  = po.supplier_id
WHERE  poi.material_id = 4                                  -- сахар-песок
  AND  po.order_date >= DATE '2025-01-01'
GROUP  BY s.supplier_name
ORDER  BY price_rank;

-- 2.3 Топ-N в каждой группе: 2 лучших клиента по выручке в каждом типе клиента
WITH rev AS (
    SELECT c.customer_type,
           c.customer_name,
           sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS revenue
    FROM   orders      AS o
    JOIN   order_items AS oi ON oi.order_id   = o.order_id
    JOIN   customers   AS c  ON c.customer_id = o.customer_id
    WHERE  o.status <> 'Отменён'
      AND  o.order_date >= DATE '2025-01-01'
    GROUP  BY c.customer_type, c.customer_name
), ranked AS (
    SELECT rev.*,
           row_number() OVER (PARTITION BY customer_type ORDER BY revenue DESC) AS rn
    FROM   rev
)
SELECT customer_type, rn, customer_name, round(revenue / 1e6, 2) AS revenue_mln
FROM   ranked
WHERE  rn <= 2
ORDER  BY customer_type, rn;

-- 2.4 NTILE: разбить партии Линии 3 на 4 квартиля по проценту брака
--     и посмотреть, какая смена попадает в «худший» квартиль
WITH q AS (
    SELECT shift,
           ntile(4) OVER (ORDER BY 1.0 * defect_qty / produced_qty) AS quartile
    FROM   production_batches
    WHERE  line_id = 3
)
SELECT quartile,
       count(*)                                  AS batches,
       count(*) FILTER (WHERE shift = 'Ночь')    AS night,
       count(*) FILTER (WHERE shift = 'День')    AS day
FROM   q
GROUP  BY quartile
ORDER  BY quartile;

-- 2.5 PERCENT_RANK и CUME_DIST: относительное положение менеджера
SELECT e.full_name,
       round(avg(oi.discount_pct), 2)                                   AS avg_discount,
       round(percent_rank() OVER (ORDER BY avg(oi.discount_pct))::numeric, 3) AS pct_rank,
       round(cume_dist()    OVER (ORDER BY avg(oi.discount_pct))::numeric, 3) AS cume_dist
FROM   orders      AS o
JOIN   order_items AS oi ON oi.order_id   = o.order_id
JOIN   employees   AS e  ON e.employee_id = o.employee_id
WHERE  o.status <> 'Отменён'
GROUP  BY e.full_name
ORDER  BY avg_discount;


-- =====================================================================
-- 3. АГРЕГАТНЫЕ ОКОННЫЕ ФУНКЦИИ
-- =====================================================================

-- 3.1 Нарастающий итог выручки по месяцам 2025 г. + доля месяца в году
WITH m AS (
    SELECT date_trunc('month', o.order_date)::date                         AS month,
           sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100))  AS revenue
    FROM   orders      AS o
    JOIN   order_items AS oi ON oi.order_id = o.order_id
    WHERE  o.status <> 'Отменён'
      AND  o.order_date BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'
    GROUP  BY 1
)
SELECT month,
       round(revenue / 1e6, 2)                                             AS revenue_mln,
       round(sum(revenue) OVER (ORDER BY month) / 1e6, 2)                  AS running_mln,
       round(100 * revenue / sum(revenue) OVER (), 1)                      AS share_pct
FROM   m
ORDER  BY month;

-- 3.2 Скользящее среднее брака за 7 смен (ROWS) на Линии 3
SELECT production_date,
       shift,
       round(100.0 * defect_qty / produced_qty, 2)                         AS defect_pct,
       round(avg(100.0 * defect_qty / produced_qty)
                 OVER (ORDER BY production_date, shift
                       ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2)       AS ma7_pct
FROM   production_batches
WHERE  line_id = 3
  AND  production_date BETWEEN DATE '2025-03-01' AND DATE '2025-03-06'
ORDER  BY production_date, shift;

-- 3.3 ЛОВУШКА рамки по умолчанию.
--     С ORDER BY рамка = RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW:
--     строки с ОДИНАКОВЫМ ключом сортировки (пиры) входят в рамку целиком.
SELECT production_date,
       shift,
       produced_qty,
       sum(produced_qty) OVER (ORDER BY production_date)                   AS range_default,
       sum(produced_qty) OVER (ORDER BY production_date
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS rows_frame
FROM   production_batches
WHERE  line_id = 1
  AND  production_date BETWEEN DATE '2025-03-03' AND DATE '2025-03-05'
ORDER  BY production_date, shift;
-- В range_default у дневной и ночной смены одного дня ОДИНАКОВЫЙ итог.

-- 3.4 RANGE со смещением по дате и GROUPS: «последние 7 календарных дней»
--     против «последние 7 строк» (в некоторые дни партий нет)
SELECT production_date,
       count(*) OVER (ORDER BY production_date
                      RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW) AS batches_7days,
       count(*) OVER (ORDER BY production_date
                      GROUPS BETWEEN 6 PRECEDING AND CURRENT ROW)                AS batches_7dates
FROM   production_batches
WHERE  line_id = 2
  AND  shift = 'День'
  AND  production_date BETWEEN DATE '2025-03-01' AND DATE '2025-03-20'
ORDER  BY production_date;

-- 3.5 Доля внутри группы: структура расходов по отделам в 2025 г.
SELECT department,
       expense_category,
       round(sum(amount) / 1e6, 2)                                         AS amount_mln,
       round(100 * sum(amount) / sum(sum(amount)) OVER (PARTITION BY department), 1)
                                                                            AS share_in_dept_pct
FROM   expenses
WHERE  expense_date >= DATE '2025-01-01'
GROUP  BY department, expense_category
ORDER  BY department, amount_mln DESC;


-- =====================================================================
-- 4. ФУНКЦИИ СМЕЩЕНИЯ: LAG, LEAD, FIRST_VALUE, LAST_VALUE, NTH_VALUE
-- =====================================================================

-- 4.1 LAG: изменение цены молочного жира к предыдущей закупке
SELECT po.order_date,
       s.supplier_name,
       poi.unit_price,
       lag(poi.unit_price) OVER w                                          AS prev_price,
       round(100 * (poi.unit_price / lag(poi.unit_price) OVER w - 1), 1)   AS change_pct
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id      = poi.po_id
JOIN   suppliers            AS s  ON s.supplier_id = po.supplier_id
WHERE  poi.material_id = 14
  AND  po.order_date BETWEEN DATE '2025-01-20' AND DATE '2025-03-10'
WINDOW w AS (ORDER BY po.order_date, poi.po_item_id)
ORDER  BY po.order_date, poi.po_item_id;

-- 4.2 LEAD и значение по умолчанию: дата следующего заказа клиента
SELECT order_number,
       order_date,
       lead(order_date)              OVER (ORDER BY order_date, order_id) AS next_order,
       lead(order_date, 1, DATE '2025-12-31')
                                     OVER (ORDER BY order_date, order_id) - order_date AS days_to_next
FROM   orders
WHERE  customer_id = 1
  AND  order_date >= DATE '2025-10-01'
ORDER  BY order_date;

-- 4.3 FIRST_VALUE и ЛОВУШКА LAST_VALUE
--     LAST_VALUE с рамкой по умолчанию возвращает ТЕКУЩУЮ строку (рамка кончается на ней!)
SELECT po.order_date,
       poi.unit_price,
       first_value(poi.unit_price) OVER (ORDER BY po.order_date, poi.po_item_id)   AS first_price,
       last_value(poi.unit_price)  OVER (ORDER BY po.order_date, poi.po_item_id)   AS last_wrong,
       last_value(poi.unit_price)  OVER (ORDER BY po.order_date, poi.po_item_id
                                         ROWS BETWEEN UNBOUNDED PRECEDING
                                                  AND UNBOUNDED FOLLOWING)          AS last_right
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
WHERE  poi.material_id = 14
  AND  po.order_date BETWEEN DATE '2025-02-01' AND DATE '2025-02-28'
ORDER  BY po.order_date, poi.po_item_id;

-- 4.4 NTH_VALUE: вторая по величине партия брака на каждой линии в 2025 г.
SELECT DISTINCT
       line_id,
       nth_value(defect_qty, 1) OVER w AS max_defect,
       nth_value(defect_qty, 2) OVER w AS second_defect
FROM   production_batches
WHERE  production_date >= DATE '2025-01-01'
WINDOW w AS (PARTITION BY line_id ORDER BY defect_qty DESC
             ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
ORDER  BY line_id;


-- =====================================================================
-- 5. WINDOW-клауза: именованное окно и наследование
-- =====================================================================
WITH m AS (
    SELECT pc.parent_category_id                                           AS cat_id,
           date_trunc('month', o.order_date)::date                         AS month,
           sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100))  AS revenue
    FROM   orders             AS o
    JOIN   order_items        AS oi ON oi.order_id    = o.order_id
    JOIN   products           AS p  ON p.product_id   = oi.product_id
    JOIN   product_categories AS pc ON pc.category_id = p.category_id
    WHERE  o.status <> 'Отменён'
      AND  o.order_date >= DATE '2025-07-01'
    GROUP  BY 1, 2
)
SELECT cat_id,
       month,
       round(revenue / 1e6, 2)                                   AS revenue_mln,
       round(sum(revenue)  OVER w_run / 1e6, 2)                  AS running_mln,
       round(avg(revenue)  OVER w_3m  / 1e6, 2)                  AS ma3_mln,
       round(100 * (revenue / lag(revenue) OVER w - 1), 1)       AS mom_pct
FROM   m
WINDOW w     AS (PARTITION BY cat_id ORDER BY month),
       w_run AS (w ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
       w_3m  AS (w ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
ORDER  BY cat_id, month;


-- =====================================================================
-- 6. КЕЙС: план-факт нарастающим итогом (кондитерские изделия, 2025)
-- =====================================================================
WITH fact AS (
    SELECT extract(month FROM o.order_date)::int                           AS m,
           sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100))  AS fact
    FROM   orders             AS o
    JOIN   order_items        AS oi ON oi.order_id    = o.order_id
    JOIN   products           AS p  ON p.product_id   = oi.product_id
    JOIN   product_categories AS pc ON pc.category_id = p.category_id
    WHERE  o.status <> 'Отменён'
      AND  pc.parent_category_id = 2
      AND  o.order_date BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'
    GROUP  BY 1
)
SELECT sp.plan_month,
       round(sp.plan_amount / 1e6, 2)                                      AS plan_mln,
       round(f.fact / 1e6, 2)                                              AS fact_mln,
       round(100 * sum(f.fact)        OVER w
                 / sum(sp.plan_amount) OVER w, 1)                          AS ytd_completion_pct
FROM   sales_plan AS sp
JOIN   fact       AS f ON f.m = sp.plan_month
WHERE  sp.plan_year = 2025
  AND  sp.category_id = 2
WINDOW w AS (ORDER BY sp.plan_month)
ORDER  BY sp.plan_month;
