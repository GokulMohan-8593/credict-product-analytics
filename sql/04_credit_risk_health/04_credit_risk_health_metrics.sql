----*************************************************************************---
--======================Credit Risk & Health Metrics=========================--
--***************************************************************************---
"
DPD  — Days Past Due
       The number of days since an EMI was due but not paid
       DPD 0    = current, no delay
       DPD 1-30 = early delinquency (watch list)
       DPD 31-60 = sub-standard (collection alert)
       DPD 61-90 = doubtful (provision required)
       DPD 90+   = NPA / written off (loss)

NPA  — Non Performing Asset
       Any loan where DPD > 90 days
       Regulated by RBI in India
       Once NPA, interest income stops accruing

Vintage — The month a loan was originated
           Vintage analysis tracks how loans
           from each origination month perform
           over time — reveals if underwriting
           is improving or deteriorating

Risk-Adjusted Return
       Interest income earned MINUS credit losses
       on a per-grade basis — tells you which
       grade is actually profitable after defaults 
"

---=====tables=====--

SELECT * FROM loans


--=====Portfolio Overview — Current Loan Book Health======--

SELECT
    loan_status,
    risk_grade,
    COUNT(*)                                                AS loan_count,
    ROUND(SUM(loan_amount), 0)                              AS total_principal,
    ROUND(AVG(loan_amount), 0)                              AS avg_loan_size,
    ROUND(AVG(interest_rate), 2)                            AS avg_interest_rate,
    ROUND(AVG(days_past_due), 1)                            AS avg_dpd,
    ROUND(SUM(loan_amount) * 100.0
        / SUM(SUM(loan_amount)) OVER (), 2)                 AS pct_of_book
FROM loans
GROUP BY loan_status, risk_grade
ORDER BY risk_grade, loan_status

--=====DPD Bucket Analysis — Delinquency Ladder=====--

-- Every loan classified into its current DPD bucket
-- This is the standard RBI-mandated classification
WITH loan_dpd AS (
    SELECT
        l.loan_id,
        l.risk_grade,
        l.loan_amount,
        l.interest_rate,
        l.disbursement_date,
        COALESCE(MAX(lp.days_past_due), 0)                  AS max_dpd
    FROM loans l
    LEFT JOIN loan_payments lp ON l.loan_id = lp.loan_id
    WHERE l.loan_status = 'active'
    GROUP BY l.loan_id, l.risk_grade,
             l.loan_amount, l.interest_rate,
             l.disbursement_date
)
SELECT
    risk_grade,
    CASE
        WHEN max_dpd = 0        THEN 'DPD 0 — Current'
        WHEN max_dpd <= 30      THEN 'DPD 1-30 — Watch'
        WHEN max_dpd <= 60      THEN 'DPD 31-60 — Substandard'
        WHEN max_dpd <= 90      THEN 'DPD 61-90 — Doubtful'
        ELSE                         'DPD 90+ — NPA'
    END                                                     AS dpd_bucket,
    COUNT(*)                                                AS loan_count,
    ROUND(SUM(loan_amount), 0)                              AS principal_at_risk,
    ROUND(100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (PARTITION BY risk_grade), 2)  AS pct_within_grade
FROM loan_dpd
GROUP BY risk_grade, dpd_bucket
ORDER BY risk_grade

--=====Default Rate by Risk Grade=====--

-- Actual default rate vs expected
-- Validates whether Lending Club grade calibration holds
SELECT
    risk_grade,
    COUNT(*)                                                AS total_loans,
    COUNT(*) FILTER (
        WHERE loan_status IN ('npa', 'defaulted'))          AS defaulted_loans,
    ROUND(100.0 * COUNT(*) FILTER (
        WHERE loan_status IN ('npa', 'defaulted'))
        / NULLIF(COUNT(*), 0), 2)                           AS actual_default_rate_pct,

    -- Expected default rates from Lending Club calibration
    CASE risk_grade
        WHEN 'A' THEN 2.0
        WHEN 'B' THEN 5.0
        WHEN 'C' THEN 10.0
        WHEN 'D' THEN 18.0
        WHEN 'E' THEN 28.0
    END                                                     AS expected_default_rate_pct,

    -- Variance: positive = worse than expected
    ROUND(100.0 * COUNT(*) FILTER (
        WHERE loan_status IN ('npa', 'defaulted'))
        / NULLIF(COUNT(*), 0), 2)
    - CASE risk_grade
        WHEN 'A' THEN 2.0  WHEN 'B' THEN 5.0
        WHEN 'C' THEN 10.0 WHEN 'D' THEN 18.0
        WHEN 'E' THEN 28.0
      END                                                   AS variance_ppt,

    ROUND(SUM(loan_amount), 0)                              AS total_disbursed,
    ROUND(SUM(loan_amount) FILTER (
        WHERE loan_status IN ('npa', 'defaulted')), 0)      AS defaulted_principal

FROM loans
GROUP BY risk_grade
ORDER BY risk_grade

--=====Risk-Adjusted Return by Grade=====--

-- The single most important credit analytics query
-- Which grade actually makes money after defaults?
WITH grade_income AS (
    SELECT
        l.risk_grade,
        COUNT(DISTINCT l.loan_id)                           AS loan_count,
        ROUND(SUM(l.loan_amount), 0)                        AS total_disbursed,
        ROUND(AVG(l.interest_rate), 2)                      AS avg_rate,

        -- Gross interest income collected
        ROUND(SUM(lp.interest_component)
            FILTER (WHERE lp.status = 'paid'), 0)           AS interest_collected,

        -- Processing fee income
        ROUND(SUM(l.processing_fee), 0)                     AS processing_fee_income,

        -- Credit losses: written off installments
        ROUND(COALESCE(SUM(lp.due_amount)
            FILTER (WHERE lp.status = 'written_off'), 0),0) AS credit_losses,

        -- Penalty income
        ROUND(SUM(lp.penalty_amount)
            FILTER (WHERE lp.status = 'paid'), 0)           AS penalty_income

    FROM loans l
    LEFT JOIN loan_payments lp ON l.loan_id = lp.loan_id
    GROUP BY l.risk_grade
)
SELECT
    risk_grade,
    loan_count,
    total_disbursed,
    avg_rate,
    interest_collected,
    processing_fee_income,
    penalty_income,
    credit_losses,

    -- Gross revenue before credit losses
    interest_collected
        + processing_fee_income
        + penalty_income                                    AS gross_revenue,

    -- Net revenue after credit losses
    interest_collected
        + processing_fee_income
        + penalty_income
        - credit_losses                                     AS net_revenue,

    -- Return on disbursement %
    ROUND(100.0 * (
        interest_collected
        + processing_fee_income
        + penalty_income
        - credit_losses
    ) / NULLIF(total_disbursed, 0), 2)                      AS net_return_pct,

    -- Gross yield %
    ROUND(100.0 * (
        interest_collected + processing_fee_income
    ) / NULLIF(total_disbursed, 0), 2)                      AS gross_yield_pct,

    -- Credit loss rate %
    ROUND(100.0 * credit_losses
        / NULLIF(total_disbursed, 0), 2)                    AS credit_loss_rate_pct,

    -- Is this grade profitable?
    CASE
        WHEN (interest_collected + processing_fee_income
              + penalty_income - credit_losses) > 0
        THEN 'profitable'
        ELSE 'loss_making'
    END                                                     AS grade_profitability

FROM grade_income
ORDER BY risk_grade

--=====Portfolio Health Dashboard=====--

-- Single query that gives the full credit health picture
-- This is what the risk team looks at every Monday
WITH portfolio AS (
    SELECT
        COUNT(DISTINCT l.loan_id)                           AS total_loans,
        ROUND(SUM(l.loan_amount), 0)                        AS total_book_size,

        -- NPA rate
        COUNT(DISTINCT l.loan_id) FILTER (
            WHERE l.loan_status IN ('npa','defaulted'))      AS npa_loans,
        ROUND(SUM(l.loan_amount) FILTER (
            WHERE l.loan_status IN ('npa','defaulted')), 0)  AS npa_amount,

        -- Active book
        COUNT(DISTINCT l.loan_id) FILTER (
            WHERE l.loan_status = 'active')                 AS active_loans,
        ROUND(SUM(l.loan_amount) FILTER (
            WHERE l.loan_status = 'active'), 0)             AS active_book,

        -- Collections efficiency
        ROUND(SUM(lp.paid_amount), 0)                       AS total_collected,
        ROUND(SUM(lp.due_amount), 0)                        AS total_due,

        -- Overdue
        COUNT(DISTINCT lp.loan_id) FILTER (
            WHERE lp.days_past_due BETWEEN 1 AND 30)        AS dpd_1_30_count,
        COUNT(DISTINCT lp.loan_id) FILTER (
            WHERE lp.days_past_due BETWEEN 31 AND 60)       AS dpd_31_60_count,
        COUNT(DISTINCT lp.loan_id) FILTER (
            WHERE lp.days_past_due > 60)                    AS dpd_60_plus_count

    FROM loans l
    LEFT JOIN loan_payments lp ON l.loan_id = lp.loan_id
)
SELECT
    total_loans,
    total_book_size,
    active_loans,
    active_book,
    npa_loans,
    npa_amount,

    -- NPA Rate (key RBI metric)
    ROUND(100.0 * npa_amount
        / NULLIF(total_book_size, 0), 2)                    AS npa_rate_pct,

    -- Collection efficiency
    ROUND(100.0 * total_collected
        / NULLIF(total_due, 0), 2)                          AS collection_efficiency_pct,

    -- Overdue counts
    dpd_1_30_count,
    dpd_31_60_count,
    dpd_60_plus_count,

    -- Early warning: DPD 1-30 as % of active loans
    ROUND(100.0 * dpd_1_30_count
        / NULLIF(active_loans, 0), 2)                       AS early_delinquency_pct,

    -- Health flags
    CASE
        WHEN ROUND(100.0 * npa_amount
            / NULLIF(total_book_size, 0), 2) > 10
        THEN '🔴 NPA Critical'
        WHEN ROUND(100.0 * npa_amount
            / NULLIF(total_book_size, 0), 2) > 5
        THEN '🟡 NPA Warning'
        ELSE '🟢 NPA Healthy'
    END                                                     AS npa_flag,

    CASE
        WHEN ROUND(100.0 * total_collected
            / NULLIF(total_due, 0), 2) < 85
        THEN '🔴 Collections Critical'
        WHEN ROUND(100.0 * total_collected
            / NULLIF(total_due, 0), 2) < 92
        THEN '🟡 Collections Warning'
        ELSE '🟢 Collections Healthy'
    END                                                     AS collections_flag

FROM portfolio

--=====Portfolio Health Dashboard By Risk Grade=====--

WITH portfolio AS (
    SELECT
		L.risk_grade,
        COUNT(DISTINCT l.loan_id)                           AS total_loans,
        ROUND(SUM(l.loan_amount), 0)                        AS total_book_size,

        -- NPA rate
        COUNT(DISTINCT l.loan_id) FILTER (
            WHERE l.loan_status IN ('npa','defaulted'))      AS npa_loans,
        ROUND(SUM(l.loan_amount) FILTER (
            WHERE l.loan_status IN ('npa','defaulted')), 0)  AS npa_amount,

        -- Active book
        COUNT(DISTINCT l.loan_id) FILTER (
            WHERE l.loan_status = 'active')                 AS active_loans,
        ROUND(SUM(l.loan_amount) FILTER (
            WHERE l.loan_status = 'active'), 0)             AS active_book,

        -- Collections efficiency
        ROUND(SUM(lp.paid_amount), 0)                       AS total_collected,
        ROUND(SUM(lp.due_amount), 0)                        AS total_due,

        -- Overdue
        COUNT(DISTINCT lp.loan_id) FILTER (
            WHERE lp.days_past_due BETWEEN 1 AND 30)        AS dpd_1_30_count,
        COUNT(DISTINCT lp.loan_id) FILTER (
            WHERE lp.days_past_due BETWEEN 31 AND 60)       AS dpd_31_60_count,
        COUNT(DISTINCT lp.loan_id) FILTER (
            WHERE lp.days_past_due > 60)                    AS dpd_60_plus_count

    FROM loans l
    LEFT JOIN loan_payments lp ON l.loan_id = lp.loan_id
	GROUP BY L.risk_grade
)
SELECT
	risk_grade,
    total_loans,
    total_book_size,
    active_loans,
    active_book,
    npa_loans,
    npa_amount,

    -- NPA Rate (key RBI metric)
    ROUND(100.0 * npa_amount
        / NULLIF(total_book_size, 0), 2)                    AS npa_rate_pct,

    -- Collection efficiency
    ROUND(100.0 * total_collected
        / NULLIF(total_due, 0), 2)                          AS collection_efficiency_pct,

    -- Overdue counts
    dpd_1_30_count,
    dpd_31_60_count,
    dpd_60_plus_count,

    -- Early warning: DPD 1-30 as % of active loans
    ROUND(100.0 * dpd_1_30_count
        / NULLIF(active_loans, 0), 2)                       AS early_delinquency_pct,

    -- Health flags
    CASE
        WHEN ROUND(100.0 * npa_amount
            / NULLIF(total_book_size, 0), 2) > 10
        THEN '🔴 NPA Critical'
        WHEN ROUND(100.0 * npa_amount
            / NULLIF(total_book_size, 0), 2) > 5
        THEN '🟡 NPA Warning'
        ELSE '🟢 NPA Healthy'
    END                                                     AS npa_flag,

    CASE
        WHEN ROUND(100.0 * total_collected
            / NULLIF(total_due, 0), 2) < 85
        THEN '🔴 Collections Critical'
        WHEN ROUND(100.0 * total_collected
            / NULLIF(total_due, 0), 2) < 92
        THEN '🟡 Collections Warning'
        ELSE '🟢 Collections Healthy'
    END                                                     AS collections_flag

FROM portfolio


