-- триггеры: проверки которые не получилось сделать через fk/check + rating_change (FOOD-105)

SET search_path TO bokareva_food, exts;

-- Тексты ошибок - для того, кто работает с приложением: что не так, без номеров бизнес-правил
-- и без uuid. ERRCODE check_violation - тот же код, что у нарушения CHECK: по сути это и есть
-- проверка, которую нельзя записать через CHECK, потому что нужна другая таблица.

-- Все блюда в заказе из одного ресторана (BR-7.3).
-- Проверяю при добавлении/изменении позиции заказа: ресторан блюда = ресторан заказа.
-- Если заказа или блюда нет, EXISTS ничего не найдёт и ошибку выдаст FK.
-- Смену ресторана у самого блюда или заказа не обрабатываю: такого сценария в требованиях нет.
CREATE OR REPLACE FUNCTION bokareva_food.check_order_restaurant()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = bokareva_food, exts
AS $$
BEGIN
    IF EXISTS (SELECT 1
               FROM "order" o
               JOIN product p ON p.product_id = NEW.product_id
               WHERE o.order_id = NEW.order_id
                 AND p.restaurant_id <> o.restaurant_id) THEN
        RAISE EXCEPTION 'Блюдо из другого ресторана нельзя добавить в этот заказ'
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER order_structure_restaurant_check
    BEFORE INSERT OR UPDATE ON bokareva_food.order_structure
    FOR EACH ROW EXECUTE FUNCTION bokareva_food.check_order_restaurant();



-- Отзыв только на то, что было в заказе (BR-9.2):
-- ресторан - ресторан этого заказа
-- блюдо - блюдо из состава этого заказа
-- Отзыв на заказ проверяет CHECK review_order_entity_chk, что клиент тот же - составной FK,
-- здесь это не повторяю.
CREATE OR REPLACE FUNCTION bokareva_food.review_entity_check()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = bokareva_food, exts
AS $$
BEGIN
    IF NEW.entity_type = 'ресторан'
       AND NOT EXISTS (SELECT 1 FROM "order" o
                       WHERE o.order_id = NEW.order_id
                         AND o.restaurant_id = NEW.entity_id) THEN
        RAISE EXCEPTION 'Можно оценить только ресторан, в котором был сделан заказ'
            USING ERRCODE = 'check_violation';

    ELSIF NEW.entity_type = 'блюдо'
       AND NOT EXISTS (SELECT 1 FROM order_structure os
                       WHERE os.order_id = NEW.order_id
                         AND os.product_id = NEW.entity_id) THEN
        RAISE EXCEPTION 'Можно оценить только блюдо из этого заказа'
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER review_entity_check
    BEFORE INSERT OR UPDATE ON bokareva_food.review
    FOR EACH ROW EXECUTE FUNCTION bokareva_food.review_entity_check();



-- FOOD-105 rating_change
-- Пересчитывает рейтинг блюда или ресторана = среднее по их отзывам (BR-9.6, BR-9.7).
-- Срабатывает на INSERT, DELETE и на UPDATE только тех полей, от которых зависит рейтинг:
-- entity_type, entity_id, rating. Правка текста или фото отзыва рейтинг не трогает.
--
-- Какие объекты пересчитать:
-- INSERT - новый объект (NEW), DELETE - старый (OLD),
-- UPDATE - оба: по AC при смене entity_type / entity_id пересчитываются все затронутые сущности - у старой отзыв пропал, у новой появился.
--
-- Проверка стека (GET DIAGNOSTICS ... = PG_CONTEXT).
-- По samples п.10 insert_test_data не должна пересчитывать рейтинги через rating_change -
-- она ставит их сама одним UPDATE в конце. Но триггер срабатывает на любой INSERT в review,
-- в том числе из генератора. Поэтому триггер смотрит стек вызовов: если среди вызывающих есть
-- insert_test_data, он ничего не делает.
-- Ищу только имя с сигнатурой insert_test_data(integer)

CREATE OR REPLACE FUNCTION bokareva_food.rating_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = bokareva_food, exts
AS $$
DECLARE
    v_stack text;
BEGIN
    GET DIAGNOSTICS v_stack = PG_CONTEXT;
    IF v_stack ~ '[ .]insert_test_data\(integer\)' THEN
        RETURN NULL;
    END IF;

    UPDATE product p
    SET rating = (SELECT round(avg(r.rating), 2)
                  FROM review r
                  WHERE r.entity_type = 'блюдо'
                    AND r.entity_id   = p.product_id)
    WHERE (OLD.entity_type = 'блюдо' AND p.product_id = OLD.entity_id)
       OR (NEW.entity_type = 'блюдо' AND p.product_id = NEW.entity_id);

    UPDATE restaurant rs
    SET rating = (SELECT round(avg(r.rating), 2)
                  FROM review r
                  WHERE r.entity_type = 'ресторан'
                    AND r.entity_id   = rs.restaurant_id)
    WHERE (OLD.entity_type = 'ресторан' AND rs.restaurant_id = OLD.entity_id)
       OR (NEW.entity_type = 'ресторан' AND rs.restaurant_id = NEW.entity_id);

    RETURN NULL;   -- AFTER-триггер: возвращаемое значение не используется
END;
$$;

CREATE TRIGGER rating_change
    AFTER INSERT OR DELETE OR UPDATE OF entity_type, entity_id, rating ON bokareva_food.review
    FOR EACH ROW EXECUTE FUNCTION bokareva_food.rating_change();
