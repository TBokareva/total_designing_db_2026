-- FOOD-103 erase_test_data()
-- truncate сразу всем списком, так не надо думать про порядок из-за fk

SET search_path TO bokareva_food, exts;

CREATE OR REPLACE PROCEDURE bokareva_food.erase_test_data()
LANGUAGE plpgsql
SET search_path = bokareva_food, exts
AS $$
BEGIN
    TRUNCATE TABLE
        review,
        payment,
        order_structure,
        courier_pay,
        "order",
        client_address,
        product,
        restaurant,
        product_category,
        client,
        courier,
        address;

    RAISE NOTICE 'erase_test_data: все таблицы схемы bokareva_food очищены';
END;
$$;
