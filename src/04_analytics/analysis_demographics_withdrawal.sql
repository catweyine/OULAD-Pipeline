
-- BP2: What patterns appear among students who withdraw?
-- Analyzes withdrawal rates across demographic factors (education, age, deprivation band, disability) and academic history.

WITH enrollment_demographics AS (
    SELECT 
        e.student_enrollment_id,
        e.student_id,
        e.course_id,
        e.num_of_prev_attempts,
        e.studied_credits,
        e.final_result,
        s.gender,
        s.region,
        s.highest_education,
        s.imd_band,
        s.age_band,
        s.disability,
        CASE WHEN UPPER(TRIM(e.final_result)) = 'WITHDRAWN' THEN 1 ELSE 0 END AS is_withdrawn
    FROM oulad.oulad_gold.dim_student_enrollment e
    INNER JOIN oulad.oulad_gold.dim_student s
        ON e.student_id = s.student_id
),

-- 1. Breakdown by Demographics (Highest Education, Age Band, IMD Band, Disability)
demographic_summary AS (
    SELECT 
        highest_education,
        age_band,
        imd_band,
        disability,
        COUNT(student_enrollment_id) AS total_enrollments,
        SUM(is_withdrawn) AS total_withdrawals,
        ROUND(SUM(is_withdrawn) * 100.0 / COUNT(student_enrollment_id), 2) AS withdrawal_rate_pct
    FROM enrollment_demographics
    GROUP BY 
        highest_education,
        age_band,
        imd_band,
        disability
),

-- 2. Breakdown by Prior Attempts and Course Load
academic_history_summary AS (
    SELECT 
        num_of_prev_attempts,
        CASE 
            WHEN studied_credits < 60 THEN '< 60 Credits'
            WHEN studied_credits BETWEEN 60 AND 120 THEN '60-120 Credits'
            ELSE '> 120 Credits'
        END AS credit_load_band,
        COUNT(student_enrollment_id) AS total_enrollments,
        SUM(is_withdrawn) AS total_withdrawals,
        ROUND(SUM(is_withdrawn) * 100.0 / COUNT(student_enrollment_id), 2) AS withdrawal_rate_pct
    FROM enrollment_demographics
    GROUP BY 
        num_of_prev_attempts,
        CASE 
            WHEN studied_credits < 60 THEN '< 60 Credits'
            WHEN studied_credits BETWEEN 60 AND 120 THEN '60-120 Credits'
            ELSE '> 120 Credits'
        END
)

-- Primary query output: Key demographic patterns associated with withdrawal
SELECT 
    highest_education,
    age_band,
    imd_band,
    disability,
    total_enrollments,
    total_withdrawals,
    withdrawal_rate_pct
FROM demographic_summary
WHERE total_enrollments >= 50 -- Filter out low sample sizes
ORDER BY withdrawal_rate_pct DESC, total_enrollments DESC;