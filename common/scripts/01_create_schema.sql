-- =====================================================================
-- Курс «Углублённый SQL». Сквозной пример «Питание +»
-- Скрипт 01: создание схемы pitanie
-- СУБД: Yandex Managed Service for PostgreSQL (PostgreSQL 16)
-- =====================================================================
-- Схема содержит два блока:
--   * Продажи и финансы    (команда А): customers, orders, order_items,
--     invoices, payments, returns, sales_plan, expenses, price_history
--   * Производство и закупки (команда Б): suppliers, raw_materials, recipes,
--     production_lines, production_batches, material_consumption,
--     equipment_downtime, purchase_orders, purchase_order_items,
--     material_writeoffs
--   * Общие справочники: regions, employees, product_categories, products
-- =====================================================================

DROP SCHEMA IF EXISTS pitanie CASCADE;
CREATE SCHEMA pitanie;
COMMENT ON SCHEMA pitanie IS 'Сквозной учебный пример: компания-производитель продуктов питания «Питание +»';

SET search_path TO pitanie;

-- ---------------------------------------------------------------------
-- Общие справочники
-- ---------------------------------------------------------------------
CREATE TABLE regions (
    region_id        integer      PRIMARY KEY,
    region_name      varchar(100) NOT NULL,
    federal_district varchar(50)  NOT NULL
);
COMMENT ON TABLE regions IS 'Регионы присутствия (клиенты, поставщики)';

CREATE TABLE employees (
    employee_id integer      PRIMARY KEY,
    full_name   varchar(150) NOT NULL,
    position    varchar(100) NOT NULL,
    department  varchar(50)  NOT NULL,
    manager_id  integer      REFERENCES employees (employee_id),
    hire_date   date         NOT NULL,
    salary      numeric(12,2) NOT NULL,
    email       varchar(100),
    phone       varchar(30)
);
COMMENT ON TABLE employees IS 'Сотрудники; manager_id — непосредственный руководитель (иерархия)';

CREATE TABLE product_categories (
    category_id        integer      PRIMARY KEY,
    category_name      varchar(100) NOT NULL,
    parent_category_id integer      REFERENCES product_categories (category_id)
);
COMMENT ON TABLE product_categories IS 'Двухуровневый классификатор продукции';

CREATE TABLE products (
    product_id        integer       PRIMARY KEY,
    sku               varchar(20)   NOT NULL UNIQUE,
    product_name      varchar(150)  NOT NULL,
    category_id       integer       NOT NULL REFERENCES product_categories (category_id),
    unit              varchar(10)   NOT NULL,
    weight_kg         numeric(8,3)  NOT NULL,
    shelf_life_days   integer       NOT NULL,
    base_price        numeric(10,2) NOT NULL,
    standard_cost     numeric(10,2) NOT NULL,
    is_active         boolean       NOT NULL DEFAULT TRUE,
    launch_date       date          NOT NULL,
    discontinued_date date
);
COMMENT ON TABLE products IS 'Готовая продукция. base_price — прайс 2025 г., standard_cost — нормативная себестоимость';

-- ---------------------------------------------------------------------
-- Продажи и финансы
-- ---------------------------------------------------------------------
CREATE TABLE price_history (
    price_id   integer       PRIMARY KEY,
    product_id integer       NOT NULL REFERENCES products (product_id),
    valid_from date          NOT NULL,
    valid_to   date,
    price      numeric(10,2) NOT NULL
);
COMMENT ON TABLE price_history IS 'История прайс-листа; valid_to IS NULL — действующая цена';

CREATE TABLE customers (
    customer_id        integer       PRIMARY KEY,
    customer_name      varchar(150)  NOT NULL,
    customer_type      varchar(30)   NOT NULL,
    region_id          integer       REFERENCES regions (region_id),
    inn                varchar(12),
    phone              varchar(30),
    email              varchar(100),
    registration_date  date          NOT NULL,
    credit_limit       numeric(14,2) NOT NULL,
    payment_terms_days integer       NOT NULL,
    manager_id         integer       REFERENCES employees (employee_id)
);
COMMENT ON TABLE customers IS 'Клиенты (B2B). payment_terms_days — отсрочка платежа, дней';

CREATE TABLE orders (
    order_id      integer      PRIMARY KEY,
    order_number  varchar(20)  NOT NULL UNIQUE,
    customer_id   integer      NOT NULL REFERENCES customers (customer_id),
    employee_id   integer      NOT NULL REFERENCES employees (employee_id),
    order_date    date         NOT NULL,
    required_date date         NOT NULL,
    shipped_date  date,
    status        varchar(20)  NOT NULL,
    channel       varchar(30)  NOT NULL,
    comment       varchar(200)
);
COMMENT ON TABLE orders IS 'Заказы клиентов; employee_id — менеджер, оформивший заказ';

CREATE TABLE order_items (
    order_item_id integer       PRIMARY KEY,
    order_id      integer       NOT NULL REFERENCES orders (order_id),
    product_id    integer       NOT NULL REFERENCES products (product_id),
    quantity      integer       NOT NULL CHECK (quantity > 0),
    unit_price    numeric(10,2) NOT NULL,
    discount_pct  numeric(5,2)  NOT NULL DEFAULT 0
);
COMMENT ON TABLE order_items IS 'Позиции заказа. Сумма строки = quantity * unit_price * (1 - discount_pct/100)';

CREATE TABLE invoices (
    invoice_id     integer       PRIMARY KEY,
    order_id       integer       NOT NULL UNIQUE REFERENCES orders (order_id),
    invoice_number varchar(20)   NOT NULL,
    invoice_date   date          NOT NULL,
    due_date       date          NOT NULL,
    amount         numeric(14,2) NOT NULL
);
COMMENT ON TABLE invoices IS 'Счета на оплату (выставляются при отгрузке)';

CREATE TABLE payments (
    payment_id     integer       PRIMARY KEY,
    invoice_id     integer       NOT NULL REFERENCES invoices (invoice_id),
    payment_date   date          NOT NULL,
    amount         numeric(14,2) NOT NULL,
    payment_method varchar(30)   NOT NULL
);
COMMENT ON TABLE payments IS 'Оплаты по счетам (возможны частичные)';

CREATE TABLE returns (
    return_id   integer     PRIMARY KEY,
    order_id    integer     NOT NULL REFERENCES orders (order_id),
    product_id  integer     NOT NULL REFERENCES products (product_id),
    return_date date        NOT NULL,
    quantity    integer     NOT NULL,
    reason      varchar(50) NOT NULL
);
COMMENT ON TABLE returns IS 'Возвраты продукции от клиентов';

CREATE TABLE sales_plan (
    plan_id     integer       PRIMARY KEY,
    plan_year   integer       NOT NULL,
    plan_month  integer       NOT NULL CHECK (plan_month BETWEEN 1 AND 12),
    category_id integer       NOT NULL REFERENCES product_categories (category_id),
    plan_amount numeric(16,2) NOT NULL
);
COMMENT ON TABLE sales_plan IS 'План продаж в рублях по месяцам и категориям верхнего уровня';

CREATE TABLE expenses (
    expense_id       integer       PRIMARY KEY,
    expense_date     date          NOT NULL,
    expense_category varchar(50)   NOT NULL,
    department       varchar(50)   NOT NULL,
    sales_channel    varchar(30),
    amount           numeric(14,2) NOT NULL,
    description      varchar(200)
);
COMMENT ON TABLE expenses IS 'Операционные расходы компании';

-- ---------------------------------------------------------------------
-- Производство и закупки
-- ---------------------------------------------------------------------
CREATE TABLE suppliers (
    supplier_id        integer      PRIMARY KEY,
    supplier_name      varchar(150) NOT NULL,
    region_id          integer      REFERENCES regions (region_id),
    inn                varchar(12),
    rating             numeric(2,1),
    contract_date      date         NOT NULL,
    payment_terms_days integer      NOT NULL,
    phone              varchar(30)
);
COMMENT ON TABLE suppliers IS 'Поставщики сырья и упаковки; rating — внутренняя оценка 1..5';

CREATE TABLE raw_materials (
    material_id     integer      PRIMARY KEY,
    material_name   varchar(100) NOT NULL,
    material_group  varchar(50)  NOT NULL,
    unit            varchar(10)  NOT NULL,
    shelf_life_days integer      NOT NULL,
    min_stock       numeric(12,2) NOT NULL
);
COMMENT ON TABLE raw_materials IS 'Сырьё и упаковочные материалы';

CREATE TABLE recipes (
    recipe_id    integer        PRIMARY KEY,
    product_id   integer        NOT NULL REFERENCES products (product_id),
    material_id  integer        NOT NULL REFERENCES raw_materials (material_id),
    qty_per_unit numeric(12,5)  NOT NULL,
    UNIQUE (product_id, material_id)
);
COMMENT ON TABLE recipes IS 'Рецептура: норма расхода сырья на 1 единицу продукции';

CREATE TABLE production_lines (
    line_id           integer      PRIMARY KEY,
    line_name         varchar(100) NOT NULL,
    workshop          varchar(100) NOT NULL,
    capacity_per_hour integer      NOT NULL,
    launch_year       integer      NOT NULL,
    responsible_id    integer      REFERENCES employees (employee_id)
);
COMMENT ON TABLE production_lines IS 'Производственные линии';

CREATE TABLE production_batches (
    batch_id        integer     PRIMARY KEY,
    batch_number    varchar(20) NOT NULL,
    product_id      integer     NOT NULL REFERENCES products (product_id),
    line_id         integer     NOT NULL REFERENCES production_lines (line_id),
    production_date date        NOT NULL,
    shift           varchar(10) NOT NULL,
    planned_qty     integer     NOT NULL,
    produced_qty    integer     NOT NULL,
    defect_qty      integer     NOT NULL,
    operator_id     integer     REFERENCES employees (employee_id)
);
COMMENT ON TABLE production_batches IS 'Производственные партии (одна партия = одна смена на линии)';

CREATE TABLE material_consumption (
    consumption_id integer        PRIMARY KEY,
    batch_id       integer        NOT NULL REFERENCES production_batches (batch_id),
    material_id    integer        NOT NULL REFERENCES raw_materials (material_id),
    quantity       numeric(14,3)  NOT NULL
);
COMMENT ON TABLE material_consumption IS 'Фактический расход сырья на партию';

CREATE TABLE equipment_downtime (
    downtime_id       integer      PRIMARY KEY,
    line_id           integer      NOT NULL REFERENCES production_lines (line_id),
    start_time        timestamp    NOT NULL,
    end_time          timestamp,
    reason            varchar(100) NOT NULL,
    downtime_category varchar(50)  NOT NULL
);
COMMENT ON TABLE equipment_downtime IS 'Простои линий; end_time IS NULL — простой не закрыт';

CREATE TABLE purchase_orders (
    po_id         integer     PRIMARY KEY,
    po_number     varchar(20) NOT NULL UNIQUE,
    supplier_id   integer     NOT NULL REFERENCES suppliers (supplier_id),
    employee_id   integer     NOT NULL REFERENCES employees (employee_id),
    order_date    date        NOT NULL,
    expected_date date        NOT NULL,
    status        varchar(20) NOT NULL
);
COMMENT ON TABLE purchase_orders IS 'Заказы поставщикам; employee_id — менеджер по закупкам';

CREATE TABLE purchase_order_items (
    po_item_id     integer       PRIMARY KEY,
    po_id          integer       NOT NULL REFERENCES purchase_orders (po_id),
    material_id    integer       NOT NULL REFERENCES raw_materials (material_id),
    quantity       numeric(14,2) NOT NULL,
    unit_price     numeric(12,2) NOT NULL,
    received_qty   numeric(14,2),
    received_date  date,
    quality_status varchar(30)
);
COMMENT ON TABLE purchase_order_items IS 'Позиции заказов поставщикам и факт приёмки';

CREATE TABLE material_writeoffs (
    writeoff_id   integer       PRIMARY KEY,
    material_id   integer       NOT NULL REFERENCES raw_materials (material_id),
    writeoff_date date          NOT NULL,
    quantity      numeric(14,2) NOT NULL,
    reason        varchar(50)   NOT NULL,
    amount        numeric(14,2) NOT NULL
);
COMMENT ON TABLE material_writeoffs IS 'Списания сырья со склада (в натуральном и денежном выражении)';

-- Индексы для типичных аналитических запросов
CREATE INDEX ix_orders_customer   ON orders (customer_id);
CREATE INDEX ix_orders_date       ON orders (order_date);
CREATE INDEX ix_items_order       ON order_items (order_id);
CREATE INDEX ix_items_product     ON order_items (product_id);
CREATE INDEX ix_payments_invoice  ON payments (invoice_id);
CREATE INDEX ix_batches_date      ON production_batches (production_date);
CREATE INDEX ix_cons_batch        ON material_consumption (batch_id);
CREATE INDEX ix_poi_po            ON purchase_order_items (po_id);
