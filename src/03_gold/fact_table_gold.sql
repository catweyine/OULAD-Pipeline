CREATE OR REPLACE TABLE oulad.oulad_gold.fact_student_vle_engagement
USING DELTA
AS
SELECT
    sv.id_student,
    sv.id_site,
    sv.code_module,
    sv.code_presentation,
    sv.date            AS interaction_date,
    sv.sum_click        AS click_count,
    dv.activity_type,
    dv.week_from,
    dv.week_to
FROM oulad.oulad_silver.student_vle_clean AS sv
INNER JOIN oulad.oulad_gold.dim_vle AS dv
    ON sv.id_site = dv.id_site
INNER JOIN oulad.oulad_gold.dim_course AS dc
    ON sv.code_module = dc.code_module
   AND sv.code_presentation = dc.code_presentation;
