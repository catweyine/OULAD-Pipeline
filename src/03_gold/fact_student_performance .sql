USE CATALOG oulad;

CREATE OR REPLACE TABLE oulad.oulad_gold.fact_student_performance 
USING DELTA
AS
--1 row = 1 student x 1 asessment 
SELECT  
XXHASH64(CONCAT_WS('|', sp.id_student, sp.id_assessment)) AS student_performance, --primary key
sp.id_student as student_key, --foreign key
sp.id_assessment as assessment_key, --foreign key
XXHASH64(CONCAT_WS('|', a.code_module, a.code_presentation)) AS module_presentation_key,--foreign key
sp.date_submitted AS submission_day_offset, 
sp.is_banked, 
sp.score,
CASE WHEN a.date IS NOT NULL THEN sp.date_submitted - a.date END AS days_late,
sp.score IS NULL  AS is_non_submission,
CASE WHEN sp.score IS NOT NULL THEN sp.score * a.weight / 100.0 END AS weighted_score 
FROM oulad.oulad_silver.student_assessment_silver AS sp
INNER JOIN oulad.oulad_silver.assessments_silver AS a
ON sp.id_assessment =a.id_assessment;
