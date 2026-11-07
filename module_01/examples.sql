-- =====================================================================
-- Курс «Углублённый SQL» · Модуль 1. Сортировка и фильтрация в запросах
-- Практические примеры преподавателя (сквозной пример «Питание +»)
-- СУБД: PostgreSQL 16 (Yandex Managed Service for PostgreSQL)
-- Все запросы только читают данные схемы pitanie.
-- =====================================================================

SET search_path TO pitanie, public;

-- ---------------------------------------------------------------------
-- Раздел 1. WHERE: базовая фильтрация
-- ---------------------------------------------------------------------

-- 1.1 Заказы, оформленные в декабре 2025 года (полуоткрытый интервал по датам)
SELECT order_id,
       order_number,
       order_date,
       status
FROM   orders
WHERE  order_date >= DATE '2025-12-01'
  AND  order_date <  DATE '2026-01-01'
ORDER  BY order_date, order_id
LIMIT  10;

-- 1.2 Сравнение строк чувствительно к регистру и пробелам:
--     'акция' и 'Акция -10%' — разные значения
SELECT comment,
       order_number
FROM   orders
WHERE  comment = 'акция'
ORDER  BY order_id
LIMIT  5;

-- 1.3 Позиции заказов со скидкой больше политики 10 %
SELECT order_item_id,
       order_id,
       product_id,
       quantity,
       unit_price,
       discount_pct
FROM   order_items
WHERE  discount_pct > 10
ORDER  BY discount_pct DESC, order_item_id
LIMIT  10;
-- всего таких позиций: 4365 (проверка ниже)
SELECT COUNT(*) AS items_over_policy
FROM   order_items
WHERE  discount_pct > 10;

-- ---------------------------------------------------------------------
-- Раздел 2. Логические операторы и приоритет: NOT > AND > OR
-- ---------------------------------------------------------------------

-- 2.1 ОШИБКА ЛОГИКИ (не синтаксиса): AND связывает сильнее OR.
--     Хотели: заказы менеджера 10, у которых канал «Дистрибуция» ИЛИ «Тендер».
--     Получили: (менеджер 10 И Дистрибуция) ИЛИ (любой Тендер)
SELECT COUNT(*) AS wrong_cnt
FROM   orders
WHERE  employee_id = 10
  AND  channel = 'Дистрибуция'
   OR  channel = 'Тендер';

-- 2.2 Правильно — со скобками
SELECT COUNT(*) AS right_cnt
FROM   orders
WHERE  employee_id = 10
  AND  (channel = 'Дистрибуция' OR channel = 'Тендер');

-- 2.3 То же через IN — короче и без ловушки приоритета
SELECT COUNT(*) AS in_cnt
FROM   orders
WHERE  employee_id = 10
  AND  channel IN ('Дистрибуция', 'Тендер');

-- 2.4 NOT: все заказы, кроме отменённых и доставленных
SELECT status,
       order_number,
       order_date
FROM   orders
WHERE  NOT (status = 'Отменён' OR status = 'Доставлен')
ORDER  BY order_date DESC
LIMIT  10;

-- ---------------------------------------------------------------------
-- Раздел 3. Предикаты IN, BETWEEN, LIKE / ILIKE, регулярные выражения
-- ---------------------------------------------------------------------

-- 3.1 IN со списком значений: клиенты-сети
SELECT customer_id,
       customer_name,
       customer_type
FROM   customers
WHERE  customer_type IN ('Федеральная сеть', 'Региональная сеть')
ORDER  BY customer_type, customer_name
LIMIT  10;

-- 3.2 BETWEEN включает обе границы: скидки от 12 до 18 % включительно
SELECT COUNT(*) AS cnt_12_18
FROM   order_items
WHERE  discount_pct BETWEEN 12 AND 18;

-- 3.3 Ловушка BETWEEN с timestamp: '2025-07-28' = 2025-07-28 00:00:00,
--     простои, начавшиеся днём 28.07, не попадают
SELECT COUNT(*) AS between_cnt
FROM   equipment_downtime
WHERE  start_time BETWEEN '2025-07-01' AND '2025-07-28';

-- правильно — полуоткрытый интервал
SELECT COUNT(*) AS halfopen_cnt
FROM   equipment_downtime
WHERE  start_time >= '2025-07-01'
  AND  start_time <  '2025-07-29';

-- 3.4 LIKE: % — любая последовательность, _ — ровно один символ
--     Все йогурты (в названии есть слово «Йогурт»)
SELECT product_id,
       sku,
       product_name,
       shelf_life_days
FROM   products
WHERE  product_name LIKE '%огурт%'
ORDER  BY product_id;

-- 3.5 Артикулы кисломолочной группы: KSM-00X (ровно одна цифра после 00)
SELECT sku,
       product_name
FROM   products
WHERE  sku LIKE 'KSM-00_'
ORDER  BY sku;

-- 3.6 LIKE регистрозависим, ILIKE — нет (расширение PostgreSQL)
SELECT COUNT(*) FILTER (WHERE comment LIKE  '%акция%') AS like_cnt,
       COUNT(*) FILTER (WHERE comment ILIKE '%акция%') AS ilike_cnt
FROM   orders;
-- примечание: FILTER — агрегатная конструкция из модуля 4, здесь просто для сравнения

-- 3.7 Экранирование: ищем буквальный символ % в комментарии
SELECT DISTINCT comment
FROM   orders
WHERE  comment LIKE '%10\%%';

-- 3.8 Грязные email: с пробелами по краям или в верхнем регистре
SELECT customer_id,
       customer_name,
       '[' || email || ']' AS email_visible
FROM   customers
WHERE  email LIKE ' %'
   OR  email LIKE '% '
   OR  email <> LOWER(email)
ORDER  BY customer_id
LIMIT  10;

-- 3.9 Регулярные выражения: ~ (с учётом регистра), ~* (без учёта)
--     Телефоны в «чистом» формате +7XXXXXXXXXX
SELECT customer_id,
       phone
FROM   customers
WHERE  phone ~ '^\+7[0-9]{10}$'
ORDER  BY customer_id
LIMIT  5;

-- 3.10 SIMILAR TO — стандарт SQL, «гибрид» LIKE и regexp (используется редко)
SELECT sku,
       product_name
FROM   products
WHERE  sku SIMILAR TO '(SYR|SOU)-%'
ORDER  BY sku;

-- ---------------------------------------------------------------------
-- Раздел 4. NULL в предикатах и выражениях
-- ---------------------------------------------------------------------

-- 4.1 Сравнение с NULL через = не работает: 0 строк
SELECT COUNT(*) AS eq_null
FROM   customers
WHERE  region_id = NULL;

-- 4.2 Правильно: IS NULL
SELECT customer_id,
       customer_name,
       region_id
FROM   customers
WHERE  region_id IS NULL
ORDER  BY customer_id;

-- 4.3 Трёхзначная логика на «игрушечных» значениях
SELECT NULL = NULL          AS eq,
       NULL <> 1            AS ne,
       TRUE  AND NULL       AS t_and_n,
       FALSE AND NULL       AS f_and_n,
       TRUE  OR  NULL       AS t_or_n,
       NOT NULL::boolean    AS not_n;

-- 4.4 Отрицание не «переворачивает» NULL:
--     клиентов НЕ из региона 1 — это не «все минус регион 1»
SELECT COUNT(*)                                     AS total,
       COUNT(*) FILTER (WHERE region_id = 1)        AS reg_1,
       COUNT(*) FILTER (WHERE region_id <> 1)       AS not_reg_1,
       COUNT(*) FILTER (WHERE region_id IS NULL)    AS reg_null
FROM   customers;

-- 4.5 IS DISTINCT FROM — сравнение, в котором NULL считается обычным значением
SELECT COUNT(*) AS not_distinct_from_1
FROM   customers
WHERE  region_id IS DISTINCT FROM 1;

-- 4.6 Позиции закупок, где приёмка не «Принято» (включая ещё не полученные — NULL)
SELECT COUNT(*) FILTER (WHERE quality_status <> 'Принято')                AS by_ne,
       COUNT(*) FILTER (WHERE quality_status IS DISTINCT FROM 'Принято')  AS by_distinct
FROM   purchase_order_items;

-- 4.7 Ловушка NOT IN со списком, содержащим NULL — 0 строк!
SELECT COUNT(*) AS not_in_with_null
FROM   customers
WHERE  region_id NOT IN (1, 2, NULL);

-- без NULL в списке — ожидаемый результат
SELECT COUNT(*) AS not_in_ok
FROM   customers
WHERE  region_id NOT IN (1, 2);

-- 4.8 COALESCE: подставить значение вместо NULL; NULLIF: превратить значение в NULL
SELECT customer_id,
       customer_name,
       COALESCE(email, '(нет email)')   AS email_or_stub,
       COALESCE(region_id, 0)           AS region_or_0
FROM   customers
WHERE  email IS NULL
ORDER  BY customer_id
LIMIT  5;

-- NULLIF защищает от деления на ноль
SELECT 100.0 * 5 / NULLIF(0, 0) AS safe_div;

-- 4.9 NULL в арифметике и конкатенации «заражает» результат
SELECT 'Поставщик: ' || supplier_name || ', тел. ' || phone           AS by_concat,
       CONCAT('Поставщик: ', supplier_name, ', тел. ', phone)        AS by_concat_fn
FROM   suppliers
WHERE  supplier_id = 12;

-- ---------------------------------------------------------------------
-- Раздел 5. ORDER BY
-- ---------------------------------------------------------------------

-- 5.1 Несколько ключей: по типу клиента, затем по кредитному лимиту по убыванию
SELECT customer_type,
       customer_name,
       credit_limit
FROM   customers
ORDER  BY customer_type ASC,
          credit_limit  DESC,
          customer_name
LIMIT  10;

-- 5.2 Сортировка по выражению: позиции с наибольшей суммой скидки в рублях
SELECT order_item_id,
       order_id,
       quantity,
       unit_price,
       discount_pct,
       ROUND(quantity * unit_price * discount_pct / 100, 2) AS discount_rub
FROM   order_items
ORDER  BY quantity * unit_price * discount_pct / 100 DESC
LIMIT  5;

-- 5.3 Сортировка по псевдониму и по номеру столбца (номер — не рекомендуется)
SELECT supplier_name,
       rating AS r
FROM   suppliers
ORDER  BY r DESC;

-- 5.4 NULL при сортировке: в PostgreSQL NULL «больше» всех значений —
--     при ASC в конце, при DESC в начале. Управляем явно:
SELECT supplier_name,
       rating
FROM   suppliers
ORDER  BY rating DESC NULLS LAST
LIMIT  5;

-- 5.5 COLLATE: правила сравнения строк. База db1 использует ICU-сортировку по умолчанию;
--     "C" — побайтовое сравнение (заглавные раньше строчных, «ооо» уходит в конец)
SELECT customer_name
FROM   customers
WHERE  customer_id IN (1, 9, 69, 70, 71)
ORDER  BY customer_name COLLATE "C";

SELECT customer_name
FROM   customers
WHERE  customer_id IN (1, 9, 69, 70, 71)
ORDER  BY customer_name COLLATE "ru-RU-x-icu";

-- 5.6 Пользовательский порядок через CASE (жизненный цикл заказа)
SELECT DISTINCT status,
       CASE status
           WHEN 'Новый'     THEN 1
           WHEN 'В работе'  THEN 2
           WHEN 'Отгружен'  THEN 3
           WHEN 'Доставлен' THEN 4
           ELSE 5
       END AS step
FROM   orders
ORDER  BY step;

-- ---------------------------------------------------------------------
-- Раздел 6. TOP ↔ LIMIT, OFFSET … FETCH
-- ---------------------------------------------------------------------

-- 6.1 T-SQL: SELECT TOP (5) ... ORDER BY amount DESC
--     PostgreSQL: LIMIT
SELECT invoice_number,
       invoice_date,
       amount
FROM   invoices
ORDER  BY amount DESC
LIMIT  5;

-- 6.2 Стандарт SQL:2008 — FETCH FIRST n ROWS ONLY (работает и в PostgreSQL, и в T-SQL с OFFSET)
SELECT invoice_number,
       invoice_date,
       amount
FROM   invoices
ORDER  BY amount DESC
FETCH  FIRST 5 ROWS ONLY;

-- 6.3 WITH TIES — вернуть и «равных» последнему (аналог TOP … WITH TIES)
--     Позиции с максимальной скидкой: топ-3 + все с такой же скидкой
SELECT COUNT(*) AS with_ties_cnt
FROM  (SELECT order_item_id
       FROM   order_items
       ORDER  BY discount_pct DESC
       FETCH  FIRST 3 ROWS WITH TIES) AS t;

-- 6.4 Без ORDER BY результат LIMIT не определён (порядок не гарантирован)
SELECT order_number
FROM   orders
LIMIT  3;

-- 6.5 Постраничный вывод: страница 3 по 20 строк
SELECT order_id,
       order_number,
       order_date
FROM   orders
ORDER  BY order_date DESC, order_id DESC
OFFSET 40 ROWS
FETCH  NEXT 20 ROWS ONLY;

-- то же в краткой форме PostgreSQL
SELECT order_id,
       order_number,
       order_date
FROM   orders
ORDER  BY order_date DESC, order_id DESC
LIMIT  20 OFFSET 40;

-- 6.6 Нестабильная сортировка: по одной order_date много одинаковых значений,
--     без уникального «добивающего» ключа строки могут «перескакивать» между страницами
SELECT COUNT(*) AS orders_on_2025_12_31
FROM   orders
WHERE  order_date = DATE '2025-12-31';

-- 6.7 Keyset (seek) pagination: «следующая страница после последней увиденной строки»
--     Последняя строка предыдущей страницы: order_date = 2025-12-29, order_id = 4433
SELECT order_id,
       order_number,
       order_date
FROM   orders
WHERE  (order_date, order_id) < (DATE '2025-12-29', 4433)
ORDER  BY order_date DESC, order_id DESC
LIMIT  5;

-- 6.8 Сравнение стоимости OFFSET и keyset на большой таблице (material_consumption, ~24 тыс.)
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF)
SELECT consumption_id
FROM   material_consumption
ORDER  BY consumption_id
OFFSET 20000 LIMIT 20;

EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF)
SELECT consumption_id
FROM   material_consumption
WHERE  consumption_id > 20000
ORDER  BY consumption_id
LIMIT  20;

-- ---------------------------------------------------------------------
-- Раздел 7. Кейс: «Где теряем деньги?» — первые находки только фильтрацией
-- ---------------------------------------------------------------------

-- 7.1 Команда А: 10 позиций с самой большой скидкой в рублях сверх 10 %
SELECT order_item_id,
       order_id,
       quantity,
       unit_price,
       discount_pct,
       ROUND(quantity * unit_price * (discount_pct - 10) / 100, 2) AS over_policy_rub
FROM   order_items
WHERE  discount_pct > 10
ORDER  BY over_policy_rub DESC
FETCH  FIRST 10 ROWS ONLY;

-- 7.2 Команда Б: партии с браком выше 5 % — посмотрите на line_id и shift
SELECT batch_number,
       line_id,
       shift,
       produced_qty,
       defect_qty,
       ROUND(100.0 * defect_qty / produced_qty, 2) AS defect_pct
FROM   production_batches
WHERE  defect_qty > 0.05 * produced_qty
ORDER  BY defect_pct DESC
LIMIT  10;
