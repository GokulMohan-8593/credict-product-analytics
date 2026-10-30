----===data===----

select * from sessions
select * from  transactions 
select * from  bnpl_orders
select * from  loans 

--==============DAU / MAU / Stickiness=============--

--The Business Question
"How many users are actively using Credict each day and month — and how habitual is that usage?"

--======Daily Active Users (DAU)======--
SELECT
    session_date                                                    AS activity_date,
    COUNT(DISTINCT user_id)                                         AS dau,
    COUNT(session_id)                                               AS total_sessions,
    ROUND(COUNT(session_id) * 1.0
        / NULLIF(COUNT(DISTINCT user_id), 0), 2)                   AS sessions_per_user,
    ROUND(AVG(duration_sec) / 60.0, 2)                             AS avg_session_min
FROM sessions
GROUP BY session_date
ORDER BY session_date

--======Monthly Active Users (MAU)======--

WITH MONTHLY_METRICS AS 
(
SELECT
    DATE_TRUNC('month', session_date)                               AS month,
    COUNT(DISTINCT user_id)                                         AS mau,
    COUNT(session_id)                                               AS total_sessions,
    ROUND(AVG(duration_sec) / 60.0, 2)                             	AS avg_session_min
FROM sessions
GROUP BY DATE_TRUNC('month', session_date)
)

SELECT *,
    -- MoM MAU growth
    LAG(MAU)	OVER (ORDER BY month)           					AS prev_mau,
    ROUND(100.0 * (MAU - LAG(MAU) OVER (ORDER BY month))
        / NULLIF(LAG(MAU) OVER (ORDER BY month), 0)
    , 2)                                                            AS mom_growth_pct
FROM MONTHLY_METRICS

--======Stickiness (DAU/MAU) by Month======--


WITH dau_daily AS (
    SELECT
        session_date,
        DATE_TRUNC('month', session_date)   AS month,
        COUNT(DISTINCT user_id)             AS dau
    FROM sessions
    GROUP BY session_date
),
avg_dau AS (
    SELECT
        month,
        ROUND(AVG(dau), 2)                  AS avg_dau
    FROM dau_daily
    GROUP BY month
),
mau AS (
    SELECT
        DATE_TRUNC('month', session_date)   AS month,
        COUNT(DISTINCT user_id)             AS mau
    FROM sessions
    GROUP BY 1
)
SELECT
    m.month,
    a.avg_dau,
    m.mau,
    ROUND(100.0 * a.avg_dau
        / NULLIF(m.mau, 0), 2)              AS stickiness_pct,
    CASE
        WHEN ROUND(100.0 * a.avg_dau / NULLIF(m.mau, 0), 2) >= 50
        THEN 'Excellent'
        WHEN ROUND(100.0 * a.avg_dau / NULLIF(m.mau, 0), 2) >= 25
        THEN 'Good'
        WHEN ROUND(100.0 * a.avg_dau / NULLIF(m.mau, 0), 2) >= 10
        THEN 'Moderate'
        ELSE 'Low'
    END                                     AS stickiness_rating
FROM mau m
JOIN avg_dau a ON m.month = a.month
ORDER BY m.month

--=====DAU/MAU by City Tier=====--

WITH dau_daily AS (
    SELECT
        s.session_date,
        DATE_TRUNC('month', s.session_date) AS month,
        u.city_tier,
        COUNT(DISTINCT s.user_id)           AS dau
    FROM sessions s
    JOIN users u ON s.user_id = u.user_id
    GROUP BY 1, 2, 3
),
avg_dau AS (
    SELECT
        month,
        city_tier,
        ROUND(AVG(dau), 2)                  AS avg_dau
    FROM dau_daily
    GROUP BY month, city_tier
),
mau AS (
    SELECT
        DATE_TRUNC('month', s.session_date) AS month,
        u.city_tier,
        COUNT(DISTINCT s.user_id)           AS mau
    FROM sessions s
    JOIN users u ON s.user_id = u.user_id
    GROUP BY 1, 2
)
SELECT
    m.month,
    m.city_tier,
    ROUND(a.avg_dau, 0)                     AS avg_dau,
    m.mau,
    ROUND(100.0 * a.avg_dau
        / NULLIF(m.mau, 0), 2)              AS stickiness_pct
FROM mau m
JOIN avg_dau a
  ON m.month     = a.month
 AND m.city_tier = a.city_tier
ORDER BY m.month, m.city_tier

--=====WAU (Weekly Active Users) — Smooths Daily Noise=====--

WITH WEEKLY_METRICS AS
(
SELECT
    DATE_TRUNC('week', session_date)        				AS week,
    COUNT(DISTINCT user_id)                 				AS wau,
    COUNT(session_id)                      			 		AS total_sessions,
    ROUND(AVG(duration_sec) / 60.0, 2)     					AS avg_session_min,
    LAG(COUNT(DISTINCT user_id))
        OVER (ORDER BY DATE_TRUNC('week', session_date)) 	AS prev_wau
FROM sessions
GROUP BY DATE_TRUNC('week', session_date)
ORDER BY week
)

SELECT
	*,
    ROUND(100.0 * (wau - prev_wau) / NULLIF(prev_wau,0),2)     AS wow_growth_pct
FROM WEEKLY_METRICS

--======Product Adoption Ladder======--

"Do users start with payments and graduate to BNPL and loans over time — or are they staying stuck on just one product?

Payments (low revenue, high frequency)
      ↓
BNPL  (medium revenue, medium frequency)
      ↓
Loans (high revenue, low frequency)
      ↓
Premium Wallet (recurring revenue)  "

--=====What % of Users Use Each Product=====-

SELECT
    DISTINCT U.user_id
FROM users u
JOIN user_kyc k   ON u.user_id   = k.user_id
                  AND k.kyc_status = 'approved'
LEFT JOIN transactions t ON u.user_id = t.sender_id
LEFT JOIN bnpl_orders  b ON u.user_id = b.user_id
LEFT JOIN loans        l ON u.user_id = l.user_id
WHERE 	T.sender_id IS NULL OR 
		B.user_id IS NULL OR
		L.user_id IS NULL

WITH user_products AS 
(
	SELECT
	    COUNT(DISTINCT u.user_id)                                       AS total_activated,
	    COUNT(DISTINCT t.sender_id)                                     AS used_payments,
		COUNT(DISTINCT b.user_id)                                       AS used_bnpl,
		COUNT(DISTINCT l.user_id)                                       AS used_loans
	FROM users u
	JOIN user_kyc k   ON u.user_id   = k.user_id
	                  AND k.kyc_status = 'approved'
	LEFT JOIN transactions t ON u.user_id = t.sender_id
	LEFT JOIN bnpl_orders  b ON u.user_id = b.user_id
	LEFT JOIN loans        l ON u.user_id = l.user_id
)

SELECT 
	*,
    ROUND(100.0 * used_payments / NULLIF(total_activated, 0), 2)            AS payments_adoption_pct, 
    ROUND(100.0 * used_bnpl / NULLIF(total_activated, 0), 2)                AS bnpl_adoption_pct,
    ROUND(100.0 * used_loans / NULLIF(total_activated, 0), 2)  				AS loans_adoption_pct 
FROM user_products                  

--=====Ladder Stage Classification Per User======-

-- Classify every activated user into their current highest product stage on the ladder

WITH user_products AS (
    SELECT
        u.user_id,
        u.city_tier,
        u.signup_channel,
        CASE WHEN COUNT(DISTINCT t.transaction_id) > 0
             THEN 1 ELSE 0 END                                      AS has_payments,
        CASE WHEN COUNT(DISTINCT b.bnpl_order_id) > 0
             THEN 1 ELSE 0 END                                      AS has_bnpl,
        CASE WHEN COUNT(DISTINCT l.loan_id) > 0
             THEN 1 ELSE 0 END                                      AS has_loans
    FROM users u
    JOIN user_kyc k   ON u.user_id   = k.user_id
                      AND k.kyc_status = 'approved'
    LEFT JOIN transactions t ON u.user_id = t.sender_id
    LEFT JOIN bnpl_orders  b ON u.user_id = b.user_id
    LEFT JOIN loans        l ON u.user_id = l.user_id
    GROUP BY u.user_id, u.city_tier, u.signup_channel
)
SELECT
    user_id,
    city_tier,
    signup_channel,
    has_payments,
    has_bnpl,
    has_loans,
    CASE
        WHEN has_loans    = 1 THEN 'Stage 3 — Loans'
        WHEN has_bnpl     = 1 THEN 'Stage 2 — BNPL'
        WHEN has_payments = 1 THEN 'Stage 1 — Payments'
        ELSE                       'Stage 0 — KYC Only'
    END                                                             AS ladder_stage
INTO Product_Ladder_Stages
FROM user_products
ORDER BY user_id

SELECT 
ladder_stage,
city_tier,
signup_channel,
COUNT(user_id) AS users_in_stage,
ROUND(100.00 * (COUNT(user_id)/SUM(COUNT(user_id)) OVER (PARTITION BY city_tier,signup_channel )),2) AS Overall_Pct_Per_Segment,
ROUND(100.00 * (COUNT(user_id)/SUM(COUNT(user_id)) OVER ()),2) AS Overall_Pct_Per_stage
FROM Product_Ladder_Stages
GROUP BY ladder_stage,city_tier,signup_channel


--======Ladder Stage Distribution — Overall and by Tier=====--


SELECT
    ladder_stage,
    COUNT(*)                                                        AS users,
    ROUND(100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (), 2)                                AS pct_overall,
    COUNT(*) FILTER (WHERE city_tier = 'tier1')                    AS tier1_users,
    COUNT(*) FILTER (WHERE city_tier = 'tier2')                    AS tier2_users,
    COUNT(*) FILTER (WHERE city_tier = 'tier3')                    AS tier3_users
FROM Product_Ladder_Stages
GROUP BY ladder_stage
ORDER BY ladder_stage

--=====Time to Climb Each Ladder Rung=====----
"How many days after KYC approval does a user make their first payment, first BNPL, first loan? "

WITH activation AS (
    SELECT
        user_id,
        kyc_approved_at::DATE                                       AS activation_date
    FROM user_kyc
    WHERE kyc_status = 'approved'
),
first_payment AS (
    SELECT sender_id AS user_id, MIN(transaction_date)             AS first_payment_date
    FROM transactions
    GROUP BY sender_id
),
first_bnpl AS (
    SELECT user_id, MIN(order_date)                                AS first_bnpl_date
    FROM bnpl_orders
    GROUP BY user_id
),
first_loan AS (
    SELECT user_id, MIN(disbursement_date)                         AS first_loan_date
    FROM loans
    GROUP BY user_id
)

SELECT
    ROUND(AVG(fp.first_payment_date - a.activation_date), 1)       AS avg_days_to_first_payment,
    ROUND(AVG(fb.first_bnpl_date    - a.activation_date), 1)       AS avg_days_to_first_bnpl,
    ROUND(AVG(fl.first_loan_date    - a.activation_date), 1)       AS avg_days_to_first_loan,

    -- Percentiles — avg alone hides wide distributions
    PERCENTILE_CONT(0.50) WITHIN GROUP
        (ORDER BY fp.first_payment_date - a.activation_date)        AS p50_days_to_payment,
    PERCENTILE_CONT(0.50) WITHIN GROUP
        (ORDER BY fb.first_bnpl_date - a.activation_date)           AS p50_days_to_bnpl,
    PERCENTILE_CONT(0.50) WITHIN GROUP
        (ORDER BY fl.first_loan_date - a.activation_date)           AS p50_days_to_loan,

    PERCENTILE_CONT(0.90) WITHIN GROUP
        (ORDER BY fp.first_payment_date - a.activation_date)        AS p90_days_to_payment,
    PERCENTILE_CONT(0.90) WITHIN GROUP
        (ORDER BY fb.first_bnpl_date - a.activation_date)           AS p90_days_to_bnpl,
    PERCENTILE_CONT(0.90) WITHIN GROUP
        (ORDER BY fl.first_loan_date - a.activation_date)           AS p90_days_to_loan

FROM activation a
LEFT JOIN first_payment fp ON a.user_id = fp.user_id
LEFT JOIN first_bnpl    fb ON a.user_id = fb.user_id
LEFT JOIN first_loan    fl ON a.user_id = fl.user_id

--=====Multi-Product Users vs Single-Product Users=====--
"Users using more products = higher LTV + lower churn"

WITH user_products AS (
    SELECT
        u.user_id,
        CASE WHEN COUNT(DISTINCT t.transaction_id) > 0
             THEN 1 ELSE 0 END                                      AS has_payments,
        CASE WHEN COUNT(DISTINCT b.bnpl_order_id) > 0
             THEN 1 ELSE 0 END                                      AS has_bnpl,
        CASE WHEN COUNT(DISTINCT l.loan_id) > 0
             THEN 1 ELSE 0 END                                      AS has_loans
    FROM users u
    JOIN user_kyc k ON u.user_id = k.user_id AND k.kyc_status = 'approved'
    LEFT JOIN transactions t ON u.user_id = t.sender_id
    LEFT JOIN bnpl_orders  b ON u.user_id = b.user_id
    LEFT JOIN loans        l ON u.user_id = l.user_id
    GROUP BY u.user_id
),
product_count AS (
    SELECT
        user_id,
        has_payments + has_bnpl + has_loans                         AS products_used,
        has_payments,
        has_bnpl,
        has_loans
    FROM user_products
)
SELECT
    products_used,
    COUNT(*)                                                        AS users,
    ROUND(100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (), 2)                                 AS pct_of_users,

    -- Session engagement — do multi-product users engage more?
    ROUND(AVG(s.session_count), 1)                                  AS avg_sessions,
    ROUND(AVG(s.avg_duration_min), 1)                               AS avg_session_min
FROM product_count pc
LEFT JOIN (
    SELECT
        user_id,
        COUNT(session_id)                                           AS session_count,
        ROUND(AVG(duration_sec) / 60.0, 2)                         AS avg_duration_min
    FROM sessions
    GROUP BY user_id
) s ON pc.user_id = s.user_id
GROUP BY products_used
ORDER BY products_used

--=====Ladder Stage by Cohort Month=====--

WITH user_products AS (
    SELECT
        u.user_id,
        DATE_TRUNC('month', u.signup_date) AS cohort_month,
        CASE
            WHEN COUNT(DISTINCT l.loan_id) > 0     THEN 'Stage 3 — Loans'
            WHEN COUNT(DISTINCT b.bnpl_order_id) >0 THEN 'Stage 2 — BNPL'
            WHEN COUNT(DISTINCT t.transaction_id) >0 THEN 'Stage 1 — Payments'
            ELSE                                        'Stage 0 — KYC Only'
        END                                                         AS ladder_stage
    FROM users u
    JOIN user_kyc k ON u.user_id = k.user_id AND k.kyc_status = 'approved'
    LEFT JOIN transactions t ON u.user_id = t.sender_id
    LEFT JOIN bnpl_orders  b ON u.user_id = b.user_id
    LEFT JOIN loans        l ON u.user_id = l.user_id
    GROUP BY u.user_id, DATE_TRUNC('month', u.signup_date) 
),
activation AS (
    SELECT
        user_id,
        kyc_approved_at::DATE                                       AS activation_date
    FROM user_kyc
    WHERE kyc_status = 'approved'
),
first_payment AS (
    SELECT sender_id AS user_id, MIN(transaction_date)             AS first_payment_date
    FROM transactions
    GROUP BY sender_id
),
first_bnpl AS (
    SELECT user_id, MIN(order_date)                                AS first_bnpl_date
    FROM bnpl_orders
    GROUP BY user_id
),
first_loan AS (
    SELECT user_id, MIN(disbursement_date)                         AS first_loan_date
    FROM loans
    GROUP BY user_id
)
SELECT
    cohort_month,
    COUNT(*)                                                        AS total_users,
    ROUND(100.0 * COUNT(*) FILTER (WHERE ladder_stage = 'Stage 0 — KYC Only')
        / NULLIF(COUNT(*), 0), 1)                                   AS pct_stage0,
    ROUND(100.0 * COUNT(*) FILTER (WHERE ladder_stage = 'Stage 1 — Payments')
        / NULLIF(COUNT(*), 0), 1)                                   AS pct_stage1,
    ROUND(100.0 * COUNT(*) FILTER (WHERE ladder_stage = 'Stage 2 — BNPL')
        / NULLIF(COUNT(*), 0), 1)                                   AS pct_stage2,
    ROUND(100.0 * COUNT(*) FILTER (WHERE ladder_stage = 'Stage 3 — Loans')
        / NULLIF(COUNT(*), 0), 1)                                   AS pct_stage3,
	PERCENTILE_CONT(0.50) WITHIN GROUP
	(ORDER BY  (fp.first_payment_date - ac.activation_date )) 		AS days_to_payment,
	PERCENTILE_CONT(0.50) WITHIN GROUP
	(ORDER BY (fb.first_bnpl_date - ac.activation_date )) 			AS days_to_BNPL,
	PERCENTILE_CONT(0.50) WITHIN GROUP
	(ORDER BY (fl.first_loan_date - ac.activation_date ))					AS days_to_Loan
FROM user_products a
LEFT JOIN activation    ac ON a.user_id = ac.user_id
LEFT JOIN first_payment fp ON a.user_id = fp.user_id
LEFT JOIN first_bnpl    fb ON a.user_id = fb.user_id
LEFT JOIN first_loan    fl ON a.user_id = fl.user_id
GROUP BY cohort_month
ORDER BY cohort_month

--=============================================================================----
--------====================Cohort Retention Matrix=========================-------
--=============================================================================----

--=====Monthly Cohort Retention Matrix======--
    -- Each user's cohort = month of KYC approval (activation)
    -- Not signup date — we measure retention from first value
WITH cohort_base AS (
    SELECT
        u.user_id,
        DATE_TRUNC('month', k.kyc_approved_at)              AS cohort_month
    FROM users u
    JOIN user_kyc k ON u.user_id = k.user_id
    WHERE k.kyc_status = 'approved'
),
    -- All months a user was active (had at least one session)
user_activity AS (
    SELECT DISTINCT
        user_id,
        DATE_TRUNC('month', session_date)                   AS activity_month
    FROM sessions
),
cohort_activity AS (
    -- Join to get months since cohort start for each activity
    SELECT
        c.user_id,
        c.cohort_month,
        ua.activity_month,
        EXTRACT(MONTH FROM AGE(ua.activity_month, c.cohort_month))
            ::INT                                           AS month_number
    FROM cohort_base c
    JOIN user_activity ua ON c.user_id = ua.user_id
    WHERE ua.activity_month >= c.cohort_month
)
SELECT
    TO_CHAR(cohort_month, 'YYYY-MM')                        AS cohort_month,
    COUNT(DISTINCT user_id)                                 AS cohort_size,

    -- Month 0 = activation month 
    COUNT(DISTINCT CASE WHEN month_number = 0
          THEN user_id END)                                 AS m0,
    COUNT(DISTINCT CASE WHEN month_number = 1
          THEN user_id END)                                 AS m1,
    COUNT(DISTINCT CASE WHEN month_number = 2
          THEN user_id END)                                 AS m2,
    COUNT(DISTINCT CASE WHEN month_number = 3
          THEN user_id END)                                 AS m3,
    COUNT(DISTINCT CASE WHEN month_number = 4
          THEN user_id END)                                 AS m4,
    COUNT(DISTINCT CASE WHEN month_number = 5
          THEN user_id END)                                 AS m5,
    COUNT(DISTINCT CASE WHEN month_number = 6
          THEN user_id END)                                 AS m6
INTO MONTHLY_COHORT_RETENTION
FROM cohort_activity
GROUP BY cohort_month
ORDER BY cohort_month

--=====Retention Matrix as Percentages=====--

SELECT * FROM MONTHLY_COHORT_RETENTION

SELECT 
	cohort_month,
	cohort_size,
 	ROUND(100.0 * M0 / cohort_size, 1)              AS m0_pct,
	ROUND(100.0 * M1 / cohort_size, 1)              AS m1_pct,
 	ROUND(100.0 * M2 / cohort_size, 1)              AS m2_pct,
 	ROUND(100.0 * M3 / cohort_size, 1)              AS m3_pct,
 	ROUND(100.0 * M4 / cohort_size, 1)              AS m4_pct,
 	ROUND(100.0 * M5 / cohort_size, 1)              AS m5_pct,
 	ROUND(100.0 * M6 / cohort_size, 1)              AS m6_pct
FROM MONTHLY_COHORT_RETENTION

--=====Retention by City Tier=====--
"Are tier1 cohorts retaining better than tier3?"

WITH cohort_base AS (
    SELECT
        u.user_id,
        u.city_tier,
        DATE_TRUNC('month', k.kyc_approved_at)              AS cohort_month
    FROM users u
    JOIN user_kyc k ON u.user_id = k.user_id
    WHERE k.kyc_status = 'approved'
),
user_activity AS (
    SELECT DISTINCT
        user_id,
        DATE_TRUNC('month', session_date)                   AS activity_month
    FROM sessions
),
cohort_activity AS (
    SELECT
        c.user_id,
        c.city_tier,
        c.cohort_month,
        EXTRACT(MONTH FROM AGE(ua.activity_month, c.cohort_month))
            ::INT                                           AS month_number
    FROM cohort_base c
    JOIN user_activity ua ON c.user_id = ua.user_id
    WHERE ua.activity_month >= c.cohort_month
),
cohort_sizes AS (
    SELECT
        city_tier,
        COUNT(DISTINCT user_id)                             AS cohort_size
    FROM cohort_base
    GROUP BY city_tier
)
SELECT
    ca.city_tier,
    cs.cohort_size,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_number = 1
        THEN user_id END) / cs.cohort_size, 1)              AS m1_retention_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_number = 3
        THEN user_id END) / cs.cohort_size, 1)              AS m3_retention_pct,
	ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_number = 4
        THEN user_id END) / cs.cohort_size, 1)              AS m4_retention_pct,
	ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_number = 5
        THEN user_id END) / cs.cohort_size, 1)              AS m5_retention_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_number = 6
        THEN user_id END) / cs.cohort_size, 1)              AS m6_retention_pct
FROM cohort_activity ca
JOIN cohort_sizes cs ON ca.city_tier = cs.city_tier
GROUP BY ca.city_tier, cs.cohort_size
ORDER BY ca.city_tier

--=====Retention by Channel======--

WITH cohort_base AS (
    SELECT
        u.user_id,
        u.signup_channel,
        DATE_TRUNC('month', k.kyc_approved_at)              AS cohort_month
    FROM users u
    JOIN user_kyc k ON u.user_id = k.user_id
    WHERE k.kyc_status = 'approved'
),
user_activity AS (
    SELECT DISTINCT
        user_id,
        DATE_TRUNC('month', session_date)                   AS activity_month
    FROM sessions
),
cohort_activity AS (
    SELECT
        c.user_id,
        c.signup_channel,
        EXTRACT(MONTH FROM AGE(ua.activity_month, c.cohort_month))
            ::INT                                           AS month_number
    FROM cohort_base c
    JOIN user_activity ua ON c.user_id = ua.user_id
    WHERE ua.activity_month >= c.cohort_month
),
cohort_sizes AS (
    SELECT
        signup_channel,
        COUNT(DISTINCT user_id)                             AS cohort_size
    FROM cohort_base
    GROUP BY signup_channel
)
SELECT
    ca.signup_channel,
    cs.cohort_size,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_number = 1
        THEN user_id END) / cs.cohort_size, 1)              AS m1_retention_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_number = 3
        THEN user_id END) / cs.cohort_size, 1)              AS m3_retention_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_number = 6
        THEN user_id END) / cs.cohort_size, 1)              AS m6_retention_pct,

    -- Retention efficiency = M6 / M1
    -- High ratio = users who stay at M1 tend to stay long term
    ROUND(
        COUNT(DISTINCT CASE WHEN month_number = 6 THEN user_id END) * 1.0
        / NULLIF(COUNT(DISTINCT CASE WHEN month_number = 1
                                     THEN user_id END), 0)
    , 2)                                                    AS m1_to_m6_survival_rate

FROM cohort_activity ca
JOIN cohort_sizes cs ON ca.signup_channel = cs.signup_channel
GROUP BY ca.signup_channel, cs.cohort_size
ORDER BY m6_retention_pct DESC

--=====Average Retention Curve — Flattening Check=====--

" 	Averages all cohorts to give one retention curve
 	A flattening curve = healthy retained core base
	A curve hitting zero = no long term retention
"

WITH cohort_base AS (
    SELECT
        u.user_id,
        DATE_TRUNC('month', k.kyc_approved_at)              AS cohort_month
    FROM users u
    JOIN user_kyc k ON u.user_id = k.user_id
    WHERE k.kyc_status = 'approved'
),
user_activity AS (
    SELECT DISTINCT
        user_id,
        DATE_TRUNC('month', session_date)                   AS activity_month
    FROM sessions
),
cohort_activity AS (
    SELECT
        c.user_id,
        c.cohort_month,
        EXTRACT(MONTH FROM AGE(ua.activity_month, c.cohort_month))
            ::INT                                           AS month_number
    FROM cohort_base c
    JOIN user_activity ua ON c.user_id = ua.user_id
    WHERE ua.activity_month >= c.cohort_month
),
cohort_sizes AS (
    SELECT cohort_month,
	COUNT(DISTINCT user_id) 								AS cohort_size
    FROM cohort_base
    GROUP BY cohort_month
),
monthly_retained AS (
    SELECT
        ca.cohort_month,
        ca.month_number,
        COUNT(DISTINCT ca.user_id)                          AS retained_users,
        cs.cohort_size
    FROM cohort_activity ca
    JOIN cohort_sizes cs ON ca.cohort_month = cs.cohort_month
    GROUP BY ca.cohort_month, ca.month_number, cs.cohort_size
)
SELECT
    month_number,
    -- Weighted average retention across all cohorts
    ROUND(100.0 * SUM(retained_users)
        / NULLIF(SUM(cohort_size), 0), 2)                   AS avg_retention_pct,
    SUM(retained_users)                                     AS total_retained,
    SUM(cohort_size)                                        AS total_cohort_base
FROM monthly_retained
GROUP BY month_number
ORDER BY month_number


--=============================================================================----
--------====================4-State User Model=========================-------
--=============================================================================----

"Each month, exactly how many users are new, coming back, dropping off, or returning after being gone? Is Credict growing healthily or running on a treadmill?"

--=====Monthly User States — Core Query======--

WITH monthly_active AS (
    -- All months each user had at least one session
    SELECT DISTINCT
        user_id,
        DATE_TRUNC('month', session_date)                   AS activity_month
    FROM sessions
),
with_prev AS (
    SELECT
        user_id,
        activity_month,
        LAG(activity_month) OVER (
            PARTITION BY user_id
            ORDER BY activity_month
        )                                                   AS prev_activity_month
    FROM monthly_active
),
user_states AS (
    -- Classify each user-month as one of 4 states
    SELECT
        wa.activity_month                                   AS month,
        wa.user_id,
        CASE
            -- New: first ever month of activity
            WHEN wa.prev_activity_month IS NULL
            THEN 'new'
            -- Retained: active last month AND this month
            WHEN wa.prev_activity_month
                 = wa.activity_month - INTERVAL '1 month'
            THEN 'retained'
            -- Resurrected: was inactive for 1+ months, now back
            ELSE 'resurrected'
        END                                                 AS user_state
    FROM with_prev wa
),
-- Churned users: active last month but NOT this month
churned AS (
    SELECT
        ma.activity_month + INTERVAL '1 month'              AS month,
        ma.user_id,
        'churned'                                           AS user_state
    FROM monthly_active ma
    WHERE NOT EXISTS (
        SELECT 1
        FROM monthly_active ma2
        WHERE ma2.user_id       = ma.user_id
          AND ma2.activity_month = ma.activity_month
                                  + INTERVAL '1 month'
    )
    -- Exclude last month — can't know if Dec users will
    -- come back in Jan (outside our data window)
    AND ma.activity_month < DATE_TRUNC('month',
                                       '2024-12-01'::DATE)
)
SELECT
    TO_CHAR(month, 'YYYY-MM')                               AS month,
    user_state,
    COUNT(DISTINCT user_id)                                 AS users
FROM (
    SELECT * FROM user_states
    UNION ALL
    SELECT * FROM churned
) all_states
GROUP BY month, user_state
ORDER BY month, user_state

--====Pivoted — One Row Per Month, All 4 States as Columns=====--

WITH monthly_active AS (
    SELECT DISTINCT
        user_id,
        DATE_TRUNC('month', session_date)                   AS activity_month
    FROM sessions
),
with_prev AS (
    SELECT
        user_id,
        activity_month,
        LAG(activity_month) OVER (
            PARTITION BY user_id ORDER BY activity_month
        )                                                   AS prev_activity_month
    FROM monthly_active
),
user_states AS (
    SELECT
        activity_month                                      AS month,
        user_id,
        CASE
            WHEN prev_activity_month IS NULL
            THEN 'new'
            WHEN prev_activity_month
                 = activity_month - INTERVAL '1 month'
            THEN 'retained'
            ELSE 'resurrected'
        END                                                 AS user_state
    FROM with_prev
),
churned AS (
    SELECT
        activity_month + INTERVAL '1 month'                 AS month,
        user_id,
        'churned'                                           AS user_state
    FROM monthly_active
    WHERE NOT EXISTS (
        SELECT 1 FROM monthly_active ma2
        WHERE ma2.user_id        = monthly_active.user_id
          AND ma2.activity_month  = monthly_active.activity_month
                                   + INTERVAL '1 month'
    )
    AND activity_month < DATE_TRUNC('month', '2024-12-01'::DATE)
),
all_states AS (
    SELECT * FROM user_states
    UNION ALL
    SELECT * FROM churned
)
SELECT
    TO_CHAR(month, 'YYYY-MM')                               AS month,

    COUNT(DISTINCT CASE WHEN user_state = 'new'
          THEN user_id END)                                 AS new_users,

    COUNT(DISTINCT CASE WHEN user_state = 'retained'
          THEN user_id END)                                 AS retained_users,

    COUNT(DISTINCT CASE WHEN user_state = 'churned'
          THEN user_id END)                                 AS churned_users,

    COUNT(DISTINCT CASE WHEN user_state = 'resurrected'
          THEN user_id END)                                 AS resurrected_users,

    -- Net change = new + resurrected - churned
    COUNT(DISTINCT CASE WHEN user_state = 'new'
          THEN user_id END)
    + COUNT(DISTINCT CASE WHEN user_state = 'resurrected'
            THEN user_id END)
    - COUNT(DISTINCT CASE WHEN user_state = 'churned'
            THEN user_id END)                               AS net_user_change,

    -- Total MAU = retained + new + resurrected
    COUNT(DISTINCT CASE WHEN user_state != 'churned'
          THEN user_id END)                                 AS mau,

    -- Health ratio: retained / (retained + churned)
    -- Higher = more stable base
    ROUND(100.0 *
        COUNT(DISTINCT CASE WHEN user_state = 'retained'
              THEN user_id END)
        / NULLIF(
            COUNT(DISTINCT CASE WHEN user_state = 'retained'
                  THEN user_id END)
            + COUNT(DISTINCT CASE WHEN user_state = 'churned'
                  THEN user_id END)
          , 0), 2)                                          AS monthly_retention_rate

FROM all_states
GROUP BY month
ORDER BY month

--=====4-State by Channel — Which Channel Retains Best?======--

WITH monthly_active AS (
    SELECT DISTINCT
        s.user_id,
        u.signup_channel,
        DATE_TRUNC('month', s.session_date)                 AS activity_month
    FROM sessions s
    JOIN users u ON s.user_id = u.user_id
),
with_prev AS (
    SELECT
        user_id,
        signup_channel,
        activity_month,
        LAG(activity_month) OVER (
            PARTITION BY user_id ORDER BY activity_month
        )                                                   AS prev_activity_month
    FROM monthly_active
),
user_states AS (
    SELECT
        signup_channel,
        activity_month                                      AS month,
        user_id,
        CASE
            WHEN prev_activity_month IS NULL               THEN 'new'
            WHEN prev_activity_month
                 = activity_month - INTERVAL '1 month'     THEN 'retained'
            ELSE                                                'resurrected'
        END                                                 AS user_state
    FROM with_prev
),
churned AS (
    SELECT
        signup_channel,
        activity_month + INTERVAL '1 month'                 AS month,
        user_id,
        'churned'                                           AS user_state
    FROM monthly_active
    WHERE NOT EXISTS (
        SELECT 1 FROM monthly_active ma2
        WHERE ma2.user_id        = monthly_active.user_id
          AND ma2.activity_month  = monthly_active.activity_month
                                   + INTERVAL '1 month'
    )
    AND activity_month < DATE_TRUNC('month', '2024-12-01'::DATE)
),
all_states AS (
    SELECT * FROM user_states
    UNION ALL
    SELECT * FROM churned
)
SELECT
    signup_channel,
    COUNT(DISTINCT CASE WHEN user_state = 'new'
          THEN user_id END)                                 AS total_new,
    COUNT(DISTINCT CASE WHEN user_state = 'retained'
          THEN user_id END)                                 AS total_retained,
    COUNT(DISTINCT CASE WHEN user_state = 'churned'
          THEN user_id END)                                 AS total_churned,
    COUNT(DISTINCT CASE WHEN user_state = 'resurrected'
          THEN user_id END)                                 AS total_resurrected,

    -- Churn rate across all months
    ROUND(100.0 *
        COUNT(DISTINCT CASE WHEN user_state = 'churned'
              THEN user_id END)
        / NULLIF(
            COUNT(DISTINCT CASE WHEN user_state IN ('retained','churned')
                  THEN user_id END)
          , 0), 2)                                          AS avg_churn_rate_pct,

    -- Resurrection rate: how often do churned users come back?
    ROUND(100.0 *
        COUNT(DISTINCT CASE WHEN user_state = 'resurrected'
              THEN user_id END)
        / NULLIF(
            COUNT(DISTINCT CASE WHEN user_state = 'churned'
                  THEN user_id END)
          , 0), 2)                                          AS resurrection_rate_pct

FROM all_states
GROUP BY signup_channel
ORDER BY avg_churn_rate_pct

--=====Growth Accounting — Is Credict Growing Healthily?======--

-- The definitive growth health check
-- Shows exactly what is driving MAU movement each month
WITH monthly_active AS (
    SELECT DISTINCT
        user_id,
        DATE_TRUNC('month', session_date)                   AS activity_month
    FROM sessions
),
with_prev AS (
    SELECT
        user_id,
        activity_month,
        LAG(activity_month) OVER (
            PARTITION BY user_id ORDER BY activity_month
        )                                                   AS prev_activity_month
    FROM monthly_active
),
user_states AS (
    SELECT
        activity_month AS month, user_id,
        CASE
            WHEN prev_activity_month IS NULL               THEN 'new'
            WHEN prev_activity_month
                 = activity_month - INTERVAL '1 month'     THEN 'retained'
            ELSE                                                'resurrected'
        END                                                 AS user_state
    FROM with_prev
),
churned AS (
    SELECT
        activity_month + INTERVAL '1 month' AS month,
        user_id, 'churned'                  AS user_state
    FROM monthly_active
    WHERE NOT EXISTS (
        SELECT 1 FROM monthly_active m2
        WHERE m2.user_id = monthly_active.user_id
          AND m2.activity_month = monthly_active.activity_month
                                  + INTERVAL '1 month'
    )
    AND activity_month < DATE_TRUNC('month', '2024-12-01'::DATE)
),
all_states AS (
    SELECT * FROM user_states
	UNION ALL 
	SELECT * FROM churned
),
monthly_summary AS (
    SELECT
        TO_CHAR(month, 'YYYY-MM')                           AS month,
        COUNT(DISTINCT CASE WHEN user_state = 'new'
              THEN user_id END)                             AS new_users,
        COUNT(DISTINCT CASE WHEN user_state = 'retained'
              THEN user_id END)                             AS retained_users,
        COUNT(DISTINCT CASE WHEN user_state = 'churned'
              THEN user_id END)                             AS churned_users,
        COUNT(DISTINCT CASE WHEN user_state = 'resurrected'
              THEN user_id END)                             AS resurrected_users,
        COUNT(DISTINCT CASE WHEN user_state != 'churned'
              THEN user_id END)                             AS mau
    FROM all_states
    GROUP BY month
)
SELECT
    month,
    new_users,
    retained_users,
    churned_users,
    resurrected_users,
    mau,

    LAG(mau) OVER (ORDER BY month)                          AS prev_mau,

    -- Net change decomposed into its true drivers
    new_users + resurrected_users - churned_users           AS net_change,

    -- What % of MAU growth came from new users vs resurrection?
    ROUND(100.0 * new_users
        / NULLIF(new_users + resurrected_users, 0), 1)     AS pct_growth_from_new,

    ROUND(100.0 * resurrected_users
        / NULLIF(new_users + resurrected_users, 0), 1)     AS pct_growth_from_resurrection,

    -- Churn as % of prior MAU
    ROUND(100.0 * churned_users
        / NULLIF(LAG(mau) OVER (ORDER BY month), 0), 2)    AS monthly_churn_rate_pct

FROM monthly_summary
ORDER BY month

--=====Early Churn Signals=====--
"Which users are about to churn — before they actually do? What behavioral signals appear in the weeks 
before a user goes silent?

Churn is a lagging metric. By the time a user has churned, the CAC is already lost. Early signals let you intervene while the user is still reachable.

Week 1 after signup:  User active, sessions normal
Week 3:               Session frequency drops 50%    ← signal appears here
Week 5:               Last session ever              ← churn happens here
Week 7:               User counted as churned        ← too late

The goal is to catch users at Week 3, not Week 7."

--=====Session Frequency Drop — Week-over-Week Per User=====--

WITH weekly_sessions AS (
    SELECT
        user_id,
        DATE_TRUNC('week', session_date)                    AS week,
        COUNT(session_id)                                   AS session_count,
        ROUND(AVG(duration_sec) / 60.0, 2)                 AS avg_duration_min
    FROM sessions
    GROUP BY user_id, DATE_TRUNC('week', session_date)
),
with_prev AS (
    SELECT
        user_id,
        week,
        session_count,
        avg_duration_min,
        LAG(session_count) OVER (
            PARTITION BY user_id ORDER BY week
        )                                                   AS prev_week_sessions,
        LAG(avg_duration_min) OVER (
            PARTITION BY user_id ORDER BY week
        )                                                   AS prev_week_duration
    FROM weekly_sessions
)
SELECT
    user_id,
    week,
    session_count,
    prev_week_sessions,
    avg_duration_min,
    prev_week_duration,

    ROUND(100.0 * (session_count - prev_week_sessions)
        / NULLIF(prev_week_sessions, 0), 2)                AS session_pct_change,

    ROUND(100.0 * (avg_duration_min - prev_week_duration)
        / NULLIF(prev_week_duration, 0), 2)                AS duration_pct_change,

    -- Flag users showing early churn signals
    CASE
        WHEN session_count < prev_week_sessions * 0.50
        THEN 'high_risk'
        WHEN session_count < prev_week_sessions * 0.75
        THEN 'medium_risk'
        ELSE 'stable'
    END                                                     AS churn_risk_flag

FROM with_prev
WHERE prev_week_sessions IS NOT NULL
ORDER BY session_pct_change

--=====Days Since Last Session — Current Risk Snapshot=====--

-- Point-in-time risk segmentation
-- Shows where every user stands TODAY
WITH last_activity AS (
    SELECT
        user_id,
        MAX(session_date)                                   AS last_session_date,
        COUNT(session_id)                                   AS total_sessions,
        ROUND(AVG(duration_sec) / 60.0, 2)                 AS avg_session_min,
        COUNT(DISTINCT DATE_TRUNC('month', session_date))   AS active_months
    FROM sessions
    GROUP BY user_id
)
SELECT
    u.user_id,
    u.signup_channel,
    u.city_tier,
    u.plan_type,
    l.last_session_date,
    l.total_sessions,
    l.avg_session_min,
    l.active_months,
    '2024-12-31'::DATE - l.last_session_date               AS days_since_active,

    CASE
        WHEN '2024-12-31'::DATE - l.last_session_date <= 7
        THEN 'active'
        WHEN '2024-12-31'::DATE - l.last_session_date <= 30
        THEN 'at_risk'
        WHEN '2024-12-31'::DATE - l.last_session_date <= 60
        THEN 'dormant'
        ELSE 'churned'
    END                                                     AS risk_segment,

    -- Has outstanding loan? Churned loan users = credit risk too
    CASE WHEN lo.loan_id IS NOT NULL THEN TRUE ELSE FALSE
    END                                                     AS has_active_loan

FROM users u
JOIN user_kyc k ON u.user_id = k.user_id
              AND k.kyc_status = 'approved'
JOIN last_activity l ON u.user_id = l.user_id
LEFT JOIN loans lo ON u.user_id   = lo.user_id
                  AND lo.loan_status = 'active'
ORDER BY days_since_active DESC

--======Risk Segment Summary======---

WITH last_activity AS (
    SELECT
        user_id,
        MAX(session_date)                                   AS last_session_date,
        COUNT(session_id)                                   AS total_sessions,
        COUNT(DISTINCT DATE_TRUNC('month', session_date))   AS active_months
    FROM sessions
    GROUP BY user_id
),
segmented AS (
    SELECT
        u.user_id,
        u.signup_channel,
        u.city_tier,
        l.total_sessions,
        l.active_months,
        '2024-12-31'::DATE - l.last_session_date           AS days_since_active,
        CASE
            WHEN '2024-12-31'::DATE - l.last_session_date <= 7   THEN 'active'
            WHEN '2024-12-31'::DATE - l.last_session_date <= 30  THEN 'at_risk'
            WHEN '2024-12-31'::DATE - l.last_session_date <= 60  THEN 'dormant'
            ELSE 'churned'
        END                                                 AS risk_segment
    FROM users u
    JOIN user_kyc k    ON u.user_id = k.user_id
                      AND k.kyc_status = 'approved'
    JOIN last_activity l ON u.user_id = l.user_id
)
SELECT
    risk_segment,
    COUNT(*)                                                AS users,
    ROUND(100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (), 2)                        AS pct_of_base,
    ROUND(AVG(total_sessions), 1)                          AS avg_total_sessions,
    ROUND(AVG(active_months), 1)                           AS avg_active_months,
    ROUND(AVG(days_since_active), 0)                       AS avg_days_inactive,

    -- Channel breakdown within each risk segment
    COUNT(*) FILTER (WHERE signup_channel = 'referral')    AS referral_users,
    COUNT(*) FILTER (WHERE signup_channel = 'organic')     AS organic_users,
    COUNT(*) FILTER (WHERE signup_channel = 'paid_meta')   AS paid_meta_users,

    -- Tier breakdown
    COUNT(*) FILTER (WHERE city_tier = 'tier1')            AS tier1_users,
    COUNT(*) FILTER (WHERE city_tier = 'tier2')            AS tier2_users,
    COUNT(*) FILTER (WHERE city_tier = 'tier3')            AS tier3_users

FROM segmented
GROUP BY risk_segment
ORDER BY
    CASE risk_segment
        WHEN 'active'   THEN 1
        WHEN 'at_risk'  THEN 2
        WHEN 'dormant'  THEN 3
        WHEN 'churned'  THEN 4
    END

--=====Early Churn Signal Score Per User=====--

-- Composite churn risk score combining multiple signals
-- Higher score = higher risk = higher priority for intervention

WITH last_activity AS (
    SELECT
        user_id,
        MAX(session_date)                                   AS last_session_date,
        COUNT(session_id)                                   AS total_sessions,
        COUNT(DISTINCT DATE_TRUNC('week', session_date))    AS active_weeks
    FROM sessions
    GROUP BY user_id
),
weekly_trend AS (
    SELECT
        user_id,
        -- Compare last 4 weeks vs 4 weeks before that
        COUNT(session_id) FILTER (
            WHERE session_date >= '2024-12-01'
        )                                                   AS recent_sessions,
        COUNT(session_id) FILTER (
            WHERE session_date BETWEEN '2024-11-01'
                                   AND '2024-11-30'
        )                                                   AS prior_sessions
    FROM sessions
    GROUP BY user_id
),
churn_signals AS (
    SELECT
        u.user_id,
        u.signup_channel,
        u.city_tier,
        u.plan_type,
        l.last_session_date,
        l.total_sessions,
        l.active_weeks,
        wt.recent_sessions,
        wt.prior_sessions,
        '2024-12-31'::DATE - l.last_session_date           AS days_inactive,

        -- Signal 1: Days inactive (0-40 pts)
        LEAST(('2024-12-31'::DATE - l.last_session_date)
              * 2, 40)                                      AS score_days_inactive,

        -- Signal 2: Session frequency drop (0-30 pts)
        CASE
            WHEN wt.prior_sessions = 0 THEN 0
            WHEN wt.recent_sessions = 0 THEN 30
            WHEN wt.recent_sessions < wt.prior_sessions * 0.25 THEN 25
            WHEN wt.recent_sessions < wt.prior_sessions * 0.50 THEN 15
            WHEN wt.recent_sessions < wt.prior_sessions * 0.75 THEN 5
            ELSE 0
        END                                                 AS score_session_drop,

        -- Signal 3: Low overall engagement (0-30 pts)
        CASE
            WHEN l.total_sessions <= 2  THEN 30
            WHEN l.total_sessions <= 5  THEN 20
            WHEN l.total_sessions <= 10 THEN 10
            ELSE 0
        END                                                 AS score_low_engagement
    FROM users u
    JOIN user_kyc k ON u.user_id    = k.user_id
                   AND k.kyc_status  = 'approved'
    JOIN last_activity  l  ON u.user_id = l.user_id
    JOIN weekly_trend   wt ON u.user_id = wt.user_id
)
SELECT
    user_id,
    signup_channel,
    city_tier,
    plan_type,
    last_session_date,
    days_inactive,
    total_sessions,
    recent_sessions,
    prior_sessions,
    score_days_inactive
        + score_session_drop
        + score_low_engagement                              AS churn_risk_score,
    CASE
        WHEN score_days_inactive
             + score_session_drop
             + score_low_engagement >= 70
        THEN 'critical'
        WHEN score_days_inactive
             + score_session_drop
             + score_low_engagement >= 40
        THEN 'high'
        WHEN score_days_inactive
             + score_session_drop
             + score_low_engagement >= 20
        THEN 'medium'
        ELSE 'low'
    END                                                     AS risk_level
FROM churn_signals
ORDER BY churn_risk_score DESC


--=============================================================================----
--------====================    WIN BACK SEGMENT   =========================-------
--=============================================================================----
"Among users who have already churned, which ones are worth re-engaging —
and what is the right message for each segment?

Churned users
      High past engagement + recent churn   → Priority 1: Remind & incentivise
      High past engagement + old churn      → Priority 2: Re-introduce (product changed)
      Had active loan + churned             → Priority 3: Risk + retention alert
      Low engagement + churned              → Deprioritise (low LTV potential)
      Churned before first transaction      → Activation campaign (different from win-back)
"

--=====Core Win-Back Segments=====--

WITH last_activity AS (
    SELECT
        user_id,
        MAX(session_date)                                   AS last_session_date,
        MIN(session_date)                                   AS first_session_date,
        COUNT(session_id)                                   AS total_sessions,
        ROUND(AVG(duration_sec) / 60.0, 2)                 AS avg_session_min,
        COUNT(DISTINCT DATE_TRUNC('month', session_date))   AS active_months
    FROM sessions
    GROUP BY user_id
),
user_financials AS (
    SELECT
        u.user_id,
        COUNT(DISTINCT t.transaction_id)                    AS total_txns,
        COALESCE(SUM(t.amount), 0)                          AS total_gmv,
        COUNT(DISTINCT b.bnpl_order_id)                     AS bnpl_orders,
        COUNT(DISTINCT l.loan_id)                           AS loans_taken,
        COALESCE(SUM(l.loan_amount), 0)                     AS total_loan_amount
    FROM users u
    LEFT JOIN transactions t ON u.user_id = t.sender_id
    LEFT JOIN bnpl_orders  b ON u.user_id = b.user_id
    LEFT JOIN loans        l ON u.user_id = l.user_id
    GROUP BY u.user_id
),
churned_users AS (
    SELECT
        u.user_id,
        u.signup_channel,
        u.city_tier,
        u.plan_type,
        k.kyc_approved_at::DATE                             AS activation_date,
        la.last_session_date,
        la.first_session_date,
        la.total_sessions,
        la.avg_session_min,
        la.active_months,
        uf.total_txns,
        uf.total_gmv,
        uf.bnpl_orders,
        uf.loans_taken,
        uf.total_loan_amount,
        '2024-12-31'::DATE - la.last_session_date           AS days_since_active
    FROM users u
    JOIN user_kyc k     ON u.user_id = k.user_id
                       AND k.kyc_status = 'approved'
    JOIN last_activity  la ON u.user_id = la.user_id
    JOIN user_financials uf ON u.user_id = uf.user_id
    -- Churned = no session in last 60 days
    WHERE '2024-12-31'::DATE - la.last_session_date > 60
)
SELECT
    user_id,
    signup_channel,
    city_tier,
    plan_type,
    last_session_date,
    days_since_active,
    total_sessions,
    active_months,
    total_txns,
    ROUND(total_gmv, 0)                                     AS total_gmv,
    bnpl_orders,
    loans_taken,
    ROUND(total_loan_amount, 0)                             AS total_loan_amount,

    -- Win-back segment classification
    CASE
        WHEN total_txns = 0 AND bnpl_orders = 0
         AND loans_taken = 0
        THEN 'never_transacted'                             -- activation not win-back

        WHEN loans_taken > 0 AND days_since_active <= 90
        THEN 'lapsed_borrower_recent'                       -- highest priority

        WHEN loans_taken > 0 AND days_since_active > 90
        THEN 'lapsed_borrower_old'                          -- reintroduce products

        WHEN total_sessions >= 20
         AND days_since_active <= 90
        THEN 'high_engagement_recent_churn'                 -- easiest to win back

        WHEN total_sessions >= 20
         AND days_since_active > 90
        THEN 'high_engagement_old_churn'                    -- needs stronger hook

        WHEN total_sessions BETWEEN 5 AND 19
        THEN 'moderate_engagement_churn'                    -- moderate priority

        ELSE 'low_engagement_churn'                         -- deprioritise
    END                                                     AS winback_segment

FROM churned_users

--=====Win-Back Segment Summary======---

WITH last_activity AS (
    SELECT
        user_id,
        MAX(session_date)                                   AS last_session_date,
        COUNT(session_id)                                   AS total_sessions,
        COUNT(DISTINCT DATE_TRUNC('month', session_date))   AS active_months
    FROM sessions
    GROUP BY user_id
),
user_financials AS (
    SELECT
        u.user_id,
        COUNT(DISTINCT t.transaction_id)                    AS total_txns,
        COALESCE(SUM(t.amount), 0)                          AS total_gmv,
        COUNT(DISTINCT l.loan_id)                           AS loans_taken
    FROM users u
    LEFT JOIN transactions t ON u.user_id = t.sender_id
    LEFT JOIN loans        l ON u.user_id = l.user_id
    GROUP BY u.user_id
),
segmented AS (
    SELECT
        u.user_id,
        la.total_sessions,
        uf.total_txns,
        uf.total_gmv,
        uf.loans_taken,
        '2024-12-31'::DATE - la.last_session_date           AS days_since_active,
        CASE
            WHEN uf.total_txns = 0 AND uf.loans_taken = 0
            THEN 'never_transacted'
            WHEN uf.loans_taken > 0 AND '2024-12-31'::DATE
                 - la.last_session_date <= 90
            THEN 'lapsed_borrower_recent'
            WHEN uf.loans_taken > 0 AND '2024-12-31'::DATE
                 - la.last_session_date > 90
            THEN 'lapsed_borrower_old'
            WHEN la.total_sessions >= 20
             AND '2024-12-31'::DATE - la.last_session_date <= 90
            THEN 'high_engagement_recent_churn'
            WHEN la.total_sessions >= 20
             AND '2024-12-31'::DATE - la.last_session_date > 90
            THEN 'high_engagement_old_churn'
            WHEN la.total_sessions BETWEEN 5 AND 19
            THEN 'moderate_engagement_churn'
            ELSE 'low_engagement_churn'
        END                                                 AS winback_segment
    FROM users u
    JOIN user_kyc k      ON u.user_id = k.user_id
                        AND k.kyc_status = 'approved'
    JOIN last_activity   la ON u.user_id = la.user_id
    JOIN user_financials uf ON u.user_id = uf.user_id
    WHERE '2024-12-31'::DATE - la.last_session_date > 60
)
SELECT
    winback_segment,
    COUNT(*)                                                AS users,
    ROUND(100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (), 2)                        AS pct_of_churned,
    ROUND(AVG(total_sessions), 1)                          AS avg_sessions,
    ROUND(AVG(total_gmv), 0)                               AS avg_gmv,
    ROUND(AVG(days_since_active), 0)                       AS avg_days_inactive,
    COUNT(*) FILTER (WHERE loans_taken > 0)                AS users_with_loans
FROM segmented
GROUP BY winback_segment
ORDER BY
    CASE winback_segment
        WHEN 'lapsed_borrower_recent'       THEN 1
        WHEN 'high_engagement_recent_churn' THEN 2
        WHEN 'lapsed_borrower_old'          THEN 3
        WHEN 'high_engagement_old_churn'    THEN 4
        WHEN 'moderate_engagement_churn'    THEN 5
        WHEN 'low_engagement_churn'         THEN 6
        WHEN 'never_transacted'             THEN 7
    END
	
--=====Win-Back Message Mapping======--
-- Maps each segment to the right re-engagement message
SELECT
    winback_segment,
    campaign_priority,
    channel_recommendation,
    message_hook,
    incentive_suggested
FROM (VALUES
    (
        'lapsed_borrower_recent',
        1,
        'push_notification + sms',
        'Your loan repayment is due — stay on track with the Credict app',
        'Waive next late fee if they log in within 7 days'
    ),
    (
        'high_engagement_recent_churn',
        2,
        'push_notification + email',
        'We noticed you have been away — here is what is new on Credict',
        '₹50 cashback on next payment'
    ),
    (
        'lapsed_borrower_old',
        3,
        'email + sms',
        'Your credit limit has increased — check your new offer',
        'Pre-approved loan offer with reduced processing fee'
    ),
    (
        'high_engagement_old_churn',
        4,
        'email',
        'Credict has launched BNPL at 500+ new merchants near you',
        'First BNPL purchase fee waived'
    ),
    (
        'moderate_engagement_churn',
        5,
        'push_notification',
        'Complete 3 payments this month and earn ₹100 reward',
        'Gamified reward milestone'
    ),
    (
        'low_engagement_churn',
        6,
        'email only',
        'Your account is still active — make a payment to keep it alive',
        'No incentive — low ROI segment'
    ),
    (
        'never_transacted',
        7,
        'push_notification + sms',
        'Your KYC is approved — make your first payment and get ₹50 cashback',
        '₹50 cashback on first transaction'
    )
) AS t(winback_segment, campaign_priority, channel_recommendation,
       message_hook, incentive_suggested)
ORDER BY campaign_priority

