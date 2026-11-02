/*==========================================================================
  Amazon Marketplace Analysis - SQL Server (T-SQL)
  Environment : SQL Server (Docker) + VS Code (mssql extension)
  Contents    : database + tables, CSV import, 17 business questions,
                stored procedure (add_sales)
  Notes       : comments marked "SQL Server:" point out syntax that differs
                from PostgreSQL / MySQL
==========================================================================*/


---- Step 1 : Create database and tables

USE master;
GO
IF DB_ID('amazon_db') IS NULL CREATE DATABASE amazon_db;
GO
USE amazon_db;
GO

-- children first, parents last (foreign keys)
DROP TABLE IF EXISTS inventory, shipping, payments, order_items, orders, products, sellers, customers, category;

CREATE TABLE category (
    category_id   INT PRIMARY KEY,
    category_name VARCHAR(50)
);

CREATE TABLE customers (
    customer_id INT PRIMARY KEY,
    first_name  VARCHAR(50),
    last_name   VARCHAR(50),
    state       VARCHAR(50)
);

CREATE TABLE sellers (
    seller_id   INT PRIMARY KEY,
    seller_name VARCHAR(50),
    origin      VARCHAR(50)
);

CREATE TABLE products (
    product_id   INT PRIMARY KEY,
    product_name VARCHAR(50),
    price        DECIMAL(10,2),
    cogs         DECIMAL(10,2),
    category_id  INT,
    CONSTRAINT products_fk_category FOREIGN KEY (category_id) REFERENCES category(category_id)
);

CREATE TABLE orders (
    order_id     INT PRIMARY KEY,
    order_date   DATE,
    customer_id  INT,
    seller_id    INT,
    order_status VARCHAR(50),
    CONSTRAINT orders_fk_customers FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CONSTRAINT orders_fk_sellers   FOREIGN KEY (seller_id)   REFERENCES sellers(seller_id)
);

CREATE TABLE order_items (
    order_item_id  INT PRIMARY KEY,
    order_id       INT,
    product_id     INT,
    quantity       INT,
    price_per_unit DECIMAL(10,2),
    CONSTRAINT order_items_fk_orders   FOREIGN KEY (order_id)   REFERENCES orders(order_id),
    CONSTRAINT order_items_fk_products FOREIGN KEY (product_id) REFERENCES products(product_id)
);

CREATE TABLE payments (
    payment_id     INT PRIMARY KEY,
    order_id       INT,
    payment_date   DATE,
    payment_status VARCHAR(50),
    CONSTRAINT payments_fk_orders FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

CREATE TABLE shipping (
    shipping_id        INT PRIMARY KEY,
    order_id           INT,
    shipping_date      DATE,
    return_date        DATE,
    shipping_providers VARCHAR(50),
    delivery_status    VARCHAR(50),
    CONSTRAINT shippings_fk_orders FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

CREATE TABLE inventory (
    inventory_id    INT PRIMARY KEY,
    product_id      INT,
    stock           INT,
    warehouse_id    INT,
    last_stock_date DATE,
    CONSTRAINT inventory_fk_products FOREIGN KEY (product_id) REFERENCES products(product_id)
);
GO


---- Step 2 : Import CSV files into tables
---- SQL Server runs in Docker, so copy the CSV folder into the container first:
---- docker cp ~/Desktop/amazon sql_server_container:/tmp/amazon
---- Tables are loaded parents first, children last

BULK INSERT category
FROM '/tmp/amazon/category.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a');

BULK INSERT customers
FROM '/tmp/amazon/customers.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a');

BULK INSERT sellers
FROM '/tmp/amazon/sellers.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a');

BULK INSERT products
FROM '/tmp/amazon/products.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a');

BULK INSERT orders
FROM '/tmp/amazon/orders.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a');

BULK INSERT order_items
FROM '/tmp/amazon/order_items.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a');

BULK INSERT payments
FROM '/tmp/amazon/payments.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a');

BULK INSERT shipping
FROM '/tmp/amazon/shipping.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a');

BULK INSERT inventory
FROM '/tmp/amazon/inventory.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a');


---- Step 3 : Check row counts
---- Expected: 6 / 898 / 54 / 765 / 21629 / 21629 / 21629 / 21141 / 765

SELECT 'category'    AS table_name, COUNT(*) AS nb_rows FROM category    UNION ALL
SELECT 'customers',   COUNT(*) FROM customers   UNION ALL
SELECT 'sellers',     COUNT(*) FROM sellers     UNION ALL
SELECT 'products',    COUNT(*) FROM products    UNION ALL
SELECT 'orders',      COUNT(*) FROM orders      UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items UNION ALL
SELECT 'payments',    COUNT(*) FROM payments    UNION ALL
SELECT 'shipping',    COUNT(*) FROM shipping    UNION ALL
SELECT 'inventory',   COUNT(*) FROM inventory;


---- Step 4 : Q1 - Top selling products
---- Top 10 products by total sales value (name, total quantity sold, total sales)

-- Add total_sale column (quantity * price_per_unit)
ALTER TABLE order_items
ADD total_sale AS (quantity * price_per_unit);
GO

SELECT TOP 10
    p.product_name,
    SUM(oi.quantity)   AS total_quantity,
    SUM(oi.total_sale) AS total_sale
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
GROUP BY p.product_id, p.product_name  -- SQL Server: every non-aggregated column must be listed (PostgreSQL accepts the id alone)
ORDER BY total_sale DESC;


---- Step 5 : Q2 - Revenue by category
---- Total revenue per category and its percentage contribution to overall revenue

SELECT
    p.category_id,
    c.category_name,
    CAST(SUM(oi.total_sale) AS DECIMAL(12,0)) AS total_sale,  -- CAST controls the displayed decimals (ROUND would keep 6 in SQL Server)
    CAST(SUM(oi.total_sale) * 100.0 / (SELECT SUM(total_sale) FROM order_items) AS DECIMAL(5,2)) AS percentage_contribution  -- 100.0 avoids integer division
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
LEFT JOIN category c ON c.category_id = p.category_id
GROUP BY p.category_id, c.category_name
ORDER BY SUM(oi.total_sale) DESC;


---- Step 6 : Q3 - Average order value (AOV)
---- Average order value per customer, only customers with more than 5 orders

SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS full_name,
    COUNT(DISTINCT o.order_id) AS total_orders,
    CAST(SUM(oi.total_sale) / COUNT(DISTINCT o.order_id) AS DECIMAL(10,2)) AS average_order_value
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY c.customer_id, c.first_name, c.last_name  -- SQL Server: first_name and last_name must be listed too (PostgreSQL accepts the id alone)
HAVING COUNT(DISTINCT o.order_id) > 5
ORDER BY average_order_value DESC;


---- Step 7 : Q4 - Monthly sales trend
---- Monthly total sales over the past year of data, with current month and previous month sales

WITH monthly_sales AS (
    SELECT
        YEAR(o.order_date)  AS order_year,   -- SQL Server: YEAR()/MONTH() instead of EXTRACT()
        MONTH(o.order_date) AS order_month,
        CAST(SUM(oi.total_sale) AS DECIMAL(12,2)) AS total_sale
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.order_date >= DATEADD(YEAR, -1, (SELECT MAX(order_date) FROM orders))  -- DATEADD instead of INTERVAL; data ends 2024-07-30, so MAX replaces CURRENT_DATE
    GROUP BY YEAR(o.order_date), MONTH(o.order_date)
    -- SQL Server: no ORDER BY allowed inside a CTE
)
SELECT
    order_year,
    order_month,
    total_sale AS current_month_sale,
    LAG(total_sale, 1) OVER (ORDER BY order_year, order_month) AS last_month_sale  -- previous row's value, NULL for the first month
FROM monthly_sales
ORDER BY order_year, order_month;


---- Step 8 : Q5 - Customers with no purchases
---- Registered customers who never placed an order

SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS full_name,
    c.state
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
WHERE o.order_id IS NULL;  -- no matching order = never purchased


---- Step 9 : Q6 - Best-selling category by state
---- Top category per state with its total sales in that state

WITH ranked_sales AS (
    SELECT
        c.state,
        cat.category_name,
        SUM(oi.total_sale) AS total_sale,
        RANK() OVER (PARTITION BY c.state ORDER BY SUM(oi.total_sale) DESC) AS sales_rank  -- 1 = best category in the state
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN products p ON p.product_id = oi.product_id
    JOIN category cat ON cat.category_id = p.category_id
    GROUP BY c.state, cat.category_name
)
SELECT
    state,
    category_name,
    CAST(total_sale AS DECIMAL(12,2)) AS total_sale
FROM ranked_sales
WHERE sales_rank = 1
ORDER BY state;


---- Step 10 : Q7 - Customer lifetime value (CLTV)
---- Total value of orders per customer over their lifetime, ranked from highest to lowest

SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS full_name,
    CAST(SUM(oi.total_sale) AS DECIMAL(12,2)) AS cltv,
    DENSE_RANK() OVER (ORDER BY SUM(oi.total_sale) DESC) AS customer_ranking  -- tied customers share a rank, no gaps
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY c.customer_id, c.first_name, c.last_name  -- SQL Server: all non-aggregated columns must be listed
ORDER BY customer_ranking;


---- Step 11 : Q8 - Inventory stock alerts
---- Products with stock below 10 units, with last restock date and warehouse

SELECT
    i.inventory_id,
    p.product_name,
    i.stock AS current_stock_left,
    i.last_stock_date,
    i.warehouse_id
FROM inventory i
JOIN products p ON p.product_id = i.product_id
WHERE i.stock < 10
ORDER BY i.stock;


---- Step 12 : Q9 - Shipping delays
---- Orders shipped more than 2 days after the order date, with customer, order details and shipping provider

SELECT
    CONCAT(c.first_name, ' ', c.last_name) AS customer,
    o.*,
    s.shipping_providers,
    DATEDIFF(DAY, o.order_date, s.shipping_date) AS days_to_ship  -- SQL Server: dates can't be subtracted directly, DATEDIFF is used (PostgreSQL: shipping_date - order_date)
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN shipping s ON s.order_id = o.order_id
WHERE DATEDIFF(DAY, o.order_date, s.shipping_date) > 2;


---- Step 13 : Q10 - Payment success rate
---- Percentage of each payment status across all payments

SELECT
    RTRIM(payment_status) AS payment_status,  -- some statuses have a trailing space in the data (e.g. 'Refunded ')
    COUNT(*) AS total_payments,
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS percentage  -- 100.0 avoids integer division (SQL Server divides integers as integers)
FROM payments
GROUP BY RTRIM(payment_status)
ORDER BY COUNT(*) DESC;


---- Step 14 : Q11 - Top performing sellers
---- Top 5 sellers by total sales, with completed / failed orders and success percentage

WITH top_sellers AS (
    -- top 5 sellers by total sales value
    SELECT TOP 5  -- SQL Server: TOP replaces LIMIT (an ORDER BY inside a CTE is only allowed with TOP)
        s.seller_id,
        s.seller_name,
        SUM(oi.total_sale) AS total_sale
    FROM orders o
    JOIN sellers s ON s.seller_id = o.seller_id
    JOIN order_items oi ON oi.order_id = o.order_id
    GROUP BY s.seller_id, s.seller_name
    ORDER BY SUM(oi.total_sale) DESC
),
sellers_order_status AS (
    -- number of orders per seller and per status
    SELECT
        seller_id,
        order_status,
        COUNT(*) AS total_orders
    FROM orders
    GROUP BY seller_id, order_status
),
sellers_report AS (
    -- keep top sellers only, and ignore orders still in progress or returned
    SELECT
        ts.seller_id,
        ts.seller_name,
        sos.order_status,
        sos.total_orders
    FROM sellers_order_status sos
    JOIN top_sellers ts ON ts.seller_id = sos.seller_id
    WHERE sos.order_status NOT IN ('Inprogress', 'Returned')
)
SELECT
    seller_id,
    seller_name,
    SUM(CASE WHEN order_status = 'Completed' THEN total_orders ELSE 0 END) AS completed_orders,
    SUM(CASE WHEN order_status = 'Cancelled' THEN total_orders ELSE 0 END) AS failed_orders,
    SUM(total_orders) AS total_orders,
    CAST(SUM(CASE WHEN order_status = 'Completed' THEN total_orders ELSE 0 END) * 100.0 / SUM(total_orders) AS DECIMAL(5,2)) AS successful_orders_percentage,  -- 100.0 avoids integer division
    CAST(SUM(CASE WHEN order_status = 'Cancelled' THEN total_orders ELSE 0 END) * 100.0 / SUM(total_orders) AS DECIMAL(5,2)) AS failed_orders_percentage
FROM sellers_report
GROUP BY seller_id, seller_name;


---- Step 15 : Q12 - Product profit margin
---- Profit margin (%) of each product, ranked from highest to lowest

SELECT
    product_id,
    product_name,
    profit_margin,
    DENSE_RANK() OVER (ORDER BY profit_margin DESC) AS product_ranking
FROM (
    SELECT
        p.product_id,
        p.product_name,
        CAST(SUM(oi.total_sale - p.cogs * oi.quantity) * 100.0 / SUM(oi.total_sale) AS DECIMAL(5,2)) AS profit_margin
    FROM order_items oi
    JOIN products p ON p.product_id = oi.product_id
    GROUP BY p.product_id, p.product_name
) AS product_margins  -- SQL Server: a subquery in FROM must have an alias
ORDER BY product_ranking;


---- Step 16 : Q13 - Most returned products
---- Top 10 products by number of returns, with return rate as a percentage of units sold

SELECT TOP 10
    product_id,
    product_name,
    total_units_sold,
    total_returned,
    CAST(total_returned * 100.0 / total_units_sold AS DECIMAL(5,2)) AS return_percentage  -- 100.0 avoids integer division
FROM (
    SELECT
        p.product_id,
        p.product_name,
        COUNT(*) AS total_units_sold,
        SUM(CASE WHEN o.order_status = 'Returned' THEN 1 ELSE 0 END) AS total_returned
    FROM order_items oi
    JOIN products p ON p.product_id = oi.product_id
    JOIN orders o ON o.order_id = oi.order_id
    GROUP BY p.product_id, p.product_name
) AS product_returns  -- SQL Server: subquery in FROM needs an alias
ORDER BY total_returned DESC, return_percentage DESC;


---- Step 17 : Q14 - Returning vs new customers
---- Customers with more than 5 returns are 'Returning', otherwise 'New'

SELECT
    customer_id,
    full_name,
    total_orders,
    total_returns,
    CASE WHEN total_returns > 5 THEN 'Returning' ELSE 'New' END AS customer_type
FROM (
    SELECT
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name) AS full_name,
        COUNT(o.order_id) AS total_orders,
        SUM(CASE WHEN o.order_status = 'Returned' THEN 1 ELSE 0 END) AS total_returns
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    GROUP BY c.customer_id, c.first_name, c.last_name  -- grouped by id: several customers share the same name
) AS customer_returns  -- SQL Server: subquery in FROM needs an alias
ORDER BY total_returns DESC;


---- Step 18 : Q15 - Top 5 customers by orders in each state
---- Top 5 customers with the most orders per state, with their number of orders and total sales

SELECT
    state,
    customer_id,
    full_name,
    total_orders,
    total_sale,
    customer_rank
FROM (
    SELECT
        c.state,
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name) AS full_name,
        COUNT(DISTINCT o.order_id) AS total_orders,
        CAST(SUM(oi.total_sale) AS DECIMAL(12,2)) AS total_sale,
        DENSE_RANK() OVER (PARTITION BY c.state ORDER BY COUNT(DISTINCT o.order_id) DESC) AS customer_rank  -- rank restarts at 1 in each state; ties share a rank, so a state can show more than 5 rows
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN customers c ON c.customer_id = o.customer_id
    GROUP BY c.state, c.customer_id, c.first_name, c.last_name  -- SQL Server: all non-aggregated columns must be listed
) AS ranked_customers  -- SQL Server: subquery in FROM needs an alias
WHERE customer_rank <= 5
ORDER BY state, customer_rank;


---- Step 19 : Q16 - Revenue by shipping provider
---- Revenue handled by each shipping provider, with orders handled and average days between shipping and return

SELECT
    s.shipping_providers,
    COUNT(DISTINCT o.order_id) AS orders_handled,
    CAST(SUM(oi.total_sale) AS DECIMAL(12,0)) AS total_sale,
    -- AVG of integers returns an integer in SQL Server, so CAST to FLOAT first; DATEDIFF replaces (return_date - shipping_date)
    -- note: this measures shipping -> return, and only returned orders have a return_date (others are NULL, ignored by AVG)
    CAST(COALESCE(AVG(CAST(DATEDIFF(DAY, s.shipping_date, s.return_date) AS FLOAT)), 0) AS DECIMAL(5,1)) AS average_days
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN shipping s ON s.order_id = o.order_id
GROUP BY s.shipping_providers
ORDER BY total_sale DESC;


---- Step 20 : Q17 - Products with the biggest revenue decline (2023 vs 2024)
---- Top 10 products with the highest decrease ratio: ratio = (revenue_2024 - revenue_2023) / revenue_2023 * 100

WITH last_year_sale AS (
    -- revenue per product in 2023
    SELECT
        p.product_id,
        p.product_name,
        p.category_id,
        SUM(oi.total_sale) AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE YEAR(o.order_date) = 2023  -- SQL Server: YEAR() replaces EXTRACT(YEAR FROM ...)
    GROUP BY p.product_id, p.product_name, p.category_id
),
current_year_sale AS (
    -- revenue per product in 2024 (data ends 2024-07-30, so this year is partial)
    SELECT
        p.product_id,
        p.product_name,
        p.category_id,
        SUM(oi.total_sale) AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE YEAR(o.order_date) = 2024
    GROUP BY p.product_id, p.product_name, p.category_id
)
SELECT TOP 10
    cs.product_id,
    cs.product_name,
    cat.category_name,
    CAST(ls.revenue AS DECIMAL(12,2)) AS last_year_revenue,
    CAST(cs.revenue AS DECIMAL(12,2)) AS current_year_revenue,
    CAST(ls.revenue - cs.revenue AS DECIMAL(12,2)) AS rev_difference,
    CAST((cs.revenue - ls.revenue) * 100.0 / ls.revenue AS DECIMAL(6,2)) AS revenue_decrease_ratio
FROM last_year_sale ls
JOIN current_year_sale cs ON cs.product_id = ls.product_id
JOIN category cat ON cat.category_id = cs.category_id
WHERE ls.revenue > cs.revenue
ORDER BY revenue_decrease_ratio ASC;  -- ratio is negative: ASC puts the biggest drops first (DESC would show the smallest)


---- Step 21 : Stored procedure - add_sales
---- Records a sale (order + order item) if stock is sufficient, then reduces the inventory by the quantity sold

GO  -- SQL Server: CREATE PROCEDURE must be the first statement of its batch
CREATE OR ALTER PROCEDURE add_sales  -- SQL Server: T-SQL instead of PL/pgSQL, parameters start with @
    @p_order_id      INT,
    @p_customer_id   INT,
    @p_seller_id     INT,
    @p_order_item_id INT,
    @p_product_id    INT,
    @p_quantity      INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @v_count        INT;
    DECLARE @v_price        DECIMAL(10,2);
    DECLARE @v_product_name VARCHAR(50);

    -- get price and name of the product
    SELECT @v_price = price, @v_product_name = product_name
    FROM products
    WHERE product_id = @p_product_id;

    -- check if there is enough stock
    SELECT @v_count = COUNT(*)
    FROM inventory
    WHERE product_id = @p_product_id AND stock >= @p_quantity;

    IF @v_count > 0
    BEGIN
        -- new order
        INSERT INTO orders (order_id, order_date, customer_id, seller_id)
        VALUES (@p_order_id, CAST(GETDATE() AS DATE), @p_customer_id, @p_seller_id);  -- GETDATE() replaces CURRENT_DATE

        -- new order item (total_sale is a computed column, so it is not inserted)
        INSERT INTO order_items (order_item_id, order_id, product_id, quantity, price_per_unit)
        VALUES (@p_order_item_id, @p_order_id, @p_product_id, @p_quantity, @v_price);

        -- reduce the stock
        UPDATE inventory
        SET stock = stock - @p_quantity
        WHERE product_id = @p_product_id;

        PRINT 'Thank you, product "' + @v_product_name + '" has been added and inventory updated.';  -- PRINT replaces RAISE NOTICE
    END
    ELSE
    BEGIN
        PRINT 'Product "' + @v_product_name + '" is not available at the moment.';
    END
END;
GO

---- Testing (product 1 starts with 55 units; use new order ids if you run it again)
EXEC add_sales 25001, 2, 5, 26001, 1, 10;  -- stock 55 -> 45
SELECT product_id, stock FROM inventory WHERE product_id = 1;

EXEC add_sales 25002, 2, 5, 26002, 1, 12;  -- stock 45 -> 33
SELECT product_id, stock FROM inventory WHERE product_id = 1;

EXEC add_sales 25003, 2, 5, 26003, 1, 3;   -- stock 33 -> 30
SELECT product_id, stock FROM inventory WHERE product_id = 1;

EXEC add_sales 25004, 2, 5, 26004, 1, 40;  -- 40 > 30: "not available", stock unchanged
SELECT * FROM inventory WHERE product_id = 1;
