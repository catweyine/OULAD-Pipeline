-- =====================================================
-- DIM_COURSE VALIDATION
-- =====================================================

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT course_id) AS distinct_course_id,
    COUNT(*) - COUNT(DISTINCT course_id) AS duplicate_course_id,
    SUM(CASE WHEN course_id IS NULL THEN 1 ELSE 0 END) AS null_course_id,
    SUM(CASE WHEN code_module IS NULL THEN 1 ELSE 0 END) AS null_code_module,
    SUM(CASE WHEN code_presentation IS NULL THEN 1 ELSE 0 END) AS null_code_presentation,
    SUM(CASE WHEN module_presentation_length IS NULL THEN 1 ELSE 0 END) AS null_module_presentation_length
FROM oulad.oulad_gold.dim_course;

SELECT
    COUNT(DISTINCT CONCAT(code_module, '_', code_presentation)) AS source_count,
    (SELECT COUNT(*) FROM oulad.oulad_gold.dim_course) AS target_count
FROM oulad.oulad_silver.courses_silver;


-- =====================================================
-- DIM_VLE VALIDATION
-- =====================================================

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT vle_id) AS distinct_vle_id,
    COUNT(*) - COUNT(DISTINCT vle_id) AS duplicate_vle_id,
    SUM(CASE WHEN vle_id IS NULL THEN 1 ELSE 0 END) AS null_vle_id,
    SUM(CASE WHEN activity_type IS NULL THEN 1 ELSE 0 END) AS null_activity_type,
    SUM(CASE WHEN week_from > week_to THEN 1 ELSE 0 END) AS invalid_week_range
FROM oulad.oulad_gold.dim_vle;

SELECT
    COUNT(DISTINCT id_site) AS source_count,
    (SELECT COUNT(*) FROM oulad.oulad_gold.dim_vle) AS target_count
FROM oulad.oulad_silver.vle_silver;


-- =====================================================
-- DIM_COURSE_PHASE VALIDATION
-- =====================================================

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT phase_id) AS distinct_phase_id,
    COUNT(*) - COUNT(DISTINCT phase_id) AS duplicate_phase_id,
    SUM(CASE WHEN phase_id IS NULL THEN 1 ELSE 0 END) AS null_phase_id,
    SUM(CASE WHEN phase_name IS NULL THEN 1 ELSE 0 END) AS null_phase_name
FROM oulad.oulad_gold.dim_course_phase;


-- =====================================================
-- DIM_COURSE_WEEK VALIDATION
-- Grain: 1 row per course + week
-- =====================================================

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT CONCAT(course_id, '_', week_id)) AS distinct_course_week,
    COUNT(*) - COUNT(DISTINCT CONCAT(course_id, '_', week_id)) AS duplicate_course_week,
    SUM(CASE WHEN course_id IS NULL THEN 1 ELSE 0 END) AS null_course_id,
    SUM(CASE WHEN week_id IS NULL THEN 1 ELSE 0 END) AS null_week_id,
    SUM(CASE WHEN week_number IS NULL THEN 1 ELSE 0 END) AS null_week_number,
    SUM(CASE WHEN phase_id IS NULL THEN 1 ELSE 0 END) AS null_phase_id,
    SUM(CASE WHEN week_number <= 0 THEN 1 ELSE 0 END) AS invalid_week_number
FROM oulad.oulad_gold.dim_course_week;

SELECT
    COUNT(*) AS orphan_phase_records
FROM oulad.oulad_gold.dim_course_week cw
LEFT JOIN oulad.oulad_gold.dim_course_phase cp
    ON cw.phase_id = cp.phase_id
WHERE cp.phase_id IS NULL;

SELECT
    COUNT(*) AS orphan_course_records
FROM oulad.oulad_gold.dim_course_week cw
LEFT JOIN oulad.oulad_gold.dim_course c
    ON cw.course_id = c.course_id
WHERE c.course_id IS NULL;