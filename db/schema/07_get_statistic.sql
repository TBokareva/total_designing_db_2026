-- FOOD-106 get_statistic
-- order читаю один раз (cte delivered), дальше всё считается от него.
-- лучшее блюдо/клиента беру через distinct on - без оконных функций.
-- при равенстве выбирается случайный за счёт random() в сортировке

SET search_path TO bokareva_food, exts;

CREATE OR REPLACE FUNCTION bokareva_food.get_statistic()
RETURNS TABLE (
    restaurant_name   varchar,
    best_product_name varchar,
    total_amount      numeric,
    avg_amount        numeric,
    best_user         varchar
)
LANGUAGE sql
STABLE
SET search_path = bokareva_food, exts
AS $$
    WITH delivered AS MATERIALIZED (
        SELECT o.order_id, o.restaurant_id, o.client_id, o.total_amount
        FROM "order" o
        WHERE o.status = 'доставлен'
    ),
    amounts AS (
        SELECT d.restaurant_id,
               sum(d.total_amount)           AS total_amount,
               round(avg(d.total_amount), 2) AS avg_amount
        FROM delivered d
        GROUP BY d.restaurant_id
    ),
    best_product AS (   -- что чаще всего берут
        SELECT DISTINCT ON (d.restaurant_id)
               d.restaurant_id, p.product_name
        FROM delivered d
        JOIN order_structure os ON os.order_id   = d.order_id
        JOIN product p          ON p.product_id  = os.product_id
        GROUP BY d.restaurant_id, p.product_id, p.product_name
        ORDER BY d.restaurant_id, sum(os.quantity) DESC, random()
    ),
    best_client AS (    -- кто чаще всего заказывает. фио у клиента нет, поэтому логин
        SELECT DISTINCT ON (d.restaurant_id)
               d.restaurant_id, c.login
        FROM delivered d
        JOIN client c ON c.client_id = d.client_id
        GROUP BY d.restaurant_id, c.client_id, c.login
        ORDER BY d.restaurant_id, count(*) DESC, random()
    )
    SELECT r.restaurant_name,
           bp.product_name,
           coalesce(a.total_amount, 0),
           coalesce(a.avg_amount, 0),
           bc.login
    FROM restaurant r
    LEFT JOIN amounts      a  ON a.restaurant_id  = r.restaurant_id
    LEFT JOIN best_product bp ON bp.restaurant_id = r.restaurant_id
    LEFT JOIN best_client  bc ON bc.restaurant_id = r.restaurant_id
    ORDER BY coalesce(a.total_amount, 0) DESC, r.restaurant_name;
$$;
