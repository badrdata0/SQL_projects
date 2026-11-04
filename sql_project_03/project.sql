-- =====================================================================
-- WALMART SALES ANALYSIS : PYTHON + SQL SERVER PROJECT
-- =====================================================================
-- Workflow order:
--   1. Terminal       : environment setup and dataset download (parts 1-2)
--   2. Notebook       : load, explore and clean the data (parts 3-4)
--   3. This SQL file  : create the database (part 5, step 1)
--   4. Notebook       : export the clean data to SQL Server (part 5, step 2)
--   5. This SQL file  : check the load (part 5, step 3) and answer the
--                       business questions in T-SQL (part 6)
-- =====================================================================


-- =====================================================================
-- PART 1 : ENVIRONMENT SETUP (macOS, Apple Silicon)
-- All lines below are terminal commands, kept as comments.
-- =====================================================================

-- Kaggle API authentication
-- The Kaggle CLI reads an access token from the KAGGLE_API_TOKEN variable.
-- Saving it in ~/.zshrc makes it available in every new terminal session.
-- Replace XXXXX with your own token (never commit it).
--   echo 'export KAGGLE_API_TOKEN=XXXXX' >> ~/.zshrc
--   source ~/.zshrc
--   echo $KAGGLE_API_TOKEN | cut -c1-5     -- prints only the first 5 characters

-- Project folder and Python virtual environment
-- A virtual environment keeps this project's libraries separate from others.
-- Python 3.11+ is required by the Kaggle CLI.
--   mkdir ~/Desktop/project_walmart && code ~/Desktop/project_walmart
--   python3 --version                      -- 3.12.6 here
--   python3 -m venv my_env1                -- create the virtual environment
--   source my_env1/bin/activate            -- activate it: prompt shows (my_env1)

-- Python libraries
-- pandas (cleaning), SQLAlchemy + pymssql (SQL Server connection, the
-- equivalent of the tutor's pymysql / psycopg2), kaggle (dataset download),
-- ipykernel (notebooks in VS Code), six (dependency missing from kaggle).
--   pip install pandas sqlalchemy pymssql kaggle ipykernel six
--   printf "pandas\nsqlalchemy\npymssql\nkaggle\nipykernel\nsix\n" > requirements.txt
--   echo "my_env1/" > .gitignore            -- keep the virtual environment out of GitHub


-- =====================================================================
-- PART 2 : DOWNLOAD THE DATASET FROM KAGGLE
-- The dataset is published on Kaggle by the user najir0123
-- (format: author/dataset-name). Run in the terminal, environment active.
-- =====================================================================

--   kaggle datasets download -d najir0123/walmart-10k-sales-datasets
--   unzip walmart-10k-sales-datasets.zip   -- extracts Walmart.csv
--   ls                                     -- check that Walmart.csv is there

-- Troubleshooting: if kaggle fails with "No module named 'six'",
-- run: pip install six


-- =====================================================================
-- PART 3 : LOAD AND EXPLORE THE DATA WITH PANDAS
-- Python cells of the notebook project.ipynb, kept as comments.
-- The notebook must be saved inside the project_walmart folder,
-- with the my_env1 kernel selected in VS Code.
-- =====================================================================

--   import pandas as pd                   -- pandas: library to work with tables
--   df = pd.read_csv('Walmart.csv')       -- load the CSV (capital W: names are case-sensitive on Linux)
--   df.shape                              -- (10051, 11) = rows, columns
--   df.head()                             -- first 5 rows
--   df.info()                             -- column types and non-null counts
--   df.duplicated().sum()                 -- 51 duplicated rows
--   df.isnull().sum()                     -- 31 missing values in unit_price and quantity

-- Findings:
--   * 51 duplicated rows and 31 rows with missing unit_price / quantity
--   * unit_price is stored as text because of the "$" sign,
--     so it must be converted to a number before any calculation


-- =====================================================================
-- PART 4 : CLEAN THE DATA WITH PANDAS
-- Python cells of the notebook project.ipynb, kept as comments.
-- =====================================================================

-- 1. Remove duplicated rows (identical lines)
--   df.drop_duplicates(inplace=True)      -- inplace=True: modifies df directly
--   df.duplicated().sum()                 -- check: 0
--   df.shape                              -- (10000, 11)

-- 2. Remove rows with missing values
-- We drop instead of filling: without price or quantity, the total cannot be computed
--   df.dropna(inplace=True)
--   df.isnull().sum()                     -- check: all columns at 0
--   df.shape                              -- (9969, 11)

-- 3. Convert unit_price from text ("$74.69") to a number (74.69)
-- The "$" must be removed first, otherwise Python cannot convert it
--   df['unit_price'] = df['unit_price'].str.replace('$', '', regex=False).astype(float)
--   df.dtypes                             -- unit_price is now float64

-- 4. Create a new column: total = unit price x quantity
--   df['total'] = df['unit_price'] * df['quantity']
--   df.head()                             -- first row: 74.69 x 7 = 522.83

-- 5. Put column names in lower case (Branch -> branch, City -> city)
-- Avoids case issues between tools, especially with PostgreSQL
--   df.columns = df.columns.str.lower()

-- 6. Save the cleaned data (index=False: no row-number column)
--   df.to_csv('walmart_clean_data.csv', index=False)
--   df.shape                              -- final shape: (9969, 12)

-- Result: 9,969 clean rows and 12 columns (11 original + total)


-- =====================================================================
-- PART 5 : EXPORT THE CLEAN DATA TO SQL SERVER
-- SQL Server runs in Docker (localhost, port 1433). Connect to it from the
-- mssql extension of VS Code, then run the script below.
-- =====================================================================

-- Step 1: create the database (the table is created later by pandas)
USE master;
GO
-- Create the database only if it does not exist yet (safe to re-run)
IF DB_ID('walmart_db') IS NULL CREATE DATABASE walmart_db;
GO
USE walmart_db;   -- switch to the new database
GO

-- Check that the database exists: walmart_db must appear in the list
SELECT name FROM sys.databases;
GO

-- Step 2: export from the notebook (part 5 cells of project.ipynb)
--   from sqlalchemy import create_engine, text
--   from urllib.parse import quote_plus
--   from getpass import getpass
--   password = getpass('SQL Server password: ')   -- typed in a pop-up, never saved
--   engine = create_engine(f"mssql+pymssql://sa:{quote_plus(password)}@127.0.0.1:1433/walmart_db")
--   df.to_sql(name='walmart', con=engine, if_exists='replace', index=False)
--   pd.read_sql("SELECT COUNT(*) AS nb_rows FROM walmart", engine)   -- 9969
-- Notes:
--   * 127.0.0.1 instead of localhost forces IPv4 (Docker on Mac listens on IPv4)
--   * the number returned by to_sql is unreliable with pymssql: always check in SQL

-- Step 3: check the load
-- Number of rows really stored in the table: expected 9969
SELECT COUNT(*) FROM walmart;
GO

-- Column names and data types of the table created by pandas
-- date and time are text (varchar): they are converted in the queries (part 6)
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'walmart';
GO


-- =====================================================================
-- PART 6 : BUSINESS PROBLEMS IN T-SQL
-- =====================================================================
USE walmart_db;
GO

-- Problem 1: number of transactions and quantity sold per payment method
SELECT
    payment_method,
    COUNT(*)      AS no_payments,   -- number of transactions (one row = one invoice)
    SUM(quantity) AS no_qty_sold    -- total number of items sold
FROM walmart
GROUP BY payment_method;


-- Problem 2: best-rated category in each branch (branch, category, average rating)
SELECT branch, category, avg_rating
FROM (
    SELECT
        branch,
        category,
        AVG(rating) AS avg_rating,                      -- average rating per branch + category
        RANK() OVER (
            PARTITION BY branch                         -- restart the ranking for each branch
            ORDER BY AVG(rating) DESC                   -- rank 1 = highest average rating
        ) AS rnk
    FROM walmart
    GROUP BY branch, category                           -- T-SQL: GROUP BY 1, 2 is not allowed, use column names
) AS ranked                                             -- T-SQL: a subquery in FROM must have an alias
WHERE rnk = 1;                                          -- keep only the best category of each branch


-- Problem 3: busiest day of the week for each branch (by number of transactions)
SELECT branch, day_name, no_transactions
FROM (
    SELECT
        branch,
        DATENAME(WEEKDAY, CONVERT(date, [date], 3)) AS day_name,   -- text "05/01/19" -> real date -> "Saturday"
        COUNT(*) AS no_transactions,                               -- transactions per branch + day
        RANK() OVER (
            PARTITION BY branch                                    -- restart the ranking for each branch
            ORDER BY COUNT(*) DESC                                 -- rank 1 = most transactions
        ) AS rnk
    FROM walmart
    GROUP BY branch, DATENAME(WEEKDAY, CONVERT(date, [date], 3))   -- T-SQL: GROUP BY needs the full expression, not the alias
) AS ranked
WHERE rnk = 1;                                                     -- keep only the busiest day of each branch


-- Problem 4: total quantity of items sold per payment method
SELECT
    payment_method,
    SUM(quantity) AS no_qty_sold   -- total items sold for each payment method
FROM walmart
GROUP BY payment_method;


-- Problem 5: min, max and average rating for each city and category
SELECT
    city,
    category,
    MIN(rating) AS min_rating,   -- lowest rating of the group
    MAX(rating) AS max_rating,   -- highest rating of the group
    AVG(rating) AS avg_rating    -- average rating of the group
FROM walmart
GROUP BY city, category;         -- one result per city + category pair


-- Problem 6: total revenue and profit for each category, from highest to lowest profit
SELECT
    category,
    SUM(total) AS total_revenue,                  -- total = unit_price x quantity (column created in pandas)
    SUM(total * profit_margin) AS total_profit    -- profit = revenue x profit margin
FROM walmart
GROUP BY category
ORDER BY total_profit DESC;                       -- highest profit first


-- Problem 7: most used payment method in each branch
WITH cte AS (
    SELECT
        branch,
        payment_method,
        COUNT(*) AS total_trans,                  -- transactions per branch + payment method
        RANK() OVER (
            PARTITION BY branch                   -- restart the ranking for each branch
            ORDER BY COUNT(*) DESC                -- rank 1 = most used
        ) AS rnk
    FROM walmart
    GROUP BY branch, payment_method
)
SELECT branch, payment_method AS preferred_payment_method, total_trans
FROM cte
WHERE rnk = 1;                                    -- keep only the preferred method of each branch


-- Problem 8: number of invoices per shift (Morning / Afternoon / Evening)
-- 8a. Whole company
SELECT shift, COUNT(*) AS no_invoices
FROM (
    SELECT
        CASE
            WHEN DATEPART(HOUR, CAST([time] AS time)) < 12 THEN 'Morning'                -- text "13:08:00" -> real time -> hour
            WHEN DATEPART(HOUR, CAST([time] AS time)) BETWEEN 12 AND 17 THEN 'Afternoon'
            ELSE 'Evening'
        END AS shift
    FROM walmart
) AS shifts                                       -- T-SQL: we group in an outer query, GROUP BY cannot use the alias
GROUP BY shift
ORDER BY no_invoices DESC;

-- 8b. Per branch
SELECT branch, shift, COUNT(*) AS no_invoices
FROM (
    SELECT
        branch,
        CASE
            WHEN DATEPART(HOUR, CAST([time] AS time)) < 12 THEN 'Morning'
            WHEN DATEPART(HOUR, CAST([time] AS time)) BETWEEN 12 AND 17 THEN 'Afternoon'
            ELSE 'Evening'
        END AS shift
    FROM walmart
) AS shifts
GROUP BY branch, shift
ORDER BY branch, no_invoices DESC;


-- Problem 9: 5 branches with the highest revenue decrease ratio, 2022 -> 2023
-- ratio = (last year revenue - current year revenue) / last year revenue x 100
WITH revenue_2022 AS (
    SELECT branch, SUM(total) AS revenue
    FROM walmart
    WHERE YEAR(CONVERT(date, [date], 3)) = 2022   -- text "dd/mm/yy" -> real date -> year
    GROUP BY branch
),
revenue_2023 AS (
    SELECT branch, SUM(total) AS revenue
    FROM walmart
    WHERE YEAR(CONVERT(date, [date], 3)) = 2023
    GROUP BY branch
)
SELECT TOP 5                                      -- T-SQL: TOP 5 instead of LIMIT 5
    ls.branch,
    ls.revenue AS last_year_revenue,
    cs.revenue AS cr_year_revenue,
    ROUND((ls.revenue - cs.revenue) / ls.revenue * 100, 2) AS rev_dec_ratio   -- total is float: no CAST needed
FROM revenue_2022 AS ls
JOIN revenue_2023 AS cs ON ls.branch = cs.branch  -- same branch in both years
WHERE ls.revenue > cs.revenue                     -- keep only branches where revenue decreased
ORDER BY rev_dec_ratio DESC;                      -- biggest decrease first
