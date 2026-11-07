-- =====================================================================
-- Курс «Углублённый SQL» · Модуль 9
-- Создание представлений, табличных функций и CTE
-- Практические примеры преподавателя (PostgreSQL 16)
-- ---------------------------------------------------------------------
-- Данные читаем из схемы pitanie (только чтение!).
-- Свои объекты создаём в личной схеме stud_<фамилия>.
-- В этом файле личная схема называется stud_ivanov —
-- замените её на свою (Ctrl+H) перед выполнением.
-- Личная схема создаётся скриптом module_07/scripts/00_personal_schema.sql
-- (SET course.stud_schema = 'stud_ivanov'; затем выполнить файл) — выполните его
-- ДО этого файла: скрипт модуля 7 останавливается, если схема уже существует.
-- В личной схеме лежат копии таблиц pitanie с теми же именами, поэтому
-- исходные таблицы ниже всегда указаны с префиксом pitanie.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS stud_ivanov;
SET search_path TO stud_ivanov, pitanie, public;

-- =====================================================================
-- 1. ПРОИЗВОДНЫЕ ТАБЛИЦЫ (подзапрос во FROM)
-- =====================================================================

-- 1.1. Выручка по менеджерам → средняя выручка менеджера.
--      Агрегат от агрегата одним SELECT не посчитать: нужна производная таблица.
--      Алиас производной таблицы (t) пишем всегда: в PG ≤ 15 и T-SQL он обязателен
--      (PG 16 разрешает его опустить, но тогда к столбцам не обратиться по имени t.*).
SELECT ROUND(AVG(t.revenue), 0)  AS avg_manager_revenue,
       ROUND(MAX(t.revenue), 0)  AS max_manager_revenue,
       COUNT(*)                  AS managers
FROM  (SELECT o.employee_id,
              SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS revenue
       FROM   pitanie.orders      AS o
       JOIN   pitanie.order_items AS oi ON oi.order_id = o.order_id
       WHERE  o.status <> 'Отменён'
       GROUP  BY o.employee_id) AS t;
-- Ожидаемо: 9 менеджеров, средняя ≈ 92,1 млн, максимум ≈ 207,2 млн (Морозова Е. П.)

-- 1.2. Производная таблица в JOIN: менеджеры и их средняя скидка
SELECT e.full_name,
       d.lines,
       d.avg_discount
FROM   pitanie.employees AS e
JOIN  (SELECT o.employee_id,
              COUNT(*)                         AS lines,
              ROUND(AVG(oi.discount_pct), 2)   AS avg_discount
       FROM   pitanie.orders      AS o
       JOIN   pitanie.order_items AS oi ON oi.order_id = o.order_id
       WHERE  o.status <> 'Отменён'
       GROUP  BY o.employee_id) AS d ON d.employee_id = e.employee_id
ORDER  BY d.avg_discount DESC;
-- Ожидаемо: первым идёт Соколов Игорь Андреевич со средней скидкой ≈ 18 %

-- =====================================================================
-- 2. CTE — ОБОБЩЁННЫЕ ТАБЛИЧНЫЕ ВЫРАЖЕНИЯ (WITH)
-- =====================================================================

-- 2.1. Тот же запрос 1.1, но через CTE: читается сверху вниз
WITH manager_revenue AS (
    SELECT o.employee_id,
           SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS revenue
    FROM   pitanie.orders      AS o
    JOIN   pitanie.order_items AS oi ON oi.order_id = o.order_id
    WHERE  o.status <> 'Отменён'
    GROUP  BY o.employee_id
)
SELECT e.full_name,
       ROUND(mr.revenue / 1e6, 1)                                AS revenue_mln,
       ROUND(100 * mr.revenue / SUM(mr.revenue) OVER (), 1)      AS share_pct
FROM   manager_revenue    AS mr
JOIN   pitanie.employees  AS e ON e.employee_id = mr.employee_id
ORDER  BY mr.revenue DESC;

-- 2.2. Несколько CTE подряд: план/факт 2025 по категориям верхнего уровня.
--      Каждое CTE — один логический шаг; следующее CTE может ссылаться на предыдущее.
WITH fact AS (                       -- шаг 1: факт по месяцам и категориям нижнего уровня
    SELECT EXTRACT(MONTH FROM o.order_date)::int                           AS m,
           pc.parent_category_id                                           AS top_cat,
           SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100))  AS fact_amount
    FROM   pitanie.orders             AS o
    JOIN   pitanie.order_items        AS oi ON oi.order_id   = o.order_id
    JOIN   pitanie.products           AS p  ON p.product_id  = oi.product_id
    JOIN   pitanie.product_categories AS pc ON pc.category_id = p.category_id
    WHERE  o.status <> 'Отменён'
      AND  o.order_date >= DATE '2025-01-01'
      AND  o.order_date <  DATE '2026-01-01'
    GROUP  BY 1, 2
),
plan AS (                            -- шаг 2: план
    SELECT plan_month AS m, category_id AS top_cat, plan_amount
    FROM   pitanie.sales_plan
    WHERE  plan_year = 2025
),
pf AS (                              -- шаг 3: соединяем план и факт по полугодиям
    SELECT pl.top_cat,
           CASE WHEN pl.m <= 6 THEN 'H1' ELSE 'H2' END AS half,
           SUM(pl.plan_amount)                  AS plan_amount,
           SUM(COALESCE(f.fact_amount, 0))      AS fact_amount
    FROM   plan      AS pl
    LEFT   JOIN fact AS f ON f.m = pl.m AND f.top_cat = pl.top_cat
    GROUP  BY 1, 2
)
SELECT c.category_name,
       pf.half,
       ROUND(pf.plan_amount / 1e6, 1)                     AS plan_mln,
       ROUND(pf.fact_amount / 1e6, 1)                     AS fact_mln,
       ROUND(100 * pf.fact_amount / pf.plan_amount, 1)    AS done_pct
FROM   pf
JOIN   pitanie.product_categories AS c ON c.category_id = pf.top_cat
ORDER  BY c.category_id, pf.half;
-- Ожидаемо: «Кондитерские изделия» H2 — выполнение плана заметно ниже 100 %

-- 2.3. Повторное использование CTE: одно CTE используется дважды
--      (линии: брак ночью против брака днём)
WITH shift_quality AS (
    SELECT line_id,
           shift,
           ROUND(100.0 * SUM(defect_qty) / NULLIF(SUM(produced_qty), 0), 2) AS defect_pct
    FROM   pitanie.production_batches
    GROUP  BY line_id, shift
)
SELECT d.line_id,
       d.defect_pct                  AS day_defect_pct,
       n.defect_pct                  AS night_defect_pct,
       n.defect_pct - d.defect_pct   AS diff_pp
FROM   shift_quality AS d
JOIN   shift_quality AS n ON n.line_id = d.line_id AND n.shift = 'Ночь'
WHERE  d.shift = 'День'
ORDER  BY diff_pp DESC;
-- Ожидаемо: линия 3 — ночью ≈ 8,0 %, днём ≈ 1,6 %

-- 2.4. MATERIALIZED / NOT MATERIALIZED.
--      С PG 12 CTE, на которое ссылаются один раз, «встраивается» в запрос
--      (фильтр проталкивается внутрь). MATERIALIZED заставляет вычислить CTE
--      один раз и хранить результат — «барьер оптимизации».
EXPLAIN (COSTS OFF)
WITH b AS NOT MATERIALIZED (
    SELECT * FROM pitanie.production_batches
)
SELECT * FROM b WHERE batch_id = 100;
-- План: Index Scan using production_batches_pkey — фильтр ушёл внутрь

EXPLAIN (COSTS OFF)
WITH b AS MATERIALIZED (
    SELECT * FROM pitanie.production_batches
)
SELECT * FROM b WHERE batch_id = 100;
-- План: CTE Scan on b + Filter, внутри — Seq Scan всей таблицы

-- =====================================================================
-- 3. РЕКУРСИВНЫЕ CTE
-- =====================================================================

-- 3.1. Оргструктура: вся иерархия от генерального директора,
--      уровень и путь в иерархии
WITH RECURSIVE org AS (
    -- якорь: корень дерева
    SELECT employee_id,
           full_name,
           position,
           manager_id,
           1                                   AS lvl,
           full_name::text                     AS path
    FROM   pitanie.employees
    WHERE  manager_id IS NULL
    UNION ALL
    -- рекурсивная часть: подчинённые уже найденных
    SELECT e.employee_id,
           e.full_name,
           e.position,
           e.manager_id,
           org.lvl + 1,
           org.path || ' → ' || split_part(e.full_name, ' ', 1)
    FROM   pitanie.employees AS e
    JOIN   org ON e.manager_id = org.employee_id
)
SELECT repeat('    ', lvl - 1) || full_name AS tree,
       position,
       lvl
FROM   org
ORDER  BY path;
-- Ожидаемо: 35 строк, максимальный уровень — 4

-- 3.2. Вся команда руководителя отдела продаж (Ершова Т. Ю., id 9)
--      и выручка каждого подчинённого
WITH RECURSIVE team AS (
    SELECT employee_id, full_name, 0 AS depth
    FROM   pitanie.employees
    WHERE  employee_id = 9
    UNION ALL
    SELECT e.employee_id, e.full_name, t.depth + 1
    FROM   pitanie.employees AS e
    JOIN   team AS t ON e.manager_id = t.employee_id
),
rev AS (
    SELECT o.employee_id,
           SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS revenue,
           SUM(oi.quantity * oi.unit_price * oi.discount_pct / 100)       AS discount_rub
    FROM   pitanie.orders      AS o
    JOIN   pitanie.order_items AS oi ON oi.order_id = o.order_id
    WHERE  o.status <> 'Отменён'
    GROUP  BY o.employee_id
)
SELECT t.depth,
       t.full_name,
       ROUND(COALESCE(r.revenue, 0)      / 1e6, 1) AS revenue_mln,
       ROUND(COALESCE(r.discount_rub, 0) / 1e6, 1) AS discount_mln
FROM   team    AS t
LEFT   JOIN rev AS r ON r.employee_id = t.employee_id
ORDER  BY t.depth, revenue_mln DESC;

-- 3.3. Дерево категорий с путём (снизу вверх: от категории к корню)
WITH RECURSIVE cat AS (
    SELECT category_id, category_name, parent_category_id,
           category_name::text AS path
    FROM   pitanie.product_categories
    WHERE  parent_category_id IS NULL
    UNION ALL
    SELECT c.category_id, c.category_name, c.parent_category_id,
           cat.path || ' / ' || c.category_name
    FROM   pitanie.product_categories AS c
    JOIN   cat ON c.parent_category_id = cat.category_id
)
SELECT category_id, path
FROM   cat
ORDER  BY path;

-- 3.4. Генерация календаря рекурсивным CTE: все месяцы 2025 года,
--      в том числе те, где простоев не было (LEFT JOIN к календарю)
WITH RECURSIVE months AS (
    SELECT DATE '2025-01-01' AS m
    UNION ALL
    SELECT (m + INTERVAL '1 month')::date
    FROM   months
    WHERE  m < DATE '2025-12-01'
)
SELECT to_char(months.m, 'YYYY-MM')                                       AS month,
       COUNT(d.downtime_id)                                               AS events,
       ROUND(COALESCE(SUM(EXTRACT(EPOCH FROM d.end_time - d.start_time)) / 3600, 0), 1) AS hours
FROM   months
LEFT   JOIN pitanie.equipment_downtime AS d
       ON  d.line_id = 2
       AND d.start_time >= months.m
       AND d.start_time <  months.m + INTERVAL '1 month'
GROUP  BY months.m
ORDER  BY months.m;
-- То же без рекурсии: generate_series(DATE '2025-01-01', DATE '2025-12-01', INTERVAL '1 month')

-- 3.5. Защита от зацикливания: глубина или CYCLE (PG 14+)
WITH RECURSIVE org AS (
    SELECT employee_id, manager_id, 1 AS lvl
    FROM   pitanie.employees
    WHERE  manager_id IS NULL
    UNION ALL
    SELECT e.employee_id, e.manager_id, org.lvl + 1
    FROM   pitanie.employees AS e
    JOIN   org ON e.manager_id = org.employee_id
    WHERE  org.lvl < 10                       -- страховка по глубине
) CYCLE employee_id SET is_cycle USING visited -- стандартный синтаксис SQL:2008
SELECT lvl, COUNT(*) AS employees
FROM   org
GROUP  BY lvl
ORDER  BY lvl;

-- =====================================================================
-- 4. DATA-MODIFYING CTE (кратко) — только в личной схеме!
-- =====================================================================
DROP TABLE IF EXISTS stud_ivanov.m09_downtime_open;
DROP TABLE IF EXISTS stud_ivanov.m09_downtime_log;

CREATE TABLE stud_ivanov.m09_downtime_open AS
SELECT * FROM pitanie.equipment_downtime;

CREATE TABLE stud_ivanov.m09_downtime_log (LIKE pitanie.equipment_downtime);

-- Перенос незакрытых простоев в журнал одним оператором:
-- DELETE ... RETURNING отдаёт удалённые строки следующему шагу
WITH moved AS (
    DELETE FROM stud_ivanov.m09_downtime_open
    WHERE  end_time IS NULL
    RETURNING *
)
INSERT INTO stud_ivanov.m09_downtime_log
SELECT * FROM moved;
-- Ожидаемо: INSERT 0 4

SELECT (SELECT COUNT(*) FROM stud_ivanov.m09_downtime_open) AS left_rows,
       (SELECT COUNT(*) FROM stud_ivanov.m09_downtime_log)  AS moved_rows;

-- =====================================================================
-- 5. ПРЕДСТАВЛЕНИЯ (VIEW)
-- =====================================================================

-- 5.1. Простое представление: «строка продажи» с чистой выручкой
CREATE OR REPLACE VIEW stud_ivanov.v_order_lines AS
SELECT oi.order_item_id,
       o.order_id,
       o.order_date,
       o.customer_id,
       o.employee_id,
       o.channel,
       oi.product_id,
       oi.quantity,
       oi.unit_price,
       oi.discount_pct,
       ROUND(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100), 2) AS net_amount
FROM   pitanie.orders      AS o
JOIN   pitanie.order_items AS oi ON oi.order_id = o.order_id
WHERE  o.status <> 'Отменён';

COMMENT ON VIEW stud_ivanov.v_order_lines IS 'Строки продаж без отменённых заказов; net_amount — выручка после скидки';

-- Представление используется как таблица
SELECT channel,
       COUNT(*)                         AS lines,
       ROUND(SUM(net_amount) / 1e6, 1)  AS revenue_mln
FROM   stud_ivanov.v_order_lines
GROUP  BY channel
ORDER  BY revenue_mln DESC;

-- 5.2. CREATE OR REPLACE: можно ДОБАВИТЬ столбцы в конец,
--      нельзя удалить/переименовать/сменить тип существующих
CREATE OR REPLACE VIEW stud_ivanov.v_order_lines AS
SELECT oi.order_item_id,
       o.order_id,
       o.order_date,
       o.customer_id,
       o.employee_id,
       o.channel,
       oi.product_id,
       oi.quantity,
       oi.unit_price,
       oi.discount_pct,
       ROUND(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100), 2) AS net_amount,
       oi.discount_pct > 10                                                 AS over_policy  -- новый столбец в конце
FROM   pitanie.orders      AS o
JOIN   pitanie.order_items AS oi ON oi.order_id = o.order_id
WHERE  o.status <> 'Отменён';

-- ОЖИДАЕМАЯ ОШИБКА: попытка убрать столбец через OR REPLACE
-- ERROR: cannot drop columns from view
CREATE OR REPLACE VIEW stud_ivanov.v_order_lines AS
SELECT oi.order_item_id,
       o.order_id
FROM   pitanie.orders      AS o
JOIN   pitanie.order_items AS oi ON oi.order_id = o.order_id;

-- 5.3. Безопасность: представление скрывает столбцы (зарплата, телефон)
CREATE OR REPLACE VIEW stud_ivanov.v_employees_public AS
SELECT employee_id,
       full_name,
       position,
       department,
       manager_id,
       hire_date
FROM   pitanie.employees;
-- Аналитикам выдают права только на представление:
--   GRANT SELECT ON stud_ivanov.v_employees_public TO analyst_role;
--   (а на pitanie.employees прав не дают)
SELECT * FROM stud_ivanov.v_employees_public WHERE department = 'Закупки';

-- 5.4. Обновляемое представление и WITH CHECK OPTION.
--      Простое представление (одна таблица, без агрегатов/DISTINCT/GROUP BY)
--      PostgreSQL умеет обновлять автоматически.
DROP TABLE IF EXISTS stud_ivanov.m09_customers CASCADE;
CREATE TABLE stud_ivanov.m09_customers AS
SELECT customer_id, customer_name, customer_type, credit_limit, payment_terms_days
FROM   pitanie.customers;
ALTER TABLE stud_ivanov.m09_customers ADD PRIMARY KEY (customer_id);

CREATE OR REPLACE VIEW stud_ivanov.v_federal_chains AS
SELECT customer_id, customer_name, customer_type, credit_limit
FROM   stud_ivanov.m09_customers
WHERE  customer_type = 'Федеральная сеть'
WITH CHECK OPTION;

-- можно: изменение не выводит строку за пределы представления
UPDATE stud_ivanov.v_federal_chains
SET    credit_limit = credit_limit * 1.10
WHERE  customer_id = (SELECT MIN(customer_id) FROM stud_ivanov.v_federal_chains);
-- Ожидаемо: UPDATE 1

-- ОЖИДАЕМАЯ ОШИБКА: строка «выпала» бы из представления
-- ERROR: new row violates check option for view "v_federal_chains"
UPDATE stud_ivanov.v_federal_chains
SET    customer_type = 'Розница'
WHERE  customer_id = (SELECT MIN(customer_id) FROM stud_ivanov.v_federal_chains);

-- Какие представления обновляемы — смотрим в information_schema
SELECT table_name, is_updatable, is_insertable_into, check_option
FROM   information_schema.views
WHERE  table_schema = 'stud_ivanov'
ORDER  BY table_name;
-- v_federal_chains: YES / YES / CASCADED; v_employees_public тоже обновляемо (одна таблица!);
-- v_order_lines (JOIN + WHERE по второй таблице): NO / NO / NONE

-- 5.5. Зависимости: таблицу, на которую ссылается представление, просто так не удалить
-- ОЖИДАЕМАЯ ОШИБКА: cannot drop table m09_customers because other objects depend on it
DROP TABLE stud_ivanov.m09_customers;

-- Кто зависит от таблицы? (pg_depend через pg_rewrite)
SELECT DISTINCT v.relname AS dependent_view
FROM   pg_depend  AS d
JOIN   pg_rewrite AS r ON r.oid = d.objid
JOIN   pg_class   AS v ON v.oid = r.ev_class
WHERE  d.refobjid = 'stud_ivanov.m09_customers'::regclass
  AND  v.oid <> d.refobjid;

-- Проще: information_schema.view_table_usage
SELECT view_schema, view_name, table_schema, table_name
FROM   information_schema.view_table_usage
WHERE  view_schema = 'stud_ivanov'
ORDER  BY view_name, table_name;

-- Текст представления хранится в каталоге
SELECT pg_get_viewdef('stud_ivanov.v_employees_public'::regclass, true);

-- =====================================================================
-- 6. МАТЕРИАЛИЗОВАННЫЕ ПРЕДСТАВЛЕНИЯ
-- =====================================================================
DROP MATERIALIZED VIEW IF EXISTS stud_ivanov.mv_monthly_revenue;

CREATE MATERIALIZED VIEW stud_ivanov.mv_monthly_revenue AS
SELECT date_trunc('month', o.order_date)::date                                   AS month,
       o.channel,
       SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100))::numeric(14,2) AS revenue,
       COUNT(DISTINCT o.order_id)                                                 AS orders
FROM   pitanie.orders      AS o
JOIN   pitanie.order_items AS oi ON oi.order_id = o.order_id
WHERE  o.status <> 'Отменён'
GROUP  BY 1, 2
WITH DATA;

-- Уникальный индекс нужен для REFRESH ... CONCURRENTLY
CREATE UNIQUE INDEX ON stud_ivanov.mv_monthly_revenue (month, channel);

SELECT COUNT(*) AS rows FROM stud_ivanov.mv_monthly_revenue;   -- 91 строка: не во всех месяцах были продажи во всех 4 каналах

SELECT month, channel, revenue
FROM   stud_ivanov.mv_monthly_revenue
WHERE  channel = 'Маркетплейс'
ORDER  BY month DESC
LIMIT  3;

-- Данные «застыли» на момент создания. Обновить:
REFRESH MATERIALIZED VIEW stud_ivanov.mv_monthly_revenue;
-- без блокировки чтения (нужен уникальный индекс):
REFRESH MATERIALIZED VIEW CONCURRENTLY stud_ivanov.mv_monthly_revenue;

-- =====================================================================
-- 7. ТАБЛИЧНЫЕ ФУНКЦИИ
-- =====================================================================

-- 7.1. RETURNS TABLE: заказы клиента за период (параметризованное «представление»)
CREATE OR REPLACE FUNCTION stud_ivanov.fn_customer_orders(
    p_customer_id integer,
    p_from        date DEFAULT DATE '2024-01-01',
    p_to          date DEFAULT DATE '2025-12-31'
)
RETURNS TABLE (
    order_id     integer,
    order_number varchar,
    order_date   date,
    status       varchar,
    net_amount   numeric
)
LANGUAGE sql
STABLE
AS $$
    SELECT o.order_id,
           o.order_number,
           o.order_date,
           o.status,
           ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)), 2)
    FROM   pitanie.orders      AS o
    JOIN   pitanie.order_items AS oi ON oi.order_id = o.order_id
    WHERE  o.customer_id = p_customer_id
      AND  o.order_date BETWEEN p_from AND p_to
    GROUP  BY o.order_id, o.order_number, o.order_date, o.status
    ORDER  BY o.order_date
$$;

-- Вызов во FROM — как таблица
SELECT *
FROM   stud_ivanov.fn_customer_orders(1, DATE '2025-12-01', DATE '2025-12-31');

-- Именованные параметры
SELECT COUNT(*) AS orders, SUM(net_amount) AS total
FROM   stud_ivanov.fn_customer_orders(p_customer_id => 1, p_from => DATE '2025-01-01');

-- 7.2. RETURNS SETOF <тип таблицы>: возвращает строки целиком
CREATE OR REPLACE FUNCTION stud_ivanov.fn_line_batches(p_line_id integer, p_day date)
RETURNS SETOF pitanie.production_batches
LANGUAGE sql
STABLE
AS $$
    SELECT *
    FROM   pitanie.production_batches
    WHERE  line_id = p_line_id
      AND  production_date = p_day
$$;

SELECT batch_number, shift, planned_qty, produced_qty, defect_qty
FROM   stud_ivanov.fn_line_batches(3, DATE '2025-06-10');

-- 7.3. Функция + LATERAL (аналог CROSS APPLY из T-SQL):
--      для каждого клиента типа «Маркетплейс» — его последние 2 заказа
SELECT c.customer_name,
       f.order_number,
       f.order_date,
       f.net_amount
FROM   pitanie.customers AS c
CROSS  JOIN LATERAL (
       SELECT *
       FROM   stud_ivanov.fn_customer_orders(c.customer_id)
       ORDER  BY order_date DESC
       LIMIT  2
) AS f
WHERE  c.customer_type = 'Маркетплейс'
ORDER  BY c.customer_name, f.order_date DESC;

-- 7.4. Встраивание (inlining): SQL-функция из одного SELECT, STABLE/IMMUTABLE,
--      без SECURITY DEFINER — планировщик подставляет её текст в запрос,
--      как inline TVF в T-SQL. В плане нет «Function Scan».
EXPLAIN (COSTS OFF)
SELECT *
FROM   stud_ivanov.fn_line_batches(3, DATE '2025-06-10');

-- Метаданные функции: volatility s = STABLE, retset = true (возвращает набор)
SELECT p.proname, p.provolatile, p.proretset, pg_get_function_arguments(p.oid) AS args
FROM   pg_proc AS p
WHERE  p.pronamespace = 'stud_ivanov'::regnamespace
ORDER  BY p.proname;

-- =====================================================================
-- 8. УБОРКА (по желанию)
-- =====================================================================
-- DROP SCHEMA stud_ivanov CASCADE;   -- удалит ВСЁ в личной схеме!
