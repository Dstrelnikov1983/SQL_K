-- =====================================================================
-- Курс «Углублённый SQL». Модуль 7 (используется также в модулях 9–12)
-- Скрипт 01: СБРОС данных личной схемы к исходному состоянию pitanie
-- =====================================================================
-- Когда нужен: после экспериментов с INSERT/UPDATE/DELETE/MERGE,
-- перед лабораторной работой, перед модулями 9–12.
--
-- Что делает
--   * TRUNCATE всех 23 базовых таблиц личной схемы (одной командой);
--   * повторно копирует строки из pitanie (по общим столбцам —
--     столбцы, которые вы ДОБАВИЛИ в таблицы, получат DEFAULT/NULL);
--   * перезапускает IDENTITY-счётчики с MAX(id) + 1;
--   * НЕ удаляет ваши собственные таблицы, представления, функции.
--     ВНИМАНИЕ: TRUNCATE ... CASCADE очистит и ВАШИ таблицы, которые
--     ссылаются внешним ключом на базовые таблицы (например, стоп-лист
--     со ссылкой на customers). Скрипт выведет их имена в NOTICE.
--
-- Схема определяется так: параметр сеанса course.stud_schema
-- (его ставит 00_personal_schema.sql), иначе — первая схема search_path.
-- Перед запуском убедитесь:  SHOW search_path;
-- =====================================================================

DO $reset$
DECLARE
    v_schema text := coalesce(nullif(current_setting('course.stud_schema', true), ''),
                              current_schema());
    v_tables text[] := ARRAY[
        'regions', 'employees', 'product_categories', 'products',
        'price_history', 'customers', 'orders', 'order_items', 'invoices',
        'payments', 'returns', 'sales_plan', 'expenses',
        'suppliers', 'raw_materials', 'recipes', 'production_lines',
        'production_batches', 'material_consumption', 'equipment_downtime',
        'purchase_orders', 'purchase_order_items', 'material_writeoffs'];
    v_t     text;
    v_cols  text;
    v_list  text;
    v_dep   record;
    v_pk    record;
    v_max   bigint;
BEGIN
    IF v_schema IS NULL OR v_schema IN ('pitanie', 'public') OR v_schema LIKE 'pg\_%' THEN
        RAISE EXCEPTION 'Сброс схемы "%" запрещён', v_schema
            USING HINT = 'Выполните SET search_path TO stud_<фамилия>, pitanie, public;';
    END IF;
    IF (SELECT count(*) FROM information_schema.tables
         WHERE table_schema = v_schema AND table_name = ANY (v_tables)) <> array_length(v_tables, 1) THEN
        RAISE EXCEPTION 'В схеме % нет полного набора таблиц курса', v_schema
            USING HINT = 'Сначала выполните 00_personal_schema.sql';
    END IF;

    -- какие ЧУЖИЕ для курса таблицы будут очищены каскадом
    FOR v_dep IN
        SELECT DISTINCT src.relname
        FROM   pg_constraint c
        JOIN   pg_class src ON src.oid = c.conrelid
        JOIN   pg_class dst ON dst.oid = c.confrelid
        WHERE  c.contype = 'f'
          AND  src.relnamespace = v_schema::regnamespace
          AND  dst.relnamespace = v_schema::regnamespace
          AND  dst.relname = ANY (v_tables)
          AND  NOT (src.relname = ANY (v_tables))
    LOOP
        RAISE NOTICE 'Таблица %.% ссылается на базовые таблицы и будет очищена (CASCADE)', v_schema, v_dep.relname;
    END LOOP;

    SELECT string_agg(format('%I.%I', v_schema, t), ', ') INTO v_list FROM unnest(v_tables) AS t;
    EXECUTE 'TRUNCATE ' || v_list || ' CASCADE';

    FOREACH v_t IN ARRAY v_tables LOOP
        -- общие столбцы личной таблицы и pitanie (в порядке pitanie)
        SELECT string_agg(quote_ident(p.column_name), ', ' ORDER BY p.ordinal_position)
        INTO   v_cols
        FROM   information_schema.columns p
        JOIN   information_schema.columns s
               ON s.table_schema = v_schema AND s.table_name = p.table_name AND s.column_name = p.column_name
        WHERE  p.table_schema = 'pitanie' AND p.table_name = v_t;

        -- OVERRIDING SYSTEM VALUE — на случай GENERATED ALWAYS AS IDENTITY
        EXECUTE format('INSERT INTO %I.%I (%s) OVERRIDING SYSTEM VALUE SELECT %s FROM pitanie.%I',
                       v_schema, v_t, v_cols, v_cols, v_t);
    END LOOP;

    -- identity-счётчики -> MAX + 1
    FOR v_pk IN
        SELECT c.relname AS tbl, a.attname AS col
        FROM   pg_attribute a
        JOIN   pg_class c ON c.oid = a.attrelid
        WHERE  c.relnamespace = v_schema::regnamespace
          AND  c.relname = ANY (v_tables)
          AND  a.attidentity IN ('a', 'd')
    LOOP
        EXECUTE format('SELECT coalesce(max(%I), 0) + 1 FROM %I.%I', v_pk.col, v_schema, v_pk.tbl) INTO v_max;
        EXECUTE format('ALTER TABLE %I.%I ALTER COLUMN %I RESTART WITH %s', v_schema, v_pk.tbl, v_pk.col, v_max);
    END LOOP;

    RAISE NOTICE 'Данные схемы % восстановлены из pitanie', v_schema;
END
$reset$;

-- Контроль: число строк в нескольких ключевых таблицах
SELECT (SELECT count(*) FROM customers)            AS customers,      -- 73
       (SELECT count(*) FROM orders)               AS orders,         -- 4458
       (SELECT count(*) FROM products)             AS products,       -- 35
       (SELECT count(*) FROM price_history)        AS price_history,  -- 70
       (SELECT count(*) FROM purchase_order_items) AS po_items,       -- 2328
       (SELECT count(*) FROM equipment_downtime)   AS downtime;       -- 282
