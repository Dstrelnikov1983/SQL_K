# -*- coding: utf-8 -*-
"""
Утилита для преподавателя: выполнить SQL-файл или запрос в учебной БД
Yandex Managed Service for PostgreSQL и вывести результат.

    python run_sql.py -f file.sql          # выполнить файл целиком (одна транзакция)
    python run_sql.py -f file.sql --each   # выполнить файл по операторам, печатая результаты
    python run_sql.py -c "SELECT 1"        # выполнить одиночный запрос

Параметры подключения берутся из переменных окружения PG* (PGHOST и PGUSER
обязательны; пароль задаётся ТОЛЬКО через PGPASSWORD). Сертификат root.crt ищется в корне репозитория.
"""
import argparse
import os
import sys

import psycopg2

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

CONN = dict(
    host=os.environ.get("PGHOST"),  # адрес сервера выдаёт преподаватель
    port=int(os.environ.get("PGPORT", 6432)),
    dbname=os.environ.get("PGDATABASE", "db1"),
    user=os.environ.get("PGUSER"),
    password=os.environ.get("PGPASSWORD"),  # задайте PGPASSWORD перед запуском
    sslmode="verify-full",
    sslrootcert=os.environ.get("PGSSLROOTCERT", os.path.join(ROOT, "root.crt")),
    connect_timeout=20,
)


def split_sql(text):
    """Простой разбор на операторы с учётом строк, комментариев и $$-блоков."""
    stmts, buf, i, n = [], [], 0, len(text)
    in_s = in_d = False
    dollar = None
    while i < n:
        ch = text[i]
        if dollar:
            if text.startswith(dollar, i):
                buf.append(dollar); i += len(dollar); dollar = None; continue
            buf.append(ch); i += 1; continue
        if in_s:
            buf.append(ch)
            if ch == "'":
                in_s = False
            i += 1; continue
        if in_d:
            buf.append(ch)
            if ch == '"':
                in_d = False
            i += 1; continue
        if text.startswith("--", i):
            j = text.find("\n", i)
            j = n if j == -1 else j
            buf.append(text[i:j]); i = j; continue
        if text.startswith("/*", i):
            j = text.find("*/", i)
            j = n if j == -1 else j + 2
            buf.append(text[i:j]); i = j; continue
        if ch == "'":
            in_s = True; buf.append(ch); i += 1; continue
        if ch == '"':
            in_d = True; buf.append(ch); i += 1; continue
        if ch == "$":
            j = text.find("$", i + 1)
            if j != -1 and (j == i + 1 or text[i + 1:j].replace("_", "").isalnum()):
                dollar = text[i:j + 1]; buf.append(dollar); i = j + 1; continue
        if ch == ";":
            s = "".join(buf).strip()
            if s:
                stmts.append(s)
            buf = []; i += 1; continue
        buf.append(ch); i += 1
    s = "".join(buf).strip()
    if s:
        stmts.append(s)
    # отбросить «пустые» операторы из одних комментариев
    out = []
    for s in stmts:
        body = "\n".join(l for l in s.splitlines() if not l.strip().startswith("--")).strip()
        if body:
            out.append(s)
    return out


def show(cur, limit):
    if cur.description is None:
        print(f"OK ({cur.statusmessage})")
        return
    cols = [d[0] for d in cur.description]
    rows = cur.fetchmany(limit)
    widths = [max(len(str(c)), *(len(str(r[i])) for r in rows)) if rows else len(c) for i, c in enumerate(cols)]
    widths = [min(w, 40) for w in widths]
    print(" | ".join(str(c)[:40].ljust(w) for c, w in zip(cols, widths)))
    print("-+-".join("-" * w for w in widths))
    for r in rows:
        print(" | ".join(str(v)[:40].ljust(w) for v, w in zip(r, widths)))
    print(f"({cur.rowcount} строк)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-f", "--file")
    ap.add_argument("-c", "--command")
    ap.add_argument("--each", action="store_true", help="выполнять по операторам и печатать результаты")
    ap.add_argument("--limit", type=int, default=15)
    ap.add_argument("--stop", action="store_true", help="остановиться на первой ошибке")
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    conn = psycopg2.connect(**CONN)
    conn.autocommit = True
    cur = conn.cursor()
    cur.execute("SET search_path TO pitanie, public")
    if a.command:
        cur.execute(a.command)
        show(cur, a.limit)
        return
    text = open(a.file, encoding="utf-8").read()
    if not a.each:
        cur.execute(text)
        print("OK")
        return
    errors = 0
    for k, s in enumerate(split_sql(text), 1):
        first = next((l for l in s.splitlines() if l.strip() and not l.strip().startswith("--")), "")
        print(f"\n### [{k}] {first[:100]}")
        try:
            cur.execute(s)
            for note in conn.notices:
                print("NOTICE:", note.strip())
            conn.notices.clear()
            show(cur, a.limit)
        except Exception as e:
            errors += 1
            print("ERROR:", str(e).strip())
            if a.stop:
                break
    print(f"\nИтого ошибок: {errors}")


if __name__ == "__main__":
    main()
