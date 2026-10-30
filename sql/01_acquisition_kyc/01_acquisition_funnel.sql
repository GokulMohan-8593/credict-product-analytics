-- ============================================================
-- CREDICT — MODULE 1: USER ACQUISITION & KYC FUNNEL
-- PostgreSQL
-- ============================================================


-- ── Q1: Daily New Users ─────────────────────────────────────
SELECT
    signup_date,
    COUNT(user_id)                                     AS new_users,
    SUM(COUNT(user_id)) OVER (ORDER BY signup_date)    AS cumulative_users
FROM users
GROUP BY signup_date
ORDER BY signup_date;


-- ── Q2: Monthly New Users ───────────────────────────────────
SELECT
    TO_CHAR(signup_date, 'YYYY-MM')                    AS month,
    COUNT(user_id)                                     AS new_users,
    SUM(COUNT(user_id))
        OVER (ORDER BY TO_CHAR(signup_date, 'YYYY-MM')) AS cumulative_users
FROM users
GROUP BY 1
ORDER BY 1;


-- ── Q3: New Users by Acquisition Channel (Monthly) ──────────
SELECT
    TO_CHAR(signup_date, 'YYYY-MM')                    AS month,
    signup_channel,
    COUNT(user_id)                                     AS new_users,
    ROUND(100.0 * COUNT(user_id)
        / SUM(COUNT(user_id)) OVER (
            PARTITION BY TO_CHAR(signup_date, 'YYYY-MM')
          ), 2)                                        AS channel_share_pct
FROM users
GROUP BY 1, 2
ORDER BY 1, 2;


-- ── Q4: New Users by City Tier (Monthly) ────────────────────
SELECT
    TO_CHAR(signup_date, 'YYYY-MM')                    AS month,
    city_tier,
    COUNT(user_id)                                     AS new_users
FROM users
GROUP BY 1, 2
ORDER BY 1, 2;


-- ── Q5: KYC Funnel — Step-by-Step Conversion ────────────────
WITH funnel AS (
    SELECT
        COUNT(*)                                                    AS registered,
        COUNT(CASE WHEN phone_verified   = TRUE THEN 1 END)        AS phone_verified,
        COUNT(CASE WHEN pan_submitted    = TRUE THEN 1 END)        AS pan_submitted,
        COUNT(CASE WHEN pan_verified     = TRUE THEN 1 END)        AS pan_verified,
        COUNT(CASE WHEN aadhaar_linked   = TRUE THEN 1 END)        AS aadhaar_linked,
        COUNT(CASE WHEN selfie_submitted = TRUE THEN 1 END)        AS selfie_submitted,
        COUNT(CASE WHEN kyc_status = 'approved'  THEN 1 END)       AS kyc_approved
    FROM user_kyc
)
SELECT step, users, step_conv_pct, overall_conv_pct
FROM (
    SELECT 1 AS ord, 'Registered'     AS step, registered        AS users,
        100.0                          AS step_conv_pct,
        100.0                          AS overall_conv_pct FROM funnel
    UNION ALL
    SELECT 2,'Phone OTP', phone_verified,
        ROUND(100.0*phone_verified   /NULLIF(registered,     0),2),
        ROUND(100.0*phone_verified   /NULLIF(registered,     0),2) FROM funnel
    UNION ALL
    SELECT 3,'PAN Submitted', pan_submitted,
        ROUND(100.0*pan_submitted    /NULLIF(phone_verified, 0),2),
        ROUND(100.0*pan_submitted    /NULLIF(registered,     0),2) FROM funnel
    UNION ALL
    SELECT 4,'PAN Verified', pan_verified,
        ROUND(100.0*pan_verified     /NULLIF(pan_submitted,  0),2),
        ROUND(100.0*pan_verified     /NULLIF(registered,     0),2) FROM funnel
    UNION ALL
    SELECT 5,'Aadhaar Linked', aadhaar_linked,
        ROUND(100.0*aadhaar_linked   /NULLIF(pan_verified,   0),2),
        ROUND(100.0*aadhaar_linked   /NULLIF(registered,     0),2) FROM funnel
    UNION ALL
    SELECT 6,'Selfie Done', selfie_submitted,
        ROUND(100.0*selfie_submitted /NULLIF(aadhaar_linked, 0),2),
        ROUND(100.0*selfie_submitted /NULLIF(registered,     0),2) FROM funnel
    UNION ALL
    SELECT 7,'KYC Approved', kyc_approved,
        ROUND(100.0*kyc_approved     /NULLIF(selfie_submitted,0),2),
        ROUND(100.0*kyc_approved     /NULLIF(registered,      0),2) FROM funnel
) t
ORDER BY ord;


-- ── Q6: KYC Funnel by Acquisition Channel ───────────────────
SELECT
    u.signup_channel,
    COUNT(*)                                                        AS registered,
    COUNT(CASE WHEN k.phone_verified   = TRUE THEN 1 END)          AS phone_verified,
    COUNT(CASE WHEN k.pan_verified     = TRUE THEN 1 END)          AS pan_verified,
    COUNT(CASE WHEN k.aadhaar_linked   = TRUE THEN 1 END)          AS aadhaar_linked,
    COUNT(CASE WHEN k.selfie_submitted = TRUE THEN 1 END)          AS selfie_done,
    COUNT(CASE WHEN k.kyc_status = 'approved' THEN 1 END)          AS kyc_approved,
    ROUND(100.0 * COUNT(CASE WHEN k.kyc_status = 'approved' THEN 1 END)
        / NULLIF(COUNT(*), 0), 2)                                  AS overall_kyc_pct
FROM users u
LEFT JOIN user_kyc k ON u.user_id = k.user_id
GROUP BY u.signup_channel
ORDER BY overall_kyc_pct DESC;


-- ── Q7: KYC Funnel by City Tier ─────────────────────────────
SELECT
    u.city_tier,
    COUNT(*)                                                        AS registered,
    ROUND(100.0 * COUNT(CASE WHEN k.phone_verified   THEN 1 END)
        / NULLIF(COUNT(*), 0), 2)                                  AS phone_pct,
    ROUND(100.0 * COUNT(CASE WHEN k.pan_submitted    THEN 1 END)
        / NULLIF(COUNT(CASE WHEN k.phone_verified THEN 1 END), 0), 2) AS pan_sub_pct,
    ROUND(100.0 * COUNT(CASE WHEN k.aadhaar_linked   THEN 1 END)
        / NULLIF(COUNT(CASE WHEN k.pan_verified THEN 1 END), 0), 2)   AS aadhaar_pct,
    ROUND(100.0 * COUNT(CASE WHEN k.kyc_status = 'approved' THEN 1 END)
        / NULLIF(COUNT(CASE WHEN k.selfie_submitted THEN 1 END), 0), 2) AS approval_pct,
    ROUND(100.0 * COUNT(CASE WHEN k.kyc_status = 'approved' THEN 1 END)
        / NULLIF(COUNT(*), 0), 2)                                  AS overall_kyc_pct
FROM users u
LEFT JOIN user_kyc k ON u.user_id = k.user_id
GROUP BY u.city_tier
ORDER BY u.city_tier;


-- ── Q8: Time Between KYC Steps (Friction Analysis) ──────────
-- EPOCH gives seconds in PostgreSQL; divide by 60 for minutes
SELECT
    ROUND(AVG(EXTRACT(EPOCH FROM (pan_submitted_at   - phone_verified_at)) / 60)::NUMERIC, 1)
                                                                   AS avg_min_phone_to_pan,
    ROUND(AVG(EXTRACT(EPOCH FROM (aadhaar_linked_at  - pan_verified_at))   / 60)::NUMERIC, 1)
                                                                   AS avg_min_pan_to_aadhaar,
    ROUND(AVG(EXTRACT(EPOCH FROM (selfie_submitted_at- aadhaar_linked_at)) / 60)::NUMERIC, 1)
                                                                   AS avg_min_aadhaar_to_selfie,
    ROUND(AVG(EXTRACT(EPOCH FROM (kyc_approved_at    - selfie_submitted_at))/ 60)::NUMERIC, 1)
                                                                   AS avg_min_selfie_to_approval,
    ROUND(AVG(EXTRACT(EPOCH FROM (kyc_approved_at    - phone_verified_at)) / 60)::NUMERIC, 1)
                                                                   AS avg_total_min_to_approval
FROM user_kyc
WHERE kyc_status      = 'approved'
  AND phone_verified_at IS NOT NULL
  AND kyc_approved_at   IS NOT NULL;


-- ── Q9: KYC Approval Rate by Cohort Month (Improving?) ──────
SELECT
    TO_CHAR(u.signup_date, 'YYYY-MM')                              AS cohort_month,
    COUNT(*)                                                       AS registered,
    COUNT(CASE WHEN k.kyc_status = 'approved' THEN 1 END)         AS kyc_approved,
    ROUND(100.0 * COUNT(CASE WHEN k.kyc_status = 'approved' THEN 1 END)
        / NULLIF(COUNT(*), 0), 2)                                  AS approval_rate_pct,
    -- Month-over-month change using LAG
    ROUND(
        100.0 * COUNT(CASE WHEN k.kyc_status = 'approved' THEN 1 END)
              / NULLIF(COUNT(*), 0)
        - LAG(
            100.0 * COUNT(CASE WHEN k.kyc_status = 'approved' THEN 1 END)
                  / NULLIF(COUNT(*), 0)
          ) OVER (ORDER BY TO_CHAR(u.signup_date, 'YYYY-MM'))
    , 2)                                                           AS mom_change_ppt
FROM users u
LEFT JOIN user_kyc k ON u.user_id = k.user_id
GROUP BY TO_CHAR(u.signup_date, 'YYYY-MM')
ORDER BY 1;


-- ── Q10: New vs Activated Users Gap (The Real Growth Story) ──
SELECT
    TO_CHAR(u.signup_date, 'YYYY-MM')                              AS month,
    COUNT(DISTINCT u.user_id)                                      AS new_signups,
    COUNT(DISTINCT CASE WHEN k.kyc_status = 'approved'
                        THEN u.user_id END)                        AS kyc_activated,
    COUNT(DISTINCT u.user_id)
        - COUNT(DISTINCT CASE WHEN k.kyc_status = 'approved'
                              THEN u.user_id END)                  AS activation_gap,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN k.kyc_status = 'approved'
                                      THEN u.user_id END)
        / NULLIF(COUNT(DISTINCT u.user_id), 0), 2)                AS activation_rate_pct
FROM users u
LEFT JOIN user_kyc k ON u.user_id = k.user_id
GROUP BY TO_CHAR(u.signup_date, 'YYYY-MM')
ORDER BY 1;


-- ── Q11: KYC Rejection Reasons ──────────────────────────────
SELECT
    rejection_reason,
    COUNT(*)                                                       AS rejected_users,
    ROUND(100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (), 2)                               AS pct_of_rejections
FROM user_kyc
WHERE kyc_status = 'rejected'
  AND rejection_reason IS NOT NULL
GROUP BY rejection_reason
ORDER BY rejected_users DESC;


-- ── Q12: Top Cities by KYC Completion ───────────────────────

SELECT
    u.city,
    u.city_tier,
    COUNT(*)                                                       AS registered,
    COUNT(CASE WHEN k.kyc_status = 'approved' THEN 1 END)         AS kyc_approved,
    ROUND(100.0 * COUNT(CASE WHEN k.kyc_status = 'approved' THEN 1 END)
        / NULLIF(COUNT(*), 0), 2)                                  AS approval_rate_pct
FROM users u
LEFT JOIN user_kyc k ON u.user_id = k.user_id
GROUP BY u.city, u.city_tier
HAVING COUNT(*) >= 200
ORDER BY approval_rate_pct DESC
LIMIT 15;
