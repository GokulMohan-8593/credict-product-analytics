-- Database: Credict

----*************************************************************************---
--======================North Star Metric & Metric Tree=========================--
--***************************************************************************---
/*
North Star Metric:

MATU — Monthly Active Transacting Users

Definition: Count of KYC-approved users who completed
            at least one financial transaction
            (payment, BNPL order, or loan EMI payment)
            in a given calendar month
			
WHT NOT THESE ?	

MAU (sessions)		Opening the app ≠ value delivered
GMV					Volume metric — hides quality, inflated by large loans
Revenue				Lags by weeks, doesn’t capture user behaviour
DAU					Fintech is not a daily-use product for most users
Loan disbursements	Episodic — misses payments product entirely
Registered users	Never decreases — classic vanity metric
*/

---=====MATU — North Star Metric Monthly Trend=====--	

SELECT
    TO_CHAR(month, 'YYYY-MM')                               AS month,
    matu,
    LAG(matu) OVER (ORDER BY month)                         AS prev_matu,
    matu - LAG(matu) OVER (ORDER BY month)                  AS absolute_change,
    ROUND(100.0 * (matu - LAG(matu) OVER (ORDER BY month))
        / NULLIF(LAG(matu) OVER (ORDER BY month), 0), 2)    AS mom_growth_pct
FROM (
    SELECT
        DATE_TRUNC('month', txn_month)                      AS month,
        COUNT(DISTINCT user_id)                             AS matu
    FROM (
        -- Payments
        SELECT sender_id 									AS user_id,
               DATE_TRUNC('month', transaction_date)        AS txn_month
        FROM transactions
        WHERE status = 'success'

        UNION

        -- BNPL orders
        SELECT user_id,
               DATE_TRUNC('month', order_date)
        FROM bnpl_orders

        UNION

        -- Loan EMI payments
        SELECT user_id,
               DATE_TRUNC('month', paid_date)
        FROM loan_payments
        WHERE status = 'paid'
          AND paid_date IS NOT NULL
    ) all_transactions
    GROUP BY DATE_TRUNC('month', txn_month)
) matu_monthly
ORDER BY month;

---=====MATU Decomposition — What Drives It Each Month=====--	

-- Breaks MATU into its three product components
-- Shows which product is driving transacting users
SELECT
    TO_CHAR(month, 'YYYY-MM')                               AS month,
    payment_users,
    bnpl_users,
    loan_payers,
    total_matu,

    -- Overlap: users using multiple products
    payment_users + bnpl_users + loan_payers - total_matu   AS multi_product_overlap,

    ROUND(100.0 * payment_users
        / NULLIF(total_matu, 0), 1)                         AS pct_from_payments,
    ROUND(100.0 * bnpl_users
        / NULLIF(total_matu, 0), 1)                         AS pct_from_bnpl,
    ROUND(100.0 * loan_payers
        / NULLIF(total_matu, 0), 1)                         AS pct_from_loans

FROM (
    SELECT
        DATE_TRUNC('month', txn_month)                      AS month,
        COUNT(DISTINCT CASE WHEN product = 'payment'
              THEN user_id END)                             AS payment_users,
        COUNT(DISTINCT CASE WHEN product = 'bnpl'
              THEN user_id END)                             AS bnpl_users,
        COUNT(DISTINCT CASE WHEN product = 'loan'
              THEN user_id END)                             AS loan_payers,
        COUNT(DISTINCT user_id)                             AS total_matu
    FROM (
        SELECT sender_id AS user_id,
               DATE_TRUNC('month', transaction_date)        AS txn_month,
               'payment'                                    AS product
        FROM transactions WHERE status = 'success'

        UNION ALL

        SELECT user_id,
               DATE_TRUNC('month', order_date),
               'bnpl'
        FROM bnpl_orders

        UNION ALL

        SELECT user_id,
               DATE_TRUNC('month', paid_date),
               'loan'
        FROM loan_payments
        WHERE status = 'paid' AND paid_date IS NOT NULL
    ) all_txns
    GROUP BY DATE_TRUNC('month', txn_month)
) decomposed
ORDER BY month;

--=====L1 Driver — Supply (Active Loan Book)=====--

-- Active loan book size by month
-- Feeds MATU by enabling loan repayment transactions
SELECT
    TO_CHAR(DATE_TRUNC('month', disbursement_date), 'YYYY-MM')
                                                            AS month,
    COUNT(*) FILTER (WHERE loan_status = 'active')          AS active_loans,
    ROUND(SUM(loan_amount) FILTER (
        WHERE loan_status = 'active'), 0)                   AS active_book_size,
    COUNT(*) FILTER (WHERE loan_status
        IN ('npa','defaulted'))                             AS npa_loans,
    ROUND(100.0 * COUNT(*) FILTER (WHERE loan_status
        IN ('npa','defaulted'))
        / NULLIF(COUNT(*), 0), 2)                           AS npa_rate_pct
FROM loans
GROUP BY DATE_TRUNC('month', disbursement_date)
ORDER BY month;

--=====L1 Driver — Demand (KYC + Payment Frequency)=====--

-- Tracks both activation pipeline and usage intensity
SELECT
    TO_CHAR(u.signup_date, 'YYYY-MM')                       AS cohort_month,

    -- KYC activation (top of demand funnel)
    COUNT(DISTINCT u.user_id)                               AS signups,
    COUNT(DISTINCT CASE WHEN k.kyc_status = 'approved'
          THEN u.user_id END)                               AS kyc_activated,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN k.kyc_status = 'approved'
          THEN u.user_id END)
        / NULLIF(COUNT(DISTINCT u.user_id), 0), 2)          AS kyc_rate_pct,

    -- Payment frequency of activated users
    ROUND(COUNT(t.transaction_id) * 1.0
        / NULLIF(COUNT(DISTINCT CASE WHEN k.kyc_status = 'approved'
                                     THEN u.user_id END), 0)
    , 2)                                                    AS txns_per_activated_user,

    -- Product ladder: % who reached BNPL or loans
    ROUND(100.0 * COUNT(DISTINCT b.user_id)
        / NULLIF(COUNT(DISTINCT CASE WHEN k.kyc_status = 'approved'
                                     THEN u.user_id END), 0)
    , 2)                                                    AS bnpl_adoption_pct

FROM users u
LEFT JOIN user_kyc k    ON u.user_id = k.user_id
LEFT JOIN transactions t ON u.user_id = t.sender_id
                        AND t.status   = 'success'
LEFT JOIN bnpl_orders b  ON u.user_id = b.user_id
GROUP BY TO_CHAR(u.signup_date, 'YYYY-MM')
ORDER BY cohort_month;

---====L1 Driver — Demand (KYC + Payment Frequency)======--
-- Tracks both activation pipeline and usage intensity

SELECT
    TO_CHAR(u.signup_date, 'YYYY-MM')                       AS cohort_month,

    -- KYC activation (top of demand funnel)
    COUNT(DISTINCT u.user_id)                               AS signups,
    COUNT(DISTINCT CASE WHEN k.kyc_status = 'approved'
          THEN u.user_id END)                               AS kyc_activated,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN k.kyc_status = 'approved'
          THEN u.user_id END)
        / NULLIF(COUNT(DISTINCT u.user_id), 0), 2)          AS kyc_rate_pct,

    -- Payment frequency of activated users
    ROUND(COUNT(t.transaction_id) * 1.0
        / NULLIF(COUNT(DISTINCT CASE WHEN k.kyc_status = 'approved'
                                     THEN u.user_id END), 0)
    , 2)                                                    AS txns_per_activated_user,

    -- Product ladder: % who reached BNPL or loans
    ROUND(100.0 * COUNT(DISTINCT b.user_id)
        / NULLIF(COUNT(DISTINCT CASE WHEN k.kyc_status = 'approved'
                                     THEN u.user_id END), 0)
    , 2)                                                    AS bnpl_adoption_pct

FROM users u
LEFT JOIN user_kyc k    ON u.user_id = k.user_id
LEFT JOIN transactions t ON u.user_id = t.sender_id
                        AND t.status   = 'success'
LEFT JOIN bnpl_orders b  ON u.user_id = b.user_id
GROUP BY TO_CHAR(u.signup_date, 'YYYY-MM')
ORDER BY cohort_month;

--=====L1 Driver — Quality (NPA + App Health Proxy)=====--

-- Quality guardrails that protect MATU from being gamed
-- If NPA rises, credit availability shrinks → MATU falls

SELECT
    TO_CHAR(DATE_TRUNC('month', l.disbursement_date), 'YYYY-MM')
                                                            AS month,

    -- Credit quality
    ROUND(100.0 * COUNT(DISTINCT lp.loan_id) FILTER (WHERE l.loan_status
        IN ('npa','defaulted'))
        / NULLIF(COUNT(*), 0), 2)                           AS npa_rate_pct,

    -- Collection quality
    ROUND(100.0 * SUM(lp.paid_amount)
        / NULLIF(SUM(lp.due_amount), 0), 2)                 AS collection_efficiency_pct,

    -- Early delinquency signal (leading indicator)
    ROUND(100.0 * COUNT(DISTINCT lp.loan_id) FILTER (
        WHERE lp.days_past_due BETWEEN 1 AND 30)
        / NULLIF(COUNT(DISTINCT l.loan_id) FILTER (
            WHERE l.loan_status = 'active'), 0)
    , 2)                                                    AS early_delinquency_pct

FROM loans l
LEFT JOIN loan_payments lp ON l.loan_id = lp.loan_id
GROUP BY DATE_TRUNC('month', l.disbursement_date)
ORDER BY month;

--=====Simulated MATU Drop — Root Cause Analysis=====--

-- The money query: MATU dropped 18% in October
-- Walk through every branch of the metric tree
-- to find which L1 driver caused it

WITH sep AS (
    SELECT
        COUNT(DISTINCT CASE WHEN product IN ('payment','bnpl','loan')
              THEN user_id END)                             AS matu,
        COUNT(DISTINCT CASE WHEN product = 'payment'
              THEN user_id END)                             AS payment_matu,
        COUNT(DISTINCT CASE WHEN product = 'bnpl'
              THEN user_id END)                             AS bnpl_matu,
        COUNT(DISTINCT CASE WHEN product = 'loan'
              THEN user_id END)                             AS loan_matu
    FROM (
        SELECT sender_id AS user_id, 'payment' AS product
        FROM transactions
        WHERE status = 'success'
          AND transaction_date BETWEEN '2024-09-01' AND '2024-09-30'
        UNION ALL
        SELECT user_id, 'bnpl'
        FROM bnpl_orders
        WHERE order_date BETWEEN '2024-09-01' AND '2024-09-30'
        UNION ALL
        SELECT user_id, 'loan'
        FROM loan_payments
        WHERE status = 'paid'
          AND paid_date BETWEEN '2024-09-01' AND '2024-09-30'
    ) t
),
oct AS (
    SELECT
        COUNT(DISTINCT CASE WHEN product IN ('payment','bnpl','loan')
              THEN user_id END)                             AS matu,
        COUNT(DISTINCT CASE WHEN product = 'payment'
              THEN user_id END)                             AS payment_matu,
        COUNT(DISTINCT CASE WHEN product = 'bnpl'
              THEN user_id END)                             AS bnpl_matu,
        COUNT(DISTINCT CASE WHEN product = 'loan'
              THEN user_id END)                             AS loan_matu
    FROM (
        SELECT sender_id AS user_id, 'payment' AS product
        FROM transactions
        WHERE status = 'success'
          AND transaction_date BETWEEN '2024-10-01' AND '2024-10-31'
        UNION ALL
        SELECT user_id, 'bnpl'
        FROM bnpl_orders
        WHERE order_date BETWEEN '2024-10-01' AND '2024-10-31'
        UNION ALL
        SELECT user_id, 'loan'
        FROM loan_payments
        WHERE status = 'paid'
          AND paid_date BETWEEN '2024-10-01' AND '2024-10-31'
    ) t
)

SELECT
    'MATU (North Star)'                                     AS metric,
    s.matu                                                  AS sep_value,
    o.matu                                                  AS oct_value,
    ROUND(100.0 * (o.matu - s.matu)
        / NULLIF(s.matu, 0), 2)                             AS pct_change
FROM sep s, oct o

UNION ALL 

SELECT 'L1: Payment Users',
    s.payment_matu,
	o.payment_matu,
    ROUND(100.0*(o.payment_matu-s.payment_matu)
        /NULLIF(s.payment_matu,0),2) 
FROM sep s, oct o

UNION ALL 

SELECT 'L1: BNPL Users',
    s.bnpl_matu, o.bnpl_matu,
    ROUND(100.0*(o.bnpl_matu-s.bnpl_matu)
        /NULLIF(s.bnpl_matu,0),2) 
FROM sep s, oct o

UNION ALL 

SELECT 'L1: Loan Payers',
    s.loan_matu, o.loan_matu,
    ROUND(100.0*(o.loan_matu-s.loan_matu)
        /NULLIF(s.loan_matu,0),2)
FROM sep s, oct o;

-- Whichever L1 shows the biggest % drop
-- is the branch to investigate next
-- Then drill into its L2 drivers
