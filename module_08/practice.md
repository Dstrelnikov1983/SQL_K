# Модуль 8. Практическая работа «Оконные функции»

> Демонстрация преподавателя + повторение слушателями. Весь код — в файле [`examples.sql`](examples.sql).

| | |
|---|---|
| **Цель** | Освоить синтаксис `OVER (PARTITION BY … ORDER BY … рамка)`, функции ранжирования, оконные агрегаты, функции смещения и именованные окна; научиться обходить типичные ловушки (рамка по умолчанию, `LAST_VALUE`, фильтрация по окну) |
| **Время** | ≈ 40 минут — в составе лекции: каждый блок показывается сразу после теории (см. план в презентации) |
| **Формат** | Преподаватель показывает шаг, слушатели повторяют и отвечают на вопросы «Подумайте» |
| **Данные** | Только чтение — схема `pitanie` (личная схема не нужна) |

## Подготовка

```sql
SET search_path TO pitanie, public;
```

Формула выручки строки (не отменённые заказы): `oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)`.

## Шаг 1. Окно против GROUP BY

```sql
-- GROUP BY: 5 строк — по одной на линию
SELECT line_id,
       round(avg(100.0 * defect_qty / produced_qty), 2) AS avg_defect_pct
FROM   production_batches
GROUP  BY line_id;
```

| line_id | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| avg_defect_pct | 1.62 | 2.34 | **4.78** | 1.65 | 1.57 |

```sql
-- окно: КАЖДАЯ партия + средний брак её линии рядом
SELECT batch_id, line_id, shift,
       round(100.0 * defect_qty / produced_qty, 2) AS defect_pct,
       round(avg(100.0 * defect_qty / produced_qty) OVER (PARTITION BY line_id), 2) AS line_avg_pct
FROM   production_batches
WHERE  production_date = DATE '2025-06-02'
ORDER  BY line_id, shift;
```

**Ожидаемо:** 10 строк; у Линии 3 ночью брак 6.25 % при среднем по линии за день 4.16 %.

Обратите внимание: среднее посчитано по строкам, **прошедшим WHERE** (только 02.06.2025), — окно вычисляется после фильтрации.

## Шаг 2. OVER () и доля от итога; окно поверх GROUP BY

```sql
SELECT r.region_name,
       count(*)                                           AS returns_cnt,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS share_pct
FROM   returns   AS rt
JOIN   orders    AS o ON o.order_id    = rt.order_id
JOIN   customers AS c ON c.customer_id = o.customer_id
LEFT   JOIN regions AS r ON r.region_id = c.region_id
GROUP  BY r.region_name
ORDER  BY returns_cnt DESC
LIMIT  5;
```

| region_name | returns_cnt | share_pct |
|---|---|---|
| Новосибирская область | 106 | 34.4 |
| Красноярский край | 75 | 24.4 |
| Москва и МО | 32 | 10.4 |

`sum(count(*)) OVER ()` — оконная сумма **групповых** `count(*)`: сначала `GROUP BY`, потом окно.

**Подумайте:** почему почти 60 % возвратов — из двух сибирских регионов? Какие столбцы `products` проверить?

## Шаг 3. Порядок выполнения и фильтр по окну

```sql
SELECT batch_id, line_id, defect_qty
FROM   production_batches
WHERE  row_number() OVER (PARTITION BY line_id ORDER BY defect_qty DESC) <= 3;
-- ERROR: window functions are not allowed in WHERE
```

Логический порядок: `FROM → WHERE → GROUP BY → HAVING → оконные функции → SELECT → DISTINCT → ORDER BY → LIMIT`.
Решение — CTE или подзапрос:

```sql
WITH ranked AS (
    SELECT batch_id, line_id, production_date, shift, defect_qty,
           row_number() OVER (PARTITION BY line_id ORDER BY defect_qty DESC, batch_id) AS rn
    FROM   production_batches
)
SELECT * FROM ranked WHERE rn <= 3 ORDER BY line_id, rn;
```

**Ожидаемо:** 15 строк; у Линии 3 все три худшие партии — **ночные** (230, 217, 214 шт. брака).

## Шаг 4. ROW_NUMBER, RANK, DENSE_RANK

```sql
SELECT material_name, shelf_life_days,
       row_number() OVER (ORDER BY shelf_life_days DESC) AS rn,
       rank()       OVER (ORDER BY shelf_life_days DESC) AS rnk,
       dense_rank() OVER (ORDER BY shelf_life_days DESC) AS drnk
FROM   raw_materials
ORDER  BY shelf_life_days DESC, material_name
LIMIT  10;
```

| material_name | shelf_life_days | rn | rnk | drnk |
|---|---|---|---|---|
| Коробка картонная | 1825 | 1 | 1 | 1 |
| Соль пищевая | 1825 | 2 | 1 | 1 |
| Пакет тетра-пак 1 л | 1095 | 5 | 3 | 2 |
| Стаканчик 0,3 кг с крышкой | 1095 | 3 | 3 | 2 |
| Флоу-пак плёнка | 1095 | 4 | 3 | 2 |
| Ванилин | 730 | 7 | 6 | 3 |

* `RANK` после двух «первых» даёт 3 (пропуск), `DENSE_RANK` — 2 (без пропусков).
* `ROW_NUMBER` среди равных значений раздаёт номера **произвольно** (см. «Пакет» — rn = 5).
  Для воспроизводимости добавляйте второй ключ сортировки.

## Шаг 5. Топ-N в каждой группе

Блок 2.3 `examples.sql`: 2 лучших клиента 2025 г. в каждом типе клиента (`row_number() OVER (PARTITION BY customer_type ORDER BY revenue DESC)` в CTE + `WHERE rn <= 2`).

**Ожидаемо:** 12 строк; среди дистрибьюторов — «Лотос» (13,93 млн) и «Ромашка» (13,18 млн).

**Подумайте:** «Ромашка» в базе заведена трижды (модуль 7). Какое место она заняла бы после объединения дублей?

## Шаг 6. NTILE, PERCENT_RANK, CUME_DIST

```sql
WITH q AS (
    SELECT shift,
           ntile(4) OVER (ORDER BY 1.0 * defect_qty / produced_qty) AS quartile
    FROM   production_batches
    WHERE  line_id = 3
)
SELECT quartile, count(*) AS batches,
       count(*) FILTER (WHERE shift = 'Ночь') AS night
FROM   q GROUP BY quartile ORDER BY quartile;
```

| quartile | batches | night |
|---|---|---|
| 1 | 314 | 0 |
| 2 | 314 | 1 |
| 3 | 313 | 313 |
| 4 | 313 | 313 |

Половина партий Линии 3 с худшим браком — **все** ночные. Блок 2.5: `percent_rank()` по средней скидке менеджеров —
Соколов И. А. (18,01 %) имеет `pct_rank = 1.000`.

## Шаг 7. Нарастающий итог и доля месяца

```sql
WITH m AS (
    SELECT date_trunc('month', o.order_date)::date AS month,
           sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)) AS revenue
    FROM   orders AS o JOIN order_items AS oi ON oi.order_id = o.order_id
    WHERE  o.status <> 'Отменён'
      AND  o.order_date BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'
    GROUP  BY 1
)
SELECT month,
       round(revenue / 1e6, 2)                            AS revenue_mln,
       round(sum(revenue) OVER (ORDER BY month) / 1e6, 2) AS running_mln,
       round(100 * revenue / sum(revenue) OVER (), 1)     AS share_pct
FROM   m ORDER BY month;
```

**Ожидаемо:** 12 строк; итог года — **445,11 млн**; июль — провал: 24,71 млн (5,6 % года).

## Шаг 8. Рамки ROWS / RANGE / GROUPS и ловушка рамки по умолчанию

```sql
SELECT production_date, shift, produced_qty,
       sum(produced_qty) OVER (ORDER BY production_date) AS range_default,
       sum(produced_qty) OVER (ORDER BY production_date
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS rows_frame
FROM   production_batches
WHERE  line_id = 1
  AND  production_date BETWEEN DATE '2025-03-03' AND DATE '2025-03-05'
ORDER  BY production_date, shift;
```

| production_date | shift | produced_qty | range_default | rows_frame |
|---|---|---|---|---|
| 2025-03-03 | День | 1047 | **2275** | 1047 |
| 2025-03-03 | Ночь | 1228 | 2275 | 2275 |
| 2025-03-04 | День | 942 | **4167** | 3217 |

С `ORDER BY` и без явной рамки действует `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` — все строки
с **той же датой** (пиры) входят в рамку. Нарастающий итог «скачет» сразу на две смены.

| Рамка | Единица смещения | Пример |
|---|---|---|
| `ROWS` | физические строки | `ROWS BETWEEN 6 PRECEDING AND CURRENT ROW` — 7 строк |
| `RANGE` | значение ключа сортировки | `RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW` — 7 календарных дней |
| `GROUPS` | группы пиров | `GROUPS BETWEEN 6 PRECEDING AND CURRENT ROW` — 7 различных дат |

Блок 3.4: на Линии 2 (дневная смена, март 2025) «7 календарных дней» содержат 6 партий, «7 дат» — 7 партий
(в воскресенье линия не работает).

Скользящее среднее брака за 7 смен (блок 3.2): `avg(...) OVER (ORDER BY production_date, shift ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)`.

## Шаг 9. LAG / LEAD

```sql
SELECT po.order_date, s.supplier_name, poi.unit_price,
       lag(poi.unit_price) OVER w AS prev_price,
       round(100 * (poi.unit_price / lag(poi.unit_price) OVER w - 1), 1) AS change_pct
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id      = poi.po_id
JOIN   suppliers            AS s  ON s.supplier_id = po.supplier_id
WHERE  poi.material_id = 14                                  -- молочный жир
  AND  po.order_date BETWEEN DATE '2025-01-20' AND DATE '2025-03-10'
WINDOW w AS (ORDER BY po.order_date, poi.po_item_id)
ORDER  BY po.order_date;
```

| order_date | supplier_name | unit_price | prev_price | change_pct |
|---|---|---|---|---|
| 2025-02-07 | АО "Тверское молоко" | 775.90 | 773.79 | 0.3 |
| 2025-02-14 | ООО "Масложир Юг" | **1010.28** | 775.90 | **30.2** |
| 2025-02-19 | ООО "Масложир Юг" | 988.82 | 1010.28 | −2.1 |

Первая строка окна — `NULL` в `prev_price`. Третий аргумент задаёт значение по умолчанию: `lead(order_date, 1, DATE '2025-12-31')` (блок 4.2).

**Подумайте:** в каком модуле и какой команде пригодится этот скачок цены? (Подсказка: себестоимость масла.)

## Шаг 10. FIRST_VALUE и ловушка LAST_VALUE

```sql
SELECT po.order_date, poi.unit_price,
       first_value(poi.unit_price) OVER (ORDER BY po.order_date, poi.po_item_id) AS first_price,
       last_value(poi.unit_price)  OVER (ORDER BY po.order_date, poi.po_item_id) AS last_wrong,
       last_value(poi.unit_price)  OVER (ORDER BY po.order_date, poi.po_item_id
                                         ROWS BETWEEN UNBOUNDED PRECEDING
                                                  AND UNBOUNDED FOLLOWING)   AS last_right
FROM   purchase_order_items AS poi
JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
WHERE  poi.material_id = 14
  AND  po.order_date BETWEEN DATE '2025-02-01' AND DATE '2025-02-28';
```

| order_date | unit_price | first_price | last_wrong | last_right |
|---|---|---|---|---|
| 2025-02-07 | 775.90 | 775.90 | 775.90 | 985.47 |
| 2025-02-14 | 1010.28 | 775.90 | 1010.28 | 985.47 |
| 2025-02-28 | 985.47 | 775.90 | 985.47 | 985.47 |

`last_wrong` повторяет текущую строку: рамка по умолчанию заканчивается на `CURRENT ROW`.

`NTH_VALUE(defect_qty, 2)` (блок 4.4) — вторая по величине партия брака; у Линии 3 это 217 шт.

## Шаг 11. WINDOW — именованные окна

```sql
SELECT cat_id, month,
       round(sum(revenue) OVER w_run / 1e6, 2)            AS running_mln,
       round(avg(revenue) OVER w_3m  / 1e6, 2)            AS ma3_mln,
       round(100 * (revenue / lag(revenue) OVER w - 1), 1) AS mom_pct
FROM   m
WINDOW w     AS (PARTITION BY cat_id ORDER BY month),
       w_run AS (w ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
       w_3m  AS (w ROWS BETWEEN 2 PRECEDING AND CURRENT ROW);
```

Именованное окно можно **наследовать**, добавляя рамку. Нельзя переопределить `PARTITION BY` или `ORDER BY` у наследника.

## Шаг 12. Кейс: план-факт нарастающим итогом (кондитерские изделия, 2025)

Блок 6 `examples.sql`. **Ожидаемо:**

| plan_month | plan_mln | fact_mln | ytd_completion_pct |
|---|---|---|---|
| 3 | 12.12 | 12.46 | 100.0 |
| 7 | 10.42 | 8.33 | 95.0 |
| 12 | 17.77 | 14.22 | **87.4** |

С июля выполнение плана по кондитерке нарастающим итогом падает каждый месяц.

## Типичные ошибки

| Ошибка | Симптом | Исправление |
|---|---|---|
| Оконная функция в `WHERE`/`HAVING` | `window functions are not allowed in WHERE` | CTE / подзапрос |
| Нарастающий итог без явной рамки при неуникальном ключе | «ступеньки» на одинаковых значениях | `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` + уникальный ключ |
| `LAST_VALUE` без рамки | возвращает текущую строку | `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` |
| `ROW_NUMBER` без уникального порядка | разные результаты при повторе | второй ключ сортировки (id) |
| Окно внутри агрегата `sum(x - min(x) OVER ())` | `aggregate function calls cannot contain window function calls` | окно — в CTE, агрегат — снаружи |
| `PARTITION BY` забыли | ранг/итог по всей таблице вместо группы | проверить разбиение |

## Контрольные вопросы

1. Чем оконная функция отличается от агрегатной с `GROUP BY`?
2. На каком этапе логической обработки запроса вычисляются окна? Что из этого следует?
3. Чем отличаются `RANK` и `DENSE_RANK`? Когда нужен именно `ROW_NUMBER`?
4. Какая рамка действует по умолчанию при наличии `ORDER BY`? А без него?
5. Почему `LAST_VALUE` «не работает» без явной рамки?
6. Чем `ROWS BETWEEN 6 PRECEDING` отличается от `RANGE BETWEEN INTERVAL '6 days' PRECEDING`?
