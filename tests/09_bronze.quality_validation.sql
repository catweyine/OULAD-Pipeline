-- BRONZE DATA QUALITY CHECKS: course_bronze
    -- Row count
    SELECT COUNT(*) AS total_rows
    FROM oulad.oulad_bronze.courses_bronze;

    -- Check duplicate business keys
    SELECT
        code_module,
        code_presentation,
        COUNT(*) AS duplicate_count
    FROM oulad.oulad_bronze.courses_bronze
    GROUP BY code_module, code_presentation
    HAVING COUNT(*) > 1;

    -- Check null values
    SELECT
        SUM(CASE WHEN code_module IS NULL THEN 1 ELSE 0 END) AS null_code_module,
        SUM(CASE WHEN code_presentation IS NULL THEN 1 ELSE 0 END) AS null_code_presentation,
        SUM(CASE WHEN module_presentation_length IS NULL THEN 1 ELSE 0 END) AS null_module_presentation_length
    FROM oulad.oulad_bronze.courses_bronze;

    -- Check distinct module codes
    SELECT DISTINCT code_module
    FROM oulad.oulad_bronze.courses_bronze
    ORDER BY code_module;

    -- Check distinct presentation codes
    SELECT DISTINCT code_presentation
    FROM oulad.oulad_bronze.courses_bronze
    ORDER BY code_presentation;

    -- Count invalid presentation lengths
    SELECT COUNT(*) AS invalid_presentation_length_records
    FROM oulad.oulad_bronze.courses_bronze
    WHERE module_presentation_length <= 0;
    
-- BRONZE DATA QUALITY CHECKS: vle_bronze
-- Business Key Candidate: id_site

    -- Row count
    SELECT COUNT(*) AS total_rows
    FROM oulad.oulad_bronze.vle_bronze;

    -- Check duplicate id_site values
    SELECT
        id_site,
        COUNT(*) AS duplicate_count
    FROM oulad.oulad_bronze.vle_bronze
    GROUP BY id_site
    HAVING COUNT(*) > 1;

    -- Check null values
    SELECT
        SUM(CASE WHEN id_site IS NULL THEN 1 ELSE 0 END) AS null_id_site,
        SUM(CASE WHEN code_module IS NULL THEN 1 ELSE 0 END) AS null_code_module,
        SUM(CASE WHEN code_presentation IS NULL THEN 1 ELSE 0 END) AS null_code_presentation,
        SUM(CASE WHEN activity_type IS NULL THEN 1 ELSE 0 END) AS null_activity_type,
        SUM(CASE WHEN week_from IS NULL THEN 1 ELSE 0 END) AS null_week_from,
        SUM(CASE WHEN week_to IS NULL THEN 1 ELSE 0 END) AS null_week_to
    FROM oulad.oulad_bronze.vle_bronze;

    -- Distinct values
    SELECT DISTINCT code_module
    FROM oulad.oulad_bronze.vle_bronze
    ORDER BY code_module;

    SELECT DISTINCT code_presentation
    FROM oulad.oulad_bronze.vle_bronze
    ORDER BY code_presentation;

    SELECT DISTINCT activity_type
    FROM oulad.oulad_bronze.vle_bronze
    ORDER BY activity_type;

    -- Count malformed week values
    SELECT
        COUNT(*) AS malformed_week_records
    FROM oulad.oulad_bronze.vle_bronze
    WHERE TRY_CAST(week_from AS INT) IS NULL
    OR TRY_CAST(week_to AS INT) IS NULL;

    -- Count invalid week ranges
    SELECT COUNT(*) AS invalid_week_range_records
    FROM oulad.oulad_bronze.vle_bronze
    WHERE TRY_CAST(week_from AS INT) > TRY_CAST(week_to AS INT);

    -- Count negative week values
    SELECT COUNT(*) AS negative_week_records
    FROM oulad.oulad_bronze.vle_bronze
    WHERE TRY_CAST(week_from AS INT) < 0
    OR TRY_CAST(week_to AS INT) < 0;

    -- Check ingestion dates
    SELECT DISTINCT ingestion_date
    FROM oulad.oulad_bronze.vle_bronze
    ORDER BY ingestion_date;