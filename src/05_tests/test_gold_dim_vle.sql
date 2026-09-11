-- DATA QUALITY VALIDATION: oulad.oulad_gold.dim_vle
-- Test Type: POST-LOAD / AT-REST VALIDATION
-- Layer: GOLD (Dimensional Model)

-- SECTION 1: DATA INTEGRITY CHECKS

-- CHECK 1.1: COMPLETENESS - Record Count
SELECT
    'COMPLETENESS' AS check_category,
    'Record Count' AS check_name,
    COUNT(*) AS actual_count,
    CASE
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Dimension table should contain at least 1 record' AS description
FROM oulad.oulad_gold.dim_vle;

-- CHECK 1.2: COMPLETENESS - Null Value Assessment
-- Purpose: Dimension key and attributes should be populated
SELECT
    'COMPLETENESS' AS check_category,
    'Null Value Assessment' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN vle_id IS NULL THEN 1 ELSE 0 END) AS null_vle_id,
    SUM(CASE WHEN activity_type IS NULL THEN 1 ELSE 0 END) AS null_activity_type,
    CASE
        WHEN SUM(
            CASE
                WHEN vle_id IS NULL
                  OR activity_type IS NULL
                THEN 1 ELSE 0
            END
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Dimension key and attributes should not be NULL' AS description
FROM oulad.oulad_gold.dim_vle;

-- CHECK 1.3: UNIQUENESS - Duplicate Dimension Keys
-- Purpose: VLE ID should be unique
SELECT
    'UNIQUENESS' AS check_category,
    'Duplicate Dimension Keys' AS check_name,
    COUNT(*) - COUNT(DISTINCT vle_id) AS duplicate_vle_id,
    CASE
        WHEN COUNT(*) = COUNT(DISTINCT vle_id)
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'VLE ID should be unique within the dimension table' AS description
FROM oulad.oulad_gold.dim_vle;

-- CHECK 1.4: VALIDITY - Week Range Logic
-- Purpose: Week start should not be greater than week end
SELECT
    'VALIDITY' AS check_category,
    'Week Range Logic' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN week_from > week_to THEN 1 ELSE 0 END) AS invalid_week_range,
    CASE
        WHEN SUM(CASE WHEN week_from > week_to THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Week from should be less than or equal to week to' AS description
FROM oulad.oulad_gold.dim_vle;

-- SECTION 2: CONSISTENCY CHECKS

-- CHECK 2.1: CONSISTENCY - Source to Target Record Count
-- Purpose: Verify all unique VLE records from silver are loaded into gold
SELECT
    'CONSISTENCY' AS check_category,
    'Source to Target Record Count' AS check_name,
    COUNT(DISTINCT id_site) AS source_count,
    (SELECT COUNT(*) FROM oulad.oulad_gold.dim_vle) AS target_count,
    CASE
        WHEN COUNT(DISTINCT id_site)
             = (SELECT COUNT(*) FROM oulad.oulad_gold.dim_vle)
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Gold dimension should contain all unique VLE records from silver' AS description
FROM oulad.oulad_silver.vle_silver;

-- SECTION 3: SUMMARY REPORT

-- CHECK 3.1: Overall Table Profile
-- Purpose: High-level overview of dimension quality
SELECT
    'SUMMARY' AS check_category,
    'Table Profile' AS check_name,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT vle_id) AS distinct_vle_id,
    COUNT(*) - COUNT(DISTINCT vle_id) AS duplicate_vle_id,
    SUM(CASE WHEN vle_id IS NULL THEN 1 ELSE 0 END) AS null_vle_id,
    SUM(CASE WHEN activity_type IS NULL THEN 1 ELSE 0 END) AS null_activity_type,
    SUM(CASE WHEN week_from > week_to THEN 1 ELSE 0 END) AS invalid_week_range,
    'INFO' AS status,
    'Gold dimension overview statistics' AS description
FROM oulad.oulad_gold.dim_vle;