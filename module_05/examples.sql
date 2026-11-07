-- =====================================================================
-- Курс «Углублённый SQL» · Модуль 5 «Использование вложенных запросов»
-- Практические примеры преподавателя (PostgreSQL 16, схема pitanie)
-- Все запросы проверены на учебной БД. Ожидаемые результаты — в комментариях.
-- =====================================================================

SET search_path TO pitanie, public;

-- ---------------------------------------------------------------------
-- РАЗДЕЛ 1. Некоррелированный скалярный подзапрос
-- Подзапрос выполняется ОДИН раз, возвращает одно значение (1 строка × 1 столбец).
-- ---------------------------------------------------------------------

-- 1.1 Средняя скидка по компании (именно это значение подставится в WHERE)
SELECT ROUND(AVG(discount_pct), 2) AS avg_discount
FROM   order_items;
-- 7.25

-- 1.2 Сколько позиций продано со скидкой выше средней по компании
SELECT COUNT(*) AS items_above_avg
FROM   order_items
WHERE  discount_pct > (SELECT AVG(discount_pct) FROM order_items);
-- 5 483

-- 1.3 Скалярный подзапрос в SELECT: доля каждой позиции прайса от максимальной цены
SELECT product_name,
       base_price,
       ROUND(100.0 * base_price / (SELECT MAX(base_price) FROM products), 1) AS pct_of_max
FROM   products
ORDER  BY base_price DESC
LIMIT  5;

-- 1.4 ОЖИДАЕМАЯ ОШИБКА: скалярный подзапрос вернул больше одной строки
SELECT product_name
FROM   products
WHERE  base_price = (SELECT base_price FROM products WHERE category_id = 13);
-- ERROR: more than one row returned by a subquery used as an expression

-- ---------------------------------------------------------------------
-- РАЗДЕЛ 2. Многострочный подзапрос: IN, ANY / SOME, ALL
-- ---------------------------------------------------------------------

-- 2.1 IN: клиенты из регионов Сибирского федерального округа
SELECT customer_id, customer_name, customer_type
FROM   customers
WHERE  region_id IN (SELECT region_id
                     FROM   regions
                     WHERE  federal_district = 'Сибирский')
ORDER  BY customer_name;
-- 15 строк

-- 2.2 = ANY — то же самое, что IN
SELECT COUNT(*)
FROM   customers
WHERE  region_id = ANY (SELECT region_id
                        FROM   regions
                        WHERE  federal_district = 'Сибирский');
-- 15

-- 2.3 > ALL: продукты дороже ЛЮБОГО печенья/вафель (категория 21)
SELECT product_name, base_price
FROM   products
WHERE  base_price > ALL (SELECT base_price
                         FROM   products
                         WHERE  category_id = 21)
ORDER  BY base_price;
-- 15 строк (максимум печенья/вафель — 99 руб.)

-- 2.4 > ANY (SOME): продукты дороже ХОТЯ БЫ ОДНОГО продукта категории 13 «Сыры и масло»
SELECT COUNT(*) AS cnt
FROM   products
WHERE  base_price > SOME (SELECT base_price
                          FROM   products
                          WHERE  category_id = 13);
-- 18

-- 2.5 Ловушка ALL с пустым набором: условие истинно для ВСЕХ строк
SELECT COUNT(*) AS cnt
FROM   products
WHERE  base_price > ALL (SELECT base_price
                         FROM   products
                         WHERE  category_id = 999);   -- такой категории нет
-- 35 (все продукты!)

-- ---------------------------------------------------------------------
-- РАЗДЕЛ 3. Табличный подзапрос в FROM (производная таблица)
-- ---------------------------------------------------------------------

-- 3.1 Сначала считаем показатели по менеджерам, затем фильтруем и сортируем
SELECT m.employee_id,
       e.full_name,
       m.items,
       m.avg_discount,
       m.discount_rub
FROM  (SELECT o.employee_id,
              COUNT(*)                                                AS items,
              ROUND(AVG(oi.discount_pct), 2)                          AS avg_discount,
              ROUND(SUM(oi.quantity * oi.unit_price * oi.discount_pct / 100)) AS discount_rub
       FROM   orders      AS o
       JOIN   order_items AS oi ON oi.order_id = o.order_id
       WHERE  o.status <> 'Отменён'
       GROUP  BY o.employee_id) AS m           -- псевдоним обязателен
JOIN   employees AS e ON e.employee_id = m.employee_id
ORDER  BY m.discount_rub DESC;
-- 9 строк. Лидер — Соколов И. А.: 4 167 позиций, средняя скидка 18,01 %, 38,8 млн руб. скидок

-- 3.2 Производная таблица + скалярный подзапрос: месяцы, где выручка ниже средней месячной
SELECT month, revenue
FROM  (SELECT date_trunc('month', o.order_date)::date AS month,
              ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100))) AS revenue
       FROM   orders AS o
       JOIN   order_items AS oi ON oi.order_id = o.order_id
       WHERE  o.status <> 'Отменён'
       GROUP  BY 1) AS mr
WHERE  revenue < (SELECT AVG(revenue)
                  FROM  (SELECT SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS revenue
                         FROM   orders AS o
                         JOIN   order_items AS oi ON oi.order_id = o.order_id
                         WHERE  o.status <> 'Отменён'
                         GROUP  BY date_trunc('month', o.order_date)) AS t)
ORDER  BY month;

-- ---------------------------------------------------------------------
-- РАЗДЕЛ 4. Коррелированные подзапросы
-- Подзапрос ссылается на столбец внешнего запроса и логически
-- выполняется «для каждой строки» внешнего запроса.
-- ---------------------------------------------------------------------

-- 4.1 Продукты дороже средней цены СВОЕЙ категории
SELECT p.product_name,
       p.category_id,
       p.base_price,
       (SELECT ROUND(AVG(p2.base_price), 2)
        FROM   products AS p2
        WHERE  p2.category_id = p.category_id) AS avg_in_category
FROM   products AS p
WHERE  p.base_price > (SELECT AVG(p2.base_price)
                       FROM   products AS p2
                       WHERE  p2.category_id = p.category_id)   -- корреляция
ORDER  BY p.category_id, p.base_price DESC;

-- 4.2 Партии, брак в которых выше среднего брака СВОЕЙ линии (точка входа для команды Б)
SELECT b.line_id,
       b.shift,
       COUNT(*) AS batches_above_line_avg
FROM   production_batches AS b
WHERE  1.0 * b.defect_qty / b.produced_qty >
       (SELECT 1.0 * SUM(b2.defect_qty) / SUM(b2.produced_qty)
        FROM   production_batches AS b2
        WHERE  b2.line_id = b.line_id)
GROUP  BY b.line_id, b.shift
ORDER  BY b.line_id, b.shift;
-- На линиях 1,2,4,5 выше среднего ~половина партий в обеих сменах.
-- Линия 3: ночь — 627 из 627 партий, день — 0 (строки нет!). Подозрительно.

-- 4.3 Последний заказ каждого клиента
SELECT c.customer_name,
       o.order_number,
       o.order_date
FROM   customers AS c
JOIN   orders    AS o ON o.customer_id = c.customer_id
WHERE  o.order_date = (SELECT MAX(o2.order_date)
                       FROM   orders AS o2
                       WHERE  o2.customer_id = c.customer_id)
ORDER  BY o.order_date
LIMIT  10;
-- Внимание: если у клиента 2 заказа в последний день — будут 2 строки.

-- 4.4 Top-N на группу: 2 самых дорогих продукта в каждой категории
SELECT p.category_id, p.product_name, p.base_price
FROM   products AS p
WHERE  (SELECT COUNT(*)
        FROM   products AS p2
        WHERE  p2.category_id = p.category_id
          AND  p2.base_price  > p.base_price) < 2
ORDER  BY p.category_id, p.base_price DESC;

-- 4.5 Коррелированный подзапрос в SELECT: число заказов и дата последнего заказа клиента
SELECT c.customer_name,
       (SELECT COUNT(*)          FROM orders o WHERE o.customer_id = c.customer_id) AS orders_cnt,
       (SELECT MAX(o.order_date) FROM orders o WHERE o.customer_id = c.customer_id) AS last_order
FROM   customers AS c
ORDER  BY last_order NULLS FIRST
LIMIT  5;
-- Первая строка: ООО "Новый горизонт" — 0 заказов, NULL

-- ---------------------------------------------------------------------
-- РАЗДЕЛ 5. EXISTS / NOT EXISTS — полусоединение и антисоединение
-- ---------------------------------------------------------------------

-- 5.1 EXISTS: клиенты, у которых были возвраты «Истёк срок годности»
SELECT c.customer_name, r.region_name
FROM   customers AS c
LEFT   JOIN regions AS r ON r.region_id = c.region_id
WHERE  EXISTS (SELECT 1
               FROM   orders  AS o
               JOIN   returns AS rt ON rt.order_id = o.order_id
               WHERE  o.customer_id = c.customer_id
                 AND  rt.reason = 'Истёк срок годности')
ORDER  BY r.region_name, c.customer_name;

-- 5.2 NOT EXISTS: клиенты без заказов в последние 3 месяца (с 01.10.2025)
SELECT c.customer_id, c.customer_name
FROM   customers AS c
WHERE  NOT EXISTS (SELECT 1
                   FROM   orders AS o
                   WHERE  o.customer_id = c.customer_id
                     AND  o.order_date >= DATE '2025-10-01');
-- 2 строки: 71 ооо "Свежесть" (дубль!), 73 ООО "Новый горизонт"

-- 5.3 ЛОВУШКА NOT IN + NULL: сотрудники, которые никем не руководят
-- В employees.manager_id есть NULL (у генерального директора)
SELECT COUNT(*) AS not_in_result
FROM   employees
WHERE  employee_id NOT IN (SELECT manager_id FROM employees);
-- 0 (!) — ведь x NOT IN (1, 2, NULL) = UNKNOWN

-- 5.4 Правильно: NOT EXISTS
SELECT COUNT(*) AS not_exists_result
FROM   employees AS e
WHERE  NOT EXISTS (SELECT 1
                   FROM   employees AS s
                   WHERE  s.manager_id = e.employee_id);
-- 26

-- 5.5 Или NOT IN с фильтром NULL в подзапросе
SELECT COUNT(*) AS not_in_fixed
FROM   employees
WHERE  employee_id NOT IN (SELECT manager_id
                           FROM   employees
                           WHERE  manager_id IS NOT NULL);
-- 26

-- 5.6 Ещё одна такая же ловушка: категории-листья (не являющиеся родителями)
SELECT COUNT(*) FROM product_categories
WHERE  category_id NOT IN (SELECT parent_category_id FROM product_categories);      -- 0
SELECT COUNT(*) FROM product_categories AS c
WHERE  NOT EXISTS (SELECT 1 FROM product_categories AS ch
                   WHERE ch.parent_category_id = c.category_id);                     -- 7

-- 5.7 Почему внутри EXISTS пишут SELECT 1: список столбцов не важен, важен факт наличия строки
SELECT COUNT(*) FROM customers c
WHERE  EXISTS (SELECT NULL FROM orders o WHERE o.customer_id = c.customer_id);      -- 72

-- ---------------------------------------------------------------------
-- РАЗДЕЛ 6. Планы выполнения (кратко)
-- ---------------------------------------------------------------------

-- 6.1 EXISTS → Semi Join
EXPLAIN
SELECT c.customer_id
FROM   customers c
WHERE  EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id);

-- 6.2 NOT EXISTS → Anti Join
EXPLAIN
SELECT c.customer_id
FROM   customers c
WHERE  NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id);

-- 6.3 NOT IN → фильтр с hashed SubPlan (anti join невозможен из-за семантики NULL)
EXPLAIN
SELECT c.customer_id
FROM   customers c
WHERE  c.customer_id NOT IN (SELECT o.customer_id FROM orders o);

-- ---------------------------------------------------------------------
-- РАЗДЕЛ 7. Подзапросы в HAVING и ORDER BY
-- ---------------------------------------------------------------------

-- 7.1 HAVING: менеджеры со средней скидкой выше средней по компании
SELECT o.employee_id,
       e.full_name,
       ROUND(AVG(oi.discount_pct), 2) AS avg_discount
FROM   orders      AS o
JOIN   order_items AS oi ON oi.order_id   = o.order_id
JOIN   employees   AS e  ON e.employee_id = o.employee_id
GROUP  BY o.employee_id, e.full_name
HAVING AVG(oi.discount_pct) > (SELECT AVG(discount_pct) FROM order_items)
ORDER  BY avg_discount DESC;
-- 2 строки: Соколов 18,02; Попов 8,21

-- 7.2 ORDER BY: клиенты, отсортированные по сумме возвратов (подзапрос в сортировке)
SELECT c.customer_name
FROM   customers AS c
ORDER  BY (SELECT COALESCE(SUM(r.quantity), 0)
           FROM   returns r
           JOIN   orders  o ON o.order_id = r.order_id
           WHERE  o.customer_id = c.customer_id) DESC
LIMIT  5;

-- ---------------------------------------------------------------------
-- РАЗДЕЛ 8. Подзапрос или JOIN?
-- ---------------------------------------------------------------------

-- 8.1 IN с подзапросом: каждый клиент один раз
SELECT COUNT(*) FROM customers
WHERE  customer_id IN (SELECT customer_id FROM orders WHERE channel = 'Маркетплейс');

-- 8.2 «Наивный» JOIN размножает строки
SELECT COUNT(*) FROM customers c
JOIN   orders o ON o.customer_id = c.customer_id AND o.channel = 'Маркетплейс';

-- 8.3 JOIN + DISTINCT даёт то же, что IN, но дороже по смыслу и ресурсам
SELECT COUNT(DISTINCT c.customer_id) FROM customers c
JOIN   orders o ON o.customer_id = c.customer_id AND o.channel = 'Маркетплейс';

-- 8.4 Когда JOIN лучше: нужны столбцы из второй таблицы или несколько агрегатов
-- (вместо трёх коррелированных подзапросов в SELECT — один проход с GROUP BY)
SELECT c.customer_name,
       COUNT(o.order_id)  AS orders_cnt,
       MIN(o.order_date)  AS first_order,
       MAX(o.order_date)  AS last_order
FROM   customers AS c
LEFT   JOIN orders AS o ON o.customer_id = c.customer_id
GROUP  BY c.customer_id, c.customer_name
ORDER  BY orders_cnt DESC
LIMIT  5;
