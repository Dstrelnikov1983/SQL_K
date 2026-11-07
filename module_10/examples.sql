-- =====================================================================
-- Курс «Углублённый SQL» · Модуль 10
-- Применение программных элементов: PL/pgSQL
-- Практические примеры преподавателя (PostgreSQL 16)
-- ---------------------------------------------------------------------
-- Данные читаем из pitanie (только чтение). Функции и таблицы создаём
-- в личной схеме stud_ivanov — замените на свою (Ctrl+H).
-- Личная схема создаётся скриптом module_07/scripts/00_personal_schema.sql
-- (выполните его до этого файла). В ней есть копии таблиц pitanie с теми же
-- именами, поэтому исходные таблицы всегда указаны с префиксом pitanie.
-- Вывод RAISE NOTICE в DBeaver — вкладка «Output» (включите: Ctrl+Shift+O),
-- в psql — сразу в консоли.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS stud_ivanov;
SET search_path TO stud_ivanov, pitanie, public;

-- =====================================================================
-- 1. АНОНИМНЫЙ БЛОК DO
-- =====================================================================
-- T-SQL: пакет (batch) с DECLARE @x ... PRINT
-- PostgreSQL: DO $$ ... $$ — блок PL/pgSQL без имени, ничего не возвращает,
--             вывод — через RAISE NOTICE

DO $$
BEGIN
    RAISE NOTICE 'Привет, «Питание +»! Сейчас %', now()::date;
END
$$;

-- =====================================================================
-- 2. ПЕРЕМЕННЫЕ
-- =====================================================================

-- 2.1. Объявление, типы, константы, присваивание, SELECT ... INTO
DO $$
DECLARE
    c_policy   CONSTANT numeric := 10;            -- константа: лимит скидки, %
    v_orders   integer;                            -- без начального значения = NULL
    v_revenue  numeric(14,2) := 0;
    v_from     date := DATE '2025-01-01';
    v_label    text;
BEGIN
    SELECT COUNT(DISTINCT o.order_id),
           SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100))
    INTO   v_orders, v_revenue                     -- результат запроса → переменные
    FROM   pitanie.orders      AS o
    JOIN   pitanie.order_items AS oi ON oi.order_id = o.order_id
    WHERE  o.status <> 'Отменён'
      AND  o.order_date >= v_from;

    v_label := format('Заказов с %s: %s, выручка %s млн, лимит скидки %s %%',
                      to_char(v_from, 'DD.MM.YYYY'), v_orders,
                      round(v_revenue / 1e6, 1), c_policy);
    RAISE NOTICE '%', v_label;
END
$$;
-- NOTICE: Заказов с 01.01.2025: 2240, выручка 445.1 млн, лимит скидки 10 %

-- 2.2. %TYPE и %ROWTYPE: тип «как у столбца» / «как строка таблицы»
DO $$
DECLARE
    v_name   pitanie.customers.customer_name%TYPE;    -- varchar(150)
    v_cust   pitanie.customers%ROWTYPE;               -- вся строка клиента
BEGIN
    SELECT * INTO v_cust
    FROM   pitanie.customers
    WHERE  customer_id = 1;

    v_name := v_cust.customer_name;
    RAISE NOTICE 'Клиент: %, лимит %, отсрочка % дн., менеджер id %',
                 v_name, v_cust.credit_limit, v_cust.payment_terms_days, v_cust.manager_id;
END
$$;

-- 2.3. RECORD — строка произвольной структуры (структура определяется запросом)
DO $$
DECLARE
    r record;
BEGIN
    SELECT l.line_name, COUNT(*) AS batches, SUM(b.defect_qty) AS defects
    INTO   r
    FROM   pitanie.production_batches AS b
    JOIN   pitanie.production_lines   AS l ON l.line_id = b.line_id
    WHERE  b.line_id = 3
    GROUP  BY l.line_name;

    RAISE NOTICE '%: партий %, брак % шт.', r.line_name, r.batches, r.defects;
END
$$;

-- 2.4. SELECT ... INTO STRICT: ровно одна строка, иначе ошибка
-- ОЖИДАЕМАЯ ОШИБКА: query returned more than one row
DO $$
DECLARE
    v_id integer;
BEGIN
    SELECT employee_id INTO STRICT v_id
    FROM   pitanie.employees
    WHERE  department = 'Закупки';
END
$$;

-- без STRICT лишние строки молча отбрасываются, а при 0 строк — NULL:
DO $$
DECLARE
    v_id integer;
BEGIN
    SELECT employee_id INTO v_id
    FROM   pitanie.employees
    WHERE  department = 'Маркетинг';           -- такого отдела нет
    RAISE NOTICE 'v_id = %, FOUND = %', v_id, FOUND;
END
$$;
-- NOTICE: v_id = <NULL>, FOUND = f

-- =====================================================================
-- 3. УСЛОВИЯ: IF / ELSIF / ELSE и CASE
-- =====================================================================

-- 3.1. IF: классифицируем линию 3 по проценту брака
DO $$
DECLARE
    v_pct numeric;
BEGIN
    SELECT 100.0 * SUM(defect_qty) / NULLIF(SUM(produced_qty), 0)
    INTO   v_pct
    FROM   pitanie.production_batches
    WHERE  line_id = 3 AND shift = 'Ночь';

    IF v_pct IS NULL THEN
        RAISE NOTICE 'Нет данных';
    ELSIF v_pct < 2 THEN
        RAISE NOTICE 'Брак % %% — норма', round(v_pct, 2);
    ELSIF v_pct < 5 THEN
        RAISE NOTICE 'Брак % %% — внимание', round(v_pct, 2);
    ELSE
        RAISE NOTICE 'Брак % %% — КРИТИЧНО', round(v_pct, 2);
    END IF;
END
$$;
-- NOTICE: Брак 7.94 % — КРИТИЧНО

-- 3.2. CASE (поисковый) как оператор PL/pgSQL и CASE как выражение SQL
DO $$
DECLARE
    v_debt  numeric;
    v_limit numeric;
    v_state text;
BEGIN
    SELECT SUM(i.amount) - COALESCE(SUM(p.paid), 0), MAX(c.credit_limit)
    INTO   v_debt, v_limit
    FROM   pitanie.invoices  AS i
    JOIN   pitanie.orders    AS o ON o.order_id = i.order_id
    JOIN   pitanie.customers AS c ON c.customer_id = o.customer_id
    LEFT   JOIN (SELECT invoice_id, SUM(amount) AS paid
                 FROM   pitanie.payments
                 GROUP  BY invoice_id) AS p ON p.invoice_id = i.invoice_id
    WHERE  o.customer_id = 1;

    CASE
        WHEN v_debt <= 0.8 * v_limit THEN v_state := 'в пределах лимита';
        WHEN v_debt <= v_limit       THEN v_state := 'близко к лимиту';
        ELSE                              v_state := 'ЛИМИТ ПРЕВЫШЕН';
    END CASE;

    RAISE NOTICE 'Долг % руб. при лимите % — %', round(v_debt), v_limit, v_state;
END
$$;
-- NOTICE: Долг 6907600 руб. при лимите 3000000.00 — ЛИМИТ ПРЕВЫШЕН

-- =====================================================================
-- 4. ЦИКЛЫ
-- =====================================================================

-- 4.1. LOOP ... EXIT WHEN ... CONTINUE WHEN
--      Сколько месяцев 2025 года подряд долг клиента 1 был ниже лимита?
DO $$
DECLARE
    v_month int := 0;
    v_debt  numeric;
BEGIN
    LOOP
        v_month := v_month + 1;
        EXIT WHEN v_month > 12;                          -- выход из цикла

        SELECT COALESCE(SUM(i.amount), 0)
               - COALESCE((SELECT SUM(p.amount)
                           FROM   pitanie.payments AS p
                           JOIN   pitanie.invoices AS i2 ON i2.invoice_id = p.invoice_id
                           JOIN   pitanie.orders   AS o2 ON o2.order_id   = i2.order_id
                           WHERE  o2.customer_id = 1
                             AND  p.payment_date <= (make_date(2025, v_month, 1) + INTERVAL '1 month - 1 day')::date), 0)
        INTO   v_debt
        FROM   pitanie.invoices AS i
        JOIN   pitanie.orders   AS o ON o.order_id = i.order_id
        WHERE  o.customer_id = 1
          AND  i.invoice_date <= (make_date(2025, v_month, 1) + INTERVAL '1 month - 1 day')::date;

        CONTINUE WHEN v_debt <= 3000000;                 -- в норме — к следующему месяцу
        RAISE NOTICE 'Первый месяц с превышением лимита: %, долг %', v_month, round(v_debt);
        EXIT;                                            -- нашли — выходим
    END LOOP;
END
$$;
-- NOTICE: Первый месяц с превышением лимита: 6, долг 3348488

-- 4.2. WHILE: через сколько лет при росте простоев на 50 % в год
--      линия 2 будет простаивать больше 1500 часов?
DO $$
DECLARE
    v_hours numeric := 590;     -- простои линии 2 в 2025 г., ч
    v_year  int     := 2025;
BEGIN
    WHILE v_hours <= 1500 LOOP
        v_year  := v_year + 1;
        v_hours := v_hours * 1.5;
    END LOOP;
    RAISE NOTICE 'В % г. простои составят ≈ % ч', v_year, round(v_hours);
END
$$;
-- NOTICE: В 2028 г. простои составят ≈ 1991 ч

-- 4.3. FOR по целочисленному диапазону (с шагом и REVERSE)
DO $$
BEGIN
    FOR q IN 1..4 LOOP                               -- переменная цикла объявляется сама
        RAISE NOTICE 'Квартал %: месяцы % – %', q, 3 * q - 2, 3 * q;
    END LOOP;
    FOR i IN REVERSE 10..1 BY 3 LOOP
        RAISE NOTICE 'Обратный отсчёт: %', i;
    END LOOP;
END
$$;

-- 4.4. FOR по результату запроса — самый частый цикл в аналитике
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT l.line_name,
               ROUND(100.0 * SUM(b.defect_qty) / SUM(b.produced_qty), 2) AS defect_pct
        FROM   pitanie.production_batches AS b
        JOIN   pitanie.production_lines   AS l ON l.line_id = b.line_id
        GROUP  BY l.line_id, l.line_name
        ORDER  BY l.line_id
    LOOP
        RAISE NOTICE '% — брак % %%', rpad(r.line_name, 34), r.defect_pct;
    END LOOP;
END
$$;

-- 4.5. FOREACH по массиву
DO $$
DECLARE
    v_channels text[] := ARRAY['Прямые продажи', 'Дистрибуция', 'Маркетплейс', 'Тендер'];
    v_ch       text;
    v_cnt      int;
BEGIN
    FOREACH v_ch IN ARRAY v_channels LOOP
        SELECT COUNT(*) INTO v_cnt
        FROM   pitanie.orders
        WHERE  channel = v_ch AND status = 'Отменён';
        RAISE NOTICE 'Канал «%»: отменено заказов %', v_ch, v_cnt;
    END LOOP;
END
$$;

-- 4.6. Метки и выход из вложенного цикла: EXIT <<метка>>
--      Перебираем линии по номеру и в каждой партии по дате; на первой
--      партии с браком > 3 % прекращаем ОБА цикла
DO $$
DECLARE
    r record;
BEGIN
    <<lines>>
    FOR v_line IN 1..5 LOOP
        FOR r IN
            SELECT batch_number, production_date,
                   100.0 * defect_qty / produced_qty AS pct
            FROM   pitanie.production_batches
            WHERE  line_id = v_line
            ORDER  BY production_date, batch_id
        LOOP
            IF r.pct > 3 THEN
                RAISE NOTICE 'Линия %: партия % от % — брак % %%',
                             v_line, r.batch_number, r.production_date, round(r.pct, 1);
                EXIT lines;                    -- выходим сразу из ОБОИХ циклов
            END IF;
        END LOOP;
    END LOOP lines;
END
$$;
-- NOTICE: Линия 2: партия П250102-2Д от 2025-01-02 — брак 3.7 %
-- (на линии 1 партий с браком > 3 % нет; первая на линии 2 — сразу в начале 2025 г.)

-- =====================================================================
-- 5. ДИНАМИЧЕСКИЙ SQL: EXECUTE format(...)
-- =====================================================================

-- 5.1. Число строк в нескольких таблицах — имя таблицы в переменной
DO $$
DECLARE
    v_tab text;
    v_cnt bigint;
BEGIN
    FOREACH v_tab IN ARRAY ARRAY['orders', 'order_items', 'production_batches', 'equipment_downtime'] LOOP
        EXECUTE format('SELECT COUNT(*) FROM %I.%I', 'pitanie', v_tab)
        INTO v_cnt;
        RAISE NOTICE '%: % строк', rpad(v_tab, 20), v_cnt;
    END LOOP;
END
$$;
-- %I — идентификатор (кавычки при необходимости), %L — литерал, %s — как есть

-- 5.2. Значения — через USING ($1, $2), а не склейкой строк
DO $$
DECLARE
    v_cnt bigint;
BEGIN
    EXECUTE format('SELECT COUNT(*) FROM %I.%I WHERE %I > $1 AND order_id IN '
                   '(SELECT order_id FROM pitanie.orders WHERE employee_id = $2)',
                   'pitanie', 'order_items', 'discount_pct')
    INTO  v_cnt
    USING 10, 10;
    RAISE NOTICE 'Позиций со скидкой > 10 %% у менеджера 10: %', v_cnt;
END
$$;
-- NOTICE: Позиций со скидкой > 10 % у менеджера 10: 4312 (включая отменённые заказы)

-- 5.3. SQL-инъекция: почему нельзя склеивать строки
DO $$
DECLARE
    v_input text := $q$Вектор' OR '1'='1$q$;          -- «имя клиента» от пользователя
    v_bad   text;
    v_good  text;
    v_cnt   bigint;
BEGIN
    v_bad  := 'SELECT COUNT(*) FROM pitanie.customers WHERE customer_name = ''' || v_input || '''';
    v_good := format('SELECT COUNT(*) FROM pitanie.customers WHERE customer_name = %L', v_input);

    RAISE NOTICE 'Склейка:  %', v_bad;
    EXECUTE v_bad INTO v_cnt;
    RAISE NOTICE '  → вернулось строк: % (все клиенты!)', v_cnt;

    RAISE NOTICE 'format %%L: %', v_good;
    EXECUTE v_good INTO v_cnt;
    RAISE NOTICE '  → вернулось строк: %', v_cnt;
END
$$;

-- =====================================================================
-- 6. ОБРАБОТКА ОШИБОК
-- =====================================================================

-- 6.1. EXCEPTION WHEN ... THEN — перехват конкретной ошибки
DO $$
DECLARE
    v_plan numeric := 0;
    v_fact numeric := 1500000;
    v_pct  numeric;
BEGIN
    v_pct := 100 * v_fact / v_plan;
    RAISE NOTICE 'Выполнение плана: %', v_pct;
EXCEPTION
    WHEN division_by_zero THEN
        RAISE NOTICE 'План = 0, процент выполнения не определён (SQLSTATE %: %)', SQLSTATE, SQLERRM;
END
$$;
-- NOTICE: План = 0, процент выполнения не определён (SQLSTATE 22012: division by zero)

-- 6.2. Несколько обработчиков, WHEN OTHERS и GET STACKED DIAGNOSTICS
DO $$
DECLARE
    v_id     integer;
    v_state  text;
    v_msg    text;
    v_detail text;
    v_ctx    text;
BEGIN
    SELECT employee_id INTO STRICT v_id
    FROM   pitanie.employees
    WHERE  department = 'Закупки';
EXCEPTION
    WHEN no_data_found THEN
        RAISE NOTICE 'Не найдено ни одного сотрудника';
    WHEN too_many_rows THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE,
                                v_msg   = MESSAGE_TEXT,
                                v_ctx   = PG_EXCEPTION_CONTEXT;
        RAISE NOTICE 'Ошибка %: %', v_state, v_msg;
        RAISE NOTICE 'Контекст: %', v_ctx;
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
        RAISE NOTICE 'Непредвиденная ошибка %: % (%)', SQLSTATE, SQLERRM, v_detail;
END
$$;

-- 6.3. RAISE EXCEPTION с кодом, деталями и подсказкой
-- ОЖИДАЕМАЯ ОШИБКА: Линия 7 не существует (SQLSTATE 22023, с HINT)
DO $$
DECLARE
    v_line integer := 7;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pitanie.production_lines WHERE line_id = v_line) THEN
        RAISE EXCEPTION 'Линия % не существует', v_line
              USING ERRCODE = 'invalid_parameter_value',     -- 22023
                    DETAIL  = 'В справочнике production_lines линии 1–5',
                    HINT    = 'Проверьте параметр p_line';
    END IF;
END
$$;

-- 6.4. Собственный код ошибки и его перехват
DO $$
BEGIN
    BEGIN                                           -- вложенный блок
        RAISE EXCEPTION 'Скидка 25 %% превышает политику'
              USING ERRCODE = 'P0010';              -- свой код класса P0
    EXCEPTION
        WHEN SQLSTATE 'P0010' THEN
            RAISE NOTICE 'Перехвачено нарушение политики: %', SQLERRM;
    END;
    RAISE NOTICE 'Выполнение продолжается после вложенного блока';
END
$$;

-- 6.5. ASSERT — проверка инварианта (для отладки и тестов)
-- ОЖИДАЕМАЯ ОШИБКА: «Найдено N позиций со скидкой > 10 %» (ASSERT срабатывает, если условие ложно)
DO $$
DECLARE
    v_bad int;
BEGIN
    SELECT COUNT(*) INTO v_bad
    FROM   pitanie.order_items
    WHERE  discount_pct > 10;
    ASSERT v_bad = 0, format('Найдено %s позиций со скидкой > 10 %%', v_bad);
END
$$;

-- 6.6. Блок EXCEPTION откатывает изменения своего блока (точка сохранения)
DROP TABLE IF EXISTS stud_ivanov.m10_demo;
CREATE TABLE stud_ivanov.m10_demo (id int PRIMARY KEY, note text);

DO $$
BEGIN
    INSERT INTO stud_ivanov.m10_demo VALUES (1, 'до блока');
    BEGIN
        INSERT INTO stud_ivanov.m10_demo VALUES (2, 'в блоке');
        INSERT INTO stud_ivanov.m10_demo VALUES (1, 'дубль ключа');   -- ошибка
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'Дубль ключа: вставка (2) откатилась вместе с блоком';
    END;
END
$$;

SELECT * FROM stud_ivanov.m10_demo;     -- одна строка: 1 | до блока

-- =====================================================================
-- 7. ФУНКЦИИ НА PL/pgSQL (скалярные) — мост к модулю 12
-- =====================================================================

-- 7.1. Чистая функция классификации: IMMUTABLE
CREATE OR REPLACE FUNCTION stud_ivanov.fn_defect_class(p_defect_pct numeric)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_defect_pct IS NULL THEN
        RETURN 'нет данных';
    END IF;
    RETURN CASE
               WHEN p_defect_pct < 2 THEN 'норма'
               WHEN p_defect_pct < 5 THEN 'внимание'
               ELSE 'критично'
           END;
END
$$;

SELECT line_id,
       shift,
       ROUND(100.0 * SUM(defect_qty) / SUM(produced_qty), 2)                              AS defect_pct,
       stud_ivanov.fn_defect_class(100.0 * SUM(defect_qty) / SUM(produced_qty))           AS class
FROM   pitanie.production_batches
GROUP  BY line_id, shift
ORDER  BY defect_pct DESC
LIMIT  4;

-- 7.2. Функция с проверкой параметров и чтением данных: STABLE
--      Долг по счёту на дату
CREATE OR REPLACE FUNCTION stud_ivanov.fn_invoice_debt(
    p_invoice_id integer,
    p_date       date DEFAULT DATE '2025-12-31'
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_amount numeric;
    v_paid   numeric;
BEGIN
    IF p_invoice_id IS NULL OR p_date IS NULL THEN
        RAISE EXCEPTION 'Параметры не могут быть NULL'
              USING ERRCODE = 'null_value_not_allowed';
    END IF;

    SELECT amount INTO v_amount
    FROM   pitanie.invoices
    WHERE  invoice_id = p_invoice_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Счёт % не найден', p_invoice_id
              USING ERRCODE = 'no_data_found', HINT = 'Проверьте invoice_id';
    END IF;

    SELECT COALESCE(SUM(amount), 0) INTO v_paid
    FROM   pitanie.payments
    WHERE  invoice_id = p_invoice_id
      AND  payment_date <= p_date;

    RETURN v_amount - v_paid;
END
$$;

SELECT i.invoice_number,
       i.amount,
       stud_ivanov.fn_invoice_debt(i.invoice_id) AS debt
FROM   pitanie.invoices AS i
JOIN   pitanie.orders   AS o ON o.order_id = i.order_id
WHERE  o.customer_id = 1
ORDER  BY debt DESC
LIMIT  3;

-- ОЖИДАЕМАЯ ОШИБКА: Счёт 999999 не найден
SELECT stud_ivanov.fn_invoice_debt(999999);

-- 7.3. Табличная функция на PL/pgSQL: RETURN QUERY / RETURN NEXT
--      (аналог multi-statement TVF из T-SQL)
CREATE OR REPLACE FUNCTION stud_ivanov.fn_lines_status()
RETURNS TABLE (line_id int, line_name varchar, defect_pct numeric, status text)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT l.line_id, l.line_name,
               ROUND(100.0 * SUM(b.defect_qty) / SUM(b.produced_qty), 2) AS pct
        FROM   pitanie.production_lines   AS l
        JOIN   pitanie.production_batches AS b ON b.line_id = l.line_id
        GROUP  BY l.line_id, l.line_name
    LOOP
        line_id    := r.line_id;               -- OUT-столбцы — это переменные
        line_name  := r.line_name;
        defect_pct := r.pct;
        status     := stud_ivanov.fn_defect_class(r.pct);
        RETURN NEXT;                           -- добавить строку в результат
    END LOOP;
END
$$;

SELECT * FROM stud_ivanov.fn_lines_status() ORDER BY defect_pct DESC;

-- 7.4. Метаданные: язык и категория изменчивости функций личной схемы
SELECT p.proname, l.lanname, p.provolatile,
       pg_get_function_result(p.oid) AS returns
FROM   pg_proc     AS p
JOIN   pg_language AS l ON l.oid = p.prolang
WHERE  p.pronamespace = 'stud_ivanov'::regnamespace
ORDER  BY p.proname;

-- =====================================================================
-- Шпаргалка T-SQL → PL/pgSQL
-- ---------------------------------------------------------------------
--  DECLARE @x INT = 5;           →  DECLARE x int := 5;   (внутри DO/функции)
--  SET @x = 10; SELECT @x = col  →  x := 10;  SELECT col INTO x ...
--  PRINT 'текст'                 →  RAISE NOTICE 'текст %', x;
--  IF ... BEGIN ... END ELSE     →  IF ... THEN ... ELSIF ... ELSE ... END IF;
--  WHILE ... BEGIN ... END       →  WHILE ... LOOP ... END LOOP;
--  BREAK / CONTINUE              →  EXIT / CONTINUE  (с метками: EXIT lbl)
--  BEGIN TRY ... END TRY
--  BEGIN CATCH ... END CATCH     →  BEGIN ... EXCEPTION WHEN ... THEN ... END;
--  ERROR_NUMBER(), ERROR_MESSAGE()→ SQLSTATE, SQLERRM, GET STACKED DIAGNOSTICS
--  THROW 50001, 'msg', 1;        →  RAISE EXCEPTION 'msg' USING ERRCODE = 'P0001';
--  EXEC sp_executesql @sql, N'@p INT', @p = 1
--                                →  EXECUTE format(...) USING p;
--  QUOTENAME(@name)              →  format('%I', name) / quote_ident(name)
-- =====================================================================
