-- FOOD-107 courier_salary

SET search_path TO bokareva_food, exts;

CREATE OR REPLACE PROCEDURE bokareva_food.courier_salary()
LANGUAGE plpgsql
SET search_path = bokareva_food, exts
AS $$
DECLARE
    v_month_start date := date_trunc('month', current_date)::date;
BEGIN
    WITH delivered AS (
        SELECT o.courier_id,
               count(*)          AS cnt,
               sum(o.commission) AS comm
        FROM "order" o
        WHERE o.status = 'доставлен'
          AND o.order_timestamp >= v_month_start
          AND o.order_timestamp <  v_month_start + interval '1 month'
        GROUP BY o.courier_id
    ),
    stats AS (
        SELECT c.courier_id,
               c.status,
               c.coefficient,
               coalesce(d.cnt, 0)  AS cnt,
               coalesce(d.comm, 0) AS comm
        FROM courier c
        LEFT JOIN delivered d ON d.courier_id = c.courier_id
    ),
    pay AS (
        INSERT INTO courier_pay AS t (year, month, courier_id, amount, coefficient_used)
        SELECT extract(year  FROM v_month_start)::smallint,
               extract(month FROM v_month_start)::smallint,
               s.courier_id,
               round(s.coefficient * s.comm, 2),
               s.coefficient
        FROM stats s
        ON CONFLICT (year, month, courier_id) DO UPDATE
            SET amount = round(t.coefficient_used
                               * (SELECT s.comm FROM stats s WHERE s.courier_id = t.courier_id), 2)
    )
    UPDATE courier c
    SET coefficient = CASE WHEN s.cnt <= 150 THEN 0.1
                           WHEN s.cnt <= 250 THEN 0.2
                           WHEN s.cnt <= 500 THEN 0.3
                           ELSE 0.5 END
    FROM stats s
    WHERE s.courier_id = c.courier_id
      AND s.status <> 'уволен';
END;
$$;
