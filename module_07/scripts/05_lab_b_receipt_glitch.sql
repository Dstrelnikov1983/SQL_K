-- =====================================================================
-- Курс «Углублённый SQL». Модуль 7 — подготовка лабораторной (команда Б)
-- «Сбой интеграции со складской системой, ноябрь 2025»
-- =====================================================================
-- Легенда: при переходе на новую WMS часть ноябрьских приёмок была
-- выгружена в учётную систему ПОВТОРНО. В purchase_order_items ВАШЕЙ
-- личной схемы появляются строки-дубли (тот же заказ, тот же материал,
-- то же количество и цена, но новый po_item_id).
-- Задача лабораторной — найти и устранить ошибочные приёмки.
--
-- Скрипт меняет ТОЛЬКО личную схему. Отменить: 01_reset_data.sql.
-- Перед запуском:  SET search_path TO stud_<фамилия>, pitanie, public;
-- =====================================================================

DO $glitch$
DECLARE
    v_rows bigint;
BEGIN
    IF current_schema() IS NULL OR current_schema() IN ('pitanie', 'public') THEN
        RAISE EXCEPTION 'Текущая схема — %. Скрипт выполняется только в личной схеме', current_schema()
            USING HINT = 'SET search_path TO stud_<фамилия>, pitanie, public;';
    END IF;

    -- защита от повторного запуска: дубли уже есть
    IF EXISTS (SELECT 1
               FROM   purchase_order_items
               GROUP  BY po_id, material_id
               HAVING count(*) > 1) THEN
        RAISE NOTICE 'Дубли приёмки уже присутствуют — скрипт ничего не изменил';
        RETURN;
    END IF;

    -- po_item_id не указываем: его выдаст IDENTITY личной схемы
    INSERT INTO purchase_order_items
           (po_id, material_id, quantity, unit_price, received_qty, received_date, quality_status)
    SELECT poi.po_id, poi.material_id, poi.quantity, poi.unit_price,
           poi.received_qty, poi.received_date + 1, poi.quality_status   -- выгрузка на следующий день
    FROM   purchase_order_items AS poi
    JOIN   purchase_orders      AS po ON po.po_id = poi.po_id
    WHERE  po.order_date BETWEEN DATE '2025-11-01' AND DATE '2025-11-30'
      AND  poi.po_item_id % 5 = 0
    ORDER  BY poi.po_item_id;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RAISE NOTICE 'Смоделирован сбой: добавлено % строк-дублей приёмки', v_rows;
END
$glitch$;

SELECT count(*) AS po_items_total   -- 2328 + 18 = 2346
FROM   purchase_order_items;
