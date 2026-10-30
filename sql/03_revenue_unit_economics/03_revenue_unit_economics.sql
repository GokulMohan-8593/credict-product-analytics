
--======tables=====--

SELECT * FROM bnpl_payments
SELECT * FROM bnpl_orders
SELECT * FROM wallets
SELECT * FROM transactions
SELECT * FROM LOANS

--======GMV by Product by Month======--

 "GMV = total money flowing through the platform Not revenue — but the top-line volume metric
 investors and leadership track first"

SELECT
    TO_CHAR(period_month, 'YYYY-MM')                    AS month,
    SUM(payments_gmv)                                   AS payments_gmv,
    SUM(bnpl_gmv)                                       AS bnpl_gmv,
    SUM(loan_gmv)                                       AS loan_gmv,
    SUM(payments_gmv + bnpl_gmv + loan_gmv)             AS total_gmv
FROM (
    -- Payments GMV
    SELECT
        DATE_TRUNC('month', transaction_date)           AS period_month,
        SUM(amount)                                     AS payments_gmv,
        0                                               AS bnpl_gmv,
        0                                               AS loan_gmv
    FROM transactions
    WHERE status = 'success'
    GROUP BY 1

    UNION ALL

    -- BNPL GMV
    SELECT
        DATE_TRUNC('month', order_date),
        0,
        SUM(order_amount),
        0
    FROM bnpl_orders
    GROUP BY 1

    UNION ALL

    -- Loan disbursement GMV
    SELECT
        DATE_TRUNC('month', disbursement_date),
        0,
        0,
        SUM(loan_amount)
    FROM loans
    GROUP BY 1
) combined
GROUP BY period_month
ORDER BY period_month

--=====Net Revenue Decomposition=====--

WITH payment_revenue AS (
    SELECT
        DATE_TRUNC('month', transaction_date)               AS month,
        ROUND(SUM(fee_amount), 2)                           AS mdr_revenue
    FROM transactions
    WHERE status = 'success'
      AND transaction_date BETWEEN '2024-01-01' AND '2024-12-31'
    GROUP BY 1
),
loan_revenue AS (
    SELECT
        DATE_TRUNC('month', l.disbursement_date)            AS month,

        -- Processing fee booked at disbursement
        ROUND(SUM(l.processing_fee), 2)                     AS loan_processing_fee,

        -- Interest income = only from PAID installments
        ROUND(SUM(lp.interest_component)
            FILTER (WHERE lp.status = 'paid'), 2)           AS interest_income,

        -- Penalty income from late payments
        ROUND(SUM(lp.penalty_amount)
            FILTER (WHERE lp.status = 'paid'), 2)           AS loan_penalties,

        -- Credit loss = actual written-off payment amounts
        -- NOT the full loan principal
        ROUND(SUM(lp.due_amount)
            FILTER (WHERE lp.status = 'written_off'), 2)    AS loan_credit_loss

    FROM loans l
    LEFT JOIN loan_payments lp ON l.loan_id = lp.loan_id
    WHERE l.disbursement_date BETWEEN '2024-01-01' AND '2024-12-31'
    GROUP BY 1
),
bnpl_revenue AS (
    SELECT
        DATE_TRUNC('month', b.order_date)                   AS month,

        -- Processing fee booked at order date
        ROUND(SUM(b.processing_fee), 2)                     AS bnpl_processing_fee,

        -- BNPL interest = total paid ABOVE principal portion
        -- Principal portion per payment = financed_amount / tenure_months
        ROUND(SUM(
            CASE WHEN bp.status = 'paid'
                 THEN GREATEST(
                     bp.paid_amount
                     - (b.financed_amount / b.tenure_months),
                     0)
                 ELSE 0
            END
        ), 2)                                               AS bnpl_interest_income,

        -- BNPL penalty income
        ROUND(SUM(bp.penalty_amount)
            FILTER (WHERE bp.status = 'paid'), 2)           AS bnpl_penalties,

        -- BNPL credit loss = written off installments only
        ROUND(SUM(bp.due_amount)
            FILTER (WHERE bp.status = 'overdue'
                      AND bp.days_past_due > 90), 2)        AS bnpl_credit_loss

    FROM bnpl_orders b
    LEFT JOIN bnpl_payments bp ON b.bnpl_order_id = bp.bnpl_order_id
    WHERE b.order_date BETWEEN '2024-01-01' AND '2024-12-31'
    GROUP BY 1
)
SELECT
    TO_CHAR(m.month, 'YYYY-MM')                             AS month,

    -- Revenue lines
    ROUND(COALESCE(pr.mdr_revenue, 0), 2)                   AS mdr_revenue,

    ROUND(COALESCE(lr.loan_processing_fee, 0)
        + COALESCE(br.bnpl_processing_fee, 0), 2)           AS processing_fees,

    ROUND(COALESCE(lr.interest_income, 0)
        + COALESCE(br.bnpl_interest_income, 0), 2)          AS interest_income,

    ROUND(COALESCE(lr.loan_penalties, 0)
        + COALESCE(br.bnpl_penalties, 0), 2)                AS penalty_income,

    -- Cost line — realistic credit loss
    ROUND(COALESCE(lr.loan_credit_loss, 0)
        + COALESCE(br.bnpl_credit_loss, 0), 2)              AS credit_losses,

    -- Net Revenue
    ROUND(
        COALESCE(pr.mdr_revenue, 0)
        + COALESCE(lr.loan_processing_fee, 0)
        + COALESCE(br.bnpl_processing_fee, 0)
        + COALESCE(lr.interest_income, 0)
        + COALESCE(br.bnpl_interest_income, 0)
        + COALESCE(lr.loan_penalties, 0)
        + COALESCE(br.bnpl_penalties, 0)
        - COALESCE(lr.loan_credit_loss, 0)
        - COALESCE(br.bnpl_credit_loss, 0)
    , 2)                                                    AS net_revenue,

    -- Gross margin %
    ROUND(100.0 * (
        COALESCE(pr.mdr_revenue, 0)
        + COALESCE(lr.loan_processing_fee, 0)
        + COALESCE(br.bnpl_processing_fee, 0)
        + COALESCE(lr.interest_income, 0)
        + COALESCE(br.bnpl_interest_income, 0)
        + COALESCE(lr.loan_penalties, 0)
        + COALESCE(br.bnpl_penalties, 0)
        - COALESCE(lr.loan_credit_loss, 0)
        - COALESCE(br.bnpl_credit_loss, 0)
    ) / NULLIF(
        COALESCE(pr.mdr_revenue, 0)
        + COALESCE(lr.loan_processing_fee, 0)
        + COALESCE(br.bnpl_processing_fee, 0)
        + COALESCE(lr.interest_income, 0)
        + COALESCE(br.bnpl_interest_income, 0)
        + COALESCE(lr.loan_penalties, 0)
        + COALESCE(br.bnpl_penalties, 0)
    , 0), 2)                                                AS gross_margin_pct

FROM (
    -- Spine of all months Jan–Dec 2024
    SELECT generate_series(
        '2024-01-01'::DATE,
        '2024-12-01'::DATE,
        '1 month'::INTERVAL
    )::DATE                                                 AS month
) m
LEFT JOIN payment_revenue pr ON m.month = pr.month
LEFT JOIN loan_revenue    lr ON m.month = lr.month
LEFT JOIN bnpl_revenue    br ON m.month = br.month
ORDER BY m.month

--=====ARPU by Product=====--

-- ARPU splits tell you which product monetises best
-- and what the upgrade path is worth

WITH activated_users AS (
    SELECT COUNT(DISTINCT user_id) AS total_activated
    FROM user_kyc
    WHERE kyc_status = 'approved'
),
payment_arpu AS (
    SELECT
        COUNT(DISTINCT sender_id)                       AS paying_users,
        ROUND(SUM(fee_amount), 2)                       AS total_revenue,
        ROUND(SUM(fee_amount)
            / NULLIF(COUNT(DISTINCT sender_id), 0), 2)  AS arpu
    FROM transactions
    WHERE status = 'success'
),
bnpl_arpu AS (
    SELECT
        COUNT(DISTINCT user_id)                         AS paying_users,
        ROUND(SUM(processing_fee), 2)                   AS total_revenue,
        ROUND(SUM(processing_fee)
            / NULLIF(COUNT(DISTINCT user_id), 0), 2)    AS arpu
    FROM bnpl_orders
),
loan_arpu AS (
    SELECT
        COUNT(DISTINCT l.user_id)                       AS paying_users,
        ROUND(SUM(lp.interest_component) FILTER (
            WHERE lp.status = 'paid'), 2)               AS total_revenue,
        ROUND(SUM(lp.interest_component) FILTER (
            WHERE lp.status = 'paid')
            / NULLIF(COUNT(DISTINCT l.user_id), 0), 2)  AS arpu
    FROM loans l
    LEFT JOIN loan_payments lp ON l.loan_id = lp.loan_id
)
SELECT
    'Payments (MDR)'        AS product,
    p.paying_users,
    ROUND(100.0 * p.paying_users
        / au.total_activated, 1)                        AS pct_of_activated,
    p.total_revenue,
    p.arpu                                              AS arpu_per_paying_user

FROM payment_arpu p, activated_users au

UNION ALL

SELECT
    'BNPL',
    b.paying_users,
    ROUND(100.0 * b.paying_users
        / au.total_activated, 1),
    b.total_revenue,
    b.arpu
FROM bnpl_arpu b, activated_users au

UNION ALL

SELECT
    'Loans (Interest)',
    l.paying_users,
    ROUND(100.0 * l.paying_users
        / au.total_activated, 1),
    l.total_revenue,
    l.arpu
FROM loan_arpu l, activated_users au
ORDER BY arpu_per_paying_user DESC

--=====MRR from Premium Subscriptions=====--

-- Premium plan users pay a flat monthly fee
-- Assume ₹99/month for premium plan
-- This is the subscription MRR component

WITH monthly_premium AS (
    SELECT
        TO_CHAR(
            DATE_TRUNC('month', s.session_date), 'YYYY-MM'
        )                                               AS month,
        COUNT(DISTINCT s.user_id)                       AS active_premium_users
    FROM sessions s
    JOIN users u ON s.user_id = u.user_id
    WHERE u.plan_type = 'premium'
    GROUP BY 1
)
SELECT
    month,
    active_premium_users,
    active_premium_users * 99                           AS subscription_mrr,
    active_premium_users * 99 * 12                      AS annualised_arr,

    LAG(active_premium_users * 99)
        OVER (ORDER BY month)                           AS prev_mrr,

    ROUND(100.0 * (active_premium_users * 99
        - LAG(active_premium_users * 99)
            OVER (ORDER BY month))
        / NULLIF(LAG(active_premium_users * 99)
            OVER (ORDER BY month), 0), 2)               AS mom_mrr_growth_pct

FROM monthly_premium
ORDER BY month

--=====MRR Movement — New / Retained / Expansion / Churned=====--

-- The full MRR waterfall
-- Tracks how subscription MRR moves month over month

WITH monthly_user_mrr AS (
    -- Each premium user's MRR for each month they were active
    SELECT
        s.user_id,
        DATE_TRUNC('month', s.session_date)             AS month,
        99                                              AS mrr  -- ₹99/month
    FROM sessions s
    JOIN users u ON s.user_id = u.user_id
    WHERE u.plan_type = 'premium'
    GROUP BY s.user_id, DATE_TRUNC('month', s.session_date)
),
with_prev AS (
    SELECT
        user_id,
        month,
        mrr,
        LAG(month) OVER (
            PARTITION BY user_id ORDER BY month
        )                                               AS prev_month
    FROM monthly_user_mrr
),
classified AS (
    SELECT
        month,
        user_id,
        mrr,
        CASE
            WHEN prev_month IS NULL
            THEN 'new'
            WHEN prev_month = month - INTERVAL '1 month'
            THEN 'retained'
            ELSE 'reactivated'
        END                                             AS mrr_type
    FROM with_prev
),
churned AS (
    SELECT
        mum.month + INTERVAL '1 month'                  AS month,
        mum.user_id,
        mum.mrr,
        'churned'                                       AS mrr_type
    FROM monthly_user_mrr mum
    WHERE NOT EXISTS (
        SELECT 1 FROM monthly_user_mrr m2
        WHERE m2.user_id = mum.user_id
          AND m2.month   = mum.month + INTERVAL '1 month'
    )
    AND mum.month < DATE_TRUNC('month', '2024-12-01'::DATE)
)
SELECT
    TO_CHAR(month, 'YYYY-MM')                           AS month,

    SUM(mrr) FILTER (WHERE mrr_type = 'new')            AS new_mrr,
    SUM(mrr) FILTER (WHERE mrr_type = 'retained')       AS retained_mrr,
    SUM(mrr) FILTER (WHERE mrr_type = 'reactivated')    AS reactivated_mrr,
    SUM(mrr) FILTER (WHERE mrr_type = 'churned')        AS churned_mrr,

    -- Total MRR = new + retained + reactivated
    SUM(mrr) FILTER (WHERE mrr_type != 'churned')       AS total_mrr,

    -- Net MRR change
    SUM(mrr) FILTER (WHERE mrr_type IN ('new','reactivated'))
    - SUM(mrr) FILTER (WHERE mrr_type = 'churned')      AS net_mrr_change

FROM (
    SELECT * FROM classified
    UNION ALL
    SELECT * FROM churned
) all_mrr
GROUP BY month
ORDER BY month

--=====LTV : CAC by Acquisition Channel=====--

-- The most critical unit economics metric
-- Assumes a fixed CAC per channel based on
-- typical Indian fintech blended costs
WITH channel_revenue AS (
    SELECT
        u.signup_channel,
        COUNT(DISTINCT u.user_id)                       AS total_users,

        -- Total revenue per channel
        ROUND(
            -- MDR from payments
            COALESCE(SUM(t.fee_amount), 0)
            -- BNPL processing fees
            + COALESCE(SUM(b.processing_fee), 0)
            -- Loan interest income
            + COALESCE(SUM(lp.interest_component), 0)
        , 2)                                            AS total_revenue
    FROM users u--50000
    JOIN 		(	
					SELECT DISTINCT user_id 
					FROM user_kyc  
					WHERE kyc_status = 'approved'
					) k
						ON u.user_id    = k.user_id	
    LEFT JOIN (
					SELECT 
						sender_id,
						SUM(fee_amount) AS fee_amount 
					FROM transactions
					WHERE status = 'success'
					GROUP BY sender_id
					)  t 
						ON u.user_id = t.sender_id
    LEFT JOIN (
					SELECT
						user_id,
						SUM(processing_fee) AS processing_fee 
					FROM bnpl_orders
					GROUP BY user_id
					) b 
					ON u.user_id = b.user_id
    LEFT JOIN (
					SELECT 
						l.user_id ,
						SUM(lo.interest_component) AS interest_component 
					FROM loans l
					LEFT JOIN loan_payments lo
					ON l.loan_id = lo.loan_id
					WHERE lO.status = 'paid'
					GROUP BY l.user_id 
					) lp  
					ON u.user_id = lp.user_id
    GROUP BY u.signup_channel
),
channel_cac AS (
    -- Assumed CAC per channel (₹ per install)
    -- based on Indian fintech industry benchmarks
    SELECT *
    FROM (VALUES
        ('organic',          50),
        ('referral',        150),
        ('app_store_search', 200),
        ('paid_google',     350),
        ('paid_meta',       400)
    ) AS t(signup_channel, cac_per_install_inr)
),
kyc_rates AS (
    SELECT
        u.signup_channel,
        ROUND(100.0 * COUNT(DISTINCT u.user_id) FILTER (WHERE k.kyc_status = 'approved')
            / NULLIF(COUNT(DISTINCT u.user_id), 0), 2)                   AS kyc_activation_pct
    FROM users u
    LEFT JOIN user_kyc k ON u.user_id = k.user_id
    GROUP BY u.signup_channel
)
SELECT
    cr.signup_channel,
    cr.total_users                                      AS activated_users,
    cc.cac_per_install_inr,
    kr.kyc_activation_pct,

    -- True CAC = install cost / activation rate
    ROUND(cc.cac_per_install_inr * 100.0
        / NULLIF(kr.kyc_activation_pct, 0), 0)          AS true_cac_per_activated_user,

    -- LTV = total revenue / activated users
    ROUND(cr.total_revenue
        / NULLIF(cr.total_users, 0), 2)                 AS ltv_per_user,

    -- LTV : CAC ratio (target > 3)
    ROUND(
        (cr.total_revenue / NULLIF(cr.total_users, 0))
        / NULLIF(cc.cac_per_install_inr * 100.0
                 / NULLIF(kr.kyc_activation_pct, 0), 0)
    , 2)                                                AS ltv_to_cac_ratio,

    -- Payback period in months
    -- Assumes avg monthly revenue = LTV / 12
    ROUND(
        (cc.cac_per_install_inr * 100.0
         / NULLIF(kr.kyc_activation_pct, 0))
        / NULLIF(cr.total_revenue
                 / NULLIF(cr.total_users, 0) / 12.0, 0)
    , 1)                                                AS payback_months,

    CASE
        WHEN ROUND(
            (cr.total_revenue / NULLIF(cr.total_users, 0))
            / NULLIF(cc.cac_per_install_inr * 100.0
                     / NULLIF(kr.kyc_activation_pct, 0), 0)
        , 2) >= 3   THEN 'healthy'
        WHEN ROUND(
            (cr.total_revenue / NULLIF(cr.total_users, 0))
            / NULLIF(cc.cac_per_install_inr * 100.0
                     / NULLIF(kr.kyc_activation_pct, 0), 0)
        , 2) >= 1   THEN 'marginal'
        ELSE             'unprofitable'
    END                                                 AS unit_economics_status

FROM channel_revenue  cr
JOIN channel_cac      cc ON cr.signup_channel = cc.signup_channel
JOIN kyc_rates        kr ON cr.signup_channel = kr.signup_channel
ORDER BY ltv_to_cac_ratio DESC

--=====Monthly Revenue per User (MRPU) Trend=====--

-- Tracks whether each user is becoming more valuable
-- over their lifetime — key for LTV model validity
WITH user_monthly_revenue AS (
    SELECT
        u.user_id,
        DATE_TRUNC('month', t.transaction_date)         AS month,
        SUM(t.fee_amount)                               AS payment_rev
    FROM users u
    JOIN user_kyc k ON u.user_id   = k.user_id
                   AND k.kyc_status = 'approved'
    JOIN transactions t ON u.user_id = t.sender_id
    WHERE t.status = 'success'
    GROUP BY u.user_id, DATE_TRUNC('month', t.transaction_date)
),
cohort_base AS (
    SELECT
        user_id,
        DATE_TRUNC('month', kyc_approved_at)            AS cohort_month
    FROM user_kyc
    WHERE kyc_status = 'approved'
)
SELECT
    EXTRACT(MONTH FROM AGE(
        umr.month, cb.cohort_month))::INT               AS months_since_activation,
    COUNT(DISTINCT umr.user_id)                         AS active_users,
    ROUND(AVG(umr.payment_rev), 2)                      AS avg_monthly_rev_per_user,
    ROUND(SUM(umr.payment_rev), 2)                      AS total_revenue
FROM user_monthly_revenue umr
JOIN cohort_base cb ON umr.user_id = cb.user_id
WHERE umr.month >= cb.cohort_month
GROUP BY 1
ORDER BY 1
