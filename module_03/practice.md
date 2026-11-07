# Модуль 3. Практическая работа «Извлечение данных из нескольких таблиц»

| Параметр | Значение |
|---|---|
| Цель | Научиться соединять таблицы схемы `pitanie` всеми видами JOIN, видеть «потерянные» и «размноженные» строки, находить «сирот» |
| Время | 40 минут (демонстрация преподавателя + повторение слушателями) |
| Формат | Преподаватель показывает шаг на экране → слушатели повторяют у себя → короткое обсуждение |
| Файл с кодом | [`examples.sql`](examples.sql) — все запросы этой практики (разделы 1–10) |

## Подготовка

1. Подключитесь к учебной БД (DBeaver / pgAdmin / psql): сервер `<адрес_сервера>`, порт `6432`, база `db1`, SSL `verify-full` с сертификатом `root.crt`. Логин и пароль выдаёт преподаватель.
2. Выполните первую команду сессии:

```sql
SET search_path TO pitanie, public;
```

3. Проверьте, что видите данные:

```sql
SELECT COUNT(*) FROM orders;      -- 4458
SELECT COUNT(*) FROM customers;   -- 73
```

> Все запросы этого модуля **только читают** данные. Ничего создавать не нужно.

---

## Шаг 1. Декартово произведение — «как JOIN устроен внутри»

Соедините 5 производственных линий с двумя сменами, заданными через `VALUES`.

```sql
SELECT l.line_id,
       l.line_name,
       s.shift
FROM   production_lines AS l
CROSS  JOIN (VALUES ('День'), ('Ночь')) AS s (shift)
ORDER  BY l.line_id, s.shift;
```

**Ожидаемый результат:** 10 строк (5 × 2).

Теперь забудьте условие соединения при старом синтаксисе «через запятую»:

```sql
SELECT COUNT(*) AS rows_without_condition
FROM   orders, customers;
```

**Ожидаемый результат:** `325434` = 4458 × 73. Добавьте `WHERE orders.customer_id = customers.customer_id` — получится 4458, ровно столько же, сколько даёт `JOIN … ON`.

> **Подумайте.** Почему говорят, что любой JOIN — это «декартово произведение плюс фильтр»? Что произойдёт с запросом, если в нём 4 таблицы по 10 000 строк и одно условие забыто?

---

## Шаг 2. CROSS JOIN как генератор сетки отчёта

Постройте сетку «месяц 2025 × категория верхнего уровня»:

```sql
SELECT m.month_start::date AS month_start,
       pc.category_name
FROM   generate_series(DATE '2025-01-01', DATE '2025-12-01', INTERVAL '1 month') AS m (month_start)
CROSS  JOIN product_categories AS pc
WHERE  pc.parent_category_id IS NULL
ORDER  BY month_start, pc.category_id;
```

**Ожидаемый результат:** 36 строк (12 месяцев × 3 категории).

Теперь используйте сетку, чтобы найти **пустые ячейки** — смены, в которые линия не выпускала продукцию в декабре 2025:

```sql
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
```

**Ожидаемый результат:** 48 строк. Воскресенья (7, 14, 21, 28 декабря) — стоят все 10 смен; субботы (6, 13, 20, 27) — нет ночной смены у линий 4 и 5.

> **Подумайте.** Почему без сетки эти «дыры» невозможно увидеть простым запросом к `production_batches`?

---

## Шаг 3. INNER JOIN трёх таблиц

```sql
SELECT o.order_number,
       o.order_date,
       c.customer_name,
       e.full_name AS manager
FROM   orders    AS o
JOIN   customers AS c ON c.customer_id = o.customer_id
JOIN   employees AS e ON e.employee_id = o.employee_id
WHERE  o.order_date >= DATE '2025-12-30'
ORDER  BY o.order_date, o.order_number;
```

**Ожидаемый результат:** 19 заказов за 30–31 декабря 2025 г. (первая строка — `ЗК-2025-04440`, АО "ПродМаркет", Федоров П. О.).

Проверьте, что INNER JOIN «теряет» клиентов без заказов:

```sql
SELECT COUNT(DISTINCT c.customer_id) AS customers_with_orders
FROM   customers AS c
JOIN   orders    AS o ON o.customer_id = c.customer_id;   -- 72 из 73
```

---

## Шаг 4. Внешние соединения

**LEFT JOIN** — клиент 73 появится с `NULL` в столбцах заказа:

```sql
SELECT c.customer_id, c.customer_name, o.order_number, o.order_date
FROM   customers AS c
LEFT   JOIN orders AS o ON o.customer_id = c.customer_id
WHERE  c.customer_id IN (72, 73)
ORDER  BY c.customer_id, o.order_date;
```

**Ожидаемый результат:** 28 строк: 27 заказов клиента 72 и одна строка `ООО "Новый горизонт" | NULL | NULL`.

**FULL JOIN** — регионы ↔ поставщики:

```sql
SELECT r.region_name,
       s.supplier_name
FROM   regions   AS r
FULL   JOIN suppliers AS s ON s.region_id = r.region_id
ORDER  BY r.region_id NULLS LAST, s.supplier_id;
```

**Ожидаемый результат:** 17 строк; в 5 регионах (Санкт-Петербург, Нижегородская обл., Татарстан, Свердловская обл., Красноярский край) поставщиков нет.

> **Подумайте.** Когда на практике нужен RIGHT JOIN, если его всегда можно переписать как LEFT, поменяв таблицы местами?

---

## Шаг 5. Ловушка: условие в ON или в WHERE

Задача: «все клиенты и их заказы за декабрь 2025 г.».

```sql
-- Вариант 1: фильтр по правой таблице в ON
SELECT COUNT(*) AS row_cnt,
       COUNT(DISTINCT c.customer_id) AS customers,
       COUNT(o.order_id) AS dec_orders
FROM   customers AS c
LEFT   JOIN orders AS o
       ON  o.customer_id = c.customer_id
       AND o.order_date >= DATE '2025-12-01';

-- Вариант 2: тот же фильтр в WHERE
SELECT COUNT(*) AS row_cnt,
       COUNT(DISTINCT c.customer_id) AS customers,
       COUNT(o.order_id) AS dec_orders
FROM   customers AS c
LEFT   JOIN orders AS o ON o.customer_id = c.customer_id
WHERE  o.order_date >= DATE '2025-12-01';
```

**Ожидаемый результат:**

| Вариант | row_cnt | customers | dec_orders |
|---|---|---|---|
| ON | 228 | **73** | 218 |
| WHERE | 218 | **63** | 218 |

Во втором варианте 10 клиентов без декабрьских заказов исчезли: для них `o.order_date IS NULL`, а `NULL >= дата` — это UNKNOWN, и WHERE строку отбрасывает. LEFT JOIN фактически стал INNER JOIN.

> **Правило.** Фильтр по **правой** (необязательной) таблице LEFT JOIN — в `ON`. Фильтр по **левой** таблице — в `WHERE` (в `ON` он не отфильтрует строки, а только «обнулит» правую часть: проверьте пример 5.3 в `examples.sql` — 180 строк вместо ожидаемых 4 клиентов HoReCa).

---

## Шаг 6. Цепочка из 5 таблиц

```sql
SELECT o.order_number,
       p.product_name,
       sub.category_name AS subcategory,
       top.category_name AS category,
       oi.quantity,
       oi.unit_price,
       oi.discount_pct
FROM   orders             AS o
JOIN   order_items        AS oi  ON oi.order_id     = o.order_id
JOIN   products           AS p   ON p.product_id    = oi.product_id
JOIN   product_categories AS sub ON sub.category_id = p.category_id
JOIN   product_categories AS top ON top.category_id = sub.parent_category_id
WHERE  o.order_number = 'ЗК-2024-00001'
ORDER  BY oi.order_item_id;
```

**Ожидаемый результат:** 6 позиций первого заказа. Обратите внимание на скидки 12–20 % — при политике «не более 10 %». К этому факту команда А вернётся в лабораторной.

Цепочка производства с **составным ключом** (норма vs факт для партии 1):

```sql
SELECT b.batch_number,
       m.material_name,
       ROUND(r.qty_per_unit * b.produced_qty, 2) AS norm_qty,
       mc.quantity                               AS fact_qty
FROM   production_batches   AS b
JOIN   recipes              AS r  ON r.product_id   = b.product_id
JOIN   material_consumption AS mc ON mc.batch_id    = b.batch_id
                                 AND mc.material_id = r.material_id
JOIN   raw_materials        AS m  ON m.material_id  = r.material_id
WHERE  b.batch_id = 1;
```

**Ожидаемый результат:** 2 строки: «Молоко сырое» 949.66 / 977.824 (+3,0 %), «Пакет тетра-пак 1 л» 922.00 / 939.308 (+1,9 %).

> **Типичная ошибка.** Соединить `material_consumption` только по `batch_id`, забыв `material_id`. Для всей таблицы это даёт 107 929 строк вместо 24 275 — каждая строка нормы «склеивается» с каждой строкой факта партии.

---

## Шаг 7. USING и опасный NATURAL JOIN

```sql
SELECT COUNT(*) FROM invoices NATURAL JOIN payments;                       -- 3477
SELECT COUNT(*) FROM invoices AS i JOIN payments AS p ON p.invoice_id = i.invoice_id;  -- 4519
```

У `invoices` и `payments` два одноимённых столбца — `invoice_id` **и** `amount`. NATURAL JOIN соединил их по обоим и оставил только оплаты, равные сумме счёта. Частичные оплаты пропали без единой ошибки.

```sql
SELECT COUNT(*) FROM employees NATURAL JOIN customers;   -- 0 (общие manager_id, email, phone)
```

> **Правило.** `USING (col)` — допустим и удобен. `NATURAL JOIN` — не используйте в рабочем коде: запрос «ломается» при добавлении в таблицу столбца с совпадающим именем.

---

## Шаг 8. «Сироты» и anti-join

```sql
-- Клиенты без заказов
SELECT c.customer_id, c.customer_name, c.registration_date
FROM   customers AS c
LEFT   JOIN orders AS o ON o.customer_id = c.customer_id
WHERE  o.order_id IS NULL;
```

**Ожидаемый результат:** 1 строка — `ООО "Новый горизонт"`, зарегистрирован 20.11.2025.

```sql
-- Счета без единой оплаты
SELECT COUNT(*)
FROM   invoices AS i
LEFT   JOIN payments AS p ON p.invoice_id = i.invoice_id
WHERE  p.payment_id IS NULL;     -- 229
```

Подставьте `COALESCE` для читаемого вывода:

```sql
SELECT c.customer_name,
       COALESCE(r.region_name, '— регион не указан —') AS region_name
FROM   customers AS c
LEFT   JOIN regions AS r ON r.region_id = c.region_id
WHERE  c.region_id IS NULL;      -- Фермер, Мегаполис, Юпитер
```

> **Подумайте.** Почему в anti-join проверяют `IS NULL` у первичного ключа правой таблицы, а не у произвольного столбца (например `p.payment_method`)?

---

## Шаг 9. SELF-JOIN

```sql
-- Сотрудник и руководитель
SELECT e.full_name,
       e.position,
       COALESCE(m.full_name, '— (высшее руководство)') AS manager
FROM   employees AS e
LEFT   JOIN employees AS m ON m.employee_id = e.manager_id
ORDER  BY e.employee_id;
```

**Ожидаемый результат:** 35 строк; у Орлова В. П. (генеральный директор) — «высшее руководство». С INNER JOIN строк было бы 34.

```sql
-- Один материал, один месяц, разные поставщики, цена выше на 15 %+
SELECT m.material_name,
       sa.supplier_name AS expensive_supplier, a.unit_price AS expensive_price,
       sb.supplier_name AS cheap_supplier,     b.unit_price AS cheap_price
FROM   purchase_order_items AS a
JOIN   purchase_orders      AS poa ON poa.po_id      = a.po_id
JOIN   purchase_order_items AS b   ON b.material_id  = a.material_id
JOIN   purchase_orders      AS pob ON pob.po_id      = b.po_id
JOIN   suppliers            AS sa  ON sa.supplier_id = poa.supplier_id
JOIN   suppliers            AS sb  ON sb.supplier_id = pob.supplier_id
JOIN   raw_materials        AS m   ON m.material_id  = a.material_id
WHERE  poa.supplier_id <> pob.supplier_id
  AND  date_trunc('month', poa.order_date) = date_trunc('month', pob.order_date)
  AND  a.unit_price > b.unit_price * 1.15
  AND  a.material_id = 4
  AND  poa.order_date >= DATE '2025-12-01';
```

**Ожидаемый результат:** 3 пары: сахар у ООО "АгроСнаб-М" по 82,10–85,29 руб./кг против 65,06 у АО "Сахарный комбинат Воронеж" в том же месяце.

---

## Шаг 10. Эффект «размножения строк»

```sql
SELECT SUM(i.amount) AS invoiced_correct
FROM   invoices AS i;                                   -- 821 243 564.75

SELECT SUM(i.amount) AS invoiced_inflated, COUNT(*) AS row_cnt
FROM   invoices AS i
LEFT   JOIN payments AS p ON p.invoice_id = i.invoice_id;  -- 923 186 907.89, 4748 строк
```

Сумма счетов «выросла» на 101,9 млн руб. — счёт с двумя оплатами посчитан дважды (например, `СЧ-2024-00005` на 330 803,11 оплачен двумя платежами по 165 401,56).

> **Правило.** Прежде чем суммировать после JOIN, спросите себя: «Какова гранулярность результата — одна строка на что?». Если к «одному» присоединено «многое», суммы «одного» нельзя складывать.

---

## Типичные ошибки (сводка)

| Ошибка | Симптом | Исправление |
|---|---|---|
| Забыто условие соединения | Число строк = произведение таблиц | Проверять `COUNT(*)` после каждого нового JOIN |
| Фильтр по правой таблице LEFT JOIN в WHERE | LEFT превратился в INNER, «пропали» строки | Перенести условие в `ON` |
| NATURAL JOIN | Неожиданно мало/0 строк | Явный `ON` или `USING` |
| Соединение не по всему составному ключу | «Размножение» строк | Все столбцы связи в `ON` |
| SUM по «одной» стороне после JOIN с «многими» | Завышенные суммы | Агрегировать отдельно (модули 4–5, 9) |
| INNER JOIN к справочнику с NULL-ключами | Пропали строки (заказы клиентов без региона) | LEFT JOIN + COALESCE |

## Вопросы для самопроверки

1. Сколько строк вернёт `CROSS JOIN` таблиц на 12 и 3 строки? А `LEFT JOIN` тех же таблиц по условию, которое никогда не выполняется?
2. Чем `USING (order_id)` отличается от `ON o.order_id = i.order_id` в списке столбцов результата?
3. Как найти поставщиков, у которых не было ни одного заказа? (Ответ: `suppliers LEFT JOIN purchase_orders … WHERE po.po_id IS NULL`; в наших данных таких нет — 0 строк.)
4. Зачем в self-join пар используют условие `a.id < b.id`, а не `a.id <> b.id`?
