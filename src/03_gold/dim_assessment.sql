-- =====================================================================
-- dim_assessment — grain: 1 row per assessment
-- =====================================================================
CREATE OR REPLACE TABLE oulad.oulad_gold.dim_assessment AS
SELECT
    id_assessment as assessment_key, --Primary key
    CONCAT(code_module, '_', code_presentation) AS course_id,   -- FK -> dim_course
    assessment_type,
    date AS assessment_day_offset,   -- days from presentation start; NULL for exams
    weight
FROM oulad.oulad_silver.assessments_silver;