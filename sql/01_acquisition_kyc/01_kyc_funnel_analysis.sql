
-- ============================================================
-- CREDICT — MODULE 1: USER ACQUISITION & KYC FUNNEL
-- ============================================================

-- ===========================TABLES =================================
SELECT * FROM USERS
SELECT * FROM user_kyc
SELECT * FROM active_users

--==========KYC STATUS DISTRIBUTION==========---

SELECT 
kyc_status,
COUNT(*) AS COUNT
FROM user_kyc
GROUP BY kyc_status
--"approved"	15989
--"pending"		30493
--"rejected"	3469

SELECT DISTINCT phone_verified FROM USER_KYC --BOOLEAN
SELECT DISTINCT pan_submitted FROM USER_KYC --BOOLEAN
SELECT DISTINCT pan_verified FROM USER_KYC --BOOLEAN
SELECT DISTINCT aadhaar_linked FROM USER_KYC --BOOLEAN
SELECT DISTINCT selfie_submitted FROM USER_KYC --BOOLEAN

SELECT DISTINCT REJECTION_REASON FROM USER_KYC 
"rejection_reason"
"photo_quality"
"name_mismatch"
"fraud_flag"
"id_expired"
"blurry_selfie"

--=============FUNNNEL ANALYSIS===============--

select
	count(*) as total_users,
	count(case when phone_verified = 'true' then '1' end) as phone_verified_count,
	count(case when pan_submitted = 'true' then '1' end) as pan_submitted_count,
	count(case when pan_verified = 'true' then '1' end) as pan_verified_count,
	count(case when aadhaar_linked = 'true' then '1' end) as aadhaar_linked_count,
	count(case when selfie_submitted = 'true' then '1' end) as selfie_submitted_count
from user_kyc
--"total_users"	"phone_verified_count"	"pan_submitted_count"	"pan_verified_count"	"aadhaar_linked_count"	"selfie_submitted_count"
--50000					46042					38118					33602					25160					17589

--===============FUNNNEL CTE=================--

WITH KYC_FUNNEL AS 
(
		SELECT 
		1 AS step_no,
		'TOTAL_USERS' AS STAGE,
		COUNT(*) AS USERS
		FROM USER_kyc
UNION ALL
		SELECT 
		2 AS step_no,
		'PHONE_VERIFIED',
		COUNT(*) 
		FILTER ( WHERE phone_verified = 'true' )  
		FROM user_kyc
UNION ALL
		SELECT 
		3 AS step_no,
		'PAN_SUBMITTED',
		COUNT(*) 
		FILTER ( WHERE pan_submitted = 'true' )  
		FROM user_kyc
UNION ALL
		SELECT 
		4 AS step_no,
		'PAN_VERFIED',
		COUNT(*) 
		FILTER ( WHERE pan_verified = 'true' )  
		FROM user_kyc
UNION ALL
		SELECT 
		5 AS step_no,
		'AADHAR_LINKED',
		COUNT(*) 
		FILTER ( WHERE aadhaar_linked = 'true' )  
		FROM user_kyc
UNION ALL
		SELECT 
		6 AS step_no,
		'SELFIE_SUBMITTED',
		COUNT(*) 
		FILTER ( WHERE selfie_submitted = 'true' )  
		FROM user_kyc

),
PREVIOUS_STEP AS 
(
SELECT 
	step_no,
	STAGE,
	USERS,
	LAG(USERS) OVER (ORDER BY step_no) AS PREV_STEP_USERS
FROM KYC_FUNNEL
)
--============CONVERSION PERCENTAGE=============---
SELECT
	step_no,
	STAGE,
	USERS,
	COALESCE(ROUND((USERS * 100)/PREV_STEP_USERS,2),100) AS CONVERSION_PCT,
	COALESCE(ROUND((100-((USERS*100)/PREV_STEP_USERS)),2),100) AS DROP_OFF_PCT
FROM PREVIOUS_STEP

---====KYC COMPLETION BY AQUISITION CHANNEL====--

SELECT
    signup_channel,
    COUNT(*) AS users
FROM users
GROUP BY signup_channel
ORDER BY users DESC;
--"signup_channel"		"users"
--"organic"				15008
--"referral"			12617
--"paid_google"			10106
--"paid_meta"			7298
--"app_store_search"	4971

==--null check

SELECT
	A.USER_ID,
	u.signup_channel
--SELECT COUNT(*)
FROM USER_KYC A--50000
LEFT JOIN USERS U
ON A.USER_ID = U.user_id--50000
WHERE U.signup_channel IS NULL
---NO NULLS

--=========CHANNEL WISE CONVERSION PCT=========---

CREATE OR REPLACE VIEW vw_channel_kyc_funnel AS (
SELECT 
		U.signup_channel AS CHANNEL,
		COUNT(*) AS Total_Users,
		COUNT(*) 
		FILTER ( WHERE phone_verified = 'true' ) AS  Phone_Verified,
		COUNT(*) 
		FILTER ( WHERE pan_submitted = 'true' )  AS pan_submitted,
		COUNT(*) 
		FILTER ( WHERE pan_verified = 'true' )  AS pan_verified,
		COUNT(*) 
		FILTER ( WHERE aadhaar_linked = 'true' )  AS aadhaar_linked,
		COUNT(*) 
		FILTER ( WHERE selfie_submitted = 'true' )  AS selfie_submitted
--SELECT COUNT(*)
FROM user_kyc A--50000
LEFT JOIN USERS U
ON A.USER_ID = U.user_id--50000
GROUP BY U.signup_channel
)

SELECT 
	CHANNEL,
	ROUND((Phone_Verified *100)/Total_Users,2) AS "PCT_PHONE_VERIFIED",
	ROUND((pan_submitted *100)/Total_Users,2) AS "PCT_pan_submitted",
	ROUND((pan_verified *100)/Total_Users,2) AS "PCT_pan_verified",
	ROUND((aadhaar_linked *100)/Total_Users,2) AS "PCT_aadhaar_linked",
	ROUND((selfie_submitted *100)/Total_Users,2) AS "PCT_selfie_submitted"
FROM vw_channel_kyc_funnel
ORDER BY 6 DESC

--==STEP TO STEP CHANNEL WISE CONVERSION PCT=---

SELECT 
	CHANNEL,
	ROUND((Phone_Verified *100)/Total_Users,2) AS "signup_to_phone_pct",
	ROUND((pan_submitted *100)/PHONE_VERIFIED,2) AS "phone_to_pan_pct",
	ROUND((pan_verified *100)/pan_submitted,2) AS "pan_to_verified_pct",
	ROUND((aadhaar_linked *100)/pan_verified,2) AS "verified_to_aadhaar_pct",
	ROUND((selfie_submitted *100)/aadhaar_linked,2) AS "aadhaar_to_selfie_pct"
FROM vw_channel_kyc_funnel
ORDER BY 5 DESC

--============KYC Funnel by City Tier============--

SELECT
    city_tier,
    COUNT(*) AS total_users
FROM users
GROUP BY city_tier
ORDER BY total_users DESC

CREATE OR REPLACE VIEW  CITY_FUNNEL AS 
SELECT 
		U.city_tier AS city_tier,
		COUNT(*) AS Total_Users,
		COUNT(*) 
		FILTER ( WHERE phone_verified = 'true' ) AS  Phone_Verified,
		COUNT(*) 
		FILTER ( WHERE pan_submitted = 'true' )  AS pan_submitted,
		COUNT(*) 
		FILTER ( WHERE pan_verified = 'true' )  AS pan_verified,
		COUNT(*) 
		FILTER ( WHERE aadhaar_linked = 'true' )  AS aadhaar_linked,
		COUNT(*) 
		FILTER ( WHERE selfie_submitted = 'true' )  AS selfie_submitted
--SELECT COUNT(*)
FROM user_kyc A--50000
LEFT JOIN USERS U
ON A.USER_ID = U.user_id--50000
GROUP BY U.city_tier

--SELECT * FROM CITY_FUNNEL

SELECT 
	city_tier,
	ROUND((Phone_Verified *100)/Total_Users,2) AS "PCT_PHONE_VERIFIED",
	ROUND((pan_submitted *100)/Total_Users,2) AS "PCT_pan_submitted",
	ROUND((pan_verified *100)/Total_Users,2) AS "PCT_pan_verified",
	ROUND((aadhaar_linked *100)/Total_Users,2) AS "PCT_aadhaar_linked",
	ROUND((selfie_submitted *100)/Total_Users,2) AS "PCT_selfie_submitted"
FROM CITY_FUNNEL
ORDER BY 6 DESC;

--==STEP TO STEP TIER WISE CONVERSION PCT=---

SELECT 
	city_tier,
	ROUND((Phone_Verified *100)/Total_Users,2) AS "signup_to_phone_pct",
	ROUND((pan_submitted *100)/Phone_Verified,2) AS "phone_to_pan_pct",
	ROUND((pan_verified *100)/pan_submitted,2) AS "pan_to_verified_pct",
	ROUND((aadhaar_linked *100)/pan_verified,2) AS "verified_to_aadhaar_pct",
	ROUND((selfie_submitted *100)/aadhaar_linked,2) AS "aadhaar_to_selfie_pct"
FROM CITY_FUNNEL
ORDER BY 5 DESC

--===============KYC Funnel by DEVICE===============--

SELECT * FROM devices

SELECT
    device_type,
    COUNT(DISTINCT user_id) AS total_users
FROM devices
GROUP BY device_type
ORDER BY total_users DESC;
--"device_type"	"total_users"
--"android"			39687
--"ios"				11758

--==NULL CHECK
SELECT DISTINCT 
	A.user_id 
FROM devices A
LEFT JOIN CITY_FUNNEL B
ON A.USER_ID =B.USER_ID
WHERE A.user_id IS NULL
--NO NULLS

CREATE OR REPLACE VIEW DEVICE_FUNNEL AS
SELECT 
		B.DEVICE_TYPE AS DEVICE_TYPE,
		COUNT(*) AS Total_Users,
		COUNT(*) 
		FILTER ( WHERE phone_verified = 'true' ) AS  Phone_Verified,
		COUNT(*) 
		FILTER ( WHERE pan_submitted = 'true' )  AS pan_submitted,
		COUNT(*) 
		FILTER ( WHERE pan_verified = 'true' )  AS pan_verified,
		COUNT(*) 
		FILTER ( WHERE aadhaar_linked = 'true' )  AS aadhaar_linked,
		COUNT(*) 
		FILTER ( WHERE selfie_submitted = 'true' )  AS selfie_submitted
--SELECT COUNT(*)
FROM user_kyc A--50000
LEFT JOIN devices B
ON A.USER_ID =B.USER_ID
WHERE B.is_primary= 'true'
GROUP BY device_type


SELECT 
	DEVICE_TYPE,
	ROUND((Phone_Verified *100)/Total_Users,2) AS "PCT_PHONE_VERIFIED",
	ROUND((pan_submitted *100)/Total_Users,2) AS "PCT_pan_submitted",
	ROUND((pan_verified *100)/Total_Users,2) AS "PCT_pan_verified",
	ROUND((aadhaar_linked *100)/Total_Users,2) AS "PCT_aadhaar_linked",
	ROUND((selfie_submitted *100)/Total_Users,2) AS "PCT_selfie_submitted"
FROM DEVICE_FUNNEL
ORDER BY 6 DESC;

--==STEP TO STEP DISPLAY TYPE CONVERSION PCT=---

SELECT 
	DEVICE_TYPE,
	ROUND((Phone_Verified *100)/Total_Users,2) AS "signup_to_phone_pct",
	ROUND((pan_submitted *100)/Phone_Verified,2) AS "phone_to_pan_pct",
	ROUND((pan_verified *100)/pan_submitted,2) AS "pan_to_verified_pct",
	ROUND((aadhaar_linked *100)/pan_verified,2) AS "verified_to_aadhaar_pct",
	ROUND((selfie_submitted *100)/aadhaar_linked,2) AS "aadhaar_to_selfie_pct"
FROM DEVICE_FUNNEL
ORDER BY 5 DESC


--=============TIME TO COMPLETE KYC===============--

SELECT
    column_name,
    data_type
FROM information_schema.columns
WHERE table_name = 'user_kyc'
  AND data_type LIKE '%timestamp%'
ORDER BY ordinal_position;

--===============TIME TO EACHS STEP=================--

SELECT * FROM USER_KYC 

SELECT 
	ROUND(AVG(EXTRACT(EPOCH FROM (A.phone_verified_at-(B.SIGNUP_DATE::TIMESTAMP))/60)),2) AS AVG_Minutes_Minutes_Signup_To_Phone,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.pan_submitted_at - A.phone_verified_at)/60)),2) AS AVG_Minutes_Phone_To_Pan_Submitted,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.pan_verified_at - A.pan_submitted_at)/60)),2) AS AVG_Minutes_Pan_Submitted_To_Pan_verified,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.aadhaar_linked_at - A.pan_verified_at)/60)),2) AS AVG_Minutes_Pan_Verified_To_Aadhar_linked,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.selfie_submitted_at - A.aadhaar_linked_at)/60)),2) AS AVG_Minutes_Aadhar_Linked_To_Selfie_Submited,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.kyc_approved_at - A.selfie_submitted_at)/60)),2) AS AVG_Minutes_Selfie_Submitted_To_KYC_Approved,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.kyc_approved_at - (B.SIGNUP_DATE::TIMESTAMP))/60)),2) AS AVG_Total_Minutes_To_KYC_Approved
FROM USER_KYC A
JOIN USERS B ON A.USER_ID = B.USER_ID
WHERE KYC_STATUS = 'approved'
AND A.phone_verified_at IS NOT NULL
AND A.kyc_approved_at   IS NOT NULL

--===========TIME TO EACHS STEP TIER WISE=============--


SELECT 
	B.city_tier,
	COUNT(A.Kyc_id) as Approved_Users,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.phone_verified_at-(B.SIGNUP_DATE::TIMESTAMP))/60)),2) AS AVG_Minutes_Minutes_Signup_To_Phone,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.pan_submitted_at - A.phone_verified_at)/60)),2) AS AVG_Minutes_Phone_To_Pan_Submitted,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.pan_verified_at - A.pan_submitted_at)/60)),2) AS AVG_Minutes_Pan_Submitted_To_Pan_verified,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.aadhaar_linked_at - A.pan_verified_at)/60)),2) AS AVG_Minutes_Pan_Verified_To_Aadhar_linked,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.selfie_submitted_at - A.aadhaar_linked_at)/60)),2) AS AVG_Minutes_Aadhar_Linked_To_Selfie_Submited,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.kyc_approved_at - A.selfie_submitted_at)/60)),2) AS AVG_Minutes_Selfie_Submitted_To_KYC_Approved,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.kyc_approved_at - (B.SIGNUP_DATE::TIMESTAMP))/60)),2) AS AVG_Total_Minutes_To_KYC_Approved
FROM USER_KYC A
JOIN USERS B ON A.USER_ID = B.USER_ID
WHERE KYC_STATUS = 'approved'
AND A.phone_verified_at IS NOT NULL
AND A.kyc_approved_at   IS NOT NULL
GROUP BY B.city_tier
ORDER BY 2 DESC


--===========TIME TO EACHS STEP CHANNEL WISE=============--



SELECT 
	B.signup_channel,
	COUNT(A.Kyc_id) as Approved_Users,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.phone_verified_at-(B.SIGNUP_DATE::TIMESTAMP))/60)),2) AS AVG_Minutes_Minutes_Signup_To_Phone,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.pan_submitted_at - A.phone_verified_at)/60)),2) AS AVG_Minutes_Phone_To_Pan_Submitted,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.pan_verified_at - A.pan_submitted_at)/60)),2) AS AVG_Minutes_Pan_Submitted_To_Pan_verified,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.aadhaar_linked_at - A.pan_verified_at)/60)),2) AS AVG_Minutes_Pan_Verified_To_Aadhar_linked,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.selfie_submitted_at - A.aadhaar_linked_at)/60)),2) AS AVG_Minutes_Aadhar_Linked_To_Selfie_Submited,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.kyc_approved_at - A.selfie_submitted_at)/60)),2) AS AVG_Minutes_Selfie_Submitted_To_KYC_Approved,
	ROUND(AVG(EXTRACT(EPOCH FROM (A.kyc_approved_at - (B.SIGNUP_DATE::TIMESTAMP))/60)),2) AS AVG_Total_Minutes_To_KYC_Approved
FROM USER_KYC A
JOIN USERS B ON A.USER_ID = B.USER_ID
WHERE KYC_STATUS = 'approved'
AND A.phone_verified_at IS NOT NULL
AND A.kyc_approved_at   IS NOT NULL
GROUP BY B.signup_channel
ORDER BY 2 DESC


--============Time-to-KYC Distribution Buckets============--

WITH KYC_Time AS	(
SELECT
		EXTRACT(EPOCH FROM(kyc_approved_at-(B.SIGNUP_DATE::TIMESTAMP)))/60 AS Minutes_To_KYC,
		EXTRACT(EPOCH FROM(kyc_approved_at-(B.SIGNUP_DATE::TIMESTAMP)))/3600 AS Hours_To_KYC
FROM USER_KYC A			
LEFT JOIN USERS B ON A.USER_ID = B.USER_ID
WHERE KYC_STATUS = 'approved'
					),							
Bucketed_AS_Per_Time_Taken AS (
SELECT
		CASE 	WHEN	Minutes_To_KYC<= 15		THEN	'0-15MIN'
				WHEN 	Minutes_To_KYC<= 30		THEN 	'15-30MIN'
				WHEN 	Minutes_To_KYC<= 60		THEN 	'30-60MIN'
				WHEN 	Minutes_To_KYC<= 180	THEN 	'1-3HRS'
				WHEN 	Hours_To_KYC  <= 24		THEN 	'3-24HRS'
				ELSE 	'24 HRS +'	
		END 										AS 	Time_Bucket,
		CASE	WHEN	Minutes_To_KYC <= 15		THEN 1
				WHEN 	Minutes_To_KYC <= 30 		THEN 2
				WHEN 	Minutes_To_KYC <= 60		THEN 3 
				WHEN 	Minutes_To_KYC <= 180		THEN 4
				WHEN 	Hours_To_KYC   <= 24	 	THEN 5
				ELSE 	6	
		END											AS Bucket_Order
FROM KYC_Time 
							)
SELECT 
	Time_Bucket,
	Bucket_Order,
	COUNT(*) AS Users,
	ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER(),2) AS pct_approved,
	SUM(COUNT(*)) OVER (ORDER BY Bucket_Order) AS Cumulative_Users
FROM Bucketed_AS_Per_Time_Taken A
GROUP BY Time_Bucket,Bucket_Order
ORDER BY Bucket_Order
	
--=================New vs Activated Users Gap===============--

SELECT * FROM USERS
SELECT * FROM USER_kyc
SELECT DISTINCT kyc_status FROM USER_kyc

WITH USER_GAP AS (
SELECT 
	DATE_TRUNC('month',U.signup_date) 										AS Signup_Month,
	COUNT(DISTINCT(U.user_id)) AS New_users,
	COUNT(DISTINCT(CASE WHEN B.KYC_STATUS = 'approved' THEN U.user_id END)) AS activated_users
FROM USERS U
LEFT JOIN user_kyc B ON U.user_id =B.user_id
GROUP BY DATE_TRUNC('month',U.signup_date)
)

SELECT 
	Signup_Month,
	New_users,
	(New_users-activated_users) AS activation_gap,
	ROUND(100.00*activated_users/NULLIF(New_users,0),2) AS activation_rate,
	ROUND(lAG(100.00*activated_users/NULLIF(New_users,0)) OVER (ORDER BY Signup_Month),2) 	AS prev_month_activation_rate,
	ROUND((100.00*activated_users/NULLIF(New_users,0))-
		lAG(100.00*activated_users/NULLIF(New_users,0)) OVER (ORDER BY Signup_Month),2) 	AS 	mom_activation_change_pct
FROM USER_GAP 
order by Signup_Month 

--==========Activation Gap By Channel===========--


WITH USER_GAP_BY_CHANNEL AS (
SELECT 
	DATE_TRUNC('month',U.signup_date) 									AS Signup_Month,
	U.signup_channel,
	COUNT(DISTINCT(U.user_id)) 											AS New_users,
	COUNT(DISTINCT(U.user_id)) FILTER (WHERE B.KYC_STATUS = 'approved') AS activated_users
FROM USERS U
LEFT JOIN user_kyc B ON U.user_id =B.user_id
GROUP BY DATE_TRUNC('month',U.signup_date),U.signup_channel
),
ACTIVATION AS
(
SELECT
	Signup_Month,
	signup_channel,
	New_users,
	(New_users-activated_users) 						AS activation_gap,
	ROUND(100.00*activated_users/NULLIF(New_users,0),2) AS activation_rate
FROM USER_GAP_BY_CHANNEL
ORDER BY Signup_Month,signup_channel
)

SELECT 
	TO_CHAR(Signup_Month,'MON YYYY') 																			AS signup_month,
	signup_channel,
	New_users,
	activation_gap,
	activation_rate,
	lAG(activation_rate) OVER (PARTITION BY signup_channel ORDER BY Signup_Month) 								AS prev_month_activation_rate,
	ROUND(activation_rate - lAG(activation_rate) OVER (PARTITION BY signup_channel  ORDER BY Signup_Month),2) 	AS 	mom_activation_change_pct
FROM ACTIVATION 


--==========Activation Gap By City Tier===========--


WITH USER_GAP_BY_CHANNEL AS (
SELECT 
	DATE_TRUNC('month',U.signup_date) 									AS Signup_Month,
	U.city_tier,
	COUNT(DISTINCT(U.user_id)) 											AS New_users,
	COUNT(DISTINCT(U.user_id)) FILTER (WHERE B.KYC_STATUS = 'approved') AS activated_users
FROM USERS U
LEFT JOIN user_kyc B ON U.user_id =B.user_id
GROUP BY DATE_TRUNC('month',U.signup_date),U.city_tier
),
ACTIVATION AS
(
SELECT
	Signup_Month,
	city_tier,
	New_users,
	(New_users-activated_users) 						AS activation_gap,
	ROUND(100.00*activated_users/NULLIF(New_users,0),2) AS activation_rate
FROM USER_GAP_BY_CHANNEL
ORDER BY Signup_Month,city_tier
)

SELECT 
	TO_CHAR(Signup_Month,'MON YYYY') 																		AS signup_month,
	city_tier,
	New_users,
	activation_gap,
	activation_rate,
	lAG(activation_rate) OVER (PARTITION BY city_tier ORDER BY Signup_Month) 								AS prev_month_activation_rate,
	ROUND(activation_rate - lAG(activation_rate) OVER (PARTITION BY city_tier  ORDER BY Signup_Month),2) 	AS 	mom_activation_change_pct
FROM ACTIVATION 

--=============Rejection Reasons Analysis================--

SELECT
    rejection_reason,
    COUNT(*)                                                       AS rejected_users,
    ROUND(100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (), 2)                                AS pct_of_rejections,
    SUM(COUNT(*)) OVER (ORDER BY COUNT(*) DESC)                    AS cumulative_count,
    ROUND(100.0 * SUM(COUNT(*)) OVER (ORDER BY COUNT(*) DESC)
        / SUM(COUNT(*)) OVER (), 2)                                AS cumulative_pct
FROM user_kyc
WHERE kyc_status = 'rejected'
  AND rejection_reason IS NOT NULL
GROUP BY rejection_reason
ORDER BY rejected_users DESC;

--=============Rejection Reasons by City Tier================--

SELECT
    u.city_tier,
    k.rejection_reason,
    COUNT(*)                                                        AS rejected_users,
    ROUND(100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (PARTITION BY u.city_tier), 2)        AS pct_within_tier
FROM user_kyc k
LEFT JOIN users u ON k.user_id = u.user_id
WHERE k.kyc_status = 'rejected'
  AND k.rejection_reason IS NOT NULL
GROUP BY u.city_tier, k.rejection_reason
ORDER BY u.city_tier, rejected_users DESC;

--=============Rejection Reasons by Channel ================--

SELECT
    u.signup_channel,
    k.rejection_reason,
    COUNT(*)                                                        AS rejected_users,
    ROUND(100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (PARTITION BY u.signup_channel), 2)   AS pct_within_channel
FROM user_kyc k
LEFT JOIN users u ON k.user_id = u.user_id
WHERE k.kyc_status = 'rejected'
  AND k.rejection_reason IS NOT NULL
GROUP BY u.signup_channel, k.rejection_reason
ORDER BY u.signup_channel, rejected_users DESC;

--=============Rejection Rate vs Drop-off Rate by Step ================--

-- Distinguishes between users who dropped off (never tried)
-- vs users who tried and got rejected (most recoverable)
SELECT
    COUNT(*)                                                        AS total_users,
    COUNT(*) FILTER (WHERE kyc_status = 'approved')                AS approved,
    COUNT(*) FILTER (WHERE kyc_status = 'rejected')                AS rejected,
    COUNT(*) FILTER (WHERE kyc_status = 'pending')                 AS dropped_off,
    COUNT(*) FILTER (WHERE kyc_status = 'in_review')               AS in_review,

    ROUND(100.0 * COUNT(*) FILTER (WHERE kyc_status = 'rejected')
        / NULLIF(COUNT(*) FILTER (WHERE selfie_submitted), 0), 2)  AS rejection_rate_of_completers,
    -- These are your highest priority re-engagement targets
    -- They got to selfie but failed — one retry could convert them
    COUNT(*) FILTER (WHERE kyc_status = 'rejected')                AS high_priority_reactivation
FROM user_kyc

--==================================Channel Vs Tier Heatmap ================================--

--==========KYC Activation Rate — Channel × Tier=============--

SELECT 
	DATE_TRUNC('month',U.signup_date) 													AS Signup_Month,
	U.city_tier,
	U.signup_channel,
	COUNT(DISTINCT(U.user_id)) 															AS Total_users,
	COUNT(DISTINCT(U.user_id)) FILTER (WHERE B.KYC_STATUS = 'approved') 				AS activated_users,
	ROUND(100.00*COUNT(DISTINCT(U.user_id)) FILTER (WHERE B.KYC_STATUS = 'approved')	
	/NULLIF(COUNT(DISTINCT(U.user_id)),0),2) 											AS activation_rate
FROM USERS U
LEFT JOIN user_kyc B ON U.user_id =B.user_id
GROUP BY DATE_TRUNC('month',U.signup_date),U.city_tier,U.signup_channel

--==========Full Heatmap — Every Metric Per Cell=============--

WITH EVERY_METRIC AS 
(
SELECT
	U.city_tier,
	U.signup_channel,
	COUNT(DISTINCT(U.user_id)) 															AS Signups,
	COUNT(DISTINCT(U.user_id)) FILTER (WHERE  k.kyc_status = 'approved')				AS activated,
	COUNT(DISTINCT(U.user_id)) FILTER (WHERE  k.phone_verified)							AS phone_verified_Users,
	COUNT(DISTINCT(U.user_id)) FILTER (WHERE  k.aadhaar_linked)							AS aadhaar_linked_Users,
	COUNT(DISTINCT(U.user_id)) FILTER (WHERE  k.selfie_submitted)						AS selfie_submitted_Users
FROM USERS U
LEFT JOIN user_kyc K ON U.user_id =K.user_id
GROUP BY U.city_tier,U.signup_channel
)

SELECT 
	city_tier,
	signup_channel,
	Signups,
	activated,
	ROUND(100.00* activated/NULLIF(Signups,0),2) 									AS activation_pct,
	ROUND(100.00* phone_verified_Users/NULLIF(Signups,0),2) 						AS phone_verified_Pct,
	ROUND(100.00* aadhaar_linked_Users/NULLIF(phone_verified_Users,0),2) 			AS aadhaar_linked_Pct,
	ROUND(100.00* selfie_submitted_Users/NULLIF(aadhaar_linked_Users,0),2) 			AS selfie_submitted_Pct,
	ROUND(1.0* selfie_submitted_Users/NULLIF(activated,0),2) 						AS signups_per_activation
FROM EVERY_METRIC

---====================Rank Each Cell — Best to Worst=============------

WITH CELL_METRICS AS 
(
SELECT
	U.city_tier,
	U.signup_channel,
	COUNT(DISTINCT(U.user_id)) 															AS Signups,
	COUNT(DISTINCT(U.user_id)) FILTER (WHERE  k.kyc_status = 'approved')				AS activated,
	ROUND(100.00*COUNT(DISTINCT(U.user_id)) FILTER (WHERE  k.kyc_status = 'approved')
		 /COUNT(DISTINCT(U.user_id) ),2) 												AS activation_pct
FROM USERS U
LEFT JOIN user_kyc K ON U.user_id =K.user_id
GROUP BY U.city_tier,U.signup_channel
)

SELECT
    signup_channel,
    city_tier,
    signups,
    activated,
    activation_pct,
	RANK() OVER (ORDER BY activation_pct DESC)                      			AS rank_overall,
	RANK() OVER (PARTITION BY signup_channel ORDER BY activation_pct DESC)    	AS rank_within_channel,
	RANK() OVER (PARTITION BY city_tier ORDER BY activation_pct DESC)    		AS rank_within_tier,
	CASE
        WHEN activation_pct >= 20
        THEN 'invest_more'
        WHEN activation_pct >= 10
        THEN 'monitor'
        ELSE 'optimize_before_scaling'
    END            																AS budget_recommendation
FROM CELL_METRICS

--===============Volume × Quality Matrix==============--
-- The most important strategic view:
-- High volume + high activation = scale aggressively
-- High volume + low activation  = fix or cut
-- Low volume  + high activation = grow this channel
-- Low volume  + low activation  = deprioritise

WITH cell AS (
    SELECT
        u.signup_channel,
        u.city_tier,
        COUNT(DISTINCT u.user_id)                                   				AS signups,
        COUNT(DISTINCT(u.user_id )) FILTER (WHERE k.kyc_status = 'approved')  		AS activated,
                                                 
        ROUND(100.0 * COUNT(DISTINCT CASE WHEN k.kyc_status = 'approved'
                                          THEN u.user_id END)
            / NULLIF(COUNT(DISTINCT u.user_id), 0), 2)              				AS activation_pct
    FROM users u
    LEFT JOIN user_kyc k ON u.user_id = k.user_id
    GROUP BY u.signup_channel, u.city_tier
),
averages AS (
    SELECT
        AVG(signups)        AS avg_signups,
        AVG(activation_pct) AS avg_activation
    FROM cell
)

SELECT
    c.signup_channel,
    c.city_tier,
    c.signups,
    c.activated,
    c.activation_pct,
    CASE
        WHEN c.signups >= a.avg_signups
         AND c.activation_pct >= a.avg_activation
        THEN 'Scale — High Volume, High Quality'
        WHEN c.signups >= a.avg_signups
         AND c.activation_pct < a.avg_activation
        THEN 'Fix — High Volume, Low Quality'
        WHEN c.signups < a.avg_signups
         AND c.activation_pct >= a.avg_activation
        THEN 'Grow — Low Volume, High Quality'
        ELSE
        'Deprioritise — Low Volume, Low Quality'
    END                                                             AS strategic_action
FROM cell c
CROSS JOIN averages a
ORDER BY c.activation_pct DESC

