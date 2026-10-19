-- =============================================================
-- Spendwise: load the sample bank statements
-- Run after V1__schema.sql.
--
-- Each file follows the same three steps:
--   1. Import the CSV into its staging table (MySQL Workbench:
--      right-click the staging table -> Table Data Import Wizard)
--   2. Clean the staging rows into `transactions`
--   3. Empty the staging table for the next file
-- =============================================================

USE spendwise;

-- -------------------------------------------------------------
-- File 1: Lone Star checking (Jul 1 - Oct 15)
-- Format: Date MM/DD/YYYY, separate Debit and Credit columns
-- Step 1: import data/sample/lonestar_checking_2026-07-01_to_2026-10-15.csv
--         into stg_lonestar_checking (33 rows)
-- -------------------------------------------------------------

INSERT IGNORE INTO transactions (account_id, txn_date, description, amount, import_hash, source_file)
SELECT 1,
       d,
       description,
       amt,
       SHA2(CONCAT_WS('|', 1, d, description, amt,
            ROW_NUMBER() OVER (PARTITION BY d, description, amt ORDER BY d)), 256),
       'lonestar_checking_2026-07-01_to_2026-10-15.csv'
FROM (
    SELECT STR_TO_DATE(txn_date_raw, '%m/%d/%Y') AS d,
           TRIM(description) AS description,
           CAST(COALESCE(NULLIF(credit, ''), '0') AS DECIMAL(12,2))
         - CAST(COALESCE(NULLIF(debit, ''), '0') AS DECIMAL(12,2)) AS amt   -- money in minus money out
    FROM stg_lonestar_checking
) AS cleaned;
-- Expected: 33 rows added

TRUNCATE stg_lonestar_checking;

-- -------------------------------------------------------------
-- File 2: Bayou card (Jul 1 - Sep 30)
-- Format: Transaction Date YYYY-MM-DD, one Amount column (purchases positive)
-- Step 1: import data/sample/bayou_card_2026-07-01_to_2026-09-30.csv
--         into stg_bayou_card (93 rows)
-- -------------------------------------------------------------

INSERT IGNORE INTO transactions (account_id, txn_date, description, amount, import_hash, source_file)
SELECT 2,
       d,
       description,
       amt,
       SHA2(CONCAT_WS('|', 2, d, description, amt,
            ROW_NUMBER() OVER (PARTITION BY d, description, amt ORDER BY d)), 256),
       'bayou_card_2026-07-01_to_2026-09-30.csv'
FROM (
    SELECT STR_TO_DATE(txn_date_raw, '%Y-%m-%d') AS d,
           TRIM(description) AS description,
           -CAST(amount AS DECIMAL(12,2)) AS amt     -- flip the sign: purchases become negative
    FROM stg_bayou_card
) AS cleaned;
-- Expected: 93 rows added (126 total)

TRUNCATE stg_bayou_card;

-- -------------------------------------------------------------
-- File 3: Bayou card (Sep 16 - Oct 15) - overlaps file 2 on Sep 16-30
-- Step 1: import data/sample/bayou_card_2026-09-16_to_2026-10-15.csv
--         into stg_bayou_card (30 rows)
-- -------------------------------------------------------------

INSERT IGNORE INTO transactions (account_id, txn_date, description, amount, import_hash, source_file)
SELECT 2,
       d,
       description,
       amt,
       SHA2(CONCAT_WS('|', 2, d, description, amt,
            ROW_NUMBER() OVER (PARTITION BY d, description, amt ORDER BY d)), 256),
       'bayou_card_2026-09-16_to_2026-10-15.csv'
FROM (
    SELECT STR_TO_DATE(txn_date_raw, '%Y-%m-%d') AS d,
           TRIM(description) AS description,
           -CAST(amount AS DECIMAL(12,2)) AS amt
    FROM stg_bayou_card
) AS cleaned;
-- Expected: 16 rows added, 14 duplicates skipped (142 total)

TRUNCATE stg_bayou_card;

-- -------------------------------------------------------------
-- Categorize every transaction using category_rules.
-- If several rules match, the lowest priority number wins.
-- (WHERE txn_id > 0 satisfies Workbench's Safe Update mode.)
-- -------------------------------------------------------------

UPDATE transactions t
SET category_id = (
    SELECT r.category_id
    FROM category_rules r
    WHERE t.description LIKE CONCAT('%', r.pattern, '%')
    ORDER BY r.priority, r.rule_id
    LIMIT 1
)
WHERE t.txn_id > 0;

-- Anything no rule matched goes to Uncategorized (category 13)
UPDATE transactions
SET category_id = 13
WHERE category_id IS NULL AND txn_id > 0;

-- -------------------------------------------------------------
-- Checks
-- -------------------------------------------------------------

-- 142 transactions in total
SELECT COUNT(*) AS total_transactions FROM transactions;

-- Transactions per category: Dining & Coffee 38, Groceries 28, Transport 17, ...
SELECT c.name, COUNT(*) AS num_transactions
FROM transactions t
JOIN categories c ON t.category_id = c.category_id
GROUP BY c.name
ORDER BY num_transactions DESC;

-- Two separate identical coffees on Aug 21 are both kept
SELECT txn_date, description, amount
FROM transactions
WHERE txn_date = '2026-08-21' AND description LIKE 'STARBUCKS%';