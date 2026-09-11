CREATE OR REPLACE TABLE oulad.oulad_gold.fact_student_performance
USING DELTA
AS
-- Grain: 1 row = 1 student x 1 assessment
SELECT
    -- Fact surrogate key
    XXHASH64(
        sp.id_student,
        sp.id_assessment
    ) AS student_performance_key,
    -- Foreign keys from Gold dimensions
    ds.student_id,
    da.assessment_key,
    dmp.course_id,
    -- Measures / fact attributes
    sp.date_submitted AS submission_day_offset,
    sp.is_banked,
    sp.score,
    CASE
        WHEN da.assessment_day_offset IS NOT NULL
         AND sp.date_submitted IS NOT NULL
        THEN sp.date_submitted - da.assessment_day_offset
        ELSE NULL
    END AS days_late,
    CASE
        WHEN sp.score IS NULL THEN TRUE
        ELSE FALSE
    END AS is_non_submission,
    CASE
        WHEN sp.score IS NOT NULL
         AND da.weight IS NOT NULL
        THEN sp.score * da.weight / 100.0
        ELSE NULL
    END AS weighted_score

FROM oulad.oulad_silver.student_assessment_silver AS sp

INNER JOIN oulad.oulad_gold.dim_student AS ds
    ON sp.id_student = ds.student_id

INNER JOIN oulad.oulad_gold.dim_assessment AS da
    ON sp.id_assessment = da.id_assessment

INNER JOIN oulad.oulad_gold.dim_course AS dmp
    ON da.module_presentation_key = dmp.course_id;




select * from oulad.oulad_gold.fact_student_performance limit 10;
