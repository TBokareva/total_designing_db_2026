-- триггеры: проверки которые не получилось сделать через fk/check + rating_change (FOOD-105)

SET search_path TO bokareva_food, exts;

-- BR-7.3 все блюда в заказе из одного ресторана
-- одна функция на три таблицы. order_structure проверяем при вставке позиции,
-- а product и order - если вдруг поменяют ресторан задним числом
CREATE OR REPLACE FUNCTION bokareva_food.check_order_restaurant()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = bokareva_food, exts
AS $$
DECLARE
    v_order_restaurant   uuid;
    v_product_restaurant uuid;
BEGIN
    IF TG_TABLE_NAME = 'order_structure' THEN
        SELECT o.restaurant_id INTO v_order_restaurant
        FROM "order" o WHERE o.order_id = NEW.order_id;

        SELECT p.restaurant_id INTO v_product_restaurant
        FROM product p WHERE p.product_id = NEW.product_id;

        -- если заказа или блюда вообще нет - пусть ругается fk
        IF v_order_restaurant IS DISTINCT FROM v_product_restaurant
           AND v_order_restaurant IS NOT NULL AND v_product_restaurant IS NOT NULL THEN
            RAISE EXCEPTION 'BR-7.3: блюдо % принадлежит ресторану %, а заказ % — ресторану %',
                NEW.product_id, v_product_restaurant, NEW.order_id, v_order_restaurant
                USING ERRCODE = 'check_violation';
        END IF;

    ELSIF TG_TABLE_NAME = 'product' THEN
        IF EXISTS (SELECT 1 FROM order_structure os WHERE os.product_id = NEW.product_id) THEN
            RAISE EXCEPTION 'BR-7.3: нельзя сменить ресторан у блюда %, оно уже есть в заказах',
                NEW.product_id USING ERRCODE = 'check_violation';
        END IF;

    ELSIF TG_TABLE_NAME = 'order' THEN
        IF EXISTS (SELECT 1 FROM order_structure os WHERE os.order_id = NEW.order_id) THEN
            RAISE EXCEPTION 'BR-7.3: нельзя сменить ресторан у заказа %, в нём уже есть позиции',
                NEW.order_id USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER order_structure_restaurant_check
    BEFORE INSERT OR UPDATE ON bokareva_food.order_structure
    FOR EACH ROW EXECUTE FUNCTION bokareva_food.check_order_restaurant();

CREATE TRIGGER product_restaurant_change_check
    BEFORE UPDATE OF restaurant_id ON bokareva_food.product
    FOR EACH ROW WHEN (OLD.restaurant_id IS DISTINCT FROM NEW.restaurant_id)
    EXECUTE FUNCTION bokareva_food.check_order_restaurant();

CREATE TRIGGER order_restaurant_change_check
    BEFORE UPDATE OF restaurant_id ON bokareva_food."order"
    FOR EACH ROW WHEN (OLD.restaurant_id IS DISTINCT FROM NEW.restaurant_id)
    EXECUTE FUNCTION bokareva_food.check_order_restaurant();



-- проверка review.entity_id (BR-9.2) - оценить можно только то что было в заказе:
--   этот заказ (тоже самое есть в check, тут просто сообщение понятнее)
--   ресторан этого заказа
--   блюдо из состава заказа
-- что клиент тот же самый - проверяет составной fk, тут не дублирую
CREATE OR REPLACE FUNCTION bokareva_food.review_entity_check()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = bokareva_food, exts
AS $$
BEGIN
    IF NEW.entity_type = 'заказ' THEN
        IF NEW.entity_id <> NEW.order_id THEN
            RAISE EXCEPTION 'BR-9.2: отзыв на заказ должен ссылаться на свой заказ % (получено %)',
                NEW.order_id, NEW.entity_id USING ERRCODE = 'check_violation';
        END IF;

    ELSIF NEW.entity_type = 'ресторан' THEN
        IF NOT EXISTS (SELECT 1 FROM "order" o
                       WHERE o.order_id = NEW.order_id
                         AND o.restaurant_id = NEW.entity_id) THEN
            RAISE EXCEPTION 'BR-9.2: ресторан % не является рестораном заказа %',
                NEW.entity_id, NEW.order_id USING ERRCODE = 'check_violation';
        END IF;

    ELSIF NEW.entity_type = 'блюдо' THEN
        IF NOT EXISTS (SELECT 1 FROM order_structure os
                       WHERE os.order_id = NEW.order_id
                         AND os.product_id = NEW.entity_id) THEN
            RAISE EXCEPTION 'BR-9.2: блюда % нет в заказе %',
                NEW.entity_id, NEW.order_id USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER review_entity_check
    BEFORE INSERT OR UPDATE ON bokareva_food.review
    FOR EACH ROW EXECUTE FUNCTION bokareva_food.review_entity_check();



-- FOOD-105 rating_change
-- после insert/update/delete в review пересчитываем рейтинг блюда или ресторана.
-- при update пересчитываю и старую и новую сущность - вдруг отзыв перекинули на другое блюдо.
-- у заказа рейтинга нет, его пропускаем. avg по пустому = NULL, так что
-- если отзывы удалили, рейтинг сам станет NULL
--
-- в insert_test_data триггер не нужен (samples, п.10) - там рейтинги ставятся одним update в конце.
-- сначала делала через set_config флаг, но его может включить кто угодно,
-- поэтому теперь смотрю стек вызовов: если нас вызвал insert_test_data - выходим

CREATE OR REPLACE FUNCTION bokareva_food.rating_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = bokareva_food, exts
AS $$
DECLARE
    -- что пересчитать: тип + id
    v_types bokareva_food.review_entity_type[] := '{}';
    v_ids   uuid[] := '{}';
    i       int;
    v_stack text;
BEGIN
    GET DIAGNOSTICS v_stack = PG_CONTEXT;
    IF v_stack ~ 'PL/pgSQL function (bokareva_food\.)?insert_test_data\(integer\)' THEN
        RETURN NULL;
    END IF;

    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_types := v_types || OLD.entity_type;
        v_ids   := v_ids   || OLD.entity_id;
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_types := v_types || NEW.entity_type;
        v_ids   := v_ids   || NEW.entity_id;
    END IF;

    FOR i IN 1 .. coalesce(array_length(v_ids, 1), 0) LOOP
        IF v_types[i] = 'блюдо' THEN
            UPDATE product p
            SET rating = (SELECT round(avg(r.rating), 2)
                          FROM review r
                          WHERE r.entity_type = 'блюдо'
                            AND r.entity_id   = p.product_id)
            WHERE p.product_id = v_ids[i];

        ELSIF v_types[i] = 'ресторан' THEN
            UPDATE restaurant rs
            SET rating = (SELECT round(avg(r.rating), 2)
                          FROM review r
                          WHERE r.entity_type = 'ресторан'
                            AND r.entity_id   = rs.restaurant_id)
            WHERE rs.restaurant_id = v_ids[i];
        END IF;
    END LOOP;

    RETURN NULL;
END;
$$;

CREATE TRIGGER rating_change
    AFTER INSERT OR UPDATE OR DELETE ON bokareva_food.review
    FOR EACH ROW EXECUTE FUNCTION bokareva_food.rating_change();
