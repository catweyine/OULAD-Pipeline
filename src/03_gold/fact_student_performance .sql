CREATE OR REPLACE TABLE oulad.oulad_gold.fact_student_performance
USING DELTA
AS
SELECT
    XXHASH64(sp.id_student, sp.id_assessment) AS student_performance_key,
    se.student_enrollment_id,          
    da.assessment_key,
    dc.course_id,
    dcw.week_id,
    da.assessment_day_offset AS assessment_date,   
    sp.date_submitted AS submission_day_offset,
    sp.is_banked,
    sp.score,
    CASE WHEN da.assessment_day_offset IS NOT NULL
         AND sp.date_submitted IS NOT NULL
        THEN sp.date_submitted - da.assessment_day_offset
        ELSE NULL
    END AS days_late,
    CASE WHEN sp.score IS NULL THEN TRUE ELSE FALSE END AS is_non_submission,
    CASE WHEN sp.score IS NOT NULL AND da.weight IS NOT NULL
        THEN sp.score * da.weight / 100.0
        ELSE NULL
    END AS weighted_score

FROM oulad.oulad_silver.student_assessment_silver AS sp

INNER JOIN oulad.oulad_silver.assessments_silver AS a
    ON sp.id_assessment = a.id_assessment

INNER JOIN oulad.oulad_gold.dim_assessment AS da
    ON sp.id_assessment = da.assessment_key

INNER JOIN oulad.oulad_gold.dim_course AS dc
    ON  a.code_module = dc.code_module
    AND a.code_presentation = dc.code_presentation

LEFT JOIN oulad.oulad_gold.dim_student_enrollment AS se   
    ON  sp.id_student = se.student_id
    AND dc.course_id  = se.course_id

LEFT JOIN oulad.oulad_gold.dim_course_week AS dcw
    ON  dcw.course_id = dc.course_id
    AND dcw.week_id  = CASE WHEN sp.date_submitted >=0 THEN CEIL(sp.date_submitted / 7.0) ELSE floor(sp.date_submitted / 7.0) end; 