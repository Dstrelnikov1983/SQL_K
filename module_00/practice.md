# Модуль 0. Практическая работа «Подключение к учебной БД и знакомство с данными»

| | |
|---|---|
| **Цель** | Настроить защищённое подключение к Yandex Managed Service for PostgreSQL, научиться находить объекты схемы `pitanie` через системный каталог и получить первое представление о данных «Питание +» |
| **Время** | 40 минут (15 мин — демонстрация преподавателя, 25 мин — повторение слушателями) |
| **Формат** | Преподаватель показывает каждый шаг, слушатели повторяют на своих компьютерах |
| **Файл с кодом** | [`examples.sql`](examples.sql) |
| **Результат** | Работающее подключение в DBeaver (или psql), выполненные запросы-разведки, заполненная «карточка данных» (шаг 9) |

---

## Подготовка

1. Установите клиент (любой один):
   - **DBeaver Community** 24.x и новее — https://dbeaver.io (рекомендуется);
   - **pgAdmin 4**;
   - **psql** 16 (входит в дистрибутив PostgreSQL, в Windows — `C:\Program Files\PostgreSQL\16\bin\psql.exe`);
   - **VS Code + SQLTools** с драйвером PostgreSQL.
2. Скачайте сертификат **`root.crt`** из корня репозитория курса (или по ссылке Yandex Cloud: `https://storage.yandexcloud.net/cloud-certs/CA.pem`) и положите в постоянную папку:
   - Windows: `%APPDATA%\postgresql\root.crt` (например, `C:\Users\<вы>\AppData\Roaming\postgresql\root.crt`);
   - Linux / macOS: `~/.postgresql/root.crt`.
3. Получите у преподавателя **логин и пароль**.

### Параметры подключения

| Параметр | Значение |
|---|---|
| Хост | `<адрес_сервера>` |
| Порт | `6432` (пулер соединений Odyssey) |
| База данных | `db1` |
| Пользователь / пароль | выдаёт преподаватель |
| SSL | режим `verify-full`, корневой сертификат `root.crt` |

> **Почему `verify-full`?** Это самый строгий режим: трафик шифруется, а клиент проверяет, что сертификат сервера подписан доверенным центром (Yandex) **и** выдан именно на этот хост. Режимы `require`/`prefer` не защищают от подмены сервера.

---

## Шаг 1. Создайте подключение в DBeaver

1. **База данных → Новое соединение** → выберите **PostgreSQL** → *Далее*.
2. Вкладка **Главное (Main)**:
   - *Подключение через*: **Host**;
   - *Хост*: `<адрес_сервера>`;
   - *Порт*: `6432`;
   - *База данных*: `db1`;
   - *Аутентификация*: **Database Native**, *Пользователь* и *Пароль* — выданные преподавателем;
   - включите **Показать все базы данных** — не нужно (оставьте выключенным).
3. Вкладка **SSL**:
   - поставьте галочку **Использовать SSL**;
   - *Корневой сертификат (CA)*: укажите путь к `root.crt`;
   - *Режим SSL (SSL mode)*: **verify-full**;
   - сертификат и ключ клиента оставьте пустыми.
4. Нажмите **Тест соединения**. При первом запуске DBeaver предложит скачать драйвер — согласитесь.
5. Ожидаемый результат: окно «Подключено» с версией `PostgreSQL 16.x`.
6. *Готово* → переименуйте соединение в **«Питание + (учебная)»**.

> **Типичные ошибки**
>
> | Сообщение | Причина и решение |
> |---|---|
> | `Connection attempt timed out` | Неверный порт (нужен **6432**, не 5432) или блокировка сети. Проверьте `Test-NetConnection <адрес_сервера> -Port 6432` (PowerShell) |
> | `root certificate file ... does not exist` | Неверный путь к `root.crt` |
> | `server certificate for "..." does not match host name` | В поле *Хост* указан IP-адрес или опечатка — для `verify-full` нужен точный FQDN |
> | `password authentication failed` | Неверный логин/пароль, проверьте раскладку |

## Шаг 2 (альтернатива). Подключение через psql

Windows PowerShell:

```powershell
$env:PGSSLROOTCERT = "$env:APPDATA\postgresql\root.crt"
psql "host=<адрес_сервера> port=6432 dbname=db1 user=<логин> sslmode=verify-full target_session_attrs=read-write"
```

Linux / macOS:

```bash
psql "host=<адрес_сервера> port=6432 dbname=db1 user=<логин> \
      sslmode=verify-full sslrootcert=$HOME/.postgresql/root.crt"
```

psql спросит пароль. Полезные метакоманды psql:

| Команда | Что делает |
|---|---|
| `\conninfo` | параметры текущего подключения, в т. ч. SSL |
| `\dn` | список схем |
| `\dt pitanie.*` | таблицы схемы `pitanie` |
| `\d+ pitanie.orders` | структура таблицы с комментариями |
| `\x auto` | «вертикальный» вывод широких строк |
| `\timing on` | показывать время выполнения запроса |
| `\q` | выход |

## Шаг 3. Установите схему по умолчанию

Откройте SQL-редактор (в DBeaver: **F3** или *SQL Editor → New script*) и выполните:

```sql
SET search_path TO pitanie, public;
```

Теперь можно писать `FROM orders` вместо `FROM pitanie.orders`.

> `SET` действует только в **текущей сессии**. В DBeaver можно задать схему навсегда: *Изменить соединение → Initialization (Bootstrap queries)* → добавить `SET search_path TO pitanie, public;`, либо выбрать схему `pitanie` в выпадающем списке на панели инструментов редактора.

Проверьте, где вы и кто вы:

```sql
SELECT version()                      AS server_version,
       current_database()             AS db,
       current_user                   AS usr,
       current_setting('search_path') AS search_path;
```

**Ожидаемый результат:**

```text
server_version                  | db  | usr      | search_path
--------------------------------+-----+----------+----------------
PostgreSQL 16.13 (Ubuntu ...)   | db1 | <логин>  | pitanie, public
```

## Шаг 4. Какие таблицы есть в схеме

```sql
SELECT t.table_name,
       obj_description(format('%I.%I', t.table_schema, t.table_name)::regclass) AS description
FROM   information_schema.tables AS t
WHERE  t.table_schema = 'pitanie'
  AND  t.table_type   = 'BASE TABLE'
ORDER  BY t.table_name;
```

**Ожидаемый результат:** 23 строки — от `customers` до `suppliers`, у каждой таблицы есть описание-комментарий.

> **Подумайте.** `information_schema` — часть стандарта SQL, а `pg_catalog` — «родной» каталог PostgreSQL. Почему для переносимых скриптов лучше `information_schema`, а для глубокого анализа — `pg_catalog`?

## Шаг 5. Структура таблицы

```sql
SELECT column_name,
       data_type,
       numeric_precision AS prec,
       numeric_scale     AS scale,
       is_nullable
FROM   information_schema.columns
WHERE  table_schema = 'pitanie'
  AND  table_name   = 'order_items'
ORDER  BY ordinal_position;
```

**Ожидаемый результат:**

```text
column_name   | data_type | prec | scale | is_nullable
--------------+-----------+------+-------+------------
order_item_id | integer   | 32   | 0     | NO
order_id      | integer   | 32   | 0     | NO
product_id    | integer   | 32   | 0     | NO
quantity      | integer   | 32   | 0     | NO
unit_price    | numeric   | 10   | 2     | NO
discount_pct  | numeric   | 5    | 2     | NO
```

> В DBeaver то же самое видно в дереве: *Схемы → pitanie → Таблицы → order_items → Колонки*. Вкладка **ER-диаграмма** у схемы рисует связи автоматически — откройте её.

## Шаг 6. Связи между таблицами (внешние ключи)

```sql
SELECT con.conrelid::regclass  AS child_table,
       a.attname               AS fk_column,
       con.confrelid::regclass AS parent_table
FROM   pg_constraint AS con
JOIN   pg_attribute  AS a
       ON  a.attrelid = con.conrelid
       AND a.attnum   = ANY (con.conkey)
WHERE  con.contype = 'f'
  AND  con.connamespace = 'pitanie'::regnamespace
ORDER  BY con.conrelid::regclass::text, a.attname;
```

**Ожидаемый результат:** 30 строк. Фрагмент:

```text
child_table          | fk_column          | parent_table
---------------------+--------------------+-------------------
customers            | manager_id         | employees
customers            | region_id          | regions
employees            | manager_id         | employees        ← самоссылка (иерархия)
...
product_categories   | parent_category_id | product_categories ← самоссылка
```

> **Подумайте.** Две таблицы ссылаются сами на себя. Какие вопросы бизнеса потребуют SELF-JOIN или рекурсивного запроса (модули 3 и 9)?

## Шаг 7. Объём данных

```sql
SELECT 'orders'               AS table_name, COUNT(*) AS rows_cnt FROM orders
UNION ALL SELECT 'order_items',          COUNT(*) FROM order_items
UNION ALL SELECT 'customers',            COUNT(*) FROM customers
UNION ALL SELECT 'production_batches',   COUNT(*) FROM production_batches
UNION ALL SELECT 'material_consumption', COUNT(*) FROM material_consumption
UNION ALL SELECT 'purchase_order_items', COUNT(*) FROM purchase_order_items
ORDER  BY rows_cnt DESC;
```

**Ожидаемый результат:**

```text
table_name           | rows_cnt
---------------------+---------
material_consumption | 24275
order_items          | 17576
production_batches   | 6062
orders               | 4458
purchase_order_items | 2328
customers            | 73
```

Сравните с «быстрой» оценкой из статистики:

```sql
SELECT relname AS table_name, n_live_tup AS approx_rows
FROM   pg_stat_user_tables
WHERE  schemaname = 'pitanie'
ORDER  BY n_live_tup DESC;
```

> **Подумайте.** У части таблиц (например, `products`) статистика показывает 70 строк, а `COUNT(*)` — 35. Откуда расхождение? *(Подсказка: данные перезагружались, а статистика обновляется фоновыми процессами autovacuum/ANALYZE.)* Какой способ годится для отчёта руководству?

## Шаг 8. Период и справочные значения

```sql
SELECT MIN(order_date) AS date_from, MAX(order_date) AS date_to FROM orders;

SELECT status, COUNT(*) AS orders_cnt
FROM   orders
GROUP  BY status
ORDER  BY orders_cnt DESC;
```

**Ожидаемый результат:** период 2024-01-01 … 2025-12-31; статусы: Доставлен 4212, Отменён 177, Отгружен 30, Новый 22, В работе 17.

```sql
SELECT line_id, line_name, workshop, capacity_per_hour, launch_year
FROM   production_lines
ORDER  BY line_id;
```

**Ожидаемый результат:** 5 линий; самая старая — *Линия 2 — масло, сыры, соусы*, 2009 г.

## Шаг 9. Первые «крупные цифры»

```sql
-- Выручка по годам без отменённых заказов, млн руб.
SELECT EXTRACT(YEAR FROM o.order_date)::int AS yr,
       ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) / 1e6, 1) AS revenue_mln
FROM   orders      AS o
JOIN   order_items AS oi ON oi.order_id = o.order_id
WHERE  o.status <> 'Отменён'
GROUP  BY yr
ORDER  BY yr;
```

**Ожидаемый результат:** 2024 — **384,0**; 2025 — **445,1** млн руб. (+15,9 %).

```sql
-- Выпуск и брак по годам
SELECT EXTRACT(YEAR FROM production_date)::int AS yr,
       SUM(produced_qty) AS produced,
       SUM(defect_qty)   AS defects,
       ROUND(100.0 * SUM(defect_qty) / NULLIF(SUM(produced_qty), 0), 2) AS defect_pct
FROM   production_batches
GROUP  BY yr
ORDER  BY yr;
```

**Ожидаемый результат:** 2024 — 3 757 449 ед., брак 2,39 %; 2025 — 4 062 469 ед., брак **2,64 %**.

> **Подумайте.** Выручка выросла на 16 %, а брак — с 2,39 до 2,64 %. Это хорошо или плохо? Каких данных не хватает, чтобы ответить?

Заполните «карточку данных» (понадобится в лабораторной):

| Показатель | Значение |
|---|---|
| Таблиц в схеме | 23 |
| Внешних ключей | 30 |
| Период данных | 01.01.2024 – 31.12.2025 |
| Самая большая таблица | `material_consumption`, 24 275 строк |
| Выручка 2024 / 2025 | 384,0 / 445,1 млн руб. |
| Брак 2024 / 2025 | 2,39 % / 2,64 % |

## Типичные ошибки

| Ошибка | Как исправить |
|---|---|
| `relation "orders" does not exist` | Не выполнен `SET search_path TO pitanie, public;` или новая вкладка редактора открыла новую сессию |
| `permission denied for schema pitanie` при `CREATE`/`INSERT` | Это нормально: схема `pitanie` только для чтения. Свои объекты — в личной схеме `stud_<фамилия>` (с модуля 7) |
| Суммы в копейках «плывут» | Используйте `ROUND(..., 2)`; денежные столбцы имеют тип `numeric`, не `float` |
| В DBeaver выводятся только 200 строк | Это ограничение клиента (*Result set fetch size*), а не данных; для подсчёта используйте `COUNT(*)` |

## Контрольные вопросы

1. Чем отличаются режимы SSL `require` и `verify-full`?
2. Где хранится описание таблиц и столбцов в PostgreSQL? Назовите два способа его получить.
3. Почему `n_live_tup` нельзя использовать вместо `COUNT(*)` в отчёте?
4. Какие две таблицы ссылаются сами на себя и зачем?
