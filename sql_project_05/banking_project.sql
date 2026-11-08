/* =========================================================
   Banking Risk Analysis - SQL Server (T-SQL)
   ========================================================= */

-- ---------------------------------------------------------
-- 1. Create the database
-- ---------------------------------------------------------
USE master;                                            -- switch to master
GO
-- Create the database only if it does not exist yet (safe to re-run)
IF DB_ID('banking_project') IS NULL CREATE DATABASE banking_project;
GO
USE banking_project;                                   -- switch to the project database
GO

-- Check that the database exists: banking_project must appear in the list
SELECT name FROM sys.databases;
GO


-- ---------------------------------------------------------
-- 2. Create the customer table (same column order as Banking.csv)
-- ---------------------------------------------------------
DROP TABLE IF EXISTS customer;                         -- safe to re-run
GO

CREATE TABLE customer (
    -- Customer profile
    Client_ID                 VARCHAR(20),
    Name                      VARCHAR(50),
    Age                       INT,
    Location_ID               INT,
    Joined_Bank               DATE,
    Banking_Contact           VARCHAR(50),
    Nationality               VARCHAR(50),
    Occupation                VARCHAR(50),
    Fee_Structure             VARCHAR(20),
    Loyalty_Classification    VARCHAR(20),

    -- Financial amounts
    Estimated_Income          DECIMAL(15,2),
    Superannuation_Savings    DECIMAL(15,2),
    Amount_of_Credit_Cards    INT,
    Credit_Card_Balance       DECIMAL(15,2),
    Bank_Loans                DECIMAL(15,2),
    Bank_Deposits             DECIMAL(15,2),
    Checking_Accounts         DECIMAL(15,2),
    Saving_Accounts           DECIMAL(15,2),
    Foreign_Currency_Account  DECIMAL(15,2),
    Business_Lending          DECIMAL(15,2),

    -- Codes (1, 2, 3...)
    Properties_Owned          INT,
    Risk_Weighting            INT,
    BRId                      INT,                     -- 1 Retail, 2 Institutional, 3 Private Bank, 4 Commercial
    GenderId                  INT,                     -- 1 Male, 2 Female
    IAId                      INT                      -- investment advisor ID
);
GO


-- ---------------------------------------------------------
-- 3. Load the CSV with BULK INSERT
-- Before this step, copy the file into the Docker container (Mac Terminal):
--   docker cp ./Banking.csv sql_server_container:/tmp/Banking.csv
-- ---------------------------------------------------------
SET DATEFORMAT dmy;                                    -- dates in the CSV are day-month-year (06-05-2019)

BULK INSERT customer
FROM '/tmp/Banking.csv'                                -- path INSIDE the container
WITH (
    FORMAT          = 'CSV',
    FIRSTROW        = 2,                               -- skip the header row
    FIELDTERMINATOR = ',',                             -- column separator
    ROWTERMINATOR   = '0x0a'                           -- line ending (LF)
);
GO

-- Check: must return banking_project / 3000
SELECT DB_NAME() AS current_database,
       COUNT(*)  AS row_count
FROM customer;
GO

SELECT TOP 5 * FROM customer;                          -- preview the first rows
GO


/* =========================================================
   BUSINESS QUESTIONS
   Total loan    = Bank_Loans + Business_Lending + Credit_Card_Balance
   Total deposit = Bank_Deposits + Saving_Accounts + Checking_Accounts + Foreign_Currency_Account
   ========================================================= */

-- Q1. What are the bank's key figures? (dashboard home page)
SELECT COUNT(*)                                                   AS total_clients,
       SUM(Bank_Loans + Business_Lending + Credit_Card_Balance)   AS total_loan,
       SUM(Bank_Deposits + Saving_Accounts + Checking_Accounts
           + Foreign_Currency_Account)                            AS total_deposit,
       SUM(Checking_Accounts)                                     AS total_checking,
       SUM(Saving_Accounts)                                       AS total_saving,
       SUM(Business_Lending)                                      AS total_business_lending
FROM customer;
GO

-- Q2. Do men and women borrow differently?
SELECT CASE GenderId WHEN 1 THEN 'Male' WHEN 2 THEN 'Female' END  AS gender,              -- code -> label
       COUNT(*)                                                   AS clients,
       SUM(Bank_Loans + Business_Lending + Credit_Card_Balance)   AS total_loan,
       AVG(Bank_Loans + Business_Lending + Credit_Card_Balance)   AS avg_loan_per_client
FROM customer
GROUP BY GenderId;                                                                         -- one row per gender
GO

-- Q3. Which joining years brought the most new clients?
SELECT TOP 5 YEAR(Joined_Bank) AS join_year,                      -- keep only the year
       COUNT(*)                AS new_clients
FROM customer
GROUP BY YEAR(Joined_Bank)
ORDER BY new_clients DESC;                                        -- busiest years first
GO

-- Q4. Which income band holds most of the bank loans?
SELECT CASE WHEN Estimated_Income < 100000 THEN 'Low'
            WHEN Estimated_Income < 300000 THEN 'Mid'
            ELSE 'High' END                                       AS income_band,
       COUNT(*)                                                   AS clients,
       SUM(Bank_Loans)                                            AS total_bank_loans,
       CAST(SUM(Bank_Loans) * 100.0 / SUM(SUM(Bank_Loans)) OVER ()
            AS DECIMAL(5,1))                                      AS pct_of_loans          -- share of the grand total
FROM customer
GROUP BY CASE WHEN Estimated_Income < 100000 THEN 'Low'
              WHEN Estimated_Income < 300000 THEN 'Mid'
              ELSE 'High' END
ORDER BY total_bank_loans DESC;
GO

-- Q5. Which banking relationship lends the most?
SELECT CASE BRId WHEN 1 THEN 'Retail'       WHEN 2 THEN 'Institutional'
                 WHEN 3 THEN 'Private Bank' WHEN 4 THEN 'Commercial' END AS banking_relationship,
       COUNT(*)        AS clients,
       SUM(Bank_Loans) AS total_bank_loans
FROM customer
GROUP BY BRId
ORDER BY total_bank_loans DESC;
GO

-- Q6. Top 3 nationalities by bank loans
SELECT TOP 3 Nationality,
       SUM(Bank_Loans) AS total_bank_loans
FROM customer
GROUP BY Nationality
ORDER BY total_bank_loans DESC;
GO

-- Q7. Top 10 occupations by bank loans
SELECT TOP 10 Occupation,
       COUNT(*)        AS clients,
       SUM(Bank_Loans) AS total_bank_loans
FROM customer
GROUP BY Occupation
ORDER BY total_bank_loans DESC;
GO

-- Q8. Where are the deposits? (deposit analysis by nationality)
SELECT Nationality,
       SUM(Bank_Deposits)     AS bank_deposits,
       SUM(Saving_Accounts)   AS saving,
       SUM(Checking_Accounts) AS checking,
       SUM(Bank_Deposits + Saving_Accounts + Checking_Accounts
           + Foreign_Currency_Account) AS total_deposit
FROM customer
GROUP BY Nationality
ORDER BY total_deposit DESC;
GO

-- Q9. Do risky clients borrow more than they deposit? (loan-to-deposit ratio by risk level)
SELECT Risk_Weighting,
       COUNT(*) AS clients,
       SUM(Bank_Loans + Business_Lending + Credit_Card_Balance) AS total_loan,
       SUM(Bank_Deposits + Saving_Accounts + Checking_Accounts
           + Foreign_Currency_Account)                          AS total_deposit,
       CAST(SUM(Bank_Loans + Business_Lending + Credit_Card_Balance)
            / SUM(Bank_Deposits + Saving_Accounts + Checking_Accounts + Foreign_Currency_Account)
            AS DECIMAL(5,2))                                    AS loan_to_deposit_ratio  -- > 1 = lends more than it holds
FROM customer
GROUP BY Risk_Weighting
ORDER BY Risk_Weighting;
GO


-- ---------------------------------------------------------
-- Q10. Clean view for Power BI (labels and totals already computed)
-- ---------------------------------------------------------
CREATE OR ALTER VIEW vw_customer_dashboard AS
SELECT *,
       CASE GenderId WHEN 1 THEN 'Male' WHEN 2 THEN 'Female' END AS Gender,
       CASE BRId WHEN 1 THEN 'Retail'       WHEN 2 THEN 'Institutional'
                 WHEN 3 THEN 'Private Bank' WHEN 4 THEN 'Commercial' END AS Banking_Relationship,
       CASE WHEN Estimated_Income < 100000 THEN 'Low'
            WHEN Estimated_Income < 300000 THEN 'Mid'
            ELSE 'High' END                                       AS Income_Band,
       YEAR(Joined_Bank)                                          AS Join_Year,
       Bank_Loans + Business_Lending + Credit_Card_Balance        AS Total_Loan,
       Bank_Deposits + Saving_Accounts + Checking_Accounts
           + Foreign_Currency_Account                             AS Total_Deposit
FROM customer;
GO

SELECT TOP 5 * FROM vw_customer_dashboard;             -- check the view
GO


-- ---------------------------------------------------------
-- Q11. Stored procedure: key figures for any nationality
-- ---------------------------------------------------------
CREATE OR ALTER PROCEDURE sp_kpi_by_nationality
    @nationality VARCHAR(50)                           -- input parameter
AS
BEGIN
    SELECT @nationality       AS nationality,
           COUNT(*)           AS clients,
           SUM(Total_Loan)    AS total_loan,
           SUM(Total_Deposit) AS total_deposit
    FROM vw_customer_dashboard
    WHERE Nationality = @nationality;
END;
GO

EXEC sp_kpi_by_nationality @nationality = 'European';  -- run the procedure
GO
