CREATE OR REPLACE TABLE oulad.oulad_gold.dim_assessment AS
SELECT
 a.id_assessment AS assessment_key, --Primary key
 a.id_assessment, --natural key/source key
a.assessment_type,
a.assessment_type = 'Exam' AS is_exam,
a.date AS assessment_day_offset, -- rename date for clarity (date is information about the final submission date of the assessment calculated as the number of days since the start of the module-presentation.
a.weight,
  CASE WHEN assessment_day_offset IS NULL THEN 'unscheduled'
    WHEN c.module_presentation_length IS NULL THEN 'unknown'
    WHEN assessment_day_offset <= c.module_presentation_length * 0.33 THEN 'early'
    WHEN assessment_day_offset <= c.module_presentation_length * 0.66 THEN 'mid'
     ELSE 'late' END AS presentation_phase

FROM oulad.oulad_silver.assessments_silver a
LEFT JOIN oulad.oulad_silver.courses_silver c
ON a.code_module = c.code_module
AND a.code_presentation = c.code_presentation;