-- History of granted loans
--  This query prepares a summary of the granted loans in the following dimensions:
SELECT
    EXTRACT(YEAR FROM date) AS year_of_loan,
    EXTRACT(QUARTER FROM date) AS quarter_of_loan,
    EXTRACT(MONTH FROM date) AS month_of_loan,
    SUM(amount) AS total_amount_of_loans,
    AVG(amount) AS avg_amount_of_loans,
    COUNT(amount) AS total_of_given_loans
FROM loan
GROUP BY year_of_loan, quarter_of_loan, month_of_loan WITH ROLLUP
ORDER BY year_of_loan DESC, quarter_of_loan DESC, month_of_loan DESC;
--  In the query results, NULL values represent the aggregated totals for different periods.
-- For example NULL value in month_of_loan represent the total of quarter.

-- Loan status
-- Here we know, that exists 682 granted loans in the database, of which 606 have been repaid and 76 have not.
SELECT  status, count(status) as count_of_loans
FROM loan
GROUP BY status;
-- Status of loans: A = 203, B = 31, C = 403, D = 45. These results show that statuses 'A' & 'C' represent granted loans. On the other hand, statuses 'B' & 'D' represent ungranted loans.

-- Analysis of accounts
WITH cte AS (
    SELECT account_id,
           COUNT(loan_id) AS number_of_loans,
           SUM(amount) AS amount_of_loans,
           AVG(amount) AS avg_amount
    FROM loan
    WHERE status IN ('A', 'C') -- Now we know that granted loans are in 'A' & 'C' status.
    GROUP BY account_id;
)
-- Using the CTE and ROW_NUMBER() to calculate account rankings.
-- We could use the ORDER BY method, but it would only sort the values without assigning explicit ranks.
SELECT *,
       row_number() over (order by number_of_loans DESC) as rank_loans_count,
       row_number() over (order by amount_of_loans DESC) as rank_amount_count
FROM cte;

-- This query retrieves the total number of fully repaid loans (statuses 'A' and 'C'),
-- grouped by client gender. It ensures that each loan is counted only once
-- by selecting only the primary owner from the disp table.
SELECT COUNT(DISTINCT l.loan_id) AS total_loans, c.gender
FROM loan l
JOIN account a ON a.account_id = l.account_id
JOIN disp d ON a.account_id = d.account_id AND d.type = 'OWNER'  -- Filtering only primary owner.
JOIN client c ON c.client_id = d.client_id
WHERE l.status IN ('A','C') -- Only fully repaid loans.
GROUP BY c.gender;

-- Client analysis -- Průměrný věk
CREATE temporary table client_analysis1 as
SELECT c.gender, SUM(amount) as amount,
       2025 - extract(year from birth_date) as age_of_client,
       COUNT(amount) as amount_count
FROM loan l
JOIN account a on l.account_id = a.account_id
JOIN client c on a.district_id = c.district_id
JOIN disp d on a.account_id = d.account_id
GROUP BY gender, age_of_client;

SELECT SUM(amount_count) AS amount_count, gender
FROM client_analysis1
GROUP BY gender;
-- Result: Males have repaid a higher total loan amount than females.

-- Client analysis 2
SELECT gender, round(avg(age_of_client),0) as avg_age_of_clients
FROM client_analysis1
GROUP BY gender;
-- Result: AVG ages of genders are - Male 77 years old and Female 75 years old.

-- Client analysis 3
WITH cte AS (
    SELECT di.district_id,
           di.A2 AS city,  -- Přidání názvu města
           di.A3 AS region,  -- Přidání regionu
           COUNT(DISTINCT c.client_id) AS customer_amount,  -- Počet unikátních klientů
           SUM(l.amount) AS loans_sum,  -- Celková částka půjček
           COUNT(l.loan_id) AS loans_count  -- Celkový počet půjček
    FROM loan l
    JOIN account a ON a.account_id = l.account_id
    JOIN disp d ON a.account_id = d.account_id AND d.type = 'OWNER'  -- Jen hlavní vlastník účtu
    JOIN client c ON c.client_id = d.client_id
    JOIN district di ON a.district_id = di.district_id
    WHERE l.status IN ('A','C')  -- Pouze splacené půjčky
    GROUP BY di.district_id, di.A2, di.A3  -- Přidání city a region do GROUP BY
)
SELECT *,ROUND(loans_sum/SUM(loans_sum) OVER (),3) AS perc_share
FROM cte
ORDER BY perc_share DESC;

-- Client (account balance is above 1000, have more than 5 loans and born after 1990)
SELECT
    c.client_id,
    SUM(l.amount - l.payments) AS balance,
    EXTRACT(YEAR FROM c.birth_date) AS birth_year,
    count(loan_id) as total_loans
FROM loan l
JOIN account a ON l.account_id = a.account_id
JOIN disp di ON a.account_id = di.account_id AND di.type = 'OWNER'
JOIN client c ON di.client_id = c.client_id
WHERE l.status IN ('A', 'C')
  -- AND EXTRACT(YEAR FROM c.birth_date) > 1990
GROUP BY c.client_id, EXTRACT(YEAR FROM c.birth_date)
HAVING SUM(l.amount - l.payments) > 1000
   -- AND COUNT(l.loan_id) > 5
ORDER BY total_loans DESC;

-- Verification of the separate condition: Born after 1990
SELECT COUNT(*) FROM client WHERE EXTRACT(YEAR FROM birth_date) > 1990;
-- Result: 0 clients were born after 1990.

-- Verification of the separate condition: Have more than 5 loans.
SELECT
    c.client_id,
    COUNT(l.loan_id) AS total_loans
FROM loan l
JOIN account a ON l.account_id = a.account_id
JOIN disp d ON a.account_id = d.account_id AND d.type = 'OWNER'
JOIN client c ON d.client_id = c.client_id
GROUP BY c.client_id
ORDER BY total_loans DESC;
-- Result: Clients have a maximum of 1 loan.

-- Card expiration:
-- Verification of the card issued.
SELECT card_id,issued
FROM card ca
ORDER BY issued DESC;
-- Result: The most recent card was issued on 12/29/1998.

-- Expiring cards procedure.
DELIMITER $$

DROP PROCEDURE IF EXISTS expiring_cards_VELCOVSKY;
CREATE PROCEDURE expiring_cards_VELCOVSKY()
BEGIN
    IF EXISTS (SELECT * FROM information_schema.tables WHERE table_name = 'cards_expiration_procedure') THEN
        TRUNCATE TABLE cards_expiration_procedure;
    ELSE
        CREATE TABLE cards_expiration_procedure (
            client_id INT,
            card_id INT,
            expiration_date DATE,
            client_address VARCHAR(255) -- A3 from district
        );
    END IF;

    INSERT INTO cards_expiration_procedure (client_id, card_id, expiration_date, client_address)
    SELECT
        c.client_id,
        cr.card_id,
        DATE_ADD(cr.issued, INTERVAL 3 YEAR) AS expiration_date,
        d.A3 AS client_address
    FROM card cr
    JOIN disp disp ON cr.disp_id = disp.disp_id
    JOIN client c ON disp.client_id = c.client_id
    JOIN district d ON c.district_id = d.district_id
    WHERE
        DATE_ADD(cr.issued, INTERVAL 3 YEAR) - INTERVAL 7 DAY <= '2001-01-01'
        AND DATE_ADD(cr.issued, INTERVAL 3 YEAR) >= '2001-01-01';
END $$

DELIMITER ;
-- No data appeared because the latest card was issued in 1998.
-- Since cards expire 3 years after issuance, the last possible expiration was in 2001.
-- Using CURRENT_DATE (2025) means no cards match the expiration condition.
-- Solution: We used '2001-01-01' to simulate a past date when cards were still expiring.

-- Calling the procedure in date 2001-01-01.
CALL expiring_cards_VELCOVSKY();
select * from cards_expiration_procedure



