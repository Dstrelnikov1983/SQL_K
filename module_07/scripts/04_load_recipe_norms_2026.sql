-- =====================================================================
-- Курс «Углублённый SQL». Модуль 7
-- Загрузка новых норм расхода сырья 2026 г. (команда Б, источник для UPSERT)
-- Создаёт в ТЕКУЩЕЙ (личной) схеме таблицу recipe_norms_2026 и загружает в неё
-- данные файла module_07/data/recipe_norms_2026.csv
-- =====================================================================
-- Перед запуском:  SET search_path TO stud_<фамилия>, pitanie, public;
-- Повторный запуск безопасен: таблица пересоздаётся.
--
-- Почему INSERT, а не COPY: серверная команда COPY ... FROM 'файл' читает
-- файл НА СЕРВЕРЕ СУБД и требует роли pg_read_server_files — в Managed
-- Service такого доступа нет. Альтернативы (файл читается на ВАШЕМ ПК):
--   * psql (после создания таблицы этим скриптом, вместо INSERT):
--     \copy recipe_norms_2026 (line_no, product_id, material_id, qty_per_unit, change_note) FROM 'module_07/data/recipe_norms_2026.csv' WITH (FORMAT csv, HEADER true, DELIMITER ';', ENCODING 'UTF8')
--   * DBeaver: ПКМ по таблице -> Import Data -> CSV (разделитель «;», UTF-8).
-- =====================================================================

DO $guard$
BEGIN
    IF current_schema() IS NULL OR current_schema() IN ('pitanie', 'public') THEN
        RAISE EXCEPTION 'Текущая схема — %. Загрузка разрешена только в личную схему', current_schema()
            USING HINT = 'SET search_path TO stud_<фамилия>, pitanie, public;';
    END IF;
    EXECUTE format('DROP TABLE IF EXISTS %I.recipe_norms_2026', current_schema());
    EXECUTE format($ddl$
        CREATE TABLE %I.recipe_norms_2026 (
            line_no      integer       PRIMARY KEY,
            product_id   integer       NOT NULL,
            material_id  integer       NOT NULL,
            qty_per_unit numeric(12,5) NOT NULL,
            change_note  varchar(100)
        )$ddl$, current_schema());
    EXECUTE format('COMMENT ON TABLE %I.recipe_norms_2026 IS %L', current_schema(), 'Карта норм расхода 2026 г. от главного технолога (источник для UPSERT)');
END
$guard$;

INSERT INTO recipe_norms_2026
       (line_no, product_id, material_id, qty_per_unit, change_note)
VALUES
       (1, 8, 10, 0.04200, 'Снижение нормы наполнителя (новая дозировка)'),
       (2, 9, 11, 0.04200, 'Снижение нормы наполнителя (новая дозировка)'),
       (3, 23, 8, 0.01800, 'Без изменений'),
       (4, 23, 9, 0.02200, 'Без изменений'),
       (5, 12, 22, 0.00180, 'Новая плёнка тоньше'),
       (6, 18, 22, 0.00350, 'Новая плёнка тоньше'),
       (7, 13, 14, 0.15000, 'Без изменений'),
       (8, 8, 18, 0.00200, 'Новый компонент: стабилизатор'),
       (9, 9, 18, 0.00200, 'Новый компонент: стабилизатор'),
       (10, 18, 16, 0.00005, 'Новый компонент: ароматизатор'),
       (11, 24, 16, 0.00005, 'Новый компонент: ароматизатор'),
       (12, 8, 10, 0.04200, 'Снижение нормы наполнителя (новая дозировка)');

-- Контроль: 12 строк, но уникальных пар (product_id, material_id) — 11
SELECT count(*)                                  AS total_rows,
       count(DISTINCT (product_id, material_id)) AS unique_pairs
FROM   recipe_norms_2026;
