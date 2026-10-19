-- =============================================================
-- Spendwise: V1 schema and reference data
-- Run this whole file in MySQL Workbench (MySQL 8).
-- Named in Flyway style so the Spring Boot app can reuse it in Week 2.
-- =============================================================

DROP DATABASE IF EXISTS spendwise;
CREATE DATABASE spendwise;
USE spendwise;

-- -------------------------------------------------------------
-- Core tables
-- -------------------------------------------------------------

CREATE TABLE accounts (
    account_id       INT PRIMARY KEY AUTO_INCREMENT,
    name             VARCHAR(60)  NOT NULL UNIQUE,
    institution      VARCHAR(60)  NOT NULL,
    account_type     ENUM('CHECKING', 'SAVINGS', 'CREDIT_CARD') NOT NULL,
    opening_balance  DECIMAL(12,2) NOT NULL DEFAULT 0,
    opened_on        DATE NOT NULL,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE categories (
    category_id   INT PRIMARY KEY AUTO_INCREMENT,
    name          VARCHAR(40) NOT NULL UNIQUE,
    kind          ENUM('EXPENSE', 'INCOME', 'TRANSFER') NOT NULL
);

-- Rules that turn a bank description into a category.
-- A transaction gets the category of the matching rule with the LOWEST priority number.
CREATE TABLE category_rules (
    rule_id      INT PRIMARY KEY AUTO_INCREMENT,
    pattern      VARCHAR(100) NOT NULL,          -- matched with: description LIKE CONCAT('%', pattern, '%')
    category_id  INT NOT NULL,
    priority     INT NOT NULL DEFAULT 100,
    FOREIGN KEY (category_id) REFERENCES categories(category_id)
);

-- One row per real transaction. Sign convention:
--   amount < 0  money left the account (purchase, bill, payment out)
--   amount > 0  money came in (paycheck, refund, payment received)
CREATE TABLE transactions (
    txn_id        BIGINT PRIMARY KEY AUTO_INCREMENT,
    account_id    INT NOT NULL,
    txn_date      DATE NOT NULL,
    description   VARCHAR(255) NOT NULL,
    amount        DECIMAL(12,2) NOT NULL,
    category_id   INT NULL,                       -- filled in by the categorization step
    import_hash   CHAR(64) NOT NULL,              -- fingerprint that stops duplicate imports
    source_file   VARCHAR(120) NOT NULL,
    imported_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_transactions_hash (import_hash),
    FOREIGN KEY (account_id)  REFERENCES accounts(account_id),
    FOREIGN KEY (category_id) REFERENCES categories(category_id)
);

-- Monthly spending limit per category. month = first day of the month.
CREATE TABLE budgets (
    category_id   INT NOT NULL,
    month         DATE NOT NULL,
    limit_amount  DECIMAL(10,2) NOT NULL CHECK (limit_amount > 0),
    PRIMARY KEY (category_id, month),
    FOREIGN KEY (category_id) REFERENCES categories(category_id)
);

-- -------------------------------------------------------------
-- Staging tables: raw CSV rows land here first, exactly as the bank
-- exported them (everything is text). The load step cleans them into
-- `transactions`, then the staging table is emptied for the next file.
-- -------------------------------------------------------------

-- Lone Star Bank checking export: Date (MM/DD/YYYY), Description, Debit, Credit, Balance
CREATE TABLE stg_lonestar_checking (
    txn_date_raw  VARCHAR(20),
    description   VARCHAR(255),
    debit         VARCHAR(20),
    credit        VARCHAR(20),
    balance       VARCHAR(20)
);

-- Bayou credit card export: Transaction Date (YYYY-MM-DD), Description,
-- Amount (POSITIVE = purchase, NEGATIVE = payment or refund)
CREATE TABLE stg_bayou_card (
    txn_date_raw  VARCHAR(20),
    description   VARCHAR(255),
    amount        VARCHAR(20)
);

-- -------------------------------------------------------------
-- Reference data
-- -------------------------------------------------------------

INSERT INTO accounts (account_id, name, institution, account_type, opening_balance, opened_on) VALUES
(1, 'Everyday Checking', 'Lone Star Bank', 'CHECKING',    2400.00, '2026-07-01'),
(2, 'Bayou Rewards Card', 'Bayou Card',    'CREDIT_CARD',    0.00, '2026-07-01');

INSERT INTO categories (category_id, name, kind) VALUES
(1,  'Income',            'INCOME'),
(2,  'Rent',              'EXPENSE'),
(3,  'Utilities',         'EXPENSE'),
(4,  'Phone & Internet',  'EXPENSE'),
(5,  'Groceries',         'EXPENSE'),
(6,  'Dining & Coffee',   'EXPENSE'),
(7,  'Transport',         'EXPENSE'),
(8,  'Shopping',          'EXPENSE'),
(9,  'Subscriptions',     'EXPENSE'),
(10, 'Fitness',           'EXPENSE'),
(11, 'Cash',              'EXPENSE'),
(12, 'Transfers',         'TRANSFER'),
(13, 'Uncategorized',     'EXPENSE');

INSERT INTO category_rules (pattern, category_id, priority) VALUES
('PAYROLL',          1,  10),
('INTEREST PAYMENT', 1,  10),
('RENT',             2,  10),
('RELIANT ENERGY',   3,  10),
('XFINITY',          4,  10),
('T-MOBILE',         4,  10),
('HEB',              5,  20),
('KROGER',           5,  20),
('STARBUCKS',        6,  20),
('CHIPOTLE',         6,  20),
('PAPPASITOS',       6,  20),
('PHO ',             6,  20),
('SWEETGREEN',       6,  20),
('UBER',             7,  20),
('SHELL OIL',        7,  20),
('AMAZON',           8,  50),
('NETFLIX',          9,  10),
('SPOTIFY',          9,  10),
('ADOBE',            9,  10),
('PLANET FITNESS',  10,  10),
('ATM WITHDRAWAL',  11,  10),
('PAYMENT - THANK YOU', 12, 5),
('CARD ONLINE PAYMENT', 12, 5),
('ZELLE',           12,  30);

INSERT INTO budgets (category_id, month, limit_amount) VALUES
(5, '2026-07-01', 350), (6, '2026-07-01', 150), (7, '2026-07-01', 200), (8, '2026-07-01', 120), (9, '2026-07-01', 50),
(5, '2026-08-01', 350), (6, '2026-08-01', 150), (7, '2026-08-01', 200), (8, '2026-08-01', 120), (9, '2026-08-01', 50),
(5, '2026-09-01', 350), (6, '2026-09-01', 150), (7, '2026-09-01', 200), (8, '2026-09-01', 120), (9, '2026-09-01', 50),
(5, '2026-10-01', 350), (6, '2026-10-01', 150), (7, '2026-10-01', 200), (8, '2026-10-01', 120), (9, '2026-10-01', 50);
