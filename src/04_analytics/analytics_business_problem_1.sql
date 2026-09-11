WITH engagement AS (
    SELECT
        student_enrollment_id,
        SUM(sum_click)                   AS total_clicks,
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
)
SELECT
    COALESCE(e.student_enrollment_id, p.student_enrollment_id) AS student_enrollment_id,
    COALESCE(e.total_clicks, 0)      AS total_clicks,
    COALESCE(e.active_days, 0)       AS active_days,
    p.avg_score,
    p.total_weighted_score,
    p.assessment_count
FROM engagement e
FULL OUTER JOIN performance p
    ON e.student_enrollment_id = p.student_enrollment_id;