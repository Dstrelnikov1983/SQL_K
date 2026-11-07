# Модуль 9. Практическая работа
## Производные таблицы, CTE, представления и табличные функции

| | |
|---|---|
| **Цель** | Научиться разбивать сложный аналитический запрос на шаги (производные таблицы, CTE), обходить иерархии рекурсивным CTE и «упаковывать» повторяющуюся логику в представления и табличные функции |
| **Время** | 40 мин (демонстрация преподавателя + повторение слушателями) |
| **Формат** | Преподаватель показывает шаг, слушатели повторяют у себя и отвечают на вопросы «Подумайте» |
| **Файл с кодом** | `module_09/examples.sql` |
| **Данные** | схема `pitanie` (только чтение) + личная схема `stud_<фамилия>` |

> **Сюжет.** Аналитики «Питание +» каждый день пишут одни и те же соединения:
> «заказы + позиции + товары», «партии + линии + брак». Запросы растут до сотни строк, в них
> ошибаются. Сегодня мы научимся разбивать запрос на понятные шаги и сохранять
> проверенную логику в базе — в виде представлений и функций, которыми смогут пользоваться
> и другие члены команды.

---

## Подготовка (5 мин)

1. Подключитесь к учебной БД (DBeaver / psql): сервер `<адрес_сервера>`, порт `6432`, база `db1`, SSL `verify-full` с сертификатом `root.crt`.
2. Убедитесь, что у вас есть **личная схема** `stud_<фамилия>`. Её создаёт скрипт `module_07/scripts/00_personal_schema.sql` (выполнялся в модуле 7). Если схемы ещё нет — выполните его:

```sql
SET course.stud_schema = 'stud_ivanov';   -- вместо ivanov — ваша фамилия латиницей
-- затем выполнить весь файл module_07/scripts/00_personal_schema.sql как скрипт (Alt+X в DBeaver)
```

> В личной схеме лежат **копии** таблиц `pitanie` с теми же именами (`orders`, `production_batches`, …).
> Поэтому в примерах модуля все исходные таблицы указаны с префиксом **`pitanie.`** — представления и функции
> читают эталонные данные, а не вашу копию, которую вы могли изменить в модуле 7.

3. Настройте путь поиска: сначала личная схема, затем общие данные.

```sql
SET search_path TO stud_ivanov, pitanie, public;
```

> Во всех примерах ниже `stud_ivanov` — замените на свою схему (в DBeaver: Ctrl+F → Replace).
> **Ничего не создавайте в схеме `pitanie`** — она общая и доступна только для чтения.

---

## Часть 1. Производные таблицы

### Шаг 1. Агрегат от агрегата

Задача: какова **средняя выручка одного менеджера**? `AVG(SUM(...))` в одном `SELECT` написать нельзя — сначала считаем выручку каждого менеджера во вложенном запросе, затем усредняем.

```sql
SELECT ROUND(AVG(t.revenue), 0)  AS avg_manager_revenue,
       ROUND(MAX(t.revenue), 0)  AS max_manager_revenue,
       COUNT(*)                  AS managers
FROM  (SELECT o.employee_id,
              SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS revenue
       FROM   pitanie.orders      AS o
       JOIN   pitanie.order_items AS oi ON oi.order_id = o.order_id
       WHERE  o.status <> 'Отменён'
       GROUP  BY o.employee_id) AS t;
```

**Ожидаемый результат:**

| avg_manager_revenue | max_manager_revenue | managers |
|---|---|---|
| 92124473 | 207234961 | 9 |

> **Подумайте.** Что будет, если убрать алиас `AS t`? (PostgreSQL 16 впервые разрешил подзапрос во FROM без алиаса — запрос выполнится. Но в PG ≤ 15 будет ошибка `subquery in FROM must have an alias`, в T-SQL — тоже ошибка. К тому же без алиаса не на что сослаться в `t.revenue`. Правило курса: **алиас у производной таблицы пишем всегда**.)

### Шаг 2. Производная таблица в JOIN

```sql
SELECT e.full_name, d.lines, d.avg_discount
FROM   pitanie.employees AS e
JOIN  (SELECT o.employee_id,
              COUNT(*)                       AS lines,
              ROUND(AVG(oi.discount_pct), 2) AS avg_discount
       FROM   pitanie.orders      AS o
       JOIN   pitanie.order_items AS oi ON oi.order_id = o.order_id
       WHERE  o.status <> 'Отменён'
       GROUP  BY o.employee_id) AS d ON d.employee_id = e.employee_id
ORDER  BY d.avg_discount DESC;
```

**Ожидаемый результат (фрагмент):**

| full_name | lines | avg_discount |
|---|---|---|
| Соколов Игорь Андреевич | 4167 | **18.01** |
| Попов Станислав Игоревич | 133 | 8.29 |
| Павлов Сергей Дмитриевич | 1590 | 5.23 |

> **Подумайте.** Политика компании — скидка не более 10 %. Что говорит средняя скидка 18 %? Это повод для отдельного расследования команды А.

---

## Часть 2. CTE (WITH)

### Шаг 3. Тот же запрос через CTE

```sql
WITH manager_revenue AS (
    SELECT o.employee_id,
           SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS revenue
    FROM   pitanie.orders      AS o
    JOIN   pitanie.order_items AS oi ON oi.order_id = o.order_id
    WHERE  o.status <> 'Отменён'
    GROUP  BY o.employee_id
)
SELECT e.full_name,
       ROUND(mr.revenue / 1e6, 1)                           AS revenue_mln,
       ROUND(100 * mr.revenue / SUM(mr.revenue) OVER (), 1) AS share_pct
FROM   manager_revenue   AS mr
JOIN   pitanie.employees AS e ON e.employee_id = mr.employee_id
ORDER  BY mr.revenue DESC;
```

**Ожидаемо:** 9 строк, первая — Морозова Е. П. (207,2 млн, 25,0 %), вторая — Соколов И. А. (176,9 млн, 21,3 %).

### Шаг 4. Цепочка из нескольких CTE: план/факт 2025

Каждое CTE — один шаг: `fact` → `plan` → `pf` (соединение) → итоговый `SELECT`. Код см. в `examples.sql`, раздел 2.2.

**Ожидаемый результат:**

| category_name | half | plan_mln | fact_mln | done_pct |
|---|---|---|---|---|
| Молочная продукция | H1 | 117.7 | 111.8 | 94.9 |
| Молочная продукция | H2 | 117.1 | 114.9 | 98.2 |
| Кондитерские изделия | H1 | 75.0 | 72.8 | 97.1 |
| **Кондитерские изделия** | **H2** | **97.4** | **77.9** | **80.0** |
| Бакалея | H1 | 35.3 | 35.0 | 99.2 |
| Бакалея | H2 | 35.1 | 32.7 | 93.3 |

> **Подумайте.** План кондитерки на H2 вырос с 75 до 97,4 млн (+30 %), а факт почти не изменился. Кто виноват — продажи или планирование?

### Шаг 5. Повторное использование CTE (самосоединение)

Одно CTE `shift_quality` используется в запросе дважды — как «дневная» и «ночная» копия.

```sql
WITH shift_quality AS (
    SELECT line_id, shift,
           ROUND(100.0 * SUM(defect_qty) / NULLIF(SUM(produced_qty), 0), 2) AS defect_pct
    FROM   pitanie.production_batches
    GROUP  BY line_id, shift
)
SELECT d.line_id,
       d.defect_pct                AS day_defect_pct,
       n.defect_pct                AS night_defect_pct,
       n.defect_pct - d.defect_pct AS diff_pp
FROM   shift_quality AS d
JOIN   shift_quality AS n ON n.line_id = d.line_id AND n.shift = 'Ночь'
WHERE  d.shift = 'День'
ORDER  BY diff_pp DESC;
```

**Ожидаемо:** первая строка — линия 3: день 1.62 %, ночь **7.94 %**, разница 6.32 п. п.; у остальных линий разница ≈ 0.

### Шаг 6. MATERIALIZED и NOT MATERIALIZED

Выполните оба запроса с `EXPLAIN (COSTS OFF)` (раздел 2.4 `examples.sql`) и сравните планы:

| Вариант | План |
|---|---|
| `NOT MATERIALIZED` | `Index Scan using production_batches_pkey` — условие «протолкнулось» внутрь CTE |
| `MATERIALIZED` | `CTE Scan on b` + `Filter`, внутри `Seq Scan on production_batches` — сначала вся таблица |

> **Подумайте.** Когда `MATERIALIZED` полезен? (CTE используется несколько раз и считается дорого; нужно зафиксировать результат «тяжёлой» или volatile-функции.)

---

## Часть 3. Рекурсивные CTE

### Шаг 7. Оргструктура компании

```sql
WITH RECURSIVE org AS (
    SELECT employee_id, full_name, position, manager_id,
           1 AS lvl, full_name::text AS path            -- якорь: генеральный директор
    FROM   pitanie.employees
    WHERE  manager_id IS NULL
    UNION ALL
    SELECT e.employee_id, e.full_name, e.position, e.manager_id,
           org.lvl + 1,
           org.path || ' → ' || split_part(e.full_name, ' ', 1)   -- рекурсивная часть
    FROM   pitanie.employees AS e
    JOIN   org ON e.manager_id = org.employee_id
)
SELECT repeat('    ', lvl - 1) || full_name AS tree, position, lvl
FROM   org
ORDER  BY path;
```

**Ожидаемо:** 35 строк, 4 уровня (1 + 4 + 10 + 20 сотрудников), дерево с отступами:

```text
Орлов Виктор Петрович
    Белова Марина Сергеевна
        Егоров Максим Ильич
        Котова Наталья Михайловна
            Тихонова Вера Андреевна
    Громов Алексей Иванович
        Ершова Татьяна Юрьевна
            Волков Денис Сергеевич
            ...
```

> **Типичная ошибка.** Забыть условие соединения в рекурсивной части или соединить «не в ту сторону» (`e.employee_id = org.manager_id` — пойдём вверх, а не вниз). Для страховки ограничивайте глубину (`WHERE org.lvl < 10`) или используйте `CYCLE` (раздел 3.5).

### Шаг 8. Команда руководителя отдела продаж и её выручка

Раздел 3.2 `examples.sql`: якорь — Ершова Т. Ю. (id 9), к команде присоединяем выручку и скидки.

**Ожидаемо (фрагмент):**

| depth | full_name | revenue_mln | discount_mln |
|---|---|---|---|
| 0 | Ершова Татьяна Юрьевна | 0.0 | 0.0 |
| 1 | Морозова Елена Павловна | 207.2 | 10.3 |
| 1 | Соколов Игорь Андреевич | 176.9 | **38.8** |
| 1 | Новикова Ольга Игоревна | 108.3 | 3.4 |

### Шаг 9. Путь в дереве категорий и генерация календаря

* Раздел 3.3 — путь `Молочная продукция / Сыры и масло` (10 строк).
* Раздел 3.4 — рекурсивный календарь месяцев 2025 и простои линии 2. Календарь нужен, чтобы в отчёте были **все** месяцы, даже без событий (LEFT JOIN от календаря).

**Ожидаемо:** 12 строк, например `2025-04 | 11 событий | 81.9 ч`.

> **Подумайте.** Чем рекурсивный календарь отличается от `generate_series()`? (Результат тот же; `generate_series` короче и быстрее, рекурсия — переносима в другие СУБД.)

### Шаг 10. Data-modifying CTE (кратко)

В личной схеме перенесём незакрытые простои в журнал **одним** оператором (раздел 4):

```sql
WITH moved AS (
    DELETE FROM stud_ivanov.m09_downtime_open
    WHERE  end_time IS NULL
    RETURNING *
)
INSERT INTO stud_ivanov.m09_downtime_log
SELECT * FROM moved;
```

**Ожидаемо:** `INSERT 0 4`; в исходной копии остаётся 278 строк, в журнале — 4.

---

## Часть 4. Представления

### Шаг 11. Создаём представление `v_order_lines`

Раздел 5.1. После создания представлением пользуются как таблицей:

```sql
SELECT channel, COUNT(*) AS lines, ROUND(SUM(net_amount) / 1e6, 1) AS revenue_mln
FROM   stud_ivanov.v_order_lines
GROUP  BY channel
ORDER  BY revenue_mln DESC;
```

**Ожидаемо:** Дистрибуция 8979 / 410.5; Прямые продажи 7133 / 383.3; Маркетплейс 641 / 19.6; Тендер 170 / 15.6.

### Шаг 12. Что можно и чего нельзя в `CREATE OR REPLACE VIEW`

* Добавить столбец **в конец** — можно (раздел 5.2, столбец `over_policy`).
* Удалить/переименовать/сменить тип столбца — нельзя: `ERROR: cannot drop columns from view` (ожидаемая ошибка). Нужно `DROP VIEW` + `CREATE VIEW`.

### Шаг 13. Безопасность: скрываем столбцы

Представление `v_employees_public` не содержит `salary`, `email`, `phone`. Права выдаются только на представление: `GRANT SELECT ON stud_ivanov.v_employees_public TO analyst_role;` (демонстрационно, у слушателей нет прав создавать роли).

### Шаг 14. Обновляемое представление и WITH CHECK OPTION

Раздел 5.4: копия клиентов в личной схеме и представление «только федеральные сети» с `WITH CHECK OPTION`.

| Действие | Результат |
|---|---|
| `UPDATE ... SET credit_limit = credit_limit * 1.10` | `UPDATE 1` |
| `UPDATE ... SET customer_type = 'Розница'` | **ожидаемая ошибка** `new row violates check option for view "v_federal_chains"` |

Проверка в `information_schema.views`: `v_federal_chains` — `YES / YES / CASCADED`, `v_order_lines` — `NO` (соединение двух таблиц).

### Шаг 15. Зависимости

`DROP TABLE stud_ivanov.m09_customers;` → **ожидаемая ошибка** `cannot drop table m09_customers because other objects depend on it`. Посмотрите зависимости в `information_schema.view_table_usage` (4 строки) и текст представления — `pg_get_viewdef(...)`.

### Шаг 16. Материализованное представление

Раздел 6: `mv_monthly_revenue` — выручка по месяцам и каналам, **91 строка**. Данные хранятся физически и не меняются, пока не выполнен `REFRESH MATERIALIZED VIEW`. Для `REFRESH ... CONCURRENTLY` нужен уникальный индекс.

> **Подумайте.** Отчёт для правления обновляется раз в сутки, а запрос к сырым данным идёт 40 секунд. Обычное или материализованное представление? Чем рискуем?

---

## Часть 5. Табличные функции

### Шаг 17. `RETURNS TABLE` — «параметризованное представление»

Раздел 7.1: `fn_customer_orders(p_customer_id, p_from, p_to)`, `LANGUAGE sql`, `STABLE`.

```sql
SELECT * FROM stud_ivanov.fn_customer_orders(1, DATE '2025-12-01', DATE '2025-12-31');
```

**Ожидаемо:** 7 заказов ТД «Вектор» в декабре 2025, среди них один «Отгружен» и один «В работе». Вызов с именованными параметрами `fn_customer_orders(p_customer_id => 1, p_from => DATE '2025-01-01')` — 46 заказов на 8 424 049,27 руб.

### Шаг 18. `RETURNS SETOF таблица`

Раздел 7.2: `fn_line_batches(3, DATE '2025-06-10')` → 2 партии; у ночной брак 118 из 1314 шт. (≈ 9 %), у дневной — 20 из 1407.

### Шаг 19. Функция + LATERAL (аналог CROSS APPLY)

Раздел 7.3: для каждого клиента типа «Маркетплейс» — 2 последних заказа. **Ожидаемо:** 6 строк (3 клиента × 2 заказа).

### Шаг 20. Встраивание (inlining) и метаданные

`EXPLAIN` вызова `fn_line_batches` показывает обычный `Index Scan` по таблице — функция встроена в запрос, как inline TVF в T-SQL. В `pg_proc` у функций `provolatile = s` (STABLE) и `proretset = true`.

| T-SQL | PostgreSQL |
|---|---|
| `CREATE FUNCTION f(@p INT) RETURNS TABLE AS RETURN (SELECT ...)` (inline TVF) | `CREATE FUNCTION f(p int) RETURNS TABLE(...) LANGUAGE sql STABLE AS $$ SELECT ... $$` |
| multi-statement TVF `RETURNS @t TABLE (...)` | `LANGUAGE plpgsql` + `RETURN QUERY` / `RETURN NEXT` (модуль 10) |
| `CROSS APPLY dbo.f(t.id)` | `CROSS JOIN LATERAL f(t.id)` |
| `OUTER APPLY` | `LEFT JOIN LATERAL ... ON TRUE` |

---

## Типичные ошибки

| Ошибка | Причина | Как исправить |
|---|---|---|
| `relation "v_order_lines" does not exist` | не настроен `search_path` или объект создан в другой схеме | `SET search_path TO stud_ivanov, pitanie, public;` или полное имя |
| `permission denied for schema pitanie` при `CREATE VIEW` | попытка создать объект в общей схеме | создавайте в `stud_<фамилия>` |
| `cannot drop columns from view` | `CREATE OR REPLACE` с другим набором столбцов | `DROP VIEW ...; CREATE VIEW ...` |
| `cannot change return type of existing function` | изменили `RETURNS TABLE` | `DROP FUNCTION f(типы); CREATE FUNCTION ...` |
| Рекурсия «не останавливается» | цикл в данных или неверное условие JOIN | ограничение глубины, `CYCLE`, проверка направления связи |
| Агрегаты в представлении «задваиваются» | JOIN «один ко многим» до группировки | агрегировать в CTE до соединения |

## Контрольные вопросы

1. Чем производная таблица отличается от CTE? Когда CTE удобнее?
2. Что такое якорная и рекурсивная части рекурсивного CTE? Почему между ними `UNION ALL`?
3. Какие представления PostgreSQL обновляет автоматически?
4. Что делает `WITH CHECK OPTION`? Чем `LOCAL` отличается от `CASCADED`?
5. Чем материализованное представление отличается от обычного? Как и когда его обновлять?
6. Почему табличную функцию на SQL стоит объявлять `STABLE`, а не `VOLATILE`?
