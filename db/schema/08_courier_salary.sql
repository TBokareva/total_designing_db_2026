-- FOOD-107 courier_salary
-- запускается в конце месяца и считает текущий месяц.
-- месяц заказа беру по order_timestamp, как и в генераторе и в how_much_money
-- если запустить второй раз - запись перезапишется, дубля не будет

SET search_path TO bokareva_food, exts;

CREATE OR REPLACE PROCEDURE bokareva_food.courier_salary()
LANGUAGE plpgsql
SET search_path = bokareva_food, exts
AS $$
DECLARE
    v_month_start date := date_trunc('month', current_date)::date;
    v_year        int  := extract(year  FROM current_date)::int;
    v_month       int  := extract(month FROM current_date)::int;
    v_rows        int;
BEGIN
    -- если за этот месяц запись уже есть, берём коэффициент из неё:
    -- после первого запуска в courier.coefficient уже лежит коэффициент на следующий месяц
    WITH stats AS (
        SELECT c.courier_id,
               c.status,
               coalesce(cp.coefficient_used, c.coefficient) AS coef_current,
               count(o.order_id)                            AS cnt,
               coalesce(sum(o.commission), 0)               AS comm
        FROM courier c
        LEFT JOIN courier_pay cp
               ON cp.courier_id = c.courier_id
              AND cp.year  = v_year
              AND cp.month = v_month
        LEFT JOIN "order" o
               ON o.courier_id = c.courier_id
              AND o.status = 'доставлен'
              AND o.order_timestamp >= v_month_start
              AND o.order_timestamp <  v_month_start + interval '1 month'
        GROUP BY c.courier_id, c.status, cp.coefficient_used, c.coefficient
    ),
    upsert AS (
        INSERT INTO courier_pay AS t (year, month, courier_id, amount, coefficient_used)
        SELECT v_year, v_month, s.courier_id,
               round(s.coef_current * s.comm, 2),
               s.coef_current
        FROM stats s
        ON CONFLICT (year, month, courier_id) DO UPDATE
            SET amount           = EXCLUDED.amount,
                coefficient_used = EXCLUDED.coefficient_used
        RETURNING t.courier_id
    )
    UPDATE courier c
    SET coefficient = CASE WHEN s.cnt <= 150 THEN 0.1
                           WHEN s.cnt <= 250 THEN 0.2
                           WHEN s.cnt <= 500 THEN 0.3
                           ELSE 0.5 END
    FROM stats s
    WHERE c.courier_id = s.courier_id
      AND s.status <> 'уволен'                 -- уволенным коэфф. не меняем
      AND EXISTS (SELECT 1 FROM upsert u WHERE u.courier_id = s.courier_id);

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RAISE NOTICE 'courier_salary: начислено за %-%, коэффициент обновлён у % работающих курьеров',
        v_year, lpad(v_month::text, 2, '0'), v_rows;
END;
$$;
