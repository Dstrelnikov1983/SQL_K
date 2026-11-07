# Модуль 11. Практическая работа «Транзакции и блокировки в двух сессиях»

**Цель:** на данных «Питание +» увидеть, как PostgreSQL фиксирует и откатывает изменения,
что происходит при ошибке внутри транзакции, как две параллельные сессии блокируют
друг друга, как возникает и обнаруживается взаимоблокировка и чем отличаются уровни изоляции.

**Время:** 40 минут (преподаватель показывает шаг на проекторе → слушатели повторяют).

**Формат:** индивидуально, у каждого **два окна** SQL-редактора (две независимые сессии)
и, для шагов 7–9, третье окно-«монитор».

---

## 0. Подготовка (5 мин)

### 0.1. Личная схема и таблицы модуля

1. Если личная схема ещё не создана — выполните `module_07/scripts/00_personal_schema.sql` (перед запуском `SET course.stud_schema = 'stud_<фамилия>';`, выполнить файл целиком).
2. Откройте `module_11/scripts/01_setup.sql`, замените `stud_ivanov` на свою схему
   (`Ctrl+F → Replace All`) и выполните скрипт целиком (DBeaver: **Alt+X**).
3. Последний запрос скрипта должен вернуть:

| table_name | rows |
|---|---|
| customers | 73 |
| orders | 4458 |
| invoices | 4242 |
| payments | 4519 |
| purchase_orders | 955 |
| purchase_order_items | 2328 |
| material_stock | 24 |
| material_requests | 12 |
| line_crews | 5 |

> Скрипт перезапускаемый: если в ходе экспериментов данные «поплыли», просто запустите его ещё раз.

### 0.2. Две независимые сессии

**DBeaver.** `Window → Preferences → Editors → SQL Editor → Connections`:
включите **Open separate connection for each editor**. Откройте два редактора
(`Ctrl+]` дважды) на подключении к `db1`. Расположите их рядом (перетащите вкладку вправо).

**psql.** Откройте два терминала и в каждом подключитесь:

```bash
psql "host=<адрес_сервера> port=6432 dbname=db1 user=<логин> sslmode=verify-full sslrootcert=root.crt"
```

В **каждом** окне выполните (замените фамилию):

```sql
SET search_path TO stud_ivanov, pitanie, public;
SELECT pg_backend_pid() AS my_pid, current_schema() AS schema;
```

**Ожидаемо:** номера `my_pid` в двух окнах **разные**, `schema` = ваша личная схема.
Если `pid` совпадает — окна делят одно соединение, сценарии ниже не получатся.

> ⚠️ Забытый `SET search_path` во второй сессии — самая частая ошибка: запросы пойдут
> в общую схему `pitanie`. Проверяйте `current_schema()`.

### 0.3. Режим фиксации

| Клиент | Автокоммит (по умолчанию) | Ручной режим |
|---|---|---|
| DBeaver | кнопка **Auto-Commit** на панели инструментов | переключить на **Manual Commit**: DBeaver сам открывает транзакцию, кнопки **Commit / Rollback** |
| psql | `\set AUTOCOMMIT on` | `\set AUTOCOMMIT off` — psql сам посылает `BEGIN` перед первым оператором |

В практике работаем в **Auto-Commit** и пишем `BEGIN` / `COMMIT` / `ROLLBACK` явно — так
видно границы транзакции.

---

## Шаг 1. Автокоммит против явной транзакции (3 мин)

**Окно 1:**

```sql
SELECT txid_current() AS tx;
SELECT txid_current() AS tx;
```

**Ожидаемо:** два разных номера (например `6641491` и `6641497`) — каждый оператор в
автокоммите является отдельной транзакцией.

```sql
BEGIN;
SELECT txid_current() AS tx, now() AS tx_start, clock_timestamp() AS wall_clock;
SELECT txid_current() AS tx, now() AS tx_start, clock_timestamp() AS wall_clock;
COMMIT;
```

**Ожидаемо:** номер транзакции и `now()` в обеих строках **одинаковые**, `clock_timestamp()` — разный.

> **Подумайте.** Какое время попадёт в поле `updated_at DEFAULT now()` для всех строк,
> вставленных одной долгой транзакцией?

---

## Шаг 2. Транзакция «оплата счёта»: COMMIT и ROLLBACK (5 мин)

Счёт `СЧ-2025-04070` клиента «Торговый дом Вектор»: 78 290,05 руб., оплат нет.

```sql
BEGIN;
INSERT INTO payments (invoice_id, payment_date, amount, payment_method)
VALUES (4070, DATE '2025-12-25', 50000, 'Банковский перевод')
RETURNING payment_id;

SELECT i.amount - SUM(p.amount) AS balance
FROM   invoices AS i
JOIN   payments AS p ON p.invoice_id = i.invoice_id
WHERE  i.invoice_id = 4070
GROUP  BY i.amount;
```

**Ожидаемо:** `payment_id = 5001`, `balance = 28290.05`.

**Окно 2 (пока окно 1 не зафиксировало):**

```sql
SELECT COUNT(*) FROM payments WHERE invoice_id = 4070;
```

**Ожидаемо:** `0` — незафиксированные изменения другой сессии не видны (грязного чтения нет).

**Окно 1:** `COMMIT;` → в окне 2 повторите запрос: теперь `1`.

Повторите в окне 1 оплату на **40 000**: `balance` станет `-11709.95` → выполните `ROLLBACK;`
и убедитесь, что оплата не сохранилась (по-прежнему одна запись на 50 000).

---

## Шаг 3. Ошибка внутри транзакции (4 мин)

```sql
BEGIN;
UPDATE customers SET credit_reserved = 500000 WHERE customer_id = 2;
INSERT INTO payments (invoice_id, payment_date, amount, payment_method)
VALUES (4070, DATE '2025-12-27', -100, 'Банковский перевод');
SELECT 1;
COMMIT;
SELECT credit_reserved FROM customers WHERE customer_id = 2;
```

**Ожидаемо:**

```text
ERROR: new row for relation "payments" violates check constraint "ck_payments_amount"
ERROR: current transaction is aborted, commands ignored until end of transaction block
COMMIT  →  сервер отвечает ROLLBACK
credit_reserved = 0.00      -- UPDATE тоже отменён
```

> **Подумайте.** В SQL Server при `XACT_ABORT OFF` после такой ошибки `UPDATE` остался бы
> в транзакции и `COMMIT` его зафиксировал бы. Какое поведение безопаснее для учёта оплат?

> **psql:** `\set ON_ERROR_ROLLBACK interactive` — psql сам ставит savepoint перед каждым
> оператором, и ошибка не «ломает» всю транзакцию (удобно при ручной работе, опасно в скриптах).

---

## Шаг 4. SAVEPOINT: объединяем дубли «Ромашки» (5 мин)

```sql
BEGIN;
UPDATE orders SET customer_id = 2 WHERE customer_id = 69;      -- UPDATE 65
SAVEPOINT after_69;

DELETE FROM customers WHERE customer_id = 70;                  -- ошибка FK
ROLLBACK TO SAVEPOINT after_69;

UPDATE orders SET customer_id = 2 WHERE customer_id = 70;      -- UPDATE 72
DELETE FROM customers WHERE customer_id IN (69, 70);           -- DELETE 2
SELECT COUNT(*) FROM orders WHERE customer_id = 2;             -- 230
ROLLBACK;                                                      -- в практике откатываем
```

**Ожидаемо:** ошибка `violates foreign key constraint "fk_orders_customer"` не прервала
транзакцию целиком — откат только до `after_69`, первые 65 перенесённых заказов сохранились
до финального `ROLLBACK`.

**Типичная ошибка:** после ошибки выполнить следующий `UPDATE`, не сделав
`ROLLBACK TO SAVEPOINT` — получите `current transaction is aborted`.

---

## Шаг 5. EXCEPTION-блок = неявный savepoint (4 мин)

Выполните блок из `examples.sql`, раздел 5 (пакет из трёх оплат, одна с отрицательной суммой).

**Ожидаемо:**

```text
NOTICE:  Счёт 4070: пропущен (23514: new row for relation "payments" violates check constraint "ck_payments_amount")
NOTICE:  Проведено: 2, отклонено: 1
```

Проверка — две новые оплаты (счета 4021 и 3965):

```sql
SELECT payment_id, invoice_id, amount FROM payments WHERE payment_id > 5001 ORDER BY payment_id;
```

> **Подумайте.** Каждый вход в `BEGIN … EXCEPTION` создаёт подтранзакцию. Почему не стоит
> оборачивать в такой блок каждую строку цикла на миллион строк?

---

## Шаг 6. COMMIT внутри процедуры (3 мин)

Создайте процедуру `release_credit_reserves` из `examples.sql` (раздел 6) и выполните:

```sql
UPDATE customers SET credit_reserved = 100000 WHERE customer_id <= 50;   -- UPDATE 50
CALL release_credit_reserves(20);       -- NOTICE: Снято резервов: 50
```

Затем внутри явной транзакции:

```sql
BEGIN;
UPDATE customers SET credit_reserved = 100000 WHERE customer_id <= 5;
CALL release_credit_reserves(20);       -- ERROR: invalid transaction termination
ROLLBACK;
```

**Вывод:** `COMMIT` в процедуре разрешён, только если `CALL` выполнен вне явного блока
транзакции (в автокоммите).

---

## Шаг 7. Блокировка и монитор (5 мин) — ДВЕ СЕССИИ + ОКНО 3

| Шаг | Окно 1 | Окно 2 | Окно 3 (монитор) |
|---|---|---|---|
| 7.1 | `BEGIN;`<br>`UPDATE customers SET credit_reserved = 1 WHERE customer_id = 1;` | | |
| 7.2 | | `UPDATE customers SET credit_limit = 2500000 WHERE customer_id = 1;`<br>**⏳ зависает** | |
| 7.3 | | | запрос ниже |
| 7.4 | `ROLLBACK;` | `UPDATE 1` — мгновенно продолжилось | |

```sql
-- окно 3
SELECT pid,
       pg_blocking_pids(pid) AS blocked_by,
       state,
       wait_event_type,
       left(query, 50)       AS query
FROM   pg_stat_activity
WHERE  datname = current_database()
  AND  usename = current_user
  AND  pid <> pg_backend_pid()
  AND  state <> 'idle';
```

**Ожидаемо (7.3):** строка окна 2 — `state = active`, `wait_event_type = Lock`,
`blocked_by = {pid окна 1}`; строка окна 1 — `idle in transaction`.

Верните лимит: `UPDATE customers SET credit_limit = 3000000 WHERE customer_id = 1;`

Повторите 7.1–7.2, но в окне 2 перед `UPDATE` выполните `SET lock_timeout = '2s';`.
**Ожидаемо:** через 2 с `ERROR: canceling statement due to lock timeout`.
Не забудьте `ROLLBACK;` в окне 1 и `RESET lock_timeout;` в окне 2.

---

## Шаг 8. Потерянное обновление и FOR UPDATE (5 мин) — ДВЕ СЕССИИ

Два менеджера резервируют кредитный лимит «Ромашки» (лимит 4 000 000).

| Шаг | Окно 1 (резерв 1,5 млн) | Окно 2 (резерв 2 млн) |
|---|---|---|
| 1 | `BEGIN;` | `BEGIN;` |
| 2 | `SELECT credit_reserved FROM customers WHERE customer_id = 2;` → `0.00` | |
| 3 | | то же → `0.00` |
| 4 | `UPDATE customers SET credit_reserved = 1500000 WHERE customer_id = 2;` | |
| 5 | | `UPDATE customers SET credit_reserved = 2000000 WHERE customer_id = 2;` ⏳ |
| 6 | `COMMIT;` | `UPDATE 1` → `COMMIT;` |
| 7 | `SELECT credit_reserved …` → **2000000.00** | |

Резерв первого менеджера **потерян**. Сбросьте: `UPDATE customers SET credit_reserved = 0 WHERE customer_id = 2;`

Повторите, добавив в шаги 2–3 `FOR UPDATE`, а в шаги 4–5 — `credit_reserved = credit_reserved + …`.
**Ожидаемо:** окно 2 ждёт уже на `SELECT … FOR UPDATE`, после `COMMIT` окна 1 видит
`1500000.00`; итог — **3500000.00**.

> **Подумайте.** Можно ли обойтись без `FOR UPDATE`? (Да — одним оператором
> `UPDATE … SET x = x + 1500000 WHERE credit_limit - credit_reserved >= 1500000`.)

---

## Шаг 9. Взаимоблокировка (4 мин) — ДВЕ СЕССИИ

| Шаг | Окно 1 | Окно 2 |
|---|---|---|
| 1 | `BEGIN;` | `BEGIN;` |
| 2 | `UPDATE customers SET credit_reserved = credit_reserved + 100000 WHERE customer_id = 2;` | |
| 3 | | `UPDATE customers SET credit_reserved = credit_reserved + 50000 WHERE customer_id = 8;` |
| 4 | `UPDATE … WHERE customer_id = 8;` ⏳ | |
| 5 | | `UPDATE … WHERE customer_id = 2;` — через ≈1 с ошибка |
| 6 | `UPDATE 1` → `COMMIT;` | `ROLLBACK;` |

**Ожидаемый текст ошибки (реальный вывод учебного сервера):**

```text
ERROR:  deadlock detected
DETAIL:  Process 2335017 waits for ShareLock on transaction 6639748; blocked by process 2333390.
         Process 2333390 waits for ShareLock on transaction 6639756; blocked by process 2335017.
HINT:  See server log for query details.
CONTEXT:  while updating tuple (1,30) in relation "customers"
SQLSTATE: 40P01
```

`SHOW deadlock_timeout;` → `1s`: столько сервер ждёт, прежде чем искать цикл ожиданий.
Изменить параметр может только администратор кластера.

> **Подумайте.** Как переписать оба сценария, чтобы deadlock был невозможен?
> (Захватывать строки в одном порядке: `SELECT … WHERE customer_id IN (2, 8) ORDER BY customer_id FOR UPDATE`.)

---

## Шаг 10. Уровни изоляции (5 мин) — ДВЕ СЕССИИ

### 10.1. Неповторяемое чтение

| Шаг | Окно 1 | Окно 2 |
|---|---|---|
| 1 | `BEGIN ISOLATION LEVEL READ COMMITTED;`<br>`SELECT credit_limit FROM customers WHERE customer_id = 1;` → `3000000.00` | |
| 2 | | `UPDATE customers SET credit_limit = 1000000 WHERE customer_id = 1;` |
| 3 | тот же `SELECT` → **`1000000.00`** | |
| 4 | `COMMIT;` | `UPDATE customers SET credit_limit = 3000000 WHERE customer_id = 1;` |

Повторите с `REPEATABLE READ`: в шаге 3 — **`3000000.00`** (снимок на момент первого запроса).

### 10.2. Write skew на SERIALIZABLE

Правило: на Линии 3 в ночную смену должна остаться хотя бы одна бригада.

| Шаг | Окно 1 | Окно 2 |
|---|---|---|
| 1 | `BEGIN ISOLATION LEVEL SERIALIZABLE;` | `BEGIN ISOLATION LEVEL SERIALIZABLE;` |
| 2 | `SELECT COUNT(*) FROM line_crews WHERE line_id = 3 AND shift = 'Ночь' AND on_duty;` → `2` | то же → `2` |
| 3 | `UPDATE line_crews SET on_duty = FALSE WHERE line_id = 3 AND crew_name = 'Бригада 3-А';` | `UPDATE line_crews SET on_duty = FALSE WHERE line_id = 3 AND crew_name = 'Бригада 3-Б';` |
| 4 | `COMMIT;` — успех | `COMMIT;` — ошибка |

```text
ERROR:  could not serialize access due to read/write dependencies among transactions
DETAIL:  Reason code: Canceled on identification as a pivot, during commit attempt.
HINT:  The transaction might succeed if retried.
SQLSTATE: 40001
```

Повторите с `REPEATABLE READ` — обе транзакции зафиксируются, бригад на смене останется **0**.
Верните: `UPDATE line_crews SET on_duty = TRUE;`

---

## Завершение

Перезапустите `01_setup.sql`, чтобы вернуть данные в исходное состояние.

## Типичные ошибки

| Симптом | Причина | Что делать |
|---|---|---|
| Окно 2 «висит» бесконечно | В окне 1 открыта транзакция (`idle in transaction`) | `COMMIT`/`ROLLBACK` в окне 1; в DBeaver проверьте режим Manual Commit |
| `current transaction is aborted` | После ошибки не выполнен `ROLLBACK` / `ROLLBACK TO SAVEPOINT` | Завершить транзакцию |
| Блокировки не воспроизводятся | Оба редактора на одном соединении (одинаковый `pg_backend_pid()`) | Включить separate connection |
| Данные «не те» | Во втором окне не выполнен `SET search_path` | Проверить `current_schema()` |
| `invalid transaction termination` | `CALL` процедуры с `COMMIT` внутри `BEGIN … ` | Вызывать в автокоммите |
