-- 1. Avg payment (rounded)

SELECT 
    payment_type,
    ROUND(AVG(payment_value)) AS rounded_avg_payment
FROM amazon_brazil.payments
GROUP BY payment_type
ORDER BY rounded_avg_payment ASC;


-- 2. % of orders by payment type

SELECT 
    payment_type,
    ROUND(COUNT(DISTINCT order_id) * 100.0 / 
          (SELECT COUNT(DISTINCT order_id) FROM amazon_brazil.payments), 1) 
          AS percentage_orders
FROM amazon_brazil.payments
GROUP BY payment_type
ORDER BY percentage_orders DESC;


-- 3. Products (100–500 BRL + 'Smart')

SELECT 
    product_id,
    price
FROM amazon_brazil.order_items oi
JOIN amazon_brazil.products p 
    ON oi.product_id = p.product_id
WHERE price BETWEEN 100 AND 500
AND p.product_category_name ILIKE '%smart%'
ORDER BY price DESC;


-- 4. Top 3 months by sales

SELECT 
    TO_CHAR(o.order_purchase_timestamp, 'Month') AS month,
    ROUND(SUM(p.payment_value)) AS total_sales
FROM amazon_brazil.orders o
JOIN amazon_brazil.payments p 
    ON o.order_id = p.order_id
GROUP BY month
ORDER BY total_sales DESC
LIMIT 3;


-- 5. Categories with price diff > 500

SELECT 
    p.product_category_name,
    MAX(oi.price) - MIN(oi.price) AS price_difference
FROM amazon_brazil.order_items oi
JOIN amazon_brazil.products p 
    ON oi.product_id = p.product_id
GROUP BY p.product_category_name
HAVING MAX(oi.price) - MIN(oi.price) > 500;


-- 6. Payment type with least variance

SELECT 
    payment_type,
    STDDEV(payment_value) AS std_deviation
FROM amazon_brazil.payments
GROUP BY payment_type
ORDER BY std_deviation ASC;


-- 7. Missing/invalid category

SELECT 
    product_id,
    product_category_name
FROM amazon_brazil.products
WHERE product_category_name IS NULL
   OR LENGTH(TRIM(product_category_name)) = 1;


-- ✅ ANALYSIS – II
-- 8. Order value segmentation

SELECT 
    CASE 
        WHEN payment_value < 200 THEN 'Low'
        WHEN payment_value BETWEEN 200 AND 1000 THEN 'Medium'
        ELSE 'High'
    END AS order_value_segment,
    payment_type,
    COUNT(*) AS count
FROM amazon_brazil.payments
GROUP BY order_value_segment, payment_type
ORDER BY count DESC;


-- 9. Category price stats

SELECT 
    p.product_category_name,
    MIN(oi.price) AS min_price,
    MAX(oi.price) AS max_price,
    AVG(oi.price) AS avg_price
FROM amazon_brazil.order_items oi
JOIN amazon_brazil.products p 
    ON oi.product_id = p.product_id
GROUP BY p.product_category_name
ORDER BY avg_price DESC;


-- 10. Customers with multiple orders

SELECT 
    c.customer_unique_id,
    COUNT(o.order_id) AS total_orders
FROM amazon_brazil.orders o
JOIN amazon_brazil.customers c 
    ON o.customer_id = c.customer_id
GROUP BY c.customer_unique_id
HAVING COUNT(o.order_id) > 1;


-- 11. Customer segmentation (Temp Table)

CREATE TEMP TABLE customer_orders AS
SELECT 
    c.customer_unique_id,
    COUNT(o.order_id) AS total_orders
FROM amazon_brazil.orders o
JOIN amazon_brazil.customers c 
    ON o.customer_id = c.customer_id
GROUP BY c.customer_unique_id;

SELECT 
    customer_unique_id,
    CASE 
        WHEN total_orders = 1 THEN 'New'
        WHEN total_orders BETWEEN 2 AND 4 THEN 'Returning'
        ELSE 'Loyal'
    END AS customer_type
FROM customer_orders;


-- 12. Top 5 revenue categories

SELECT 
    p.product_category_name,
    SUM(oi.price + oi.freight_value) AS total_revenue
FROM amazon_brazil.order_items oi
JOIN amazon_brazil.products p 
    ON oi.product_id = p.product_id
GROUP BY p.product_category_name
ORDER BY total_revenue DESC
LIMIT 5;


-- ✅ ANALYSIS – III
-- 13. Sales by season

SELECT 
    season,
    SUM(total_sales) AS total_sales
FROM (
    SELECT 
        CASE 
            WHEN EXTRACT(MONTH FROM o.order_purchase_timestamp) IN (3,4,5) THEN 'Spring'
            WHEN EXTRACT(MONTH FROM o.order_purchase_timestamp) IN (6,7,8) THEN 'Summer'
            WHEN EXTRACT(MONTH FROM o.order_purchase_timestamp) IN (9,10,11) THEN 'Autumn'
            ELSE 'Winter'
        END AS season,
        p.payment_value AS total_sales
    FROM amazon_brazil.orders o
    JOIN amazon_brazil.payments p 
        ON o.order_id = p.order_id
) sub
GROUP BY season;


-- 14. Products above avg quantity
SELECT 
    product_id,
    SUM(quantity) AS total_quantity_sold
FROM amazon_brazil.order_items
GROUP BY product_id
HAVING SUM(quantity) > (
    SELECT AVG(total_qty)
    FROM (
        SELECT SUM(quantity) AS total_qty
        FROM amazon_brazil.order_items
        GROUP BY product_id
    ) avg_table
);


-- 15. Monthly revenue (2018)

SELECT 
    DATE_TRUNC('month', o.order_purchase_timestamp) AS month,
    SUM(p.payment_value) AS total_revenue
FROM amazon_brazil.orders o
JOIN amazon_brazil.payments p 
    ON o.order_id = p.order_id
WHERE EXTRACT(YEAR FROM o.order_purchase_timestamp) = 2018
GROUP BY month
ORDER BY month;

-- 16. Customer segmentation (CTE)

WITH customer_counts AS (
    SELECT 
        c.customer_unique_id,
        COUNT(o.order_id) AS total_orders
    FROM amazon_brazil.orders o
    JOIN amazon_brazil.customers c 
        ON o.customer_id = c.customer_id
    GROUP BY c.customer_unique_id
)
SELECT 
    CASE 
        WHEN total_orders BETWEEN 1 AND 2 THEN 'Occasional'
        WHEN total_orders BETWEEN 3 AND 5 THEN 'Regular'
        ELSE 'Loyal'
    END AS customer_type,
    COUNT(*) AS count
FROM customer_counts
GROUP BY customer_type;

-- 17. Top 20 customers (Ranking)

SELECT 
    customer_id,
    AVG(payment_value) AS avg_order_value,
    RANK() OVER (ORDER BY AVG(payment_value) DESC) AS customer_rank
FROM amazon_brazil.orders o
JOIN amazon_brazil.payments p 
    ON o.order_id = p.order_id
GROUP BY customer_id
LIMIT 20;

-- 18. Recursive CTE (Cumulative sales)
WITH RECURSIVE sales_cte AS (
    SELECT 
        product_id,
        DATE_TRUNC('month', MIN(order_purchase_timestamp)) AS sale_month,
        SUM(price) AS total_sales
    FROM amazon_brazil.order_items oi
    JOIN amazon_brazil.orders o 
        ON oi.order_id = o.order_id
    GROUP BY product_id

    UNION ALL

    SELECT 
        s.product_id,
        s.sale_month + INTERVAL '1 month',
        s.total_sales
    FROM sales_cte s
)
SELECT * FROM sales_cte;

-- 	19. MoM growth by payment type

WITH monthly_sales AS (
    SELECT 
        payment_type,
        DATE_TRUNC('month', o.order_purchase_timestamp) AS sale_month,
        SUM(payment_value) AS monthly_total
    FROM amazon_brazil.orders o
    JOIN amazon_brazil.payments p 
        ON o.order_id = p.order_id
    WHERE EXTRACT(YEAR FROM o.order_purchase_timestamp) = 2018
    GROUP BY payment_type, sale_month
)
SELECT 
    payment_type,
    sale_month,
    monthly_total,
    ROUND(
        (monthly_total - LAG(monthly_total) OVER (PARTITION BY payment_type ORDER BY sale_month))
        * 100.0 /
        LAG(monthly_total) OVER (PARTITION BY payment_type ORDER BY sale_month),
        2
    ) AS monthly_change
FROM monthly_sales;