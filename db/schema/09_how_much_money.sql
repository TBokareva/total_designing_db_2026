-- FOOD-108 how_much_money
-- месяцы генерю рекурсивным cte от первого до последнего месяца с доставками,
-- чтобы пустые месяцы тоже попали в отчёт (с нулями). prev_commission через lag

SET search_path TO bokareva_food, exts;

CREATE OR REPLACE VIEW bokareva_food.how_much_money AS
WITH RECURSIVE
bounds AS (
    SELECT date_trunc('month', min(o.order_timestamp))::date AS first_month,
           date_trunc('month', max(o.order_timestamp))::date AS last_month
    FROM bokareva_food."order" o
    WHERE o.status = 'доставлен'
),
months (month_start) AS (
    SELECT b.first_month
    FROM bounds b
    WHERE b.first_month IS NOT NULL            -- если доставок нет вообще, отчёт пустой
    UNION ALL
    SELECT (m.month_start + interval '1 month')::date
    FROM months m
    CROSS JOIN bounds b
    WHERE m.month_start < b.last_month
),
orders_by_month AS (
    SELECT date_trunc('month', o.order_timestamp)::date AS month_start,
           sum(o.order_amount) AS sum_no_commission,
           sum(o.total_amount) AS sum_with_commission
    FROM bokareva_food."order" o
    WHERE o.status = 'доставлен'
    GROUP BY 1
),
pay_by_month AS (
    SELECT make_date(cp.year, cp.month, 1) AS month_start,
           sum(cp.amount) AS courier_pay
    FROM bokareva_food.courier_pay cp
    GROUP BY 1
),
base AS (
    SELECT m.month_start,
           coalesce(ob.sum_no_commission,   0)::numeric AS sum_no_commission,
           coalesce(ob.sum_with_commission, 0)::numeric AS sum_with_commission,
           coalesce(pb.courier_pay,         0)::numeric AS courier_pay
    FROM months m
    LEFT JOIN orders_by_month ob ON ob.month_start = m.month_start
    LEFT JOIN pay_by_month    pb ON pb.month_start = m.month_start
)
SELECT to_char(b.month_start, 'YYYY-MM')                          AS year_month,
       b.sum_no_commission,
       b.sum_with_commission,
       b.sum_with_commission - b.sum_no_commission                AS commission,
       lag(b.sum_with_commission - b.sum_no_commission)
           OVER (ORDER BY b.month_start)                          AS prev_commission,
       (b.sum_with_commission - b.sum_no_commission)
         - lag(b.sum_with_commission - b.sum_no_commission)
               OVER (ORDER BY b.month_start)                      AS commission_diff,
       b.courier_pay,
       (b.sum_with_commission - b.sum_no_commission) - b.courier_pay AS net_profit
FROM base b
ORDER BY b.month_start;
