-- DIM_COURSE
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT course_id) AS distinct_course_id,
    SUM(CASE WHEN course_id IS NULL THEN 1 ELSE 0 END) AS null_course_id,
    SUM(CASE WHEN code_module IS NULL THEN 1 ELSE 0 END) AS null_code_module,
    SUM(CASE WHEN code_presentation IS NULL THEN 1 ELSE 0 END) AS null_code_presentation,
    COUNT(*) - COUNT(DISTINCT course_id) AS duplicate_course_id
FROM oulad.oulad_gold.dim_course;

SELECT
    COUNT(DISTINCT CONCAT(code_module,'_',code_presentation)) AS source_count,
    (SELECT COUNT(*)
     FROM oulad.oulad_gold.dim_course) AS target_count
FROM oulad.oulad_silver.courses_silver;

-- DIM_VLE
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT vle_id) AS distinct_vle_id,
    SUM(CASE WHEN vle_id IS NULL THEN 1 ELSE 0 END) AS null_vle_id,
    SUM(CASE WHEN activity_type IS NULL THEN 1 ELSE 0 END) AS null_activity_type,
    SUM(CASE WHEN week_from IS NULL THEN 1 ELSE 0 END) AS null_week_from,
    SUM(CASE WHEN week_to IS NULL THEN 1 ELSE 0 END) AS null_week_to,
    COUNT(*) - COUNT(DISTINCT vle_id) AS duplicate_vle_id,
    SUM(CASE WHEN week_from > week_to THEN 1 ELSE 0 END) AS invalid_week_range
FROM oulad.oulad_gold.dim_vle;

SELECT
    COUNT(DISTINCT id_site) AS source_count,
    (SELECT COUNT(*)
     FROM oulad.oulad_gold.dim_vle) AS target_count
FROM oulad.oulad_silver.vle_silver;