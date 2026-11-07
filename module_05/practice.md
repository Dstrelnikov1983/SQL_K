# Модуль 5. Практическая работа «Вложенные запросы: от скалярного подзапроса до NOT EXISTS»

| Параметр | Значение |
|---|---|
| Цель | Научиться писать некоррелированные и коррелированные подзапросы, применять `IN`, `ANY/ALL`, `EXISTS/NOT EXISTS`, распознавать ловушку `NOT IN` + `NULL` |
| Время | 45 минут (преподаватель показывает шаг, слушатели повторяют и отвечают на вопросы «Подумайте») |
| Формат | Демонстрация + повторение за преподавателем, индивидуально |
| Файл с кодом | `module_05/examples.sql` (разделы 1–8 соответствуют шагам) |

## Подготовка

1. Подключитесь к учебной БД (DBeaver / pgAdmin / psql):

| Параметр | Значение |
|---|---|
| Сервер | `<адрес_сервера>` |
| Порт | `6432` |
| База | `db1` |
| SSL | `verify-full`, сертификат `root.crt` |

2. Выполните в начале сессии:

```sql
SET search_path TO pitanie, public;
```

3. Проверьте, что данные доступны:

```sql
SELECT COUNT(*) FROM order_items;   -- 17576
```

> Все запросы этой работы — только чтение (`SELECT`). Схему `pitanie` не изменяем.

---

## Шаг 1. Скалярный подзапрос в WHERE

Задача: сколько позиций продано со скидкой выше средней по компании?

```sql
SELECT ROUND(AVG(discount_pct), 2) AS avg_discount
FROM   order_items;
```

**Ожидаемый результат:** `7.25`.

Теперь подставим это значение «на лету»:

```sql
SELECT COUNT(*) AS items_above_avg
FROM   order_items
WHERE  discount_pct > (SELECT AVG(discount_pct) FROM order_items);
```

**Ожидаемый результат:** `5483`.

> **Подумайте.** Почему нельзя написать `WHERE discount_pct > AVG(discount_pct)`? (Агрегат нельзя использовать в `WHERE` — `WHERE` фильтрует строки до группировки.)

**Типичная ошибка** — скалярный подзапрос вернул несколько строк:

```sql
-- ОЖИДАЕМАЯ ОШИБКА
SELECT product_name
FROM   products
WHERE  base_price = (SELECT base_price FROM products WHERE category_id = 13);
-- ERROR: more than one row returned by a subquery used as an expression
```

Исправление: `IN (...)`, `= ANY (...)` или агрегат в подзапросе (`MAX`, `MIN`).

---

## Шаг 2. Многострочный подзапрос: IN, ANY, ALL

```sql
SELECT customer_id, customer_name, customer_type
FROM   customers
WHERE  region_id IN (SELECT region_id
                     FROM   regions
                     WHERE  federal_district = 'Сибирский')
ORDER  BY customer_name;
```

**Ожидаемый результат:** 15 клиентов (АО "Восход", АО "Перекрёсток Регион", ...).

Сравнения с набором:

```sql
-- дороже ЛЮБОГО печенья/вафель (категория 21)
SELECT product_name, base_price
FROM   products
WHERE  base_price > ALL (SELECT base_price FROM products WHERE category_id = 21)
ORDER  BY base_price;
```

**Ожидаемый результат:** 15 строк, начиная с «Молоко ультрапастеризованное 3,2 % — 112.00» (максимальная цена печенья — 99).

| Запись | Смысл | Эквивалент |
|---|---|---|
| `x = ANY (подзапрос)` | равен хотя бы одному | `x IN (подзапрос)` |
| `x > ANY (подзапрос)` | больше хотя бы одного | `x > (SELECT MIN(...))` |
| `x > ALL (подзапрос)` | больше всех | `x > (SELECT MAX(...))` — **но** см. ниже |
| `x <> ALL (подзапрос)` | не равен ни одному | `x NOT IN (подзапрос)` |

Ловушка пустого набора:

```sql
SELECT COUNT(*) FROM products
WHERE  base_price > ALL (SELECT base_price FROM products WHERE category_id = 999);
```

**Ожидаемый результат:** `35` — все продукты! `ALL` над пустым набором истинно, а `> (SELECT MAX(...))` дало бы 0 строк (`MAX` пустого набора — `NULL`).

> **Подумайте.** В каком бизнес-отчёте такая разница может привести к неверному выводу?

---

## Шаг 3. Производная таблица в FROM

Посчитаем показатели менеджеров, а затем отсортируем:

```sql
SELECT m.employee_id, e.full_name, m.items, m.avg_discount, m.discount_rub
FROM  (SELECT o.employee_id,
              COUNT(*)                                                      AS items,
              ROUND(AVG(oi.discount_pct), 2)                                AS avg_discount,
              ROUND(SUM(oi.quantity * oi.unit_price * oi.discount_pct / 100)) AS discount_rub
       FROM   orders      AS o
       JOIN   order_items AS oi ON oi.order_id = o.order_id
       WHERE  o.status <> 'Отменён'
       GROUP  BY o.employee_id) AS m
JOIN   employees AS e ON e.employee_id = m.employee_id
ORDER  BY m.discount_rub DESC;
```

**Ожидаемый результат (фрагмент):**

| employee_id | full_name | items | avg_discount | discount_rub |
|---|---|---|---|---|
| 10 | Соколов Игорь Андреевич | 4167 | 18.01 | 38 779 099 |
| 11 | Морозова Елена Павловна | 3625 | 4.02 | 10 324 708 |
| 16 | Павлов Сергей Дмитриевич | 1590 | 5.23 | 7 095 398 |

> **Подумайте.** Политика компании — скидка не более 10 %. Что говорит средняя скидка 18 % у одного менеджера? Что ещё нужно проверить, прежде чем идти к руководству?

**Типичная ошибка:** забыть псевдоним производной таблицы. В PostgreSQL 16 это допустимо, но в других СУБД (и в PG ≤ 15) — ошибка; всегда давайте псевдоним.

---

## Шаг 4. Коррелированный подзапрос — «для каждой строки»

Продукты дороже средней цены **своей** категории:

```sql
SELECT p.product_name, p.category_id, p.base_price
FROM   products AS p
WHERE  p.base_price > (SELECT AVG(p2.base_price)
                       FROM   products AS p2
                       WHERE  p2.category_id = p.category_id)
ORDER  BY p.category_id, p.base_price DESC;
```

**Ожидаемый результат:** 14 строк.

Тот же приём на производственных данных — партии с браком выше среднего по своей линии:

```sql
SELECT b.line_id, b.shift, COUNT(*) AS batches_above_line_avg
FROM   production_batches AS b
WHERE  1.0 * b.defect_qty / b.produced_qty >
       (SELECT 1.0 * SUM(b2.defect_qty) / SUM(b2.produced_qty)
        FROM   production_batches AS b2
        WHERE  b2.line_id = b.line_id)
GROUP  BY b.line_id, b.shift
ORDER  BY b.line_id, b.shift;
```

**Ожидаемый результат:**

| line_id | shift | batches_above_line_avg |
|---|---|---|
| 1 | День / Ночь | 330 / 298 |
| 2 | День / Ночь | 319 / 314 |
| **3** | **Ночь** | **627** (строки «День» нет) |
| 4 | День / Ночь | 314 / 270 |
| 5 | День / Ночь | 307 / 273 |

> **Подумайте.** Почему у Линии 3 нет строки «День»? Что это значит для команды Б?

Последний заказ каждого клиента и top-N на группу:

```sql
-- последний заказ
SELECT c.customer_name, o.order_number, o.order_date
FROM   customers AS c
JOIN   orders    AS o ON o.customer_id = c.customer_id
WHERE  o.order_date = (SELECT MAX(o2.order_date)
                       FROM   orders o2
                       WHERE  o2.customer_id = c.customer_id)
ORDER  BY o.order_date
LIMIT  10;

-- 2 самых дорогих продукта каждой категории
SELECT p.category_id, p.product_name, p.base_price
FROM   products AS p
WHERE  (SELECT COUNT(*)
        FROM   products p2
        WHERE  p2.category_id = p.category_id
          AND  p2.base_price  > p.base_price) < 2
ORDER  BY p.category_id, p.base_price DESC;
```

**Ожидаемый результат:** в первом запросе первая строка — `ооо "Свежесть"`, 2025-09-06; во втором — 14 строк (7 категорий × 2).

**Типичная ошибка:** перепутать псевдонимы (`WHERE p.category_id = p.category_id`) — условие всегда истинно, подзапрос становится некоррелированным и считает среднее по всей таблице.

---

## Шаг 5. EXISTS / NOT EXISTS

Клиенты без заказов в последние 3 месяца:

```sql
SELECT c.customer_id, c.customer_name
FROM   customers AS c
WHERE  NOT EXISTS (SELECT 1
                   FROM   orders o
                   WHERE  o.customer_id = c.customer_id
                     AND  o.order_date >= DATE '2025-10-01');
```

**Ожидаемый результат:** 2 строки — 71 `ооо "Свежесть"`, 73 `ООО "Новый горизонт"`.

> **Подумайте.** Название `ооо "Свежесть"` написано строчными буквами. Не дубль ли это другого клиента? Как проверить с помощью подзапроса по ИНН?

### Ловушка NOT IN + NULL

```sql
-- сотрудники, которые никем не руководят
SELECT COUNT(*) FROM employees
WHERE  employee_id NOT IN (SELECT manager_id FROM employees);
```

**Ожидаемый результат:** `0` (!).

```sql
SELECT COUNT(*) FROM employees e
WHERE  NOT EXISTS (SELECT 1 FROM employees s WHERE s.manager_id = e.employee_id);
```

**Ожидаемый результат:** `26`.

Почему так: у генерального директора `manager_id IS NULL`. Условие `5 NOT IN (1, 2, NULL)` раскрывается в `5 <> 1 AND 5 <> 2 AND 5 <> NULL` → `TRUE AND TRUE AND UNKNOWN` → `UNKNOWN`, строка отбрасывается.

| | `NOT IN` | `NOT EXISTS` |
|---|---|---|
| NULL в подзапросе | результат пустой | работает корректно |
| План выполнения | `Filter: NOT (hashed SubPlan)` | `Anti Join` |
| Рекомендация | только если столбец `NOT NULL` | по умолчанию |

---

## Шаг 6. Смотрим планы

```sql
EXPLAIN
SELECT c.customer_id FROM customers c
WHERE  EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id);
```

**Ожидаемый результат:** `Nested Loop Semi Join ... Index Only Scan using ix_orders_cu...`

Замените `EXISTS` на `NOT EXISTS` — увидите `Nested Loop Anti Join`. Для `NOT IN` — `Seq Scan ... Filter: (NOT (hashed SubPlan 1))`.

> **Подумайте.** Коррелированный подзапрос «выполняется для каждой строки» — это логическая модель. Что на самом деле сделал оптимизатор с `EXISTS`?

---

## Шаг 7. Подзапросы в HAVING и ORDER BY

```sql
SELECT o.employee_id, e.full_name, ROUND(AVG(oi.discount_pct), 2) AS avg_discount
FROM   orders o
JOIN   order_items oi ON oi.order_id   = o.order_id
JOIN   employees   e  ON e.employee_id = o.employee_id
GROUP  BY o.employee_id, e.full_name
HAVING AVG(oi.discount_pct) > (SELECT AVG(discount_pct) FROM order_items)
ORDER  BY avg_discount DESC;
```

**Ожидаемый результат:** 2 строки — Соколов 18.02, Попов 8.21.

---

## Шаг 8. Подзапрос или JOIN?

```sql
SELECT COUNT(*) FROM customers
WHERE  customer_id IN (SELECT customer_id FROM orders WHERE channel = 'Маркетплейс');   -- 3

SELECT COUNT(*) FROM customers c
JOIN   orders o ON o.customer_id = c.customer_id AND o.channel = 'Маркетплейс';         -- 175
```

> **Подумайте.** Почему JOIN дал 175? Когда нужен `JOIN` (нужны столбцы второй таблицы, агрегаты), а когда — `IN`/`EXISTS` (только факт наличия)?

---

## Итог практической работы

| Инструмент | Когда применять |
|---|---|
| Скалярный подзапрос | сравнение с одним числом (среднее, максимум, лимит) |
| `IN` / `ANY` / `ALL` | сравнение со списком значений |
| Производная таблица | многошаговые расчёты: «сначала посчитать, потом отфильтровать» |
| Коррелированный подзапрос | сравнение с показателем **своей** группы, последний/первый элемент группы |
| `EXISTS` / `NOT EXISTS` | проверка наличия/отсутствия связанных строк; безопасно при `NULL` |
