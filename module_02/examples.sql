-- =====================================================================
-- Курс «Углублённый SQL» · Модуль 2. Применение типов данных и встроенных функций
-- Практические примеры преподавателя (сквозной пример «Питание +»)
-- СУБД: PostgreSQL 16 (Yandex Managed Service for PostgreSQL)
-- Все запросы только читают данные схемы pitanie.
-- Запросы, помеченные «-- ОЖИДАЕМАЯ ОШИБКА», демонстрируют ошибку намеренно.
-- =====================================================================

SET search_path TO pitanie, public;

-- ---------------------------------------------------------------------
-- Раздел 1. Типы данных: что лежит в таблицах «Питание +»
-- ---------------------------------------------------------------------

-- 1.1 Типы столбцов таблицы из системного каталога (information_schema)
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

-- 1.2 pg_typeof — тип любого выражения
SELECT pg_typeof(42)                    AS t_int,
       pg_typeof(42.0)                  AS t_numeric,
       pg_typeof(42.0::real)            AS t_real,
       pg_typeof('42')                  AS t_unknown,
       pg_typeof(DATE '2025-12-31')     AS t_date,
       pg_typeof(now())                 AS t_now;

-- 1.3 numeric — точный, float — приближённый
SELECT 0.1::float8 + 0.2::float8           AS float_sum,
       0.1::float8 + 0.2::float8 = 0.3     AS float_eq,
       0.1::numeric + 0.2::numeric         AS numeric_sum,
       0.1::numeric + 0.2::numeric = 0.3   AS numeric_eq;

-- 1.4 Ошибка переполнения точности numeric(5,2): максимум 999.99
SELECT 1234.5::numeric(5,2);                          -- ОЖИДАЕМАЯ ОШИБКА: numeric field overflow

-- 1.5 Строковые типы: char(n) дополняет пробелами, varchar(n) ограничивает длину, text — без ограничения
SELECT 'АБВ'::char(6)                        AS as_char,
       LENGTH('АБВ'::char(6))                AS len_char,
       OCTET_LENGTH('АБВ'::char(6))          AS bytes_char,
       'АБВ'::varchar(6)                     AS as_varchar,
       OCTET_LENGTH('АБВ')                   AS bytes_utf8;

SELECT 'Слишком длинное значение'::varchar(5) AS cut_by_cast;   -- явный CAST обрезает молча

-- 1.6 Дата/время: date, timestamp, timestamptz, interval
SELECT DATE '2025-12-31'                                   AS d,
       TIMESTAMP '2025-12-31 23:30:00'                     AS ts,
       TIMESTAMPTZ '2025-12-31 23:30:00+03'                AS tstz,
       (TIMESTAMPTZ '2025-12-31 23:30:00+03'
            AT TIME ZONE 'Asia/Novosibirsk')::text         AS in_novosibirsk,
       INTERVAL '1 day 2 hours'                            AS iv;

-- 1.7 boolean — значения TRUE / FALSE / NULL
SELECT product_name,
       is_active,
       NOT is_active AS is_discontinued
FROM   products
WHERE  NOT is_active;

-- 1.8 Обзорно: uuid, jsonb, массивы (в схеме pitanie не используются, но встречаются в реальных системах)
SELECT gen_random_uuid()                                           AS new_uuid,
       '{"sku": "SYR-001", "price": 189, "tags": ["масло","молочка"]}'::jsonb ->> 'sku'  AS json_sku,
       ('{"sku": "SYR-001", "price": 189}'::jsonb -> 'price')::int + 1                    AS json_price_plus1,
       ARRAY[7, 10, 14]                                            AS shelf_life_arr,
       (ARRAY[7, 10, 14])[2]                                       AS second_elem,
       string_to_array('День;Ночь', ';')                           AS shifts;

-- ---------------------------------------------------------------------
-- Раздел 2. Неявное и явное преобразование
-- ---------------------------------------------------------------------

-- 2.1 Явное: CAST(x AS type) — стандарт SQL; x::type — сокращение PostgreSQL
SELECT CAST('2025-03-01' AS date)   AS by_cast,
       '2025-03-01'::date           AS by_colons,
       CAST(189.567 AS numeric(10,2)) AS rounded_by_cast,
       '42'::integer + 1            AS str_to_int;

-- 2.2 Неявное: строковый литерал «подстраивается» под тип столбца
SELECT COUNT(*) AS orders_dec_2025
FROM   orders
WHERE  order_date >= '2025-12-01';           -- '2025-12-01' неявно → date

-- 2.3 Неудачные преобразования
SELECT 'abc'::integer;                       -- ОЖИДАЕМАЯ ОШИБКА: invalid input syntax for type integer
SELECT '2025-02-30'::date;                   -- ОЖИДАЕМАЯ ОШИБКА: date/time field value out of range
SELECT 3000000000::integer;                  -- ОЖИДАЕМАЯ ОШИБКА: integer out of range

-- 2.4 ИНН — это строка, а не число: при CAST в число теряются ведущие нули
SELECT customer_id,
       inn,
       LENGTH(inn)    AS len,
       inn::bigint    AS inn_as_number
FROM   customers
WHERE  inn LIKE '0%'
ORDER  BY customer_id;

-- 2.5 Целочисленное деление: integer / integer → integer (дробь отбрасывается)
SELECT 7 / 2           AS int_div,
       7 / 2.0         AS num_div,
       7::numeric / 2  AS cast_div,
       -7 / 2          AS neg_int_div,
       7 % 2           AS remainder;

-- 2.6 Та же ловушка на данных: доля брака как defect_qty / produced_qty — всегда 0!
SELECT batch_number,
       defect_qty,
       produced_qty,
       defect_qty / produced_qty                       AS wrong_share,
       100 * defect_qty / produced_qty                 AS wrong_pct_int,
       ROUND(100.0 * defect_qty / produced_qty, 2)     AS right_pct
FROM   production_batches
ORDER  BY batch_id
LIMIT  5;

-- 2.7 Округление: numeric — «от нуля» (half away from zero), float8 — к чётному (banker's)
SELECT ROUND(2.5)          AS num_2_5,
       ROUND(3.5)          AS num_3_5,
       ROUND(2.5::float8)  AS flt_2_5,
       ROUND(3.5::float8)  AS flt_3_5,
       ROUND(-2.5)         AS num_neg_2_5;

-- ROUND(x, n) существует только для numeric
SELECT ROUND(2.567::float8, 1);              -- ОЖИДАЕМАЯ ОШИБКА: function round(double precision, integer) does not exist
SELECT ROUND(2.567::float8::numeric, 1) AS fixed;

-- 2.8 to_char / to_number / to_date — форматные преобразования
--     G (разделитель групп) и D (десятичный знак) зависят от lc_numeric сессии
SELECT to_char(1245137.26, 'FM999G999G990D00')         AS money_en,     -- 1,245,137.26
       to_char(100 * 0.0794, 'FM990D0') || ' %'        AS pct_fmt,
       to_date('08.03.2025', 'DD.MM.YYYY')             AS parsed_date,
       to_date('240101', 'YYMMDD')                     AS from_batch_code;

SET lc_numeric = 'ru_RU.UTF-8';

SELECT to_char(1245137.26, 'FM999G999G990D00')         AS money_ru,     -- 1 245 137,26
       to_number('1 245 137,26', '9G999G999D99')       AS parsed_num;

RESET lc_numeric;

-- надёжный вариант без зависимости от локали: убрать пробелы, заменить запятую
SELECT REPLACE(REPLACE('1 245 137,26', ' ', ''), ',', '.')::numeric AS parsed_safe;

-- ---------------------------------------------------------------------
-- Раздел 3. Математические функции
-- ---------------------------------------------------------------------

-- 3.1 Базовый набор
SELECT ROUND(189.456, 2)     AS round_2,
       ROUND(1622899.67, -3) AS round_thousands,
       TRUNC(189.456, 1)     AS trunc_1,
       CEIL(2.1)             AS ceil_,
       FLOOR(-2.1)           AS floor_,
       ABS(-15)              AS abs_,
       POWER(1.1, 3)         AS power_,
       SQRT(2)               AS sqrt_,
       MOD(17, 5)            AS mod_,
       SIGN(-3.2)            AS sign_;

-- 3.2 GREATEST / LEAST — максимум/минимум из списка значений В СТРОКЕ (не агрегат!)
--     Цена со скидкой, но не ниже себестоимости (пример «минимальной цены»)
SELECT oi.order_item_id,
       oi.unit_price,
       oi.discount_pct,
       p.standard_cost,
       ROUND(oi.unit_price * (1 - oi.discount_pct / 100), 2)                       AS net_price,
       GREATEST(ROUND(oi.unit_price * (1 - oi.discount_pct / 100), 2), p.standard_cost) AS floor_price
FROM   order_items AS oi
JOIN   products    AS p ON p.product_id = oi.product_id
WHERE  oi.product_id = 13
ORDER  BY oi.order_item_id
LIMIT  5;

-- 3.3 Сколько коробок нужно: CEIL(количество / вложение)
SELECT order_item_id,
       quantity,
       CEIL(quantity / 12.0)  AS boxes_by_12,
       quantity / 12          AS wrong_boxes_int
FROM   order_items
ORDER  BY order_item_id
LIMIT  5;

-- 3.4 random() — для выборки и тестовых данных (результат каждый раз разный)
SELECT ROUND(random()::numeric, 4)            AS r,
       FLOOR(random() * 5 + 1)::int           AS line_1_to_5;

-- воспроизводимо: setseed() перед random()
SELECT setseed(0.42);
SELECT ROUND(random()::numeric, 6) AS same_every_time;

-- 3.5 Деление на ноль и NULLIF: стоимость единицы списанного сырья
--     (в таблице есть 7 списаний с quantity = 0)
SELECT writeoff_id, quantity, amount, amount / quantity AS unit_cost
FROM   material_writeoffs
WHERE  writeoff_id = 16;                     -- ОЖИДАЕМАЯ ОШИБКА: division by zero

SELECT writeoff_id,
       quantity,
       amount,
       ROUND(amount / NULLIF(quantity, 0), 2) AS unit_cost
FROM   material_writeoffs
WHERE  writeoff_id IN (2, 16)
ORDER  BY writeoff_id;

-- ---------------------------------------------------------------------
-- Раздел 4. Строковые функции
-- ---------------------------------------------------------------------

-- 4.1 Длина, регистр, обрезка пробелов
SELECT customer_id,
       '[' || email || ']'              AS raw_email,
       LENGTH(email)                    AS len_raw,
       LOWER(TRIM(email))               AS clean_email,
       LENGTH(LOWER(TRIM(email)))       AS len_clean
FROM   customers
WHERE  customer_id IN (1, 5, 12)
ORDER  BY customer_id;

SELECT UPPER('ооо "Свежесть"')         AS up,
       LOWER('ООО  "РОМАШКА"')         AS low,
       INITCAP('комаров илья петрович') AS initcap_,
       LTRIM('  тендер №45/2025')      AS ltrim_,
       TRIM(BOTH '"' FROM '"Колос"')   AS trim_quotes;

-- 4.2 SUBSTRING, LEFT, RIGHT, POSITION / STRPOS, SPLIT_PART — разбор номера партии П240101-1Д
SELECT batch_number,
       SUBSTRING(batch_number FROM 2 FOR 6)        AS date_code,
       SUBSTRING(batch_number, 2, 6)               AS date_code_short,
       SPLIT_PART(batch_number, '-', 2)            AS line_shift,
       RIGHT(batch_number, 1)                      AS shift_letter,
       POSITION('-' IN batch_number)               AS dash_pos,
       STRPOS(batch_number, '-')                   AS dash_pos2
FROM   production_batches
ORDER  BY batch_id
LIMIT  4;

-- 4.3 REPLACE и регулярные выражения: нормализация телефонов к формату +7XXXXXXXXXX
SELECT customer_id,
       phone,
       regexp_replace(phone, '\D', '', 'g')                          AS digits_only,
       '+7' || RIGHT(regexp_replace(phone, '\D', '', 'g'), 10)       AS phone_norm
FROM   customers
WHERE  customer_id IN (1, 2, 5, 6)
ORDER  BY customer_id;

-- 4.4 Нормализация названия для поиска дублей: верхний регистр, без ОПФ, кавычек и «(дубль)»
SELECT customer_id,
       customer_name,
       TRIM(regexp_replace(
                regexp_replace(UPPER(customer_name),
                               '\m(ООО|АО|ИП)\M|"|\(ДУБЛЬ\)', '', 'g'),
                '\s+', ' ', 'g'))                                   AS name_norm
FROM   customers
WHERE  inn IN ('7924695572', '8423916122', '562810604315')
ORDER  BY inn, customer_id;

-- 4.5 Склейка строк: || против CONCAT / CONCAT_WS при NULL; format()
SELECT supplier_name || ' / ' || phone                       AS by_pipes,
       CONCAT(supplier_name, ' / ', phone)                    AS by_concat,
       CONCAT_WS(' / ', supplier_name, phone, inn)            AS by_concat_ws,
       format('%s (рейтинг %s)', supplier_name, COALESCE(rating::text, 'нет')) AS by_format
FROM   suppliers
WHERE  supplier_id IN (1, 12)
ORDER  BY supplier_id;

-- 4.6 LPAD / RPAD: номер документа с ведущими нулями
SELECT po_id,
       po_number,
       'ЗП-' || EXTRACT(YEAR FROM order_date) || '-' || LPAD(po_id::text, 5, '0') AS rebuilt_number
FROM   purchase_orders
ORDER  BY po_id
LIMIT  3;

-- ---------------------------------------------------------------------
-- Раздел 5. Дата и время
-- ---------------------------------------------------------------------

-- 5.1 Текущие значения (зависят от момента запуска)
SELECT CURRENT_DATE                AS today,
       NOW()                       AS now_tz,
       LOCALTIMESTAMP              AS now_local,
       current_setting('TimeZone') AS server_tz;

-- 5.2 EXTRACT / date_part
SELECT order_date,
       EXTRACT(YEAR    FROM order_date) AS y,
       EXTRACT(QUARTER FROM order_date) AS q,
       EXTRACT(MONTH   FROM order_date) AS m,
       EXTRACT(ISODOW  FROM order_date) AS iso_dow,     -- 1 = понедельник … 7 = воскресенье
       date_part('week', order_date)    AS iso_week
FROM   orders
WHERE  order_id = 4458;

-- 5.3 date_trunc — «обрезка» до начала периода
SELECT start_time,
       date_trunc('month', start_time) AS month_start,
       date_trunc('hour',  start_time) AS hour_start,
       date_trunc('week',  start_time) AS week_start
FROM   equipment_downtime
WHERE  downtime_id = 148;

-- 5.4 Арифметика дат: date − date = integer (дни); timestamp − timestamp = interval
SELECT order_number,
       order_date,
       shipped_date,
       shipped_date - order_date                AS lead_days,
       pg_typeof(shipped_date - order_date)     AS type_
FROM   orders
WHERE  order_id IN (1, 2, 3)
ORDER  BY order_id;

SELECT downtime_id,
       start_time,
       end_time,
       (end_time - start_time)::text                              AS duration,
       ROUND(EXTRACT(EPOCH FROM end_time - start_time) / 3600, 2) AS hours
FROM   equipment_downtime
WHERE  end_time IS NOT NULL
ORDER  BY end_time - start_time DESC
LIMIT  3;

-- 5.5 Интервалы: прибавить к дате, AGE, справа — ловушка «конец месяца»
SELECT DATE '2025-01-31' + INTERVAL '1 month'              AS jan31_plus_month,
       DATE '2025-12-31' + 30                              AS plus_30_days,
       (DATE '2025-12-31' - INTERVAL '1 year')::date       AS minus_year,
       AGE(DATE '2025-12-31', DATE '2009-01-01')::text     AS line2_age,
       EXTRACT(YEAR FROM AGE(DATE '2025-12-31', DATE '2009-01-01')) AS line2_full_years;

-- 5.6 Возраст производственных линий на дату среза 31.12.2025
SELECT line_id,
       line_name,
       launch_year,
       2025 - launch_year                                           AS age_years,
       make_date(launch_year, 1, 1)                                 AS launch_date_approx,
       AGE(DATE '2025-12-31', make_date(launch_year, 1, 1))::text   AS age_full
FROM   production_lines
ORDER  BY launch_year;

-- 5.7 to_char с форматами на русском: TM-префикс + lc_time
SET lc_time = 'ru_RU.UTF-8';

SELECT to_char(DATE '2025-03-08', 'DD.MM.YYYY')              AS ru_numeric,
       to_char(DATE '2025-03-08', 'TMDay, DD TMMonth YYYY')  AS ru_long,
       to_char(DATE '2025-03-08', 'TMMon YYYY')              AS ru_short,
       to_char(DATE '2025-03-08', 'YYYY-"Q"Q')               AS year_quarter,
       to_char(TIMESTAMP '2025-03-08 22:15', 'HH24:MI')      AS hh_mi;

-- 5.8 generate_series — календарь (все дни декабря 2025 и день недели)
SELECT d::date                         AS day,
       to_char(d, 'TMDy')              AS dow,
       EXTRACT(ISODOW FROM d) IN (6, 7) AS is_weekend
FROM   generate_series(DATE '2025-12-01', DATE '2025-12-31', INTERVAL '1 day') AS d
ORDER  BY d
LIMIT  10;

-- календарь месяцев 2025 года
SELECT to_char(m, 'YYYY-MM')        AS ym,
       to_char(m, 'TMMonth')        AS month_name
FROM   generate_series(DATE '2025-01-01', DATE '2025-12-01', INTERVAL '1 month') AS m;

-- 5.9 Простой незакрытый: длительность «на сейчас» нельзя посчитать от NULL — подставим дату среза
SELECT downtime_id,
       line_id,
       start_time,
       end_time,
       (COALESCE(end_time, TIMESTAMP '2026-01-01 00:00') - start_time)::text AS open_duration
FROM   equipment_downtime
WHERE  end_time IS NULL
ORDER  BY start_time;

-- ---------------------------------------------------------------------
-- Раздел 6. Условные выражения CASE
-- ---------------------------------------------------------------------

-- 6.1 Поисковый CASE: категории скидок
SELECT order_item_id,
       discount_pct,
       CASE
           WHEN discount_pct = 0   THEN 'без скидки'
           WHEN discount_pct <= 10 THEN 'в рамках политики'
           WHEN discount_pct <= 15 THEN 'сверх политики'
           ELSE 'критично (>15 %)'
       END AS discount_class
FROM   order_items
WHERE  order_item_id IN (1, 2, 123, 6100, 8509)
ORDER  BY order_item_id;

-- 6.2 Простой CASE: расшифровка буквы смены из номера партии
SELECT batch_number,
       CASE RIGHT(batch_number, 1)
           WHEN 'Д' THEN 'День'
           WHEN 'Н' THEN 'Ночь'
           ELSE '??'
       END AS shift_from_code,
       shift
FROM   production_batches
ORDER  BY batch_id
LIMIT  4;

-- 6.3 CASE для защиты от деления на ноль и для «светофора»
SELECT batch_number,
       line_id,
       shift,
       ROUND(100.0 * defect_qty / NULLIF(produced_qty, 0), 2) AS defect_pct,
       CASE
           WHEN 100.0 * defect_qty / NULLIF(produced_qty, 0) >= 5 THEN 'красный'
           WHEN 100.0 * defect_qty / NULLIF(produced_qty, 0) >= 2 THEN 'жёлтый'
           ELSE 'зелёный'
       END AS traffic_light
FROM   production_batches
WHERE  production_date = DATE '2025-06-02'
ORDER  BY line_id, shift;

-- 6.4 Кейс: выявление продаж ниже себестоимости (команда А) — только функции и выражения
SELECT oi.order_item_id,
       o.order_date,
       p.product_name,
       oi.unit_price,
       oi.discount_pct,
       ROUND(oi.unit_price * (1 - oi.discount_pct / 100), 2)                     AS net_price,
       p.standard_cost,
       ROUND(oi.unit_price * (1 - oi.discount_pct / 100) - p.standard_cost, 2)   AS margin_per_unit
FROM   order_items AS oi
JOIN   orders      AS o ON o.order_id   = oi.order_id
JOIN   products    AS p ON p.product_id = oi.product_id
WHERE  oi.unit_price * (1 - oi.discount_pct / 100) < p.standard_cost
  AND  o.order_date >= DATE '2025-03-01'
ORDER  BY margin_per_unit
LIMIT  5;

-- 6.5 Кейс: часы простоев линии 2 по годам (команда Б)
--     (агрегат SUM — модуль 4; здесь важна функция EXTRACT(EPOCH …))
SELECT ROUND(SUM(EXTRACT(EPOCH FROM end_time - start_time)) / 3600, 1) AS hours_2024
FROM   equipment_downtime
WHERE  line_id = 2
  AND  start_time >= '2024-01-01' AND start_time < '2025-01-01';

SELECT ROUND(SUM(EXTRACT(EPOCH FROM end_time - start_time)) / 3600, 1) AS hours_2025
FROM   equipment_downtime
WHERE  line_id = 2
  AND  start_time >= '2025-01-01' AND start_time < '2026-01-01';
