-- =====================================================================
-- Курс «Углублённый SQL» · Модуль 6 «Объединение наборов»
-- Практические примеры преподавателя (PostgreSQL 16, схема pitanie)
-- Все запросы проверены на учебной БД. Ожидаемые результаты — в комментариях.
-- =====================================================================

SET search_path TO pitanie, public;

-- ---------------------------------------------------------------------
-- РАЗДЕЛ 1. UNION и UNION ALL
-- ---------------------------------------------------------------------

-- 1.1 Регионы, где у «Питание +» есть клиенты ИЛИ поставщики (без повторов)
SELECT region_id FROM customers WHERE region_id IS NOT NULL
UNION
SELECT region_id FROM suppliers
ORDER  BY region_id;
-- 12 строк

-- 1.2 UNION ALL сохраняет все строки (73 клиента − 3 без региона + 12 поставщиков)
SELECT COUNT(*) AS cnt
FROM  (SELECT region_id FROM customers WHERE region_id IS NOT NULL
       UNION ALL
       SELECT region_id FROM suppliers) AS t;
-- 82

-- 1.3 Единый справочник контактов с признаком источника
--     Имена столбцов берутся из ПЕРВОГО запроса; ORDER BY — один, в самом конце.
SELECT 'Сотрудник' AS contact_type, full_name     AS name, phone FROM employees
UNION ALL
SELECT 'Клиент',                     customer_name,         phone FROM customers
UNION ALL
SELECT 'Поставщик',                  supplier_name,         phone FROM suppliers
ORDER  BY contact_type, name
LIMIT  10;

-- 1.4 Сводка по источникам того же набора
SELECT contact_type, COUNT(*) AS cnt, COUNT(phone) AS with_phone
FROM  (SELECT 'Сотрудник' AS contact_type, phone FROM employees
       UNION ALL
       SELECT 'Клиент',    phone FROM customers
       UNION ALL
       SELECT 'Поставщик', phone FROM suppliers) AS c
GROUP  BY contact_type
ORDER  BY contact_type;

-- ---------------------------------------------------------------------
-- РАЗДЕЛ 2. Требования к совместимости наборов
-- ---------------------------------------------------------------------

-- 2.1 ОЖИДАЕМАЯ ОШИБКА: разное число столбцов
SELECT customer_id, customer_name FROM customers
UNION
SELECT supplier_id FROM suppliers;
-- ERROR: each UNION query must have the same number of columns

-- 2.2 ОЖИДАЕМАЯ ОШИБКА: несовместимые типы (integer и date)
SELECT customer_id FROM customers
UNION
SELECT registration_date FROM customers;
-- ERROR: UNION types integer and date cannot be matched

-- 2.3 Явное приведение типов решает проблему
SELECT customer_id::text AS val FROM customers WHERE customer_id <= 2
UNION ALL
SELECT registration_date::text   FROM customers WHERE customer_id <= 2;

-- 2.4 ОЖИДАЕМАЯ ОШИБКА: ORDER BY внутри ветки без скобок
SELECT customer_name FROM customers ORDER BY customer_name
UNION ALL
SELECT supplier_name FROM suppliers;
-- ERROR: syntax error at or near "UNION"

-- 2.5 Правильно: скобки + LIMIT внутри ветки — «3 первых клиента и 3 первых поставщика»
(SELECT customer_name AS name FROM customers ORDER BY customer_name LIMIT 3)
UNION ALL
(SELECT supplier_name         FROM suppliers ORDER BY supplier_name LIMIT 3);

-- ---------------------------------------------------------------------
-- РАЗДЕЛ 3. INTERSECT и EXCEPT
-- ---------------------------------------------------------------------

-- 3.1 INTERSECT: материалы, которые поставляют и АгроСнаб-М (3), и Специи и Ко (12)
SELECT poi.material_id
FROM   purchase_order_items poi JOIN purchase_orders po ON po.po_id = poi.po_id
WHERE  po.supplier_id = 3
INTERSECT
SELECT poi.material_id
FROM   purchase_order_items poi JOIN purchase_orders po ON po.po_id = poi.po_id
WHERE  po.supplier_id = 12
ORDER  BY 1;
-- 4 строки: 15 соль, 16 ванилин, 18 желатин, 24 чеснок

-- 3.2 EXCEPT: клиенты, покупавшие в 2024 г., но не покупавшие в 2025 г.
SELECT customer_id FROM orders
WHERE  order_date <  DATE '2025-01-01' AND status <> 'Отменён'
EXCEPT
SELECT customer_id FROM orders
WHERE  order_date >= DATE '2025-01-01' AND status <> 'Отменён';
-- 0 строк — на уровне клиентов оттока нет. Пустой результат — тоже результат!

-- 3.3 EXCEPT по паре столбцов: «клиент — товар», которые были в 2024 г. и исчезли в 2025 г.
SELECT COUNT(*) AS lost_pairs
FROM  (SELECT o.customer_id, oi.product_id
       FROM   orders o JOIN order_items oi ON oi.order_id = o.order_id
       WHERE  o.order_date <  DATE '2025-01-01' AND o.status <> 'Отменён'
       EXCEPT
       SELECT o.customer_id, oi.product_id
       FROM   orders o JOIN order_items oi ON oi.order_id = o.order_id
       WHERE  o.order_date >= DATE '2025-01-01' AND o.status <> 'Отменён') AS t;
-- 127

-- 3.4 EXCEPT несимметричен: A − B ≠ B − A
SELECT po.supplier_id, poi.material_id
FROM   purchase_orders po JOIN purchase_order_items poi ON poi.po_id = po.po_id
WHERE  po.order_date >= DATE '2025-01-01'
EXCEPT
SELECT po.supplier_id, poi.material_id
FROM   purchase_orders po JOIN purchase_order_items poi ON poi.po_id = po.po_id
WHERE  po.order_date <  DATE '2025-01-01'
ORDER  BY 1, 2;
-- 4 строки: новый поставщик 12 «Специи и Ко» — материалы 15, 16, 18, 24
-- А в обратную сторону (2024 EXCEPT 2025) — 0 строк: ни одну пару «поставщик-материал» не прекратили.

-- ---------------------------------------------------------------------
-- РАЗДЕЛ 4. ALL-варианты и NULL в операциях над множествами
-- ---------------------------------------------------------------------

-- 4.1 Мультимножества: UNION / UNION ALL / INTERSECT ALL / EXCEPT ALL на VALUES
SELECT x FROM (VALUES (1),(1),(1),(2),(NULL)) a(x)
INTERSECT ALL
SELECT x FROM (VALUES (1),(1),(3),(NULL)) b(x)
ORDER  BY x;
-- 1, 1, NULL — каждый элемент берётся min(m, n) раз; NULL совпадает с NULL!

SELECT x FROM (VALUES (1),(1),(1),(2),(NULL)) a(x)
EXCEPT ALL
SELECT x FROM (VALUES (1),(1),(3),(NULL)) b(x)
ORDER  BY x;
-- 1, 2 — каждый элемент берётся max(m − n, 0) раз

SELECT x FROM (VALUES (1),(1),(1),(2),(NULL)) a(x)
EXCEPT
SELECT x FROM (VALUES (1),(1),(3),(NULL)) b(x);
-- 2

-- 4.2 Сравните с NOT IN: NULL в правом наборе «ломает» NOT IN, но не EXCEPT
SELECT x FROM (VALUES (1),(2)) a(x)
WHERE  x NOT IN (SELECT y FROM (VALUES (1),(NULL::int)) b(y));
-- 0 строк

-- 4.3 EXCEPT ALL на реальных данных: сколько возвратов «лишние» по числу строк
SELECT COUNT(*) AS cnt
FROM  (SELECT product_id FROM returns
       EXCEPT ALL
       SELECT product_id FROM returns WHERE reason = 'Истёк срок годности') AS t;
-- 102 строки возвратов по другим причинам (308 − 206)

-- ---------------------------------------------------------------------
-- РАЗДЕЛ 5. Приоритет операций
-- ---------------------------------------------------------------------

-- 5.1 INTERSECT связывает сильнее, чем UNION / EXCEPT
SELECT x FROM (VALUES (1),(2)) a(x)
UNION
SELECT x FROM (VALUES (3)) b(x)
INTERSECT
SELECT x FROM (VALUES (1)) c(x)
ORDER  BY x;
-- 1, 2   ← вычислено как A UNION (B INTERSECT C)

-- 5.2 Скобки меняют порядок
(SELECT x FROM (VALUES (1),(2)) a(x)
 UNION
 SELECT x FROM (VALUES (3)) b(x))
INTERSECT
SELECT x FROM (VALUES (1)) c(x);
-- 1

-- 5.3 UNION и EXCEPT одного приоритета — выполняются слева направо
SELECT x FROM (VALUES (1),(2)) a(x)
EXCEPT
SELECT x FROM (VALUES (2)) b(x)
UNION
SELECT x FROM (VALUES (2)) c(x)
ORDER  BY x;
-- 1, 2   ← (A EXCEPT B) UNION C

-- ---------------------------------------------------------------------
-- РАЗДЕЛ 6. LATERAL — аналог CROSS APPLY / OUTER APPLY
-- ---------------------------------------------------------------------

-- 6.1 CROSS JOIN LATERAL: 3 крупнейших заказа каждого клиента (top-N на группу)
SELECT c.customer_name,
       t.order_number,
       t.order_date,
       t.amount
FROM   customers AS c
CROSS  JOIN LATERAL (
         SELECT o.order_number, o.order_date, i.amount
         FROM   orders   AS o
         JOIN   invoices AS i ON i.order_id = o.order_id
         WHERE  o.customer_id = c.customer_id      -- ссылка на внешнюю таблицу
         ORDER  BY i.amount DESC
         LIMIT  3) AS t
ORDER  BY c.customer_name, t.amount DESC
LIMIT  9;

-- 6.2 Сколько строк вернулось и кого «потеряли»
SELECT COUNT(*) AS rows_cnt, COUNT(DISTINCT c.customer_id) AS customers_cnt
FROM   customers AS c
CROSS  JOIN LATERAL (SELECT i.amount
                     FROM   orders o JOIN invoices i ON i.order_id = o.order_id
                     WHERE  o.customer_id = c.customer_id
                     ORDER  BY i.amount DESC
                     LIMIT  3) AS t;
-- 216 строк, 72 клиента — клиент 73 без заказов исчез (как при CROSS APPLY)

-- 6.3 LEFT JOIN LATERAL ... ON TRUE (= OUTER APPLY): все сотрудники отдела продаж
--     и их последний заказ; у тех, кто не продаёт, — NULL
SELECT e.employee_id,
       e.full_name,
       e.position,
       lo.order_number,
       lo.order_date
FROM   employees AS e
LEFT   JOIN LATERAL (
         SELECT o.order_number, o.order_date
         FROM   orders AS o
         WHERE  o.employee_id = e.employee_id
         ORDER  BY o.order_date DESC, o.order_id DESC
         LIMIT  1) AS lo ON TRUE
WHERE  e.department = 'Продажи'
ORDER  BY e.employee_id;
-- 11 строк; у 3 Громова и 9 Ершовой (руководители) — NULL; у 60 Попова (уволен) — последний 2024-06-28

-- 6.4 Последняя поставка каждого материала и её поставщик
SELECT m.material_name,
       lp.order_date,
       lp.supplier_name,
       lp.unit_price
FROM   raw_materials AS m
CROSS  JOIN LATERAL (
         SELECT po.order_date, s.supplier_name, poi.unit_price
         FROM   purchase_order_items AS poi
         JOIN   purchase_orders      AS po ON po.po_id       = poi.po_id
         JOIN   suppliers            AS s  ON s.supplier_id  = po.supplier_id
         WHERE  poi.material_id = m.material_id
         ORDER  BY po.order_date DESC, poi.po_item_id DESC
         LIMIT  1) AS lp
ORDER  BY m.material_id
LIMIT  8;

-- 6.5 LATERAL с несколькими агрегатами за один проход (вместо 3 скалярных подзапросов)
SELECT l.line_name, s.batches, s.defect_pct, s.last_batch
FROM   production_lines AS l
CROSS  JOIN LATERAL (
         SELECT COUNT(*)                                           AS batches,
                ROUND(100.0 * SUM(b.defect_qty) / SUM(b.produced_qty), 2) AS defect_pct,
                MAX(b.production_date)                             AS last_batch
         FROM   production_batches b
         WHERE  b.line_id = l.line_id) AS s
ORDER  BY l.line_id;

-- 6.6 LATERAL + generate_series: календарь месяцев 2025 г. и выручка каждого месяца
SELECT to_char(m.month, 'YYYY-MM') AS month,
       r.revenue
FROM   generate_series(DATE '2025-01-01', DATE '2025-12-01', INTERVAL '1 month') AS m(month)
CROSS  JOIN LATERAL (
         SELECT ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100))) AS revenue
         FROM   orders o JOIN order_items oi ON oi.order_id = o.order_id
         WHERE  o.status <> 'Отменён'
           AND  o.order_date >= m.month
           AND  o.order_date <  m.month + INTERVAL '1 month') AS r
ORDER  BY m.month;

-- 6.7 LATERAL + unnest: «развернуть» массив смен в строки и посчитать брак по каждой
SELECT l.line_id, sh.shift,
       (SELECT ROUND(100.0 * SUM(b.defect_qty) / SUM(b.produced_qty), 2)
        FROM   production_batches b
        WHERE  b.line_id = l.line_id AND b.shift = sh.shift) AS defect_pct
FROM   production_lines AS l
CROSS  JOIN LATERAL unnest(ARRAY['День', 'Ночь']) AS sh(shift)
ORDER  BY l.line_id, sh.shift;
-- Линия 3: День 1,62 %, Ночь 7,94 % — на остальных линиях смены не различаются

-- 6.8 ОЖИДАЕМАЯ ОШИБКА: без LATERAL подзапрос в FROM не видит соседние таблицы
SELECT c.customer_name, t.order_number
FROM   customers AS c
CROSS  JOIN (SELECT o.order_number
             FROM   orders o
             WHERE  o.customer_id = c.customer_id
             LIMIT  3) AS t;
-- ERROR: invalid reference to FROM-clause entry for table "c"
