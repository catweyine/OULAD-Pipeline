-- SILVER DATA QUALITY CHECKS: course_silver
SELECT COUNT(*) AS total_rows
FROM oulad.oulad_silver.courses_silver;

SELECT
    code_module,
    code_presentation,
    COUNT(*) AS duplicate_count
FROM oulad.oulad_silver.courses_silver
GROUP BY code_module, code_presentation
HAVING COUNT(*) > 1;

SELECT
    SUM(CASE WHEN code_module IS NULL THEN 1 ELSE 0 END) AS null_code_module,
    SUM(CASE WHEN code_presentation IS NULL THEN 1 ELSE 0 END) AS null_code_presentation,
    SUM(CASE WHEN module_presentation_length IS NULL THEN 1 ELSE 0 END) AS null_module_presentation_length
FROM oulad.oulad_silver.courses_silver;

-- SILVER DATA QUALITY CHECKS: vle_silver
    -- Row count
    SELECT COUNT(*) AS total_rows
    FROM oulad.oulad_silver.vle_silver;

    -- Duplicate business key check
    SELECT COUNT(*) AS duplicate_id_site_records
    FROM (
        SELECT id_site
        FROM oulad.oulad_silver.vle_silver
        GROUP BY id_site
        HAVING COUNT(*) > 1
    );

    -- Null check
    SELECT
        SUM(CASE WHEN id_site IS NULL THEN 1 ELSE 0 END) AS null_id_site,
        SUM(CASE WHEN code_module IS NULL THEN 1 ELSE 0 END) AS null_code_module,
        SUM(CASE WHEN code_presentation IS NULL THEN 1 ELSE 0 END) AS null_code_presentation,
        SUM(CASE WHEN activity_type IS NULL THEN 1 ELSE 0 END) AS null_activity_type
    FROM oulad.oulad_silver.vle_silver;

    -- Count missing weeks after cleaning
    SELECT
        SUM(CASE WHEN week_from IS NULL THEN 1 ELSE 0 END) AS null_week_from,
        SUM(CASE WHEN week_to IS NULL THEN 1 ELSE 0 END) AS null_week_to
    FROM oulad.oulad_silver.vle_silver;

    -- Count invalid week ranges
    SELECT COUNT(*) AS invalid_week_range_records
    FROM oulad.oulad_silver.vle_silver
    WHERE week_from > week_to;

    -- Distinct activity types
    SELECT COUNT(DISTINCT activity_type) AS distinct_activity_types
    FROM oulad.oulad_silver.vle_silver;