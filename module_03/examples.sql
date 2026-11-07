-- =====================================================================
-- Курс «Углублённый SQL». Модуль 3. Извлечение данных из нескольких таблиц
-- Практические примеры преподавателя (сквозной пример «Питание +»)
-- СУБД: PostgreSQL 16 (Yandex Managed Service for PostgreSQL)
-- Все запросы только читают данные схемы pitanie.
-- =====================================================================

SET search_path TO pitanie, public;

-- =====================================================================
-- 1. ДЕКАРТОВО ПРОИЗВЕДЕНИЕ — ОСНОВА ЛЮБОГО JOIN
-- =====================================================================

-- 1.1. Маленький набор: 5 линий × 2 смены = 10 строк.
--      Смены заданы «на лету» конструктором VALUES.
SELECT l.line_id,
       l.line_name,
       s.shift
FROM   production_lines AS l
CROSS  JOIN (VALUES ('День'), ('Ночь')) AS s (shift)
ORDER  BY l.line_id, s.shift;
-- Ожидаемо: 10 строк

-- 1.2. Старый синтаксис через запятую — то же декартово произведение.
--      Забытое условие соединения = «взрыв» числа строк.
SELECT COUNT(*) AS rows_without_condition      -- 4458 * 73 = 325 434
FROM   orders, customers;

-- 1.3. JOIN = декартово произведение + фильтр по условию.
--      Оба запроса возвращают 4458 строк.
SELECT COUNT(*) AS rows_old_style
FROM   orders, customers
WHERE  orders.customer_id = customers.customer_id;

SELECT COUNT(*) AS rows_inner_join
FROM   orders    AS o
JOIN   customers AS c ON c.customer_id = o.customer_id;

-- 1.4. Как растёт число строк: таблица × таблица × таблица
SELECT (SELECT COUNT(*) FROM production_lines)                     AS lines,      -- 5
       (SELECT COUNT(*) FROM production_lines) * 2                 AS lines_x_shifts, -- 10
       (SELECT COUNT(*) FROM production_lines) * 2 * 730           AS lines_x_shifts_x_days; -- 7300

-- =====================================================================
-- 2. CROSS JOIN — ГЕНЕРАЦИЯ «СЕТОК» (КАРКАСОВ ОТЧЁТА)
-- =====================================================================

-- 2.1. Сетка «месяц 2025 × категория верхнего уровня»: 12 × 3 = 36 ячеек.
SELECT m.month_start::date AS month_start,
       pc.category_name
FROM   generate_series(DATE '2025-01-01', DATE '2025-12-01', INTERVAL '1 month') AS m (month_start)
CROSS  JOIN product_categories AS pc
WHERE  pc.parent_category_id IS NULL
ORDER  BY month_start, pc.category_id;
-- Ожидаемо: 36 строк

-- 2.2. Сетка + LEFT JOIN к факту: в каких ячейках «линия × смена» в декабре 2025
--      нет партий? Сетка = все дни декабря × 5 линий × 2 смены = 310 ячеек.
SELECT d.prod_date::date AS prod_date,
       l.line_id,
       s.shift
FROM   generate_series(DATE '2025-12-01', DATE '2025-12-31', INTERVAL '1 day') AS d (prod_date)
CROSS  JOIN production_lines AS l
CROSS  JOIN (VALUES ('День'), ('Ночь')) AS s (shift)
LEFT   JOIN production_batches AS b
       ON  b.line_id         = l.line_id
       AND b.production_date = d.prod_date
       AND b.shift           = s.shift
WHERE  b.batch_id IS NULL
ORDER  BY prod_date, l.line_id;
-- Ожидаемо: 48 «пустых» смен: по воскресеньям стоят все линии (4 вс × 10 = 40),
-- по субботам нет ночной смены на линиях 4 и 5 (4 сб × 2 = 8)

-- =====================================================================
-- 3. INNER JOIN
-- =====================================================================

-- 3.1. Заказ + клиент + менеджер (три таблицы, две связи)
SELECT o.order_number,
       o.order_date,
       c.customer_name,
       e.full_name AS manager
FROM   orders    AS o
JOIN   customers AS c ON c.customer_id = o.customer_id
JOIN   employees AS e ON e.employee_id = o.employee_id
WHERE  o.order_date >= DATE '2025-12-30'
ORDER  BY o.order_date, o.order_number;

-- 3.2. INNER JOIN отбрасывает строки без пары:
--      клиентов 73, а клиентов, у которых есть заказы, — 72
SELECT COUNT(DISTINCT c.customer_id) AS customers_with_orders
FROM   customers AS c
JOIN   orders    AS o ON o.customer_id = c.customer_id;

-- =====================================================================
-- 4. ВНЕШНИЕ СОЕДИНЕНИЯ: LEFT / RIGHT / FULL
-- =====================================================================

-- 4.1. LEFT JOIN: все клиенты, даже без заказов (NULL в столбцах заказа)
SELECT c.customer_id,
       c.customer_name,
       o.order_number,
       o.order_date
FROM   customers AS c
LEFT   JOIN orders AS o ON o.customer_id = c.customer_id
WHERE  c.customer_id IN (72, 73)
ORDER  BY c.customer_id, o.order_date;

-- 4.2. RIGHT JOIN — зеркальная запись LEFT JOIN (на практике пишут LEFT)
SELECT c.customer_name,
       r.region_name
FROM   regions   AS r
RIGHT  JOIN customers AS c ON c.region_id = r.region_id
WHERE  r.region_id IS NULL;
-- Ожидаемо: 3 клиента без региона (Фермер, Мегаполис, Юпитер)

-- 4.3. FULL OUTER JOIN: регионы ↔ поставщики.
--      Слева — регионы без поставщиков, справа — поставщики без региона.
SELECT r.region_name,
       s.supplier_name
FROM   regions   AS r
FULL   JOIN suppliers AS s ON s.region_id = r.region_id
ORDER  BY r.region_id NULLS LAST, s.supplier_id;
-- Ожидаемо: 17 строк, в 5 из них supplier_name IS NULL

-- =====================================================================
-- 5. ЛОВУШКА: УСЛОВИЕ В ON ИЛИ В WHERE ДЛЯ ВНЕШНЕГО СОЕДИНЕНИЯ
-- =====================================================================

-- 5.1. ПРАВИЛЬНО: фильтр по правой таблице — в ON.
--      Все 73 клиента, у тех, кто не заказывал в декабре 2025, — NULL.
SELECT COUNT(*)                     AS row_cnt,
       COUNT(DISTINCT c.customer_id) AS customers,
       COUNT(o.order_id)             AS dec_orders
FROM   customers AS c
LEFT   JOIN orders AS o
       ON  o.customer_id = c.customer_id
       AND o.order_date >= DATE '2025-12-01';

-- 5.2. ЛОВУШКА: тот же фильтр в WHERE превращает LEFT JOIN в INNER JOIN —
--      строки с NULL в o.order_date отбрасываются.
SELECT COUNT(*)                     AS row_cnt,
       COUNT(DISTINCT c.customer_id) AS customers,
       COUNT(o.order_id)             AS dec_orders
FROM   customers AS c
LEFT   JOIN orders AS o ON o.customer_id = c.customer_id
WHERE  o.order_date >= DATE '2025-12-01';

-- 5.3. А вот фильтр по ЛЕВОЙ таблице место имеет «только» в WHERE:
--      в ON он не отфильтрует клиентов, а лишь «обнулит» их заказы.
SELECT COUNT(*) AS row_cnt
FROM   customers AS c
LEFT   JOIN orders AS o
       ON  o.customer_id   = c.customer_id
       AND c.customer_type = 'HoReCa';      -- строки всех 73 клиентов останутся!
-- Ожидаемо: 180 строк = 69 клиентов «не HoReCa» с NULL + 111 заказов 4 клиентов HoReCa

-- =====================================================================
-- 6. СОЕДИНЕНИЕ БОЛЕЕ ДВУХ ТАБЛИЦ
-- =====================================================================

-- 6.1. Продажи: orders → order_items → products → product_categories (+ родитель)
SELECT o.order_number,
       p.product_name,
       sub.category_name AS subcategory,
       top.category_name AS category,
       oi.quantity,
       oi.unit_price,
       oi.discount_pct
FROM   orders             AS o
JOIN   order_items        AS oi  ON oi.order_id    = o.order_id
JOIN   products           AS p   ON p.product_id   = oi.product_id
JOIN   product_categories AS sub ON sub.category_id = p.category_id
JOIN   product_categories AS top ON top.category_id = sub.parent_category_id
WHERE  o.order_number = (SELECT MIN(order_number) FROM orders)
ORDER  BY oi.order_item_id;

-- 6.2. Производство: batches → lines → products → recipes → raw_materials.
--      Одна партия «размножается» на число строк рецептуры.
SELECT b.batch_number,
       l.line_name,
       p.product_name,
       m.material_name,
       r.qty_per_unit,
       b.produced_qty,
       ROUND(r.qty_per_unit * b.produced_qty, 2) AS norm_qty
FROM   production_batches AS b
JOIN   production_lines   AS l ON l.line_id     = b.line_id
JOIN   products           AS p ON p.product_id  = b.product_id
JOIN   recipes            AS r ON r.product_id  = b.product_id
JOIN   raw_materials      AS m ON m.material_id = r.material_id
WHERE  b.batch_id = 1
ORDER  BY m.material_id;

-- 6.3. Соединение по составному ключу: норма (recipes) vs факт (material_consumption)
--      для одной партии. Связь по ДВУМ столбцам: партия + материал.
SELECT b.batch_number,
       m.material_name,
       ROUND(r.qty_per_unit * b.produced_qty, 2)                         AS norm_qty,
       mc.quantity                                                       AS fact_qty,
       ROUND(100.0 * mc.quantity / (r.qty_per_unit * b.produced_qty) - 100, 1) AS deviation_pct
FROM   production_batches   AS b
JOIN   recipes              AS r  ON r.product_id = b.product_id
JOIN   material_consumption AS mc ON mc.batch_id   = b.batch_id
                                 AND mc.material_id = r.material_id
JOIN   raw_materials        AS m  ON m.material_id = r.material_id
WHERE  b.batch_id = 1
ORDER  BY m.material_id;

-- =====================================================================
-- 7. USING и NATURAL JOIN
-- =====================================================================

-- 7.1. USING — короткая запись для одноимённых ключей; столбец order_id
--      в результате один (без префикса)
SELECT order_id,
       o.order_number,
       i.invoice_number,
       i.amount
FROM   orders   AS o
JOIN   invoices AS i USING (order_id)
WHERE  order_id <= 3;

-- 7.2. NATURAL JOIN соединяет по ВСЕМ одноимённым столбцам.
--      invoices и payments имеют общие invoice_id И amount!
--      Получаем только оплаты, равные сумме счета: 3477 строк вместо 4519.
SELECT COUNT(*) AS natural_rows
FROM   invoices NATURAL JOIN payments;

SELECT COUNT(*) AS correct_rows
FROM   invoices AS i
JOIN   payments AS p ON p.invoice_id = i.invoice_id;

-- 7.3. Ещё хуже: employees и customers — общие столбцы manager_id, email, phone.
--      NATURAL JOIN «молча» возвращает 0 строк.
SELECT COUNT(*) AS natural_rows
FROM   employees NATURAL JOIN customers;

-- =====================================================================
-- 8. НЕИЗВЕСТНЫЕ ЗНАЧЕНИЯ: NULL ПОСЛЕ OUTER JOIN, COALESCE, «СИРОТЫ»
-- =====================================================================

-- 8.1. Anti-join: клиенты без единого заказа
SELECT c.customer_id,
       c.customer_name,
       c.registration_date
FROM   customers AS c
LEFT   JOIN orders AS o ON o.customer_id = c.customer_id
WHERE  o.order_id IS NULL;
-- Ожидаемо: 1 строка — ООО "Новый горизонт" (зарегистрирован 20.11.2025)

-- 8.2. Счета без единой оплаты (проверять NULL нужно в столбце-ключе
--      правой таблицы, который не может быть NULL в самих данных)
SELECT i.invoice_number,
       i.invoice_date,
       i.due_date,
       i.amount,
       c.customer_name
FROM   invoices  AS i
JOIN   orders    AS o ON o.order_id    = i.order_id
JOIN   customers AS c ON c.customer_id = o.customer_id
LEFT   JOIN payments AS p ON p.invoice_id = i.invoice_id
WHERE  p.payment_id IS NULL
ORDER  BY i.amount DESC
LIMIT  10;
-- Всего таких счетов 229

-- 8.3. COALESCE: заменяем NULL после внешнего соединения подписью
SELECT c.customer_name,
       COALESCE(r.region_name, '— регион не указан —') AS region_name,
       COALESCE(r.federal_district, 'н/д')              AS federal_district
FROM   customers AS c
LEFT   JOIN regions AS r ON r.region_id = c.region_id
WHERE  c.region_id IS NULL OR c.customer_id <= 2
ORDER  BY c.customer_id;

-- 8.4. Материалы, которые ни разу не списывались
SELECT m.material_id,
       m.material_name
FROM   raw_materials AS m
LEFT   JOIN material_writeoffs AS w ON w.material_id = m.material_id
WHERE  w.writeoff_id IS NULL
ORDER  BY m.material_id;
-- Ожидаемо: 2 строки (Соль пищевая, Сухофрукты микс)

-- 8.5. Менеджеры отдела продаж без закреплённых клиентов
SELECT e.employee_id,
       e.full_name,
       e.position
FROM   employees AS e
LEFT   JOIN customers AS c ON c.manager_id = e.employee_id
WHERE  e.department = 'Продажи'
  AND  c.customer_id IS NULL
ORDER  BY e.employee_id;
-- Ожидаемо: 3 строки (Громов, Ершова — руководители; Попов — уволен)

-- =====================================================================
-- 9. SELF-JOIN
-- =====================================================================

-- 9.1. Сотрудник и его руководитель. LEFT — чтобы не потерять гендиректора.
SELECT e.employee_id,
       e.full_name,
       e.position,
       COALESCE(m.full_name, '— (высшее руководство)') AS manager
FROM   employees AS e
LEFT   JOIN employees AS m ON m.employee_id = e.manager_id
ORDER  BY e.employee_id;
-- 35 строк

-- 9.2. Три уровня иерархии: сотрудник → руководитель → руководитель руководителя
SELECT e.full_name  AS employee,
       m1.full_name AS manager,
       m2.full_name AS manager_of_manager
FROM   employees AS e
JOIN   employees AS m1 ON m1.employee_id = e.manager_id
LEFT   JOIN employees AS m2 ON m2.employee_id = m1.manager_id
WHERE  e.department = 'Продажи'
  AND  e.position   = 'Менеджер по продажам'
ORDER  BY e.full_name;

-- 9.3. Классификатор: подкатегория и её родитель
SELECT child.category_id,
       child.category_name  AS subcategory,
       parent.category_name AS category
FROM   product_categories AS child
JOIN   product_categories AS parent ON parent.category_id = child.parent_category_id
ORDER  BY child.category_id;
-- 7 строк

-- 9.4. Сравнение строк одной таблицы: один материал, один месяц, разные поставщики.
--      Ищем пары закупок, где цена у одного поставщика выше другого более чем на 15 %.
SELECT a.material_id,
       m.material_name,
       sa.supplier_name AS expensive_supplier,
       a.unit_price     AS expensive_price,
       sb.supplier_name AS cheap_supplier,
       b.unit_price     AS cheap_price,
       poa.order_date   AS expensive_date,
       pob.order_date   AS cheap_date
FROM   purchase_order_items AS a
JOIN   purchase_orders      AS poa ON poa.po_id = a.po_id
JOIN   purchase_order_items AS b   ON b.material_id = a.material_id
JOIN   purchase_orders      AS pob ON pob.po_id = b.po_id
JOIN   suppliers            AS sa  ON sa.supplier_id = poa.supplier_id
JOIN   suppliers            AS sb  ON sb.supplier_id = pob.supplier_id
JOIN   raw_materials        AS m   ON m.material_id = a.material_id
WHERE  poa.supplier_id <> pob.supplier_id
  AND  date_trunc('month', poa.order_date) = date_trunc('month', pob.order_date)
  AND  a.unit_price > b.unit_price * 1.15
  AND  a.material_id = 4                                  -- Сахар-песок
  AND  poa.order_date >= DATE '2025-12-01'
ORDER  BY a.unit_price - b.unit_price DESC
LIMIT  10;

-- 9.5. Self-join «пар» без дублей: условие a.id < b.id убирает зеркальные пары (A,B)/(B,A)
--      Пары менеджеров по продажам с одним и тем же руководителем
SELECT a.full_name AS employee_1,
       b.full_name AS employee_2
FROM   employees AS a
JOIN   employees AS b
       ON  b.manager_id  = a.manager_id
       AND a.employee_id < b.employee_id
WHERE  a.manager_id = 5;                 -- подчинённые начальника отдела закупок
-- Ожидаемо: 3 пары (Карпов–Сидорова, Карпов–Абрамов, Сидорова–Абрамов)

-- =====================================================================
-- 10. ЭФФЕКТ «РАЗМНОЖЕНИЯ СТРОК» ПРИ JOIN С ТАБЛИЦЕЙ «МНОГИЕ»
-- =====================================================================

-- 10.1. Правильная сумма выставленных счетов
SELECT SUM(i.amount) AS invoiced_correct
FROM   invoices AS i;

-- 10.2. Присоединили оплаты (по счёту бывает несколько оплат) —
--       сумма счетов «выросла»: каждый счёт посчитан столько раз, сколько у него оплат.
--       Ожидаемо: 821 243 564,75 → 923 186 907,89 (+101,9 млн «из воздуха»), 4748 строк
SELECT SUM(i.amount) AS invoiced_inflated,
       COUNT(*)      AS row_cnt
FROM   invoices AS i
LEFT   JOIN payments AS p ON p.invoice_id = i.invoice_id;

-- 10.3. Пример одного счёта с несколькими оплатами
SELECT i.invoice_number,
       i.amount AS invoice_amount,
       p.payment_date,
       p.amount AS payment_amount
FROM   invoices AS i
JOIN   payments AS p ON p.invoice_id = i.invoice_id
WHERE  i.invoice_id = (SELECT invoice_id
                       FROM   payments
                       GROUP  BY invoice_id
                       ORDER  BY COUNT(*) DESC, invoice_id
                       LIMIT  1)
ORDER  BY p.payment_date;

-- 10.4. Две «многие» таблицы к одной «одной» — перемножение:
--       заказ × позиции × возвраты
SELECT o.order_id,
       COUNT(DISTINCT oi.order_item_id) AS items,
       COUNT(DISTINCT r.return_id)      AS returns_cnt,
       COUNT(*)                         AS joined_rows
FROM   orders      AS o
JOIN   order_items AS oi ON oi.order_id = o.order_id
JOIN   returns     AS r  ON r.order_id  = o.order_id
GROUP  BY o.order_id
ORDER  BY joined_rows DESC
LIMIT  5;
