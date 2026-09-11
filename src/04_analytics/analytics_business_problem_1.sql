-- BP1: How does student engagement relate to performance?
-- Aggregates VLE engagement and assessment performance independently to the enrollment
-- grain, combines them through the shared dimension key, then buckets students into
-- engagement quartiles to show how performance outcomes shift across engagement levels.

WITH engagement AS (
    SELECT
        student_enrollment_id,
        SUM(sum_click)                 AS total_clicks,
        COUNT(DISTINCT interaction_date) AS active_days
    FROM oulad.oulad_gold.fact_student_engagement
    GROUP BY student_enrollment_id
),

performance AS (
    SELECT
        student_enrollment_id,
        AVG(score)                      AS avg_score,
        SUM(weighted_score)              AS total_weighted_score,
        COUNT(student_performance_key)   AS assessment_count
    FROM oulad.oulad_gold.fact_student_performance
    GROUP BY student_enrollment_id
),

combined AS (
    SELECT
        COALESCE(e.student_enrollment_id, p.student_enrollment_id) AS student_enrollment_id,
        COALESCE(e.total_clicks, 0)      AS total_clicks,
        COALESCE(e.active_days, 0)       AS active_days,
        p.avg_score,
        p.total_weighted_score,
        p.assessment_count
    FROM engagement e
    FULL OUTER JOIN performance p
        ON e.student_enrollment_id = p.student_enrollment_id
),

-- 1. Bucket students into engagement quartiles (relative, since raw click counts
--    have no natural business threshold the way credit loads do in BP2)
engagement_tiers AS (
    SELECT
        *,
        NTILE(4) OVER (ORDER BY total_clicks) AS engagement_quartile
    FROM combined
),

-- 2. Summarize performance outcomes by engagement tier
engagement_performance_summary AS (
    SELECT
        CASE engagement_quartile
            WHEN 1 THEN 'Q1 - Lowest Engagement'
            WHEN 2 THEN 'Q2'
            WHEN 3 THEN 'Q3'
            WHEN 4 THEN 'Q4 - Highest Engagement'
        END AS engagement_tier,
        COUNT(*)                           AS student_count,
        ROUND(AVG(total_clicks), 1)        AS avg_clicks,
        ROUND(AVG(active_days), 1)         AS avg_active_days,
        ROUND(AVG(avg_score), 2)           AS avg_score,
        ROUND(AVG(total_weighted_score), 2) AS avg_weighted_score
    FROM engagement_tiers
    WHERE avg_score IS NOT NULL   -- only students with assessment data can show a performance outcome
    GROUP BY engagement_quartile
)

-- Primary query output: performance outcomes by engagement level
SELECT *
FROM engagement_performance_summary
ORDER BY engagement_tier;