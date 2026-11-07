# -*- coding: utf-8 -*-
"""
Модуль 11. Проверка (и демонстрация) сценариев «двух сессий» на учебной БД.

Две независимые сессии = два соединения psycopg2; блокирующие операторы
выполняются в отдельных потоках. Скрипт печатает, кто кого ждёт, и реальные
тексты ошибок PostgreSQL (deadlock 40P01, serialization failure 40001, NOWAIT 55P03,
lock_timeout 55P03, statement_timeout 57014, aborted transaction 25P02).

Запуск (таблицы модуля должны быть созданы скриптом 01_setup.sql в той же схеме):
    python check_two_sessions.py --schema stud_ivanov

После прогона данные возвращаются в исходное состояние (все сценарии завершаются
ROLLBACK или компенсирующим действием), но надёжнее перезапустить 01_setup.sql.
"""
import argparse
import os
import sys
import threading
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "common", "scripts"))
from run_sql import CONN  # noqa: E402
import psycopg2  # noqa: E402
import psycopg2.extensions as ext  # noqa: E402

WAIT = 1.5  # сек — сколько ждём, чтобы убедиться, что оператор заблокирован


class Session:
    def __init__(self, name, schema):
        self.name = name
        self.conn = psycopg2.connect(**CONN, application_name=f"m11_{name}")
        self.conn.autocommit = True          # BEGIN/COMMIT пишем явно, как в DBeaver Auto-commit
        self.cur = self.conn.cursor()
        self.cur.execute(f"SET search_path TO {schema}, pitanie, public")
        self.cur.execute("SELECT pg_backend_pid()")
        self.pid = self.cur.fetchone()[0]

    def run(self, sql, show=True):
        """Выполнить оператор; вернуть строки или исключение."""
        try:
            self.cur.execute(sql)
            rows = self.cur.fetchall() if self.cur.description else None
            if show:
                print(f"  [{self.name}] {sql.strip()[:90]}")
                print(f"        -> {rows if rows is not None else self.cur.statusmessage}")
            return rows
        except psycopg2.Error as e:
            msg = str(e).strip().splitlines()
            print(f"  [{self.name}] {sql.strip()[:90]}")
            print(f"        !! SQLSTATE {e.pgcode}: {' | '.join(msg)}")
            return e

    def run_async(self, sql):
        """Запустить оператор в потоке; вернуть поток (жив — значит ждёт блокировку)."""
        box = {}
        t = threading.Thread(target=lambda: box.setdefault("r", self.run(sql)))
        t.box = box
        t.start()
        time.sleep(WAIT)
        if t.is_alive():
            print(f"  [{self.name}] ... ОЖИДАЕТ блокировку")
        return t

    def close(self):
        try:
            self.conn.rollback()
        finally:
            self.conn.close()


def header(title):
    print("\n" + "=" * 78 + f"\n{title}\n" + "=" * 78)


def blocking_info(s):
    s.run("""SELECT pid, pg_blocking_pids(pid) AS blocked_by, wait_event_type,
                    left(query, 50) AS query
             FROM   pg_stat_activity
             WHERE  application_name LIKE 'm11_%' AND state = 'active'
               AND  cardinality(pg_blocking_pids(pid)) > 0""")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--schema", default="stud_ivanov")
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    s1, s2, mon = Session("S1", a.schema), Session("S2", a.schema), Session("MON", a.schema)
    print(f"pid S1={s1.pid}, S2={s2.pid}, монитор={mon.pid}")
    mon.run("SHOW lc_messages")
    mon.run("SHOW deadlock_timeout")

    # ------------------------------------------------------------------
    header("1. Ошибка внутри транзакции: current transaction is aborted (25P02)")
    s1.run("BEGIN")
    s1.run("INSERT INTO payments (invoice_id, payment_date, amount, payment_method) "
           "VALUES (4070, DATE '2025-12-20', -100, 'Банковский перевод')")
    s1.run("SELECT 1")
    s1.run("COMMIT")          # фактически выполнит ROLLBACK
    # то же с SAVEPOINT
    s1.run("BEGIN")
    s1.run("INSERT INTO payments (invoice_id, payment_date, amount, payment_method) "
           "VALUES (4070, DATE '2025-12-20', 30000, 'Банковский перевод')")
    s1.run("SAVEPOINT sp1")
    s1.run("INSERT INTO payments (invoice_id, payment_date, amount, payment_method) "
           "VALUES (4070, DATE '2025-12-20', -100, 'Банковский перевод')")
    s1.run("ROLLBACK TO SAVEPOINT sp1")
    s1.run("SELECT COUNT(*), SUM(amount) FROM payments WHERE invoice_id = 4070")
    s1.run("ROLLBACK")

    # ------------------------------------------------------------------
    header("2. Потерянное обновление: два менеджера резервируют лимит клиента 2 (READ COMMITTED)")
    s1.run("BEGIN"); s2.run("BEGIN")
    s1.run("SELECT credit_limit, credit_reserved FROM customers WHERE customer_id = 2")
    s2.run("SELECT credit_limit, credit_reserved FROM customers WHERE customer_id = 2")
    # каждый считает «в уме»: 0 + 1 500 000 и 0 + 2 000 000
    s1.run("UPDATE customers SET credit_reserved = 1500000 WHERE customer_id = 2")
    t = s2.run_async("UPDATE customers SET credit_reserved = 2000000 WHERE customer_id = 2")
    blocking_info(mon)
    s1.run("COMMIT"); t.join()
    s2.run("COMMIT")
    s1.run("SELECT credit_reserved FROM customers WHERE customer_id = 2")
    s1.run("UPDATE customers SET credit_reserved = 0 WHERE customer_id = 2")

    header("2б. Исправление: SELECT ... FOR UPDATE")
    s1.run("BEGIN"); s2.run("BEGIN")
    s1.run("SELECT credit_limit, credit_reserved FROM customers WHERE customer_id = 2 FOR UPDATE")
    t = s2.run_async("SELECT credit_limit, credit_reserved FROM customers WHERE customer_id = 2 FOR UPDATE")
    s1.run("UPDATE customers SET credit_reserved = credit_reserved + 1500000 WHERE customer_id = 2")
    s1.run("COMMIT"); t.join()
    s2.run("UPDATE customers SET credit_reserved = credit_reserved + 2000000 WHERE customer_id = 2")
    s2.run("COMMIT")
    s1.run("SELECT credit_reserved FROM customers WHERE customer_id = 2")
    s1.run("UPDATE customers SET credit_reserved = 0 WHERE customer_id = 2")

    header("2в. Атомарный UPDATE с условием (без чтения в клиент)")
    s1.run("""UPDATE customers SET credit_reserved = credit_reserved + 1500000
              WHERE customer_id = 2 AND credit_limit - credit_reserved >= 1500000
              RETURNING credit_limit, credit_reserved""")
    s1.run("""UPDATE customers SET credit_reserved = credit_reserved + 3000000
              WHERE customer_id = 2 AND credit_limit - credit_reserved >= 3000000
              RETURNING credit_limit, credit_reserved""")
    s1.run("UPDATE customers SET credit_reserved = 0 WHERE customer_id = 2")

    # ------------------------------------------------------------------
    header("3. Взаимоблокировка: встречные обновления клиентов 2 и 8 (команда А)")
    s1.run("BEGIN"); s2.run("BEGIN")
    s1.run("UPDATE customers SET credit_reserved = credit_reserved + 100000 WHERE customer_id = 2")
    s2.run("UPDATE customers SET credit_reserved = credit_reserved + 50000 WHERE customer_id = 8")
    t = s1.run_async("UPDATE customers SET credit_reserved = credit_reserved + 100000 WHERE customer_id = 8")
    blocking_info(mon)
    r2 = s2.run("UPDATE customers SET credit_reserved = credit_reserved + 50000 WHERE customer_id = 2")
    t.join()
    s1.run("COMMIT"); s2.run("COMMIT")
    s1.run("SELECT customer_id, credit_reserved FROM customers WHERE customer_id IN (2, 8) ORDER BY 1")
    s1.run("UPDATE customers SET credit_reserved = 0 WHERE customer_id IN (2, 8)")

    header("3б. Взаимоблокировка двух закупщиков: заказы поставщикам 945 и 953 (команда Б)")
    s1.run("BEGIN"); s2.run("BEGIN")
    s1.run("UPDATE purchase_orders SET status = 'Согласован' WHERE po_id = 945")
    s2.run("UPDATE purchase_orders SET status = 'Согласован' WHERE po_id = 953")
    t = s1.run_async("UPDATE purchase_orders SET expected_date = expected_date + 2 WHERE po_id = 953")
    s2.run("UPDATE purchase_orders SET expected_date = expected_date + 2 WHERE po_id = 945")
    t.join()
    s1.run("ROLLBACK"); s2.run("ROLLBACK")

    # ------------------------------------------------------------------
    header("4. NOWAIT, lock_timeout, statement_timeout")
    s1.run("BEGIN")
    s1.run("SELECT qty_on_hand FROM material_stock WHERE material_id = 14 FOR UPDATE")
    s2.run("SELECT qty_on_hand FROM material_stock WHERE material_id = 14 FOR UPDATE NOWAIT")
    s2.run("SET lock_timeout = '2s'")
    s2.run("UPDATE material_stock SET qty_on_hand = qty_on_hand - 100 WHERE material_id = 14")
    s2.run("RESET lock_timeout")
    s1.run("ROLLBACK")
    s2.run("SET statement_timeout = '1s'")
    s2.run("SELECT pg_sleep(3)")
    s2.run("RESET statement_timeout")
    s1.run("BEGIN")
    s1.run("LOCK TABLE material_stock IN SHARE MODE NOWAIT")
    s2.run("BEGIN")
    s2.run("LOCK TABLE material_stock IN EXCLUSIVE MODE NOWAIT")
    s2.run("ROLLBACK"); s1.run("ROLLBACK")

    # ------------------------------------------------------------------
    header("5. Конкурентное списание остатка: две смены берут молочный жир (id 14)")
    s1.run("BEGIN"); s2.run("BEGIN")
    s1.run("SELECT qty_on_hand FROM material_stock WHERE material_id = 14 FOR UPDATE")
    t = s2.run_async("SELECT qty_on_hand FROM material_stock WHERE material_id = 14 FOR UPDATE")
    s1.run("UPDATE material_stock SET qty_on_hand = qty_on_hand - 2000 WHERE material_id = 14")
    s1.run("COMMIT"); t.join()
    s2.run("UPDATE material_stock SET qty_on_hand = qty_on_hand - 2000 WHERE material_id = 14")
    s2.run("ROLLBACK")
    s1.run("SELECT qty_on_hand FROM material_stock WHERE material_id = 14")
    s1.run("UPDATE material_stock SET qty_on_hand = qty_on_hand + 2000 WHERE material_id = 14")

    header("5б. Очередь заявок: FOR UPDATE SKIP LOCKED")
    q = """SELECT request_id, line_id, material_id, qty FROM material_requests
           WHERE status = 'Новая' ORDER BY request_id LIMIT 3 FOR UPDATE SKIP LOCKED"""
    s1.run("BEGIN"); s2.run("BEGIN")
    s1.run(q)
    s2.run(q)
    s1.run("ROLLBACK"); s2.run("ROLLBACK")

    # ------------------------------------------------------------------
    header("6. Неповторяемое чтение: READ COMMITTED vs REPEATABLE READ")
    for lvl in ("READ COMMITTED", "REPEATABLE READ"):
        print(f"  --- {lvl}")
        s1.run(f"BEGIN ISOLATION LEVEL {lvl}")
        s1.run("SELECT credit_limit FROM customers WHERE customer_id = 1")
        s2.run("UPDATE customers SET credit_limit = 1000000 WHERE customer_id = 1")
        s1.run("SELECT credit_limit FROM customers WHERE customer_id = 1")
        s1.run("COMMIT")
        s2.run("UPDATE customers SET credit_limit = 3000000 WHERE customer_id = 1")

    header("6б. REPEATABLE READ: конкурентное обновление -> 40001")
    s1.run("BEGIN ISOLATION LEVEL REPEATABLE READ"); s2.run("BEGIN ISOLATION LEVEL REPEATABLE READ")
    s1.run("SELECT qty_on_hand FROM material_stock WHERE material_id = 14")
    s2.run("SELECT qty_on_hand FROM material_stock WHERE material_id = 14")
    s1.run("UPDATE material_stock SET qty_on_hand = qty_on_hand - 2000 WHERE material_id = 14")
    t = s2.run_async("UPDATE material_stock SET qty_on_hand = qty_on_hand - 2000 WHERE material_id = 14")
    s1.run("ROLLBACK"); t.join()     # после ROLLBACK S1 оператор S2 проходит
    s2.run("ROLLBACK")
    s1.run("BEGIN ISOLATION LEVEL REPEATABLE READ"); s2.run("BEGIN ISOLATION LEVEL REPEATABLE READ")
    s1.run("SELECT qty_on_hand FROM material_stock WHERE material_id = 14")
    s2.run("SELECT qty_on_hand FROM material_stock WHERE material_id = 14")
    s1.run("UPDATE material_stock SET qty_on_hand = qty_on_hand - 2000 WHERE material_id = 14")
    t = s2.run_async("UPDATE material_stock SET qty_on_hand = qty_on_hand - 2000 WHERE material_id = 14")
    s1.run("COMMIT"); t.join()       # а после COMMIT — ошибка сериализации
    s2.run("ROLLBACK")
    s1.run("UPDATE material_stock SET qty_on_hand = qty_on_hand + 2000 WHERE material_id = 14")

    # ------------------------------------------------------------------
    header("7. Write skew: две смены снимают по бригаде с ночной смены Линии 3")
    chk = """SELECT COUNT(*) FROM line_crews WHERE line_id = 3 AND work_date = DATE '2026-01-12'
             AND shift = 'Ночь' AND on_duty"""
    for lvl in ("REPEATABLE READ", "SERIALIZABLE"):
        print(f"  --- {lvl}")
        s1.run(f"BEGIN ISOLATION LEVEL {lvl}"); s2.run(f"BEGIN ISOLATION LEVEL {lvl}")
        s1.run(chk); s2.run(chk)
        s1.run("""UPDATE line_crews SET on_duty = FALSE WHERE line_id = 3 AND work_date = DATE '2026-01-12'
                  AND shift = 'Ночь' AND crew_name = 'Бригада 3-А'""")
        s2.run("""UPDATE line_crews SET on_duty = FALSE WHERE line_id = 3 AND work_date = DATE '2026-01-12'
                  AND shift = 'Ночь' AND crew_name = 'Бригада 3-Б'""")
        s1.run("COMMIT")
        s2.run("COMMIT")
        s1.run(chk)
        s1.run("UPDATE line_crews SET on_duty = TRUE")

    header("7б. Повтор транзакции после 40001: S1 уже сняла Бригаду 3-А, S2 повторяет попытку")
    s1.run("""UPDATE line_crews SET on_duty = FALSE WHERE line_id = 3 AND work_date = DATE '2026-01-12'
              AND shift = 'Ночь' AND crew_name = 'Бригада 3-А'""")
    s2.run("BEGIN ISOLATION LEVEL SERIALIZABLE")
    rows = s2.run(chk)
    if rows[0][0] >= 2:
        s2.run("""UPDATE line_crews SET on_duty = FALSE WHERE line_id = 3 AND work_date = DATE '2026-01-12'
                  AND shift = 'Ночь' AND crew_name = 'Бригада 3-Б'""")
        s2.run("COMMIT")
    else:
        print("        -> на смене осталась одна бригада: снимать нельзя, повтор завершён ROLLBACK")
        s2.run("ROLLBACK")
    s1.run("UPDATE line_crews SET on_duty = TRUE")

    for s in (s1, s2, mon):
        s.close()
    print("\nГотово.")


if __name__ == "__main__":
    main()
