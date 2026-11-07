# Сквозной пример курса: компания «Питание +»

## Легенда

Компания **«Питание +»** производит молочную продукцию, кондитерские изделия и бакалею
и продаёт их федеральным и региональным сетям, дистрибьюторам, HoReCa и через маркетплейсы.
Руководство решило перейти к **управлению на основе данных (data-driven management)** и
пригласило группу аналитиков. Задача группы — с помощью SQL-анализа найти ситуации,
**где компания работает неэффективно и теряет деньги**, и доказать руководству пользу нового подхода.

Группа разделена на две команды:

| Команда | Направление | Основные таблицы |
|---|---|---|
| **А — «Финансы и продажи»** | выручка, скидки, клиенты, дебиторская задолженность, возвраты, расходы, план продаж | `customers`, `orders`, `order_items`, `invoices`, `payments`, `returns`, `sales_plan`, `expenses`, `price_history` |
| **Б — «Производство и закупки»** | выпуск, брак, простои, расход сырья, поставщики, цены закупок, списания | `production_lines`, `production_batches`, `material_consumption`, `recipes`, `equipment_downtime`, `suppliers`, `raw_materials`, `purchase_orders`, `purchase_order_items`, `material_writeoffs` |

Общие справочники: `regions`, `employees`, `product_categories`, `products`.

Период данных: **01.01.2024 – 31.12.2025**. Все таблицы находятся в схеме **`pitanie`**.

## Подключение к учебной БД

| Параметр | Значение |
|---|---|
| Сервер | `<адрес_сервера>` |
| Порт | `6432` |
| База | `db1` |
| Пользователь / пароль | выдаёт преподаватель |
| SSL | `verify-full`, сертификат `root.crt` (в корне репозитория) |

Рекомендуемые клиенты: **DBeaver**, pgAdmin 4, psql, расширение *SQLTools* для VS Code.

```sql
-- первая команда в каждой сессии: чтобы не писать префикс схемы
SET search_path TO pitanie, public;
```

> **Правило работы с общей БД.** Схема `pitanie` — общая и используется только для чтения.
> Для модулей, где создаются или изменяются объекты (модули 7, 9–12), каждый слушатель
> создаёт **личную схему** `stud_<фамилия>` и копирует в неё нужные таблицы
> (скрипт в `module_07/scripts/`).

## Развёртывание (для преподавателя)

```text
common/scripts/01_create_schema.sql   -- DDL схемы pitanie (DROP + CREATE)
common/scripts/02_insert_data.sql     -- данные (INSERT, ~65 тыс. строк)
common/scripts/generate_data.py       -- генератор данных (seed фиксирован)
common/scripts/run_sql.py             -- утилита выполнения SQL-файлов (python + psycopg2)
common/data/*.csv                     -- те же данные в CSV (UTF-8, разделитель «;»)
```

```bash
export PGHOST=<адрес_сервера>   # параметры выдаёт администратор стенда
export PGUSER=<логин>
export PGPASSWORD=<пароль>
python common/scripts/run_sql.py -f common/scripts/01_create_schema.sql
python common/scripts/run_sql.py -f common/scripts/02_insert_data.sql
```

Или в psql / DBeaver выполнить оба скрипта по очереди.

## Схема данных

```text
                     regions ───────────────┬───────────────────┐
                        │                   │                   │
 employees ◄─┐      customers           suppliers               │
  (manager_id)│        │  ▲                 │                   │
     ▲  ▲  ▲──┘        │  └ manager_id      │                   │
     │  │  │        orders ─── invoices ── payments        purchase_orders
     │  │  └─────── (employee_id)                              │
     │  │             │    └── returns                  purchase_order_items
     │  │        order_items                                   │
     │  │             │                                   raw_materials ── material_writeoffs
     │  │          products ◄── price_history                 │   │
     │  │          │  │  └── product_categories (parent_id)    │   │
     │  │          │  └────────── recipes ─────────────────────┘   │
     │  │          │                                              │
     │  └── production_batches ── material_consumption ───────────┘
     │            │
     └──── production_lines ── equipment_downtime

 sales_plan (год, месяц, категория верхнего уровня)    expenses (расходы)
```

## Словарь данных

### Общие справочники

**regions** — регионы.
`region_id` PK · `region_name` · `federal_district`

**employees** — сотрудники (35 чел.).
`employee_id` PK · `full_name` · `position` · `department` (Дирекция, Финансы, Продажи, Закупки, Производство) ·
`manager_id` → employees (NULL у генерального директора) · `hire_date` · `salary` · `email` (бывает NULL) · `phone` (разные форматы)

**product_categories** — двухуровневый классификатор.
`category_id` PK · `category_name` · `parent_category_id` → product_categories (NULL у верхнего уровня: 1 Молочная продукция, 2 Кондитерские изделия, 3 Бакалея)

**products** — готовая продукция (35 SKU).
`product_id` PK · `sku` · `product_name` · `category_id` → product_categories (нижний уровень) · `unit` (шт/кг) · `weight_kg` ·
`shelf_life_days` — срок годности · `base_price` — прайс 2025 г. · `standard_cost` — нормативная себестоимость (актуальная) ·
`is_active` · `launch_date` · `discontinued_date`

### Продажи и финансы (команда А)

**price_history** — история прайс-листа: `price_id` · `product_id` · `valid_from` · `valid_to` (NULL — действует) · `price`

**customers** — клиенты (73).
`customer_id` PK · `customer_name` · `customer_type` (Федеральная сеть, Региональная сеть, Дистрибьютор, HoReCa, Розница, Маркетплейс) ·
`region_id` (бывает NULL) · `inn` · `phone` · `email` (грязные данные: пробелы, регистр, NULL) · `registration_date` ·
`credit_limit` — кредитный лимит, руб. · `payment_terms_days` — отсрочка, дн. · `manager_id` → employees (закреплённый менеджер)

**orders** — заказы (~4,5 тыс.).
`order_id` PK · `order_number` · `customer_id` · `employee_id` (менеджер) · `order_date` · `required_date` ·
`shipped_date` (NULL — не отгружен) · `status` (Новый, В работе, Отгружен, Доставлен, Отменён) ·
`channel` (Прямые продажи, Дистрибуция, Маркетплейс, Тендер) · `comment` (в основном NULL)

**order_items** — позиции заказов (~17,6 тыс.).
`order_item_id` PK · `order_id` · `product_id` · `quantity` · `unit_price` · `discount_pct` — скидка, %.
Сумма строки: `quantity * unit_price * (1 - discount_pct / 100)`.
**Политика скидок компании: не более 10 %.**

**invoices** — счета (один на отгруженный заказ): `invoice_id` · `order_id` · `invoice_number` · `invoice_date` · `due_date` · `amount`

**payments** — оплаты, возможны частичные и несколько на счёт: `payment_id` · `invoice_id` · `payment_date` · `amount` · `payment_method`

**returns** — возвраты: `return_id` · `order_id` · `product_id` · `return_date` · `quantity` · `reason`

**sales_plan** — план продаж: `plan_id` · `plan_year` · `plan_month` · `category_id` (верхний уровень) · `plan_amount`

**expenses** — расходы: `expense_id` · `expense_date` · `expense_category` · `department` · `sales_channel` (NULL — не относится к каналу) · `amount` · `description`

### Производство и закупки (команда Б)

**suppliers** — поставщики (12): `supplier_id` · `supplier_name` · `region_id` · `inn` · `rating` (1–5, бывает NULL) · `contract_date` · `payment_terms_days` · `phone`

**raw_materials** — сырьё и упаковка (24): `material_id` · `material_name` · `material_group` · `unit` · `shelf_life_days` · `min_stock`

**recipes** — нормы расхода: `recipe_id` · `product_id` · `material_id` · `qty_per_unit` — норма на 1 ед. продукции

**production_lines** — линии (5): `line_id` · `line_name` · `workshop` · `capacity_per_hour` · `launch_year` · `responsible_id` → employees

**production_batches** — партии (одна смена на линии, ~6 тыс.).
`batch_id` · `batch_number` · `product_id` · `line_id` · `production_date` · `shift` (День/Ночь) ·
`planned_qty` · `produced_qty` · `defect_qty` (брак) · `operator_id` → employees

**material_consumption** — фактический расход сырья на партию (~24 тыс.): `consumption_id` · `batch_id` · `material_id` · `quantity`

**equipment_downtime** — простои: `downtime_id` · `line_id` · `start_time` · `end_time` (NULL — не закрыт) · `reason` · `downtime_category`

**purchase_orders** — заказы поставщикам (~950): `po_id` · `po_number` · `supplier_id` · `employee_id` (закупщик) · `order_date` · `expected_date` · `status`

**purchase_order_items** — позиции закупок и приёмка (~2,3 тыс.):
`po_item_id` · `po_id` · `material_id` · `quantity` · `unit_price` · `received_qty` · `received_date` · `quality_status` (Принято, Принято частично, Отклонено; NULL — не получено)

**material_writeoffs** — списания сырья: `writeoff_id` · `material_id` · `writeoff_date` · `quantity` · `reason` · `amount` (руб.)

## Полезные формулы

```sql
-- Выручка строки заказа (без отменённых заказов)
oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)

-- Валовая маржа строки
oi.quantity * (oi.unit_price * (1 - oi.discount_pct / 100) - p.standard_cost)

-- Процент брака партии
100.0 * b.defect_qty / NULLIF(b.produced_qty, 0)

-- Перерасход сырья: факт / норма
SUM(mc.quantity) / SUM(r.qty_per_unit * b.produced_qty)
```
