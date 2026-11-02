# Amazon Marketplace Analysis with SQL Server

SQL analysis of a simulated Amazon marketplace: sales performance, customers, sellers, inventory, shipping and returns. Everything is written in **T-SQL (SQL Server)** and runs on SQL Server in Docker.

## Project goals

- Identify top products, categories, sellers and regions
- Measure customer value and buying behaviour
- Track shipping, payment and return performance
- Spot inventory risks and declining products
- Automate a sale and the matching inventory update with a stored procedure

## Dataset

Simulated marketplace data in 9 related tables, from **January 2020 to July 2024**.

| Table | Rows | Description |
|---|---|---|
| `category` | 6 | Product categories |
| `customers` | 898 | Customers and their state |
| `sellers` | 54 | Sellers and their country of origin |
| `products` | 765 | Products with price and cost of goods sold (`cogs`) |
| `orders` | 21,629 | Orders with date, customer, seller and status |
| `order_items` | 21,629 | Products, quantities and prices per order |
| `payments` | 21,629 | Payment date and status per order |
| `shipping` | 21,141 | Shipping dates, providers and delivery status |
| `inventory` | 765 | Stock level and last restock date per product |

The CSV files are not included in this repository. Dataset source: Zero Analyst.

<!-- add your schema diagram: ![Database schema](images/schema.png) -->

## Tools

- SQL Server (Docker, Apple Silicon Mac)
- VS Code with the SQL Server (mssql) extension
- T-SQL: joins, CTEs, window functions, `CASE`, subqueries, date functions, stored procedure

## How to run

1. Start SQL Server in Docker.
2. Copy the CSV files into the container:
   ```bash
   docker cp ~/Desktop/amazon sql_server_container:/tmp/amazon
   ```
3. Run `amazon_sql_project.sql` in VS Code. It creates the database and tables, imports the CSV files, runs the 17 business questions and creates the stored procedure.

## Database design

Tables are linked with foreign keys, created parents first (`category`, `customers`, `sellers`, then `products`, `orders`, then `order_items`, `payments`, `shipping`, `inventory`). A computed column `order_items.total_sale = quantity * price_per_unit` keeps sales values consistent.

## Business questions

Full queries are in [`amazon_sql_project.sql`](amazon_sql_project.sql).

### 1. Top selling products
Top 10 products by total sales value, with quantity sold. The top product is the **Apple iMac Pro** (126 units, about 630K in sales), followed by the iMac 27-Inch Retina and the Canon EOS R5. High-priced electronics drive revenue.

<!-- ![Q1](images/q1.png) -->

### 2. Revenue by category
Total revenue per category and its share of overall revenue.

<!-- ![Q2](images/q2.png) -->

### 3. Average order value (AOV)
Average order value per customer, for customers with more than 5 orders.

<!-- ![Q3](images/q3.png) -->

### 4. Monthly sales trend
Monthly sales over the last 12 months of data, compared with the previous month using `LAG()`.

<!-- ![Q4](images/q4.png) -->

### 5. Customers with no purchases
Registered customers who never ordered: a target for re-engagement campaigns.

<!-- ![Q5](images/q5.png) -->

### 6. Best-selling category by state
Top category in each state using `RANK() OVER (PARTITION BY ...)`, useful for regional marketing.

<!-- ![Q6](images/q6.png) -->

### 7. Customer lifetime value (CLTV)
Total order value per customer, ranked with `DENSE_RANK()`.

<!-- ![Q7](images/q7.png) -->

### 8. Inventory stock alerts
Products with fewer than 10 units left, with warehouse and last restock date.

<!-- ![Q8](images/q8.png) -->

### 9. Shipping delays
Orders shipped more than 2 days after the order date, with customer and shipping provider.

<!-- ![Q9](images/q9.png) -->

### 10. Payment success rate
Share of each payment status (successful, failed, refunded).

<!-- ![Q10](images/q10.png) -->

### 11. Top performing sellers
Top 5 sellers by sales, with completed and cancelled orders and their success rate (built with three chained CTEs).

<!-- ![Q11](images/q11.png) -->

### 12. Product profit margin
Profit margin per product, `(sales - cogs * quantity) / sales`, ranked from highest to lowest.

<!-- ![Q12](images/q12.png) -->

### 13. Most returned products
Top 10 products by number of returns, with the return rate over units sold.

<!-- ![Q13](images/q13.png) -->

### 14. Returning vs new customers
Customers with more than 5 returns are labelled `Returning`, the others `New`.

<!-- ![Q14](images/q14.png) -->

### 15. Top 5 customers per state
Top 5 customers by number of orders in each state, with total sales.

<!-- ![Q15](images/q15.png) -->

### 16. Revenue by shipping provider
Revenue and orders handled by each provider (bluedart, dhl, fedex), with average days between shipping and return.

<!-- ![Q16](images/q16.png) -->

### 17. Products with declining revenue (2023 vs 2024)
Top 10 products with the biggest revenue drop between 2023 and 2024.

<!-- ![Q17](images/q17.png) -->

## Stored procedure: `add_sales`

Simulates a real sale. It checks the stock for the requested product; if enough units are available, it inserts the order and the order item, then reduces the stock in `inventory` and prints a confirmation. Otherwise it prints that the product is unavailable.

```sql
EXEC add_sales 25001, 2, 5, 26001, 1, 10;   -- order, customer, seller, order item, product, quantity
SELECT product_id, stock FROM inventory WHERE product_id = 1;
```

## Data notes

- The data ends on **2024-07-30**, so "the past year" is measured from the last order date, and 2024 is a partial year in the 2023 vs 2024 comparison.
- Some text values contain a trailing space (for example `'Refunded '`), handled with `RTRIM()`.
- `shipping` has fewer rows (21,141) than `orders` (21,629): some orders have no shipping record.
- Q16 measures the time between shipping and return, not delivery time, because the table has no delivery date.

## PostgreSQL vs SQL Server

The code is commented where SQL Server syntax differs from PostgreSQL:

| PostgreSQL | SQL Server |
|---|---|
| `LIMIT 10` | `TOP 10` |
| `value::NUMERIC` | `CAST(value AS DECIMAL(p,s))` |
| `EXTRACT(YEAR FROM date)` | `YEAR(date)` |
| `date1 - date2` | `DATEDIFF(DAY, date2, date1)` |
| `date + INTERVAL '1 year'` | `DATEADD(YEAR, 1, date)` |
| `CURRENT_DATE` | `GETDATE()` |
| `RAISE NOTICE` / PL/pgSQL | `PRINT` / T-SQL procedure |
| `\copy` | `BULK INSERT` |
| `GROUP BY id` only | all non-aggregated columns in `GROUP BY` |

## What I learned

- Designing a relational schema with primary and foreign keys, and loading data in the right order
- Writing multi-step analyses with CTEs, window functions and conditional aggregation
- Spotting data quality issues (trailing spaces, partial years, missing records)
- Translating PostgreSQL syntax to T-SQL
- Automating business logic with a stored procedure
