USE CATALOG oulad;

CREATE OR REPLACE TABLE oulad.oulad_gold.fact_student_performance 
USING DELTA
AS
SELECT sp.id_student, sp.id_assessment, a.code_module, a.code_presentation,
sp.date_submitted, sp.is_banked, sp.score,
CASE WHEN a.date IS NOT NULL THEN sp.date_submitted - a.date END AS days_late,
    sp.score IS NULL  AS is_non_submission,
    CASE WHEN sp.score IS NOT NULL THEN sp.score * a.weight / 100.0 END AS weighted_contribution 
FROM oulad.oulad_silver.student_assessment_silver AS sp
INNER JOIN oulad.oulad_silver.assessments_silver AS a
ON sp.id_assessment =a.id_assessment;
