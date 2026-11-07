-- =====================================================================
-- Курс «Углублённый SQL» · Модуль 0 · Знакомство с учебной БД «Питание +»
-- Практические примеры преподавателя (проверены на PostgreSQL 16,
-- Yandex Managed Service for PostgreSQL)
-- Все запросы — только чтение. Схема pitanie не изменяется.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Сессия: где мы и кто мы
-- ---------------------------------------------------------------------

-- 1.1 Первая команда каждой сессии: схема по умолчанию
SET search_path TO pitanie, public;

-- 1.2 Версия сервера, текущая БД, пользователь, путь поиска
SELECT version()              AS server_version,
       current_database()     AS db,
       current_user           AS usr,
       current_setting('search_path') AS search_path;

-- 1.3 Адрес сервера и порт, к которому подключились
--     (клиент подключается к порту 6432 — пулеру соединений Odyssey;
--      сервер за пулером слушает 5432. Шифрование
--      проверяется на стороне клиента: sslmode=verify-full + root.crt)
SELECT inet_server_port() AS server_port,
       pg_backend_pid()   AS backend_pid,
       now()              AS server_time;

-- ---------------------------------------------------------------------
-- 2. Каталог: какие таблицы есть в схеме pitanie
-- ---------------------------------------------------------------------

-- 2.1 Список таблиц со служебными комментариями (описанием)
SELECT t.table_name,
       obj_description(format('%I.%I', t.table_schema, t.table_name)::regclass) AS description
FROM   information_schema.tables AS t
WHERE  t.table_schema = 'pitanie'
  AND  t.table_type   = 'BASE TABLE'
ORDER  BY t.table_name;
-- Ожидаемо: 23 таблицы

-- 2.2 Столбцы конкретной таблицы: имя, тип, допускает ли NULL
SELECT column_name,
       data_type,
       character_maximum_length AS max_len,
       numeric_precision        AS prec,
       numeric_scale            AS scale,
       is_nullable
FROM   information_schema.columns
WHERE  table_schema = 'pitanie'
  AND  table_name   = 'order_items'
ORDER  BY ordinal_position;

-- 2.3 Сколько столбцов в каждой таблице
SELECT table_name,
       COUNT(*) AS columns_cnt
FROM   information_schema.columns
WHERE  table_schema = 'pitanie'
GROUP  BY table_name
ORDER  BY columns_cnt DESC, table_name;

-- 2.4 Первичные ключи
SELECT tc.table_name,
       kcu.column_name AS pk_column
FROM   information_schema.table_constraints AS tc
JOIN   information_schema.key_column_usage  AS kcu
       ON  kcu.constraint_name   = tc.constraint_name
       AND kcu.constraint_schema = tc.constraint_schema
WHERE  tc.table_schema    = 'pitanie'
  AND  tc.constraint_type = 'PRIMARY KEY'
ORDER  BY tc.table_name;

-- 2.5 Внешние ключи: кто на кого ссылается (основа ER-схемы)
SELECT con.conrelid::regclass  AS child_table,
       a.attname               AS fk_column,
       con.confrelid::regclass AS parent_table
FROM   pg_constraint AS con
JOIN   pg_attribute  AS a
       ON  a.attrelid = con.conrelid
       AND a.attnum   = ANY (con.conkey)
WHERE  con.contype = 'f'
  AND  con.connamespace = 'pitanie'::regnamespace
ORDER  BY con.conrelid::regclass::text, a.attname;
-- Ожидаемо: 30 связей (внешних ключей)

-- ---------------------------------------------------------------------
-- 3. Объём данных
-- ---------------------------------------------------------------------

-- 3.1 Точное число строк в ключевых таблицах (UNION ALL из COUNT(*))
SELECT 'orders'               AS table_name, COUNT(*) AS rows_cnt FROM orders
UNION ALL SELECT 'order_items',          COUNT(*) FROM order_items
UNION ALL SELECT 'customers',            COUNT(*) FROM customers
UNION ALL SELECT 'invoices',             COUNT(*) FROM invoices
UNION ALL SELECT 'payments',             COUNT(*) FROM payments
UNION ALL SELECT 'returns',              COUNT(*) FROM returns
UNION ALL SELECT 'expenses',             COUNT(*) FROM expenses
UNION ALL SELECT 'production_batches',   COUNT(*) FROM production_batches
UNION ALL SELECT 'material_consumption', COUNT(*) FROM material_consumption
UNION ALL SELECT 'equipment_downtime',   COUNT(*) FROM equipment_downtime
UNION ALL SELECT 'purchase_orders',      COUNT(*) FROM purchase_orders
UNION ALL SELECT 'purchase_order_items', COUNT(*) FROM purchase_order_items
UNION ALL SELECT 'material_writeoffs',   COUNT(*) FROM material_writeoffs
ORDER  BY rows_cnt DESC;

-- 3.2 Оценка числа строк по статистике (быстро, но ПРИБЛИЗИТЕЛЬНО!)
--     n_live_tup может расходиться с COUNT(*), например после перезагрузки
--     данных до очередного autovacuum/ANALYZE. Для отчётов — только COUNT(*).
SELECT relname       AS table_name,
       n_live_tup    AS approx_rows
FROM   pg_stat_user_tables
WHERE  schemaname = 'pitanie'
ORDER  BY n_live_tup DESC;

-- 3.3 Размер таблиц на диске
SELECT c.relname                                  AS table_name,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM   pg_class AS c
WHERE  c.relnamespace = 'pitanie'::regnamespace
  AND  c.relkind = 'r'
ORDER  BY pg_total_relation_size(c.oid) DESC
LIMIT  5;

-- ---------------------------------------------------------------------
-- 4. Период и «формат» данных
-- ---------------------------------------------------------------------

-- 4.1 Период заказов и партий
SELECT 'orders'             AS src, MIN(order_date)      AS date_from, MAX(order_date)      AS date_to FROM orders
UNION ALL
SELECT 'production_batches',        MIN(production_date),              MAX(production_date)            FROM production_batches;

-- 4.2 Первые строки: так выглядят заказы
SELECT order_id, order_number, customer_id, employee_id,
       order_date, shipped_date, status, channel
FROM   orders
ORDER  BY order_id
LIMIT  5;

-- 4.3 Справочники: статусы заказов и каналы продаж
SELECT status, COUNT(*) AS orders_cnt
FROM   orders
GROUP  BY status
ORDER  BY orders_cnt DESC;

SELECT channel, COUNT(*) AS orders_cnt
FROM   orders
GROUP  BY channel
ORDER  BY orders_cnt DESC;

-- 4.4 Классификатор продукции (два уровня)
SELECT parent.category_name AS top_category,
       child.category_name  AS sub_category,
       COUNT(p.product_id)  AS products_cnt
FROM   product_categories AS child
JOIN   product_categories AS parent ON parent.category_id = child.parent_category_id
LEFT   JOIN products      AS p      ON p.category_id      = child.category_id
GROUP  BY parent.category_name, child.category_name
ORDER  BY top_category, sub_category;

-- 4.5 Производственные линии
SELECT line_id, line_name, workshop, capacity_per_hour, launch_year
FROM   production_lines
ORDER  BY line_id;

-- ---------------------------------------------------------------------
-- 5. Первая «разведка»: крупные цифры для руководства
-- ---------------------------------------------------------------------

-- 5.1 Выручка по годам (без отменённых заказов), млн руб.
SELECT EXTRACT(YEAR FROM o.order_date)::int AS yr,
       ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) / 1e6, 1) AS revenue_mln
FROM   orders      AS o
JOIN   order_items AS oi ON oi.order_id = o.order_id
WHERE  o.status <> 'Отменён'
GROUP  BY yr
ORDER  BY yr;

-- 5.2 Выпуск и брак по годам
SELECT EXTRACT(YEAR FROM production_date)::int AS yr,
       SUM(produced_qty)                       AS produced,
       SUM(defect_qty)                         AS defects,
       ROUND(100.0 * SUM(defect_qty) / NULLIF(SUM(produced_qty), 0), 2) AS defect_pct
FROM   production_batches
GROUP  BY yr
ORDER  BY yr;

-- 5.3 Где «грязные» данные: NULL в важных полях
SELECT COUNT(*)                              AS customers_total,
       COUNT(*) FILTER (WHERE region_id IS NULL) AS no_region,
       COUNT(*) FILTER (WHERE email IS NULL)     AS no_email
FROM   customers;

-- 5.4 Пример признака для гипотезы: позиции со скидкой выше политики 10 %
SELECT COUNT(*)                                     AS items_total,
       COUNT(*) FILTER (WHERE discount_pct > 10)    AS items_over_policy,
       MAX(discount_pct)                            AS max_discount
FROM   order_items;
