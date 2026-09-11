CREATE OR REPLACE TABLE oulad.oulad_gold.fact_student_engagement
USING DELTA
AS
SELECT
  XXHASH64(sv.id_student, sv.id_site, sv.date) AS student_engagement_key,
    sv.id_student,                        -- FK -> dim_student
    sv.id_site,                           -- FK -> dim_vle
   dc.course_id,
   -- Time dimension: days since the start of the module-presentation,
   -- per the OULAD data dictionary. Can be negative (access before
   -- the official start date).
   sv.date                AS interaction_date,
   -- Core measure
   sv.sum_click             AS click_count

FROM oulad.oulad_silver.student_vle_silver AS sv

LEFT JOIN oulad.oulad_gold.dim_course AS dc
   ON sv.code_module = dc.code_module
  AND sv.code_presentation = dc.code_presentation;
