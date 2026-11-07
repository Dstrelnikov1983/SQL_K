-- =====================================================================
-- Курс «Углублённый SQL» · Модуль 12 «Выполнение хранимых процедур»
-- Практические примеры преподавателя (PostgreSQL 16)
-- =====================================================================
-- Подготовка: module_12/scripts/01_setup.sql (замените stud_ivanov на свою схему).
-- Все объекты создаются в личной схеме. Ошибки, показываемые намеренно,
-- помечены  -- ОЖИДАЕМАЯ ОШИБКА
-- =====================================================================

SET search_path TO stud_ivanov, pitanie, public;

-- =====================================================================
-- 1. ФУНКЦИЯ И ПРОЦЕДУРА
-- =====================================================================
-- Функция возвращает значение и вызывается внутри SELECT.
CREATE OR REPLACE FUNCTION fn_invoice_balance(p_invoice_id integer)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT i.amount - COALESCE((SELECT SUM(p.amount)
                                FROM   payments AS p
                                WHERE  p.invoice_id = i.invoice_id), 0)
    FROM   invoices AS i
    WHERE  i.invoice_id = p_invoice_id;
$$;

SELECT invoice_id, invoice_number, amount,
       fn_invoice_balance(invoice_id) AS balance
FROM   invoices
WHERE  invoice_id IN (2045, 4070);              -- 198983.83 и 78290.05

-- Процедура ничего не возвращает (кроме OUT/INOUT), вызывается CALL
-- и может управлять транзакциями.
CREATE OR REPLACE PROCEDURE sp_hello(p_name text DEFAULT 'аналитик')
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE NOTICE 'Привет, %! Сейчас %', p_name, to_char(now(), 'DD.MM.YYYY HH24:MI');
END;
$$;

CALL sp_hello();
CALL sp_hello('команда А');

SELECT sp_hello();                    -- ОЖИДАЕМАЯ ОШИБКА: sp_hello() is a procedure
CALL fn_invoice_balance(4070);        -- ОЖИДАЕМАЯ ОШИБКА: fn_invoice_balance(integer) is not a procedure

-- =====================================================================
-- 2. ПАРАМЕТРЫ: DEFAULT, именованные, OUT/INOUT, перегрузка
-- =====================================================================
-- Долг клиента на дату. Параметр с DEFAULT — в конце списка.
CREATE OR REPLACE FUNCTION fn_customer_debt(p_customer_id integer,
                                            p_as_of       date DEFAULT DATE '2025-12-31')
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(SUM(i.amount), 0)
         - COALESCE((SELECT SUM(p.amount)
                     FROM   payments AS p
                     JOIN   invoices AS i2 ON i2.invoice_id = p.invoice_id
                     JOIN   orders   AS o2 ON o2.order_id   = i2.order_id
                     WHERE  o2.customer_id = p_customer_id
                       AND  p.payment_date <= p_as_of), 0)
    FROM   invoices AS i
    JOIN   orders   AS o ON o.order_id = i.order_id
    WHERE  o.customer_id = p_customer_id
      AND  i.invoice_date <= p_as_of;
$$;

SELECT fn_customer_debt(1)                                    AS debt_default,   -- 6907600.45
       fn_customer_debt(1, DATE '2024-12-31')                 AS debt_2024,      -- позиционно
       fn_customer_debt(p_as_of => DATE '2025-06-30',
                        p_customer_id => 1)                   AS debt_mid_2025;  -- по именам

-- Перегрузка: та же функция по ИНН (другой тип параметра)
CREATE OR REPLACE FUNCTION fn_customer_debt(p_inn varchar)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT SUM(fn_customer_debt(c.customer_id))
    FROM   customers AS c
    WHERE  c.inn = p_inn;
$$;

SELECT fn_customer_debt('7924695572'::varchar) AS debt_romashka_all_cards;   -- 3 карточки «Ромашки»

SELECT p.oid::regprocedure AS signature, p.prokind
FROM   pg_proc AS p
WHERE  p.proname = 'fn_customer_debt'
  AND  p.pronamespace = current_schema()::regnamespace;      -- две версии

-- OUT / INOUT в процедуре: при CALL на месте OUT-параметра передаём NULL
CREATE OR REPLACE PROCEDURE sp_customer_summary(
    IN    p_customer_id integer,
    OUT   p_name        text,
    OUT   p_debt        numeric,
    INOUT p_limit_used  numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $$
BEGIN
    SELECT c.customer_name,
           fn_customer_debt(c.customer_id),
           ROUND(100 * fn_customer_debt(c.customer_id) / c.credit_limit, 1)
    INTO   p_name, p_debt, p_limit_used
    FROM   customers AS c
    WHERE  c.customer_id = p_customer_id;
END;
$$;

CALL sp_customer_summary(1, NULL, NULL);          -- Вектор | 6907600.45 | 230.3

-- =====================================================================
-- 3. ПРОЦЕДУРА МОДИФИКАЦИИ ДАННЫХ С ВАЛИДАЦИЕЙ
-- =====================================================================
CREATE OR REPLACE PROCEDURE sp_demo_add_payment(
    p_invoice_id integer,
    p_amount     numeric,
    INOUT p_payment_id integer DEFAULT NULL)
LANGUAGE plpgsql
AS $$
DECLARE
    v_balance numeric;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Сумма оплаты должна быть положительной: %', p_amount
              USING ERRCODE = 'invalid_parameter_value',
                    HINT    = 'Проверьте выписку банка';
    END IF;

    PERFORM 1 FROM invoices WHERE invoice_id = p_invoice_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Счёт % не найден', p_invoice_id
              USING ERRCODE = 'no_data_found';
    END IF;

    v_balance := fn_invoice_balance(p_invoice_id);
    IF p_amount > v_balance THEN
        RAISE EXCEPTION 'Переплата по счёту %', p_invoice_id
              USING DETAIL = format('Остаток %s, оплата %s', v_balance, p_amount);
    END IF;

    INSERT INTO payments (invoice_id, payment_date, amount, payment_method)
    VALUES (p_invoice_id, DATE '2025-12-31', p_amount, 'Банковский перевод')
    RETURNING payment_id INTO p_payment_id;
END;
$$;

CALL sp_demo_add_payment(4070, 30000);           -- p_payment_id = 5001
CALL sp_demo_add_payment(4070, 60000);           -- ОЖИДАЕМАЯ ОШИБКА: Переплата по счёту 4070 (DETAIL: Остаток 48290.05 ...)
CALL sp_demo_add_payment(999999, 100);           -- ОЖИДАЕМАЯ ОШИБКА: Счёт 999999 не найден
CALL sp_demo_add_payment(4070, -1);              -- ОЖИДАЕМАЯ ОШИБКА: Сумма оплаты должна быть положительной
CALL sp_demo_add_payment(p_amount => 1000, p_invoice_id => 4070);   -- именованный вызов: 5002

-- =====================================================================
-- 4. ВОЗВРАТ НАБОРА СТРОК ИЗ ПРОЦЕДУРЫ: REFCURSOR
-- =====================================================================
-- Аналог «SELECT в конце процедуры» T-SQL. Курсор живёт до конца транзакции,
-- поэтому CALL и FETCH выполняются в одном BEGIN ... COMMIT.
CREATE OR REPLACE PROCEDURE sp_open_invoices(
    p_customer_id integer,
    INOUT p_cur   refcursor DEFAULT 'open_invoices')
LANGUAGE plpgsql
AS $$
BEGIN
    OPEN p_cur FOR
        SELECT i.invoice_number, i.invoice_date, i.due_date, i.amount,
               fn_invoice_balance(i.invoice_id) AS balance
        FROM   invoices AS i
        JOIN   orders   AS o ON o.order_id = i.order_id
        WHERE  o.customer_id = p_customer_id
          AND  fn_invoice_balance(i.invoice_id) > 0.01
        ORDER  BY i.due_date;
END;
$$;

BEGIN;
CALL sp_open_invoices(1);
FETCH 5 FROM open_invoices;                       -- первые 5 неоплаченных счетов Вектора
CLOSE open_invoices;
COMMIT;

-- Чаще для чтения удобнее табличная функция (модуль 9):
CREATE OR REPLACE FUNCTION fn_open_invoices(p_customer_id integer)
RETURNS TABLE (invoice_number varchar, due_date date, balance numeric)
LANGUAGE sql
STABLE
AS $$
    SELECT i.invoice_number, i.due_date, fn_invoice_balance(i.invoice_id)
    FROM   invoices AS i
    JOIN   orders   AS o ON o.order_id = i.order_id
    WHERE  o.customer_id = p_customer_id
      AND  fn_invoice_balance(i.invoice_id) > 0.01;
$$;

SELECT COUNT(*) AS open_cnt, SUM(balance) AS open_sum
FROM   fn_open_invoices(1);                       -- 45 счетов, 6 876 600,45 (с учётом оплат раздела 3)

-- =====================================================================
-- 5. ТРАНЗАКЦИИ ВНУТРИ ПРОЦЕДУРЫ
-- =====================================================================
-- Пересчёт помесячно с фиксацией каждого месяца: при сбое на 7-м месяце
-- первые 6 уже сохранены, повторный запуск продолжит с места остановки.
CREATE OR REPLACE PROCEDURE sp_demo_monthly_revenue(p_year integer)
LANGUAGE plpgsql
AS $$
DECLARE
    v_month   integer;
    v_revenue numeric;
BEGIN
    FOR v_month IN 1..12 LOOP
        SELECT SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100))
        INTO   v_revenue
        FROM   orders AS o
        JOIN   order_items AS oi ON oi.order_id = o.order_id
        WHERE  o.status <> 'Отменён'
          AND  o.order_date >= make_date(p_year, v_month, 1)
          AND  o.order_date <  make_date(p_year, v_month, 1) + INTERVAL '1 month';

        RAISE NOTICE '%-%: выручка %', p_year, lpad(v_month::text, 2, '0'), ROUND(v_revenue);
        COMMIT;                                   -- каждый месяц — своя транзакция
    END LOOP;
END;
$$;

CALL sp_demo_monthly_revenue(2025);

-- =====================================================================
-- 6. БЕЗОПАСНОСТЬ: SECURITY DEFINER / INVOKER, search_path, GRANT EXECUTE
-- =====================================================================
-- По умолчанию SECURITY INVOKER: процедура работает с правами вызывающего.
-- SECURITY DEFINER — с правами владельца (аналог EXECUTE AS OWNER).
-- Обязательно фиксировать search_path, иначе вызывающий может подменить
-- таблицу/функцию своей «одноимённой» в схеме, стоящей раньше в пути.
CREATE OR REPLACE FUNCTION fn_customer_credit_info(p_customer_id integer)
RETURNS TABLE (customer_name varchar, credit_limit numeric, debt numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = stud_ivanov, pg_temp
AS $$
    SELECT c.customer_name, c.credit_limit, fn_customer_debt(c.customer_id)
    FROM   customers AS c
    WHERE  c.customer_id = p_customer_id;
$$;

-- Права: отзываем у всех, выдаём нужной роли
REVOKE EXECUTE ON FUNCTION fn_customer_credit_info(integer) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION fn_customer_credit_info(integer) TO CURRENT_USER;  -- в жизни: TO sales_role

SELECT * FROM fn_customer_credit_info(1);

SELECT p.proname,
       p.prosecdef                       AS security_definer,
       p.proconfig                       AS fixed_settings,
       pg_get_userbyid(p.proowner)       AS owner,
       has_function_privilege(p.oid, 'EXECUTE') AS i_can_execute
FROM   pg_proc AS p
WHERE  p.pronamespace = current_schema()::regnamespace
  AND  p.proname LIKE 'fn_customer%';

SELECT routine_name, grantee, privilege_type
FROM   information_schema.routine_privileges
WHERE  routine_schema = current_schema()
  AND  routine_name = 'fn_customer_credit_info';

-- =====================================================================
-- 7. «СИСТЕМНЫЕ ХРАНИМЫЕ ПРОЦЕДУРЫ» T-SQL → СИСТЕМНЫЕ ФУНКЦИИ И ПРЕДСТАВЛЕНИЯ PG
-- =====================================================================
-- sp_help / sp_columns 'customers'  →  information_schema.columns
SELECT column_name, data_type, character_maximum_length, is_nullable, column_default
FROM   information_schema.columns
WHERE  table_schema = 'pitanie'
  AND  table_name   = 'customers'
ORDER  BY ordinal_position;

-- sp_helpindex  →  pg_indexes
SELECT indexname, indexdef
FROM   pg_indexes
WHERE  schemaname = 'pitanie'
  AND  tablename  = 'orders';

-- sp_spaceused  →  pg_total_relation_size / pg_relation_size / pg_indexes_size
SELECT c.relname                                     AS table_name,
       c.reltuples::bigint                           AS rows_estimate,
       pg_size_pretty(pg_relation_size(c.oid))       AS data,
       pg_size_pretty(pg_indexes_size(c.oid))        AS indexes,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total
FROM   pg_class AS c
WHERE  c.relnamespace = 'pitanie'::regnamespace
  AND  c.relkind = 'r'
ORDER  BY pg_total_relation_size(c.oid) DESC
LIMIT  5;

SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size;

-- sp_tables / sp_stored_procedures  →  information_schema.tables / routines
SELECT table_name, table_type
FROM   information_schema.tables
WHERE  table_schema = 'pitanie'
ORDER  BY table_name
LIMIT  5;

SELECT routine_name, routine_type, data_type AS returns
FROM   information_schema.routines
WHERE  routine_schema = current_schema()
ORDER  BY routine_type, routine_name;

-- sp_helptext  →  pg_get_functiondef  (в psql: \sf имя,  \df+ имя)
SELECT pg_get_functiondef('fn_invoice_balance(integer)'::regprocedure);

-- аргументы и тип результата
SELECT p.proname,
       CASE p.prokind WHEN 'f' THEN 'function' WHEN 'p' THEN 'procedure' END AS kind,
       pg_get_function_arguments(p.oid) AS arguments,
       pg_get_function_result(p.oid)    AS result
FROM   pg_proc AS p
WHERE  p.pronamespace = current_schema()::regnamespace
ORDER  BY kind, p.proname;

-- sp_who / sp_who2  →  pg_stat_activity
SELECT pid, usename, application_name, client_addr, state,
       now() - backend_start AS connected_for,
       left(query, 40)       AS last_query
FROM   pg_stat_activity
WHERE  datname = current_database()
ORDER  BY backend_start;

-- KILL  →  pg_cancel_backend (отменить запрос) / pg_terminate_backend (разорвать сессию)
-- Можно применять к сессиям своей роли. Несуществующий pid — FALSE + WARNING.
SELECT pg_cancel_backend(1)    AS cancelled;      -- WARNING: PID 1 is not a PostgreSQL backend process
SELECT pg_terminate_backend(1) AS terminated;

-- sp_lock  →  pg_locks
SELECT locktype, relation::regclass, mode, granted
FROM   pg_locks
WHERE  pid = pg_backend_pid();

-- sp_configure  →  pg_settings / current_setting / set_config
SELECT name, setting, unit, context, short_desc
FROM   pg_settings
WHERE  name IN ('work_mem', 'statement_timeout', 'lock_timeout', 'search_path');

SELECT current_setting('search_path')              AS path,
       set_config('work_mem', '64MB', false)       AS set_for_session,   -- как SET work_mem
       current_setting('work_mem')                 AS work_mem_now;
RESET work_mem;

-- sp_executesql  →  EXECUTE format(...) USING ...  (защита от SQL-инъекций)
DO $$
DECLARE
    v_table text := 'orders';
    v_cnt   bigint;
BEGIN
    EXECUTE format('SELECT COUNT(*) FROM %I.%I WHERE order_date >= $1', 'pitanie', v_table)
    INTO  v_cnt
    USING DATE '2025-01-01';
    RAISE NOTICE 'Заказов в % с 2025 г.: %', v_table, v_cnt;      -- 2334
END;
$$;

-- sp_depends  →  pg_depend / information_schema
SELECT DISTINCT dependent.relname AS view_name, source.relname AS uses_table
FROM   pg_depend  AS d
JOIN   pg_rewrite AS r         ON r.oid = d.objid
JOIN   pg_class   AS dependent ON dependent.oid = r.ev_class
JOIN   pg_class   AS source    ON source.oid = d.refobjid
WHERE  source.relnamespace = 'pitanie'::regnamespace
  AND  dependent.oid <> source.oid
LIMIT  10;                                         -- представления на таблицах pitanie (если есть)

-- =====================================================================
-- 8. ОТЛАДКА ПРОЦЕДУР
-- =====================================================================
-- 8.1 Трассировка уровнями сообщений
CREATE OR REPLACE PROCEDURE sp_demo_debug(p_customer_id integer)
LANGUAGE plpgsql
AS $$
DECLARE
    v_debt numeric;
    v_ctx  text;
BEGIN
    RAISE DEBUG 'старт: customer_id = %', p_customer_id;      -- видно при client_min_messages = debug
    v_debt := fn_customer_debt(p_customer_id);
    RAISE DEBUG 'долг посчитан: %', v_debt;
    GET DIAGNOSTICS v_ctx = PG_CONTEXT;
    RAISE NOTICE 'Долг клиента %: % (контекст: %)', p_customer_id, v_debt, v_ctx;
END;
$$;

CALL sp_demo_debug(1);                    -- только NOTICE
SET client_min_messages = debug;
CALL sp_demo_debug(1);                    -- + DEBUG-сообщения
RESET client_min_messages;

-- 8.2 Предупреждения компилятора PL/pgSQL
SET plpgsql.extra_warnings = 'shadowed_variables';
CREATE OR REPLACE FUNCTION fn_demo_shadow(p_id integer)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    p_id integer := 0;                    -- WARNING: variable "p_id" shadows a previously defined variable
BEGIN
    RETURN p_id;
END;
$$;
RESET plpgsql.extra_warnings;

-- 8.3 Статистика вызовов (track_functions = all на стенде)
SELECT funcname, calls, ROUND(total_time::numeric, 1) AS total_ms, ROUND(self_time::numeric, 1) AS self_ms
FROM   pg_stat_user_functions
WHERE  schemaname = current_schema()
ORDER  BY calls DESC;

-- 8.4 План запроса из тела процедуры отлаживаем отдельно
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF)
SELECT fn_invoice_balance(4070);

-- =====================================================================
-- 9. Уборка демонстрационных объектов
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_hello(text);
DROP PROCEDURE IF EXISTS sp_customer_summary(integer, text, numeric, numeric);
DROP PROCEDURE IF EXISTS sp_demo_add_payment(integer, numeric, integer);
DROP PROCEDURE IF EXISTS sp_open_invoices(integer, refcursor);
DROP PROCEDURE IF EXISTS sp_demo_monthly_revenue(integer);
DROP PROCEDURE IF EXISTS sp_demo_debug(integer);
DROP FUNCTION  IF EXISTS fn_demo_shadow(integer);
DROP FUNCTION  IF EXISTS fn_open_invoices(integer);
DROP FUNCTION  IF EXISTS fn_customer_credit_info(integer);
DROP FUNCTION  IF EXISTS fn_customer_debt(varchar);
DELETE FROM payments WHERE payment_id >= 5001;
-- fn_invoice_balance и fn_customer_debt(integer, date) оставляем — они нужны в лабораторной
