# Модуль 12. Практическая работа «Хранимые процедуры в PostgreSQL»

**Цель:** научиться создавать и вызывать функции и процедуры PostgreSQL с параметрами,
проверками и обработкой ошибок, возвращать результат через `INOUT` и `refcursor`, управлять
правами на выполнение и пользоваться системными функциями и представлениями вместо
«системных хранимых процедур» SQL Server.

**Время:** 35 минут (преподаватель показывает → слушатели повторяют).

**Файл с кодом:** `module_12/examples.sql` (разделы 1–9).

---

## 0. Подготовка (3 мин)

1. Личная схема создана скриптом `module_07/scripts/00_personal_schema.sql` (перед запуском `SET course.stud_schema = 'stud_<фамилия>';`, выполнить файл целиком).
2. Откройте `module_12/scripts/01_setup.sql`, замените `stud_ivanov` на свою схему и выполните
   скрипт целиком (DBeaver: **Alt+X**). Контроль последнего запроса:

| table_name | rows |
|---|---|
| customers | 73 |
| orders | 4458 |
| order_items | 17576 |
| invoices | 4242 |
| payments | 4519 |
| products | 35 |
| production_batches | 6062 |
| material_consumption | 24275 |
| purchase_order_items | 2328 |
| material_stock | 24 |

3. В окне редактора:

```sql
SET search_path TO stud_ivanov, pitanie, public;
SELECT current_schema();          -- ваша личная схема
```

> **DBeaver и `$$`.** Тело функции в долларовых кавычках DBeaver выполняет как один оператор,
> если выделить весь `CREATE … $$;` и нажать **Ctrl+Enter**. При ошибке «unterminated
> dollar-quoted string» — выделите оператор целиком.

---

## Шаг 1. Функция или процедура (5 мин)

Создайте функцию `fn_invoice_balance` и процедуру `sp_hello` (`examples.sql`, раздел 1).

```sql
SELECT invoice_id, invoice_number, amount, fn_invoice_balance(invoice_id) AS balance
FROM   invoices
WHERE  invoice_id IN (2045, 4070);

CALL sp_hello();
CALL sp_hello('команда А');
```

**Ожидаемо:**

| invoice_id | invoice_number | amount | balance |
|---|---|---|---|
| 2045 | СЧ-2025-02045 | 397967.66 | 198983.83 |
| 4070 | СЧ-2025-04070 | 78290.05 | 78290.05 |

`NOTICE: Привет, аналитик! Сейчас …`

Попробуйте «перепутать» вызовы:

```sql
SELECT sp_hello();               -- ERROR: sp_hello() is a procedure   HINT: To call a procedure, use CALL.
CALL fn_invoice_balance(4070);   -- ERROR: fn_invoice_balance(integer) is not a procedure
```

| | FUNCTION | PROCEDURE |
|---|---|---|
| Вызов | `SELECT f(...)`, в любом выражении | `CALL p(...)` |
| Результат | `RETURNS` скаляр / `SETOF` / `TABLE` | только `OUT` / `INOUT` |
| `COMMIT` / `ROLLBACK` внутри | нельзя | можно (если `CALL` вне `BEGIN`) |
| Аналог T-SQL | scalar / table-valued function | `CREATE PROCEDURE` / `EXEC` |

---

## Шаг 2. Параметры: DEFAULT, имена, перегрузка, OUT (6 мин)

Создайте `fn_customer_debt(p_customer_id, p_as_of DEFAULT '2025-12-31')` и вызовите тремя способами:

```sql
SELECT fn_customer_debt(1)                                           AS debt_default,
       fn_customer_debt(1, DATE '2024-12-31')                        AS debt_2024,
       fn_customer_debt(p_as_of => DATE '2025-06-30', p_customer_id => 1) AS debt_mid_2025;
```

**Ожидаемо:** `6907600.45 | 641350.26 | 3348487.78` — долг Вектора вырос в 10 раз за год.

Перегрузка — версия по ИНН:

```sql
SELECT fn_customer_debt('7924695572'::varchar) AS debt_romashka_all_cards;   -- 2908087.86
```

> **Подумайте.** Долг «Ромашки» по трём карточкам — 2,91 млн при лимите 4 млн (73 %).
> Почему контроль лимита по одной карточке этого не увидит? (Дубли клиентов — модуль 2.)

Процедура с `OUT`/`INOUT`: при `CALL` на месте выходных параметров передаётся `NULL`:

```sql
CALL sp_customer_summary(1, NULL, NULL);
```

**Ожидаемо:** одна строка `ООО "Торговый дом Вектор" | 6907600.45 | 230.3`.

**Типичная ошибка:** `CALL sp_customer_summary(1);` → `procedure sp_customer_summary(integer) does not exist`
(у `OUT`-параметров нет значений по умолчанию — их нужно перечислить).

---

## Шаг 3. Процедура модификации данных с проверками (6 мин)

Создайте `sp_demo_add_payment` (раздел 3) и выполните по очереди:

```sql
CALL sp_demo_add_payment(4070, 30000);       -- p_payment_id = 5001
CALL sp_demo_add_payment(4070, 60000);
CALL sp_demo_add_payment(999999, 100);
CALL sp_demo_add_payment(4070, -1);
CALL sp_demo_add_payment(p_amount => 1000, p_invoice_id => 4070);   -- 5002
```

**Ожидаемо:**

```text
ERROR:  Переплата по счёту 4070
DETAIL:  Остаток 48290.05, оплата 60000
CONTEXT: PL/pgSQL function sp_demo_add_payment(integer,numeric,integer) line 19 at RAISE

ERROR:  Счёт 999999 не найден
ERROR:  Сумма оплаты должна быть положительной: -1
HINT:  Проверьте выписку банка
```

> **Подумайте.** Зачем `FOR UPDATE` на строке счёта (вспомните модуль 11, потерянное обновление)?
> Что вернёт `SQLSTATE` в приложение для каждой из ошибок?

---

## Шаг 4. Набор строк из процедуры: refcursor (4 мин)

```sql
BEGIN;
CALL sp_open_invoices(1);           -- p_cur = open_invoices
FETCH 5 FROM open_invoices;
CLOSE open_invoices;
COMMIT;
```

**Ожидаемо:** 5 самых старых неоплаченных счетов Вектора, первый — `СЧ-2025-02031`, срок `2025-01-31`,
остаток 143178.83.

**Типичная ошибка:** выполнить `CALL` и `FETCH` в автокоммите отдельными операторами —
`cursor "open_invoices" does not exist` (курсор закрылся вместе с транзакцией `CALL`).

Сравните с табличной функцией: `SELECT COUNT(*), SUM(balance) FROM fn_open_invoices(1);` → `45 | 6876600.45`.

---

## Шаг 5. COMMIT внутри процедуры (3 мин)

```sql
CALL sp_demo_monthly_revenue(2025);
```

**Ожидаемо:** 12 строк `NOTICE`, например `2025-07: выручка 24709543` и `2025-12: выручка 44674536`.
Каждый месяц зафиксирован отдельно.

> **Подумайте.** Июль 2025 — самый слабый месяц года (24,7 млн против 33–45 млн в другие месяцы).
> Какие данные проверить, чтобы понять причину?

---

## Шаг 6. Безопасность: SECURITY DEFINER и GRANT EXECUTE (4 мин)

Создайте `fn_customer_credit_info` (раздел 6) и посмотрите метаданные:

```sql
SELECT p.proname, p.prosecdef AS security_definer, p.proconfig AS fixed_settings,
       has_function_privilege(p.oid, 'EXECUTE') AS i_can_execute
FROM   pg_proc AS p
WHERE  p.pronamespace = current_schema()::regnamespace
  AND  p.proname LIKE 'fn_customer%';
```

**Ожидаемо:** у `fn_customer_credit_info` — `security_definer = true`,
`fixed_settings = {search_path=stud_<фамилия>, pg_temp}`.

| Приём | Зачем |
|---|---|
| `SECURITY DEFINER` | пользователь получает доступ к данным только через функцию (без `SELECT` на таблицу) |
| `SET search_path = схема, pg_temp` | защита от подмены объектов «одноимённой» таблицей в чужой схеме |
| `REVOKE EXECUTE … FROM PUBLIC` | по умолчанию `EXECUTE` на функции есть у всех |
| `GRANT EXECUTE … TO роль` | выдаём право только нужной роли |

> На учебном стенде у всех слушателей одна учётная запись, поэтому `GRANT` выполняем
> `TO CURRENT_USER`; в боевой системе — `TO sales_role`, `TO finance_role` и т. п.

---

## Шаг 7. «Системные процедуры» T-SQL → PostgreSQL (5 мин)

Выполните запросы раздела 7 и заполните таблицу соответствий (колонка «Результат»):

| T-SQL | PostgreSQL | psql | Результат на стенде |
|---|---|---|---|
| `sp_help 'customers'`, `sp_columns` | `information_schema.columns` | `\d customers` | 11 колонок |
| `sp_helpindex` | `pg_indexes` | `\di` | у `orders` 4 индекса |
| `sp_spaceused` | `pg_size_pretty(pg_total_relation_size(...))` | `\dt+` | самая большая — `material_consumption`, ≈2 МБ |
| `sp_tables`, `sp_stored_procedures` | `information_schema.tables` / `.routines` | `\dt`, `\df` | |
| `sp_helptext` | `pg_get_functiondef(oid)` | `\sf имя` | |
| `sp_who`, `sp_who2` | `pg_stat_activity` | | |
| `KILL spid` | `pg_cancel_backend(pid)` / `pg_terminate_backend(pid)` | | `FALSE` + WARNING для pid 1 |
| `sp_lock` | `pg_locks` | | |
| `sp_configure` | `pg_settings`, `current_setting`, `set_config` | `SHOW`, `SET` | `work_mem` = 4096 kB |
| `sp_executesql` | `EXECUTE format(...) USING ...` | | 2334 заказа с 2025 г. |
| `sp_depends` | `pg_depend`, `information_schema.view_table_usage` | `\d+ view` | |

> ⚠️ `pg_terminate_backend` на учебном стенде может «убить» сессию соседа (одна учётная запись).
> Применяйте только к своему `pg_backend_pid()` из второго окна.

---

## Шаг 8. Отладка (4 мин)

```sql
CALL sp_demo_debug(1);                 -- только NOTICE
SET client_min_messages = debug;
CALL sp_demo_debug(1);                 -- + DEBUG: старт…, DEBUG: долг посчитан…
RESET client_min_messages;

SET plpgsql.extra_warnings = 'shadowed_variables';
-- создайте fn_demo_shadow → WARNING: variable "p_id" shadows a previously defined variable
RESET plpgsql.extra_warnings;

SELECT funcname, calls, ROUND(total_time::numeric, 1) AS total_ms
FROM   pg_stat_user_functions
WHERE  schemaname = current_schema()
ORDER  BY calls DESC;
```

**Ожидаемо:** в `pg_stat_user_functions` `fn_invoice_balance` вызвана тысячи раз (её дергал
`fn_open_invoices` для каждой строки) — повод переписать на соединение с агрегатом.

Приёмы отладки:

1. `RAISE NOTICE / DEBUG` с ключевыми значениями переменных, `client_min_messages`.
2. `GET DIAGNOSTICS v = PG_CONTEXT` — где мы сейчас; `GET STACKED DIAGNOSTICS` в `EXCEPTION`.
3. `pg_get_functiondef` / `\sf` — исходный код из базы; номер строки из `CONTEXT … line N`.
4. SQL из тела процедуры — отдельно, с `EXPLAIN ANALYZE`.
5. `plpgsql.extra_warnings / extra_errors` — предупреждения компилятора.
6. В DBeaver: вкладка **Source** у процедуры, **Output** (Ctrl+Shift+O) — сообщения `RAISE NOTICE`.

---

## Завершение

Выполните раздел 9 `examples.sql` (удаление демонстрационных объектов). Функции
`fn_invoice_balance` и `fn_customer_debt(integer, date)` оставьте — они нужны в лабораторной.

## Типичные ошибки

| Ошибка | Причина | Решение |
|---|---|---|
| `function … does not exist` при вызове | не совпали типы аргументов: `fn_invoice_balance(4070.0)` — `numeric` не приводится к `integer` неявно | явное приведение `::integer`, проверка сигнатуры в `\df` |
| `cannot change return type of existing function` | `CREATE OR REPLACE` с другим `RETURNS` | `DROP FUNCTION …` и создать заново |
| `input parameters after one with a default value must also have defaults` | параметр без `DEFAULT` после параметра с `DEFAULT` | переставить параметры |
| `cursor "…" does not exist` | `FETCH` после завершения транзакции `CALL` | `BEGIN; CALL …; FETCH …; COMMIT;` |
| `invalid transaction termination` | `CALL` процедуры с `COMMIT` внутри `BEGIN` | вызывать в автокоммите |
| `query has no destination for result data` | `SELECT` без `INTO` в PL/pgSQL | `SELECT … INTO v` или `PERFORM` |
