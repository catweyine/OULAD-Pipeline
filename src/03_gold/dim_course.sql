-- Grain: 1 row per course offering
-- (code_module + code_presentation)

CREATE TABLE IF NOT EXISTS oulad.oulad_gold.dim_course (
    course_id STRING,
    code_module STRING,
    code_presentation STRING,
    module_presentation_length INT
)
USING DELTA;

INSERT OVERWRITE oulad.oulad_gold.dim_course
SELECT DISTINCT
    CONCAT(code_module, '_', code_presentation) AS course_id,
    code_module,
    code_presentation,
    module_presentation_length
FROM oulad.oulad_silver.courses_silver;