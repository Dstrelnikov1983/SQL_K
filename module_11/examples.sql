-- =====================================================================
-- Курс «Углублённый SQL» · Модуль 11 «Применение транзакций»
-- Практические примеры преподавателя (PostgreSQL 16)
-- =====================================================================
-- Подготовка: выполнить module_11/scripts/01_setup.sql (замените stud_ivanov
-- на свою схему). Примеры меняют только таблицы личной схемы.
-- Блоки, помеченные «ДВЕ СЕССИИ», выполняются в двух окнах DBeaver / двух psql:
-- они оформлены комментариями, реальный вывод получен скриптом
-- module_11/scripts/check_two_sessions.py.
-- Ошибки, которые показываются намеренно, помечены  -- ОЖИДАЕМАЯ ОШИБКА
-- =====================================================================

SET search_path TO stud_ivanov, pitanie, public;

-- =====================================================================
-- 1. АВТОКОММИТ И ЯВНАЯ ТРАНЗАКЦИЯ
-- =====================================================================
-- В режиме auto-commit каждый оператор — отдельная транзакция:
-- у двух SELECT разные номера транзакций.
SELECT txid_current() AS tx;
SELECT txid_current() AS tx;

-- Явная транзакция: все операторы внутри BEGIN ... COMMIT/ROLLBACK
-- выполняются в одной транзакции и видят одно и то же now().
BEGIN;
SELECT txid_current()  AS tx,
       now()           AS tx_start,      -- время начала транзакции (не меняется)
       clock_timestamp() AS wall_clock;  -- «настенные часы» (меняются)
SELECT txid_current()  AS tx_same,
       now()           AS tx_start_same,
       clock_timestamp() AS wall_clock_later;
COMMIT;

-- ROLLBACK отменяет все изменения транзакции
BEGIN;
UPDATE customers
SET    credit_limit = 0
WHERE  customer_id = 1;                  -- «Торговый дом Вектор»

SELECT customer_id, customer_name, credit_limit
FROM   customers
WHERE  customer_id = 1;                  -- внутри транзакции: 0
ROLLBACK;

SELECT customer_id, customer_name, credit_limit
FROM   customers
WHERE  customer_id = 1;                  -- после отката: 3 000 000

-- =====================================================================
-- 2. ТРАНЗАКЦИЯ «ОПЛАТА СЧЁТА»: вставка + проверка остатка
-- =====================================================================
-- Счёт СЧ-2025-04070 (Вектор): сумма 78 290,05, оплат нет.
SELECT i.invoice_id, i.invoice_number, i.amount,
       COALESCE(SUM(p.amount), 0)            AS paid,
       i.amount - COALESCE(SUM(p.amount), 0) AS balance
FROM   invoices AS i
LEFT   JOIN payments AS p ON p.invoice_id = i.invoice_id
WHERE  i.invoice_id = 4070
GROUP  BY i.invoice_id;

-- Шаг 1: оплата 50 000 — остаток неотрицательный → COMMIT
BEGIN;
INSERT INTO payments (invoice_id, payment_date, amount, payment_method)
VALUES (4070, DATE '2025-12-25', 50000, 'Банковский перевод')
RETURNING payment_id, invoice_id, amount;

SELECT i.amount - SUM(p.amount) AS balance_after   -- 28 290,05 ≥ 0
FROM   invoices AS i
JOIN   payments AS p ON p.invoice_id = i.invoice_id
WHERE  i.invoice_id = 4070
GROUP  BY i.amount;
COMMIT;

-- Шаг 2: оплата 40 000 — переплата → ROLLBACK
BEGIN;
INSERT INTO payments (invoice_id, payment_date, amount, payment_method)
VALUES (4070, DATE '2025-12-26', 40000, 'Банковский перевод');

SELECT i.amount - SUM(p.amount) AS balance_after   -- −11 709,95 < 0  → откатываем
FROM   invoices AS i
JOIN   payments AS p ON p.invoice_id = i.invoice_id
WHERE  i.invoice_id = 4070
GROUP  BY i.amount;
ROLLBACK;

-- То же решение «на сервере»: проверка и откат внутри одного блока.
-- Ошибка в DO-блоке откатывает ВСЕ изменения блока (оператор атомарен).
DO $$
DECLARE
    v_balance numeric;
BEGIN
    INSERT INTO payments (invoice_id, payment_date, amount, payment_method)
    VALUES (4070, DATE '2025-12-26', 40000, 'Банковский перевод');

    SELECT i.amount - SUM(p.amount)
    INTO   v_balance
    FROM   invoices AS i
    JOIN   payments AS p ON p.invoice_id = i.invoice_id
    WHERE  i.invoice_id = 4070
    GROUP  BY i.amount;

    IF v_balance < 0 THEN
        RAISE EXCEPTION 'Переплата по счёту 4070: остаток станет %', v_balance
              USING ERRCODE = 'check_violation';
    END IF;
END;
$$;                                       -- ОЖИДАЕМАЯ ОШИБКА: Переплата ... −11709.95

SELECT COUNT(*) AS payments_4070, SUM(amount) AS paid   -- 1 оплата, 50 000
FROM   payments
WHERE  invoice_id = 4070;

-- =====================================================================
-- 3. ПОВЕДЕНИЕ PostgreSQL ПРИ ОШИБКЕ ВНУТРИ ТРАНЗАКЦИИ
-- =====================================================================
-- В T-SQL (XACT_ABORT OFF) после ошибки следующий оператор продолжает
-- выполняться. В PostgreSQL транзакция переходит в состояние «aborted»:
-- всё до конца блока игнорируется, COMMIT превращается в ROLLBACK.
BEGIN;
UPDATE customers SET credit_reserved = 500000 WHERE customer_id = 2;
INSERT INTO payments (invoice_id, payment_date, amount, payment_method)
VALUES (4070, DATE '2025-12-27', -100, 'Банковский перевод');  -- ОЖИДАЕМАЯ ОШИБКА: ck_payments_amount
SELECT 1;                                                      -- ОЖИДАЕМАЯ ОШИБКА: current transaction is aborted
COMMIT;                                                        -- выполнится как ROLLBACK

SELECT credit_reserved FROM customers WHERE customer_id = 2;   -- 0: UPDATE тоже отменён

-- =====================================================================
-- 4. SAVEPOINT: частичный откат
-- =====================================================================
-- Объединяем дубли «Ромашки» (69, 70 → 2). Удаление карточки, у которой
-- ещё есть заказы, падает по внешнему ключу — откатываемся к точке
-- сохранения и продолжаем, не теряя уже сделанное.
SELECT customer_id, customer_name, inn,
       (SELECT COUNT(*) FROM orders AS o WHERE o.customer_id = c.customer_id) AS orders_cnt
FROM   customers AS c
WHERE  inn = '7924695572'
ORDER  BY customer_id;                    -- 2: 93, 69: 65, 70: 72 заказа

BEGIN;
UPDATE orders SET customer_id = 2 WHERE customer_id = 69;      -- 65 строк
SAVEPOINT after_69;

DELETE FROM customers WHERE customer_id = 70;                  -- ОЖИДАЕМАЯ ОШИБКА: fk_orders_customer
ROLLBACK TO SAVEPOINT after_69;                                -- транзакция снова «живая»

UPDATE orders SET customer_id = 2 WHERE customer_id = 70;      -- 72 строки
DELETE FROM customers WHERE customer_id IN (69, 70);           -- теперь можно
RELEASE SAVEPOINT after_69;

SELECT customer_id, COUNT(*) AS orders_cnt
FROM   orders
WHERE  customer_id IN (2, 69, 70)
GROUP  BY customer_id;                                         -- 2: 230
ROLLBACK;                                                      -- демонстрация — откатываем всё

-- =====================================================================
-- 5. EXCEPTION В PL/pgSQL = НЕЯВНЫЙ SAVEPOINT (аналог TRY/CATCH)
-- =====================================================================
-- Пакет из трёх оплат: ошибочная оплата пропускается, остальные проходят.
DO $$
DECLARE
    r       record;
    v_ok    int := 0;
    v_fail  int := 0;
    v_state text;
    v_msg   text;
BEGIN
    FOR r IN
        SELECT *
        FROM  (VALUES (4021, 10000.00), (4070, -5.00), (3965, 20000.00))
              AS t(invoice_id, amount)
    LOOP
        BEGIN                                  -- ← здесь создаётся неявный savepoint
            INSERT INTO payments (invoice_id, payment_date, amount, payment_method)
            VALUES (r.invoice_id, DATE '2025-12-28', r.amount, 'Банковский перевод');
            v_ok := v_ok + 1;
        EXCEPTION
            WHEN check_violation THEN          -- ← откат к нему только этой итерации
                GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE,
                                        v_msg   = MESSAGE_TEXT;
                RAISE NOTICE 'Счёт %: пропущен (%: %)', r.invoice_id, v_state, v_msg;
                v_fail := v_fail + 1;
        END;
    END LOOP;
    RAISE NOTICE 'Проведено: %, отклонено: %', v_ok, v_fail;
END;
$$;

SELECT payment_id, invoice_id, amount, payment_date
FROM   payments
WHERE  payment_id > 5001                   -- новые оплаты этого раздела
ORDER  BY payment_id;                      -- 2 строки: счета 4021 и 3965

-- =====================================================================
-- 6. COMMIT / ROLLBACK ВНУТРИ ПРОЦЕДУРЫ
-- =====================================================================
-- Процедура (не функция!) может завершать транзакции. Пример: снимаем
-- резервы кредитных лимитов порциями, фиксируя каждую порцию.
CREATE OR REPLACE PROCEDURE release_credit_reserves(p_batch int DEFAULT 20)
LANGUAGE plpgsql
AS $$
DECLARE
    v_rows  int;
    v_total int := 0;
BEGIN
    LOOP
        UPDATE customers
        SET    credit_reserved = 0
        WHERE  customer_id IN (SELECT customer_id
                               FROM   customers
                               WHERE  credit_reserved > 0
                               LIMIT  p_batch);
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        EXIT WHEN v_rows = 0;
        v_total := v_total + v_rows;
        COMMIT;                               -- фиксируем порцию, блокировки снимаются
    END LOOP;
    RAISE NOTICE 'Снято резервов: %', v_total;
END;
$$;

UPDATE customers SET credit_reserved = 100000 WHERE customer_id <= 50;  -- 50 строк
CALL release_credit_reserves(20);          -- NOTICE: Снято резервов: 50 (порции 20+20+10)

-- Внутри явной транзакции процедура с COMMIT вызваться не может:
BEGIN;
UPDATE customers SET credit_reserved = 100000 WHERE customer_id <= 5;
CALL release_credit_reserves(20);          -- ОЖИДАЕМАЯ ОШИБКА: invalid transaction termination
ROLLBACK;

-- =====================================================================
-- 7. БЛОКИРОВКИ: что держит МОЯ транзакция
-- =====================================================================
BEGIN;
UPDATE customers SET credit_reserved = 1 WHERE customer_id = 2;  -- строковая блокировка
LOCK TABLE material_stock IN SHARE MODE;                         -- табличная блокировка

SELECT l.locktype,
       l.relation::regclass AS relation,
       l.mode,
       l.granted
FROM   pg_locks AS l
WHERE  l.pid = pg_backend_pid()
ORDER  BY l.locktype, relation::text;
ROLLBACK;

-- Строковые блокировки разной силы (на одной сессии конфликтов нет —
-- конфликт видно только из второй сессии, см. раздел 8).
BEGIN;
SELECT material_id, qty_on_hand FROM material_stock WHERE material_id = 14 FOR UPDATE;
SELECT material_id, qty_on_hand FROM material_stock WHERE material_id = 10 FOR SHARE;
SELECT material_id, qty_on_hand FROM material_stock WHERE material_id = 8  FOR NO KEY UPDATE;
SELECT material_id, qty_on_hand FROM material_stock WHERE material_id = 9  FOR KEY SHARE;
ROLLBACK;

-- Таймауты ожидания задаются на уровне сессии или транзакции
SHOW deadlock_timeout;                    -- 1s (меняет только администратор)
SET lock_timeout = '3s';
SET statement_timeout = '30s';
SHOW lock_timeout;
RESET lock_timeout;
RESET statement_timeout;

-- =====================================================================
-- 8. ДВЕ СЕССИИ: блокировки, взаимоблокировка, мониторинг
-- =====================================================================
/*  8.1  Потерянное обновление (READ COMMITTED) — резерв лимита «Ромашки»
    ─────────────────────────────────────────────────────────────────────
    Сессия 1                                  Сессия 2
    BEGIN;                                    BEGIN;
    SELECT credit_reserved FROM customers     SELECT credit_reserved FROM customers
    WHERE customer_id = 2;      -- 0          WHERE customer_id = 2;      -- 0
    UPDATE customers SET credit_reserved
           = 1500000 WHERE customer_id = 2;
                                              UPDATE customers SET credit_reserved
                                                     = 2000000 WHERE customer_id = 2;
                                              -- ⏳ ждёт Сессию 1
    COMMIT;
                                              -- UPDATE 1
                                              COMMIT;
    Итог: credit_reserved = 2 000 000, резерв 1,5 млн потерян.

    8.2  Исправление: SELECT ... FOR UPDATE — Сессия 2 ждёт и затем видит 1 500 000;
         после её UPDATE credit_reserved = credit_reserved + 2000000 итог 3 500 000.

    8.3  Deadlock — встречные обновления клиентов 2 и 8
    Сессия 1                                  Сессия 2
    BEGIN;                                    BEGIN;
    UPDATE customers SET credit_reserved
      = credit_reserved + 100000
      WHERE customer_id = 2;
                                              UPDATE customers SET credit_reserved
                                                = credit_reserved + 50000
                                                WHERE customer_id = 8;
    UPDATE ... WHERE customer_id = 8;
    -- ⏳ ждёт Сессию 2
                                              UPDATE ... WHERE customer_id = 2;
                                              -- через deadlock_timeout = 1 s:
    ERROR:  deadlock detected   (SQLSTATE 40P01)
    DETAIL: Process 2335017 waits for ShareLock on transaction 6639748; blocked by process 2333390.
            Process 2333390 waits for ShareLock on transaction 6639756; blocked by process 2335017.
    HINT:   See server log for query details.
    CONTEXT: while updating tuple (1,30) in relation "customers"
    Жертвой выбирается сессия, обнаружившая цикл (здесь — Сессия 2); её транзакция
    отменена, Сессия 1 продолжает работу и фиксирует изменения.

    8.4  NOWAIT / lock_timeout (Сессия 1 держит FOR UPDATE на material_id = 14)
    Сессия 2: SELECT ... FOR UPDATE NOWAIT;
              ERROR: could not obtain lock on row in relation "material_stock"  (55P03)
    Сессия 2: SET lock_timeout = '2s'; UPDATE material_stock ...;
              ERROR: canceling statement due to lock timeout                    (55P03)
*/

-- Мониторинг из третьего окна: кто кого блокирует
SELECT a.pid,
       pg_blocking_pids(a.pid)            AS blocked_by,
       a.state,
       a.wait_event_type,
       a.wait_event,
       now() - a.xact_start               AS xact_age,
       left(a.query, 60)                  AS query
FROM   pg_stat_activity AS a
WHERE  a.datname = current_database()
  AND  a.state <> 'idle'
ORDER  BY a.xact_start;

-- Детально: какие блокировки ожидаются и кем удерживаются
SELECT w.pid                       AS waiting_pid,
       w.locktype,
       w.relation::regclass        AS relation,
       w.mode                      AS wanted_mode,
       h.pid                       AS holding_pid,
       h.mode                      AS held_mode
FROM   pg_locks AS w
JOIN   pg_locks AS h
       ON  h.granted
       AND NOT w.granted
       AND h.pid <> w.pid
       AND h.locktype = w.locktype
       AND h.database      IS NOT DISTINCT FROM w.database
       AND h.relation      IS NOT DISTINCT FROM w.relation
       AND h.transactionid IS NOT DISTINCT FROM w.transactionid
       AND h.tuple         IS NOT DISTINCT FROM w.tuple;

-- Сессии, «зависшие» в открытой транзакции (частая причина блокировок)
SELECT pid, usename, application_name,
       now() - xact_start AS xact_age,
       left(query, 60)    AS last_query
FROM   pg_stat_activity
WHERE  state = 'idle in transaction'
ORDER  BY xact_start;

-- Предотвращение deadlock: единый порядок захвата строк
BEGIN;
SELECT customer_id
FROM   customers
WHERE  customer_id IN (8, 2)
ORDER  BY customer_id                  -- всегда по возрастанию ключа
FOR UPDATE;
UPDATE customers SET credit_reserved = credit_reserved + 100000 WHERE customer_id = 2;
UPDATE customers SET credit_reserved = credit_reserved + 100000 WHERE customer_id = 8;
ROLLBACK;

-- Очередь заявок: каждый «кладовщик» забирает свои строки, не дожидаясь чужих
BEGIN;
SELECT request_id, line_id, material_id, qty
FROM   material_requests
WHERE  status = 'Новая'
ORDER  BY request_id
LIMIT  3
FOR UPDATE SKIP LOCKED;                -- Сессия 1: 1, 2, 3; Сессия 2 в это время: 4, 5, 6
ROLLBACK;

-- =====================================================================
-- 9. УРОВНИ ИЗОЛЯЦИИ
-- =====================================================================
SHOW default_transaction_isolation;    -- read committed
SHOW transaction_isolation;

BEGIN ISOLATION LEVEL REPEATABLE READ;
SHOW transaction_isolation;            -- repeatable read
COMMIT;

BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;   -- до первого запроса транзакции
SHOW transaction_isolation;            -- serializable
COMMIT;

-- READ UNCOMMITTED синтаксически допустим, но работает как READ COMMITTED:
-- грязного чтения в PostgreSQL не бывает.
BEGIN ISOLATION LEVEL READ UNCOMMITTED;
SHOW transaction_isolation;            -- read uncommitted (поведение = read committed)
COMMIT;

-- Транзакция «только чтение» — защита отчётов от случайных изменений
BEGIN READ ONLY;
UPDATE customers SET credit_limit = 0 WHERE customer_id = 1;  -- ОЖИДАЕМАЯ ОШИБКА: read-only transaction
ROLLBACK;

-- Долгий согласованный отчёт без риска 40001
BEGIN ISOLATION LEVEL SERIALIZABLE READ ONLY DEFERRABLE;
SELECT COUNT(*) AS invoices, SUM(amount) AS total FROM invoices;
COMMIT;

/*  9.1  Неповторяемое чтение (две сессии)
    Сессия 1: BEGIN ISOLATION LEVEL READ COMMITTED;
              SELECT credit_limit FROM customers WHERE customer_id = 1;  -- 3000000
    Сессия 2: UPDATE customers SET credit_limit = 1000000 WHERE customer_id = 1;  (автокоммит)
    Сессия 1: SELECT ... ;  -- 1000000   ← значение изменилось внутри транзакции
    С REPEATABLE READ второй SELECT Сессии 1 вернёт 3000000 (снимок на начало).

    9.2  REPEATABLE READ: конкурентное обновление
    Обе сессии: BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT qty_on_hand ... (3407.231)
    Сессия 1:   UPDATE material_stock SET qty_on_hand = qty_on_hand - 2000 WHERE material_id = 14;
    Сессия 2:   то же → ⏳ ждёт
    Сессия 1:   COMMIT;
    Сессия 2:   ERROR: could not serialize access due to concurrent update  (40001)
    (если Сессия 1 делает ROLLBACK — UPDATE Сессии 2 проходит)

    9.3  Write skew: две смены снимают по бригаде с ночной смены Линии 3
    Обе: BEGIN ISOLATION LEVEL SERIALIZABLE;
         SELECT COUNT(*) FROM line_crews WHERE line_id = 3 AND shift = 'Ночь' AND on_duty;  -- 2
    Сессия 1: UPDATE ... crew_name = 'Бригада 3-А';   Сессия 2: UPDATE ... 'Бригада 3-Б';
    Сессия 1: COMMIT;  -- успех
    Сессия 2: COMMIT;
    ERROR:  could not serialize access due to read/write dependencies among transactions (40001)
    DETAIL: Reason code: Canceled on identification as a pivot, during commit attempt.
    HINT:   The transaction might succeed if retried.
    При REPEATABLE READ обе фиксируются, бригад на смене — 0.
*/

-- =====================================================================
-- 10. MVCC: версии строк
-- =====================================================================
-- xmin — транзакция, создавшая версию строки; ctid — её физический адрес.
SELECT xmin, xmax, ctid, material_id, qty_on_hand
FROM   material_stock
WHERE  material_id = 14;

UPDATE material_stock SET updated_at = now() WHERE material_id = 14;

SELECT xmin, xmax, ctid, material_id, qty_on_hand   -- новый xmin и новый ctid:
FROM   material_stock                               -- UPDATE = новая версия строки
WHERE  material_id = 14;

-- Сколько «мёртвых» версий накопилось (их убирает VACUUM)
SELECT relname, n_live_tup, n_dead_tup, last_autovacuum
FROM   pg_stat_user_tables
WHERE  schemaname = current_schema()
ORDER  BY n_dead_tup DESC
LIMIT  5;

-- =====================================================================
-- 11. Возврат данных в исходное состояние
-- =====================================================================
DELETE FROM payments WHERE payment_id >= 5001;
UPDATE customers SET credit_reserved = 0 WHERE credit_reserved <> 0;
DROP PROCEDURE IF EXISTS release_credit_reserves(int);
