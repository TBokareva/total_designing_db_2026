-- FOOD-106 get_statistic

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
    WITH delivered AS (
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
    product_qty AS (    -- сколько куплено каждого блюда
        SELECT d.restaurant_id, os.product_id, sum(os.quantity) AS qty
        FROM delivered d
        JOIN order_structure os ON os.order_id = d.order_id
        GROUP BY d.restaurant_id, os.product_id
    ),
    best_product AS (
        SELECT pq.restaurant_id,
               (array_agg(p.product_name ORDER BY random()))[1] AS product_name
        FROM product_qty pq
        JOIN (SELECT restaurant_id, max(qty) AS max_qty
              FROM product_qty
              GROUP BY restaurant_id) m
          ON m.restaurant_id = pq.restaurant_id
         AND m.max_qty       = pq.qty
        JOIN product p ON p.product_id = pq.product_id
        GROUP BY pq.restaurant_id
    ),
    client_cnt AS (     -- сколько доставленных заказов у каждого клиента
        SELECT d.restaurant_id, d.client_id, count(*) AS cnt
        FROM delivered d
        GROUP BY d.restaurant_id, d.client_id
    ),
    best_client AS (
        SELECT cc.restaurant_id,
               (array_agg(c.login ORDER BY random()))[1] AS login
        FROM client_cnt cc
        JOIN (SELECT restaurant_id, max(cnt) AS max_cnt
              FROM client_cnt
              GROUP BY restaurant_id) m
          ON m.restaurant_id = cc.restaurant_id
         AND m.max_cnt       = cc.cnt
        JOIN client c ON c.client_id = cc.client_id
        GROUP BY cc.restaurant_id
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
