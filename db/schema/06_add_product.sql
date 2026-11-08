-- FOOD-104 add_product
-- id генерится внутри, всё остальное передаётся параметрами

SET search_path TO bokareva_food, exts;

CREATE OR REPLACE PROCEDURE bokareva_food.add_product(
    p_restaurant_id       uuid,
    p_product_category_id uuid,
    p_name                varchar,
    p_price               numeric,
    p_description         text           DEFAULT 'Описание отсутствует',
    p_status              product_status DEFAULT 'доступно',
    p_photo_url           text           DEFAULT NULL,
    p_rating              numeric        DEFAULT NULL
)
LANGUAGE plpgsql
SET search_path = bokareva_food, exts
AS $$
DECLARE
    v_product_id uuid;
BEGIN
    IF p_restaurant_id IS NULL OR p_product_category_id IS NULL
       OR p_name IS NULL OR p_price IS NULL OR p_description IS NULL OR p_status IS NULL THEN
        RAISE EXCEPTION 'add_product: ресторан, категория, название, цена, описание и статус обязательны'
            USING ERRCODE = 'not_null_violation';
    END IF;

    -- проверяю заранее, чтобы ошибка была понятная, а не текст про fk
    IF NOT EXISTS (SELECT 1 FROM restaurant WHERE restaurant_id = p_restaurant_id) THEN
        RAISE EXCEPTION 'add_product: ресторан с id % не существует', p_restaurant_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM product_category WHERE product_category_id = p_product_category_id) THEN
        RAISE EXCEPTION 'add_product: категория блюда с id % не существует', p_product_category_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    -- то же что check в таблице, но с нормальным сообщением
    IF btrim(p_name) = '' THEN
        RAISE EXCEPTION 'add_product: название блюда не может быть пустым'
            USING ERRCODE = 'check_violation';
    END IF;

    IF char_length(p_name) > 100 THEN
        RAISE EXCEPTION 'add_product: название длиннее 100 символов (%)', char_length(p_name)
            USING ERRCODE = 'string_data_right_truncation';
    END IF;

    IF p_price < 0 THEN
        RAISE EXCEPTION 'add_product: цена не может быть отрицательной (%), BR-5.3', p_price
            USING ERRCODE = 'check_violation';
    END IF;

    IF p_rating IS NOT NULL AND (p_rating < 0 OR p_rating > 5) THEN
        RAISE EXCEPTION 'add_product: рейтинг должен быть от 0 до 5 (%), BR-5.4', p_rating
            USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO product (product_id, product_name, product_category_id, price,
                         restaurant_id, photo_url, rating, status, description)
    VALUES (exts.uuid_generate_v4(), p_name, p_product_category_id, p_price,
            p_restaurant_id, p_photo_url, p_rating, p_status, p_description)
    RETURNING product_id INTO v_product_id;

    RAISE NOTICE 'add_product: блюдо «%» добавлено, product_id = %', p_name, v_product_id;
END;
$$;
