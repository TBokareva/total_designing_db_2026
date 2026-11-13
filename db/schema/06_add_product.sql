-- FOOD-104 add_product

SET search_path TO bokareva_food, exts;

CREATE OR REPLACE PROCEDURE bokareva_food.add_product(
    p_restaurant_id       uuid,
    p_product_category_id uuid,
    p_name                varchar,
    p_price               numeric,
    p_description         text           DEFAULT NULL,         -- описания может не быть
    p_status              product_status DEFAULT 'доступно',   -- новое блюдо обычно сразу в продаже
    p_photo_url           text           DEFAULT NULL,         -- фото необязательно
    p_rating              numeric        DEFAULT NULL          -- у нового блюда отзывов нет
)
LANGUAGE plpgsql
SET search_path = bokareva_food, exts
AS $$
BEGIN
    INSERT INTO product (product_name, product_category_id, price, restaurant_id,
                         photo_url, rating, status, description)
    VALUES (p_name, p_product_category_id, p_price, p_restaurant_id,
            p_photo_url, p_rating, p_status, p_description);
END;
$$;
