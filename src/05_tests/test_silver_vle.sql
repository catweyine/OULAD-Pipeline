-- DATA QUALITY VALIDATION: oulad.oulad_silver.vle_silver
-- Test Type: POST-LOAD / AT-REST VALIDATION
-- Layer: SILVER (Clean/Conformed)

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
    'Silver table should contain at least 1 record' AS description
FROM oulad.oulad_silver.vle_silver;

-- CHECK 1.2: COMPLETENESS - Required Business Columns
-- Purpose: Required business columns should not be NULL after cleaning
SELECT
    'COMPLETENESS' AS check_category,
    'Required Business Columns' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN id_site IS NULL THEN 1 ELSE 0 END) AS null_id_site,
    SUM(CASE WHEN code_module IS NULL THEN 1 ELSE 0 END) AS null_code_module,
    SUM(CASE WHEN code_presentation IS NULL THEN 1 ELSE 0 END) AS null_code_presentation,
    SUM(CASE WHEN activity_type IS NULL THEN 1 ELSE 0 END) AS null_activity_type,
    SUM(CASE WHEN week_from IS NULL THEN 1 ELSE 0 END) AS null_week_from,
    SUM(CASE WHEN week_to IS NULL THEN 1 ELSE 0 END) AS null_week_to,
    CASE
        WHEN SUM(
            CASE
                WHEN id_site IS NULL
                  OR code_module IS NULL
                  OR code_presentation IS NULL
                  OR activity_type IS NULL
                  OR week_from IS NULL
                  OR week_to IS NULL
                THEN 1 ELSE 0
            END
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Required business columns should be populated in silver layer' AS description
FROM oulad.oulad_silver.vle_silver;

-- CHECK 1.3: UNIQUENESS - No Duplicate Business Keys
-- Purpose: Silver layer must contain unique VLE site records
WITH duplicate_check AS (
    SELECT
        id_site,
        COUNT(*) AS duplicate_count
    FROM oulad.oulad_silver.vle_silver
    GROUP BY id_site
    HAVING COUNT(*) > 1
)
SELECT
    'UNIQUENESS' AS check_category,
    'No Duplicate Business Keys' AS check_name,
    COUNT(*) AS duplicate_ids,
    COALESCE(SUM(duplicate_count), 0) AS total_duplicate_records,
    CASE
        WHEN COUNT(*) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'VLE site identifier should be unique in silver layer' AS description
FROM duplicate_check;

-- CHECK 1.4: VALIDITY - Week Range Logic
-- Purpose: Week start should not be greater than week end
SELECT
    'VALIDITY' AS check_category,
    'Week Range Logic' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN week_from > week_to THEN 1 ELSE 0 END) AS invalid_week_range_records,
    CASE
        WHEN SUM(CASE WHEN week_from > week_to THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Week from should be less than or equal to week to' AS description
FROM oulad.oulad_silver.vle_silver;

-- SECTION 2: BUSINESS RULE VALIDATION

-- CHECK 2.1: BUSINESS RULE - Standardized Activity Types
-- Purpose: Activity types should be cleaned and standardized
SELECT
    'BUSINESS_RULE' AS check_category,
    'Standardized Activity Types' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN activity_type != TRIM(activity_type) THEN 1 ELSE 0 END) AS unstandardized_activity_types,
    CASE
        WHEN SUM(CASE WHEN activity_type != TRIM(activity_type) THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Activity types should be trimmed and standardized in silver layer' AS description
FROM oulad.oulad_silver.vle_silver;

-- CHECK 2.2: BUSINESS RULE - Activity Type Coverage
-- Purpose: Monitor available activity categories after cleaning
SELECT
    'BUSINESS_RULE' AS check_category,
    'Activity Type Coverage' AS check_name,
    COUNT(DISTINCT activity_type) AS distinct_activity_types,
    'INFO' AS status,
    'Number of distinct activity types available for analysis' AS description
FROM oulad.oulad_silver.vle_silver;

-- SECTION 3: SUMMARY REPORT

-- CHECK 3.1: Overall Table Profile
-- Purpose: High-level overview of table quality
SELECT
    'SUMMARY' AS check_category,
    'Table Profile' AS check_name,
    COUNT(*) AS row_count,
    COUNT(*) - COUNT(DISTINCT id_site) AS duplicate_records,
    SUM(CASE WHEN id_site IS NULL THEN 1 ELSE 0 END) AS null_id_site,
    SUM(CASE WHEN code_module IS NULL THEN 1 ELSE 0 END) AS null_code_module,
    SUM(CASE WHEN code_presentation IS NULL THEN 1 ELSE 0 END) AS null_code_presentation,
    SUM(CASE WHEN activity_type IS NULL THEN 1 ELSE 0 END) AS null_activity_type,
    SUM(CASE WHEN week_from IS NULL THEN 1 ELSE 0 END) AS null_week_from,
    SUM(CASE WHEN week_to IS NULL THEN 1 ELSE 0 END) AS null_week_to,
    SUM(CASE WHEN week_from > week_to THEN 1 ELSE 0 END) AS invalid_week_range_records,
    MIN(ingestion_date) AS earliest_ingestion,
    MAX(ingestion_date) AS latest_ingestion,
    'INFO' AS status,
    'Silver layer overview statistics' AS description
FROM oulad.oulad_silver.vle_silver;