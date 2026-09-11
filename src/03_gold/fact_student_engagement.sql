CREATE OR REPLACE TABLE oulad.oulad_gold.fact_student_engagement
USING DELTA
AS
SELECT
    XXHASH64(se.student_enrollment_id, dv.vle_id, sv.date) AS engagement_id,
    se.student_enrollment_id,          -- FK -> dim_student_enrollment
    dv.vle_id,                         -- FK -> dim_vle
    dc.course_id,                      -- FK -> dim_course
    sv.date                AS interaction_date,
    dcw.week_id,                       -- FK -> dim_course_week
    SUM(sv.sum_click)      AS sum_click

FROM oulad.oulad_silver.student_vle_silver AS sv

LEFT JOIN oulad.oulad_gold.dim_course AS dc
    ON sv.code_module = dc.code_module
   AND sv.code_presentation = dc.code_presentation

LEFT JOIN oulad.oulad_gold.dim_student_enrollment AS se
    ON sv.id_student = se.student_id
   AND dc.course_id  = se.course_id

LEFT JOIN oulad.oulad_gold.dim_vle AS dv
    ON sv.id_site = dv.vle_id

LEFT JOIN oulad.oulad_gold.dim_course_week AS dcw
    ON dc.course_id = dcw.course_id
   AND dcw.week_id  = FLOOR(sv.date/7.0)+1 

GROUP BY
    se.student_enrollment_id,
    dv.vle_id,
    dc.course_id,
    sv.date,
    dcw.week_id;