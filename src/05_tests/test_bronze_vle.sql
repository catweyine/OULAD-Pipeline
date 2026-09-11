-- DATA QUALITY VALIDATION: oulad.oulad_bronze.vle_bronze
-- Test Type: POST-LOAD / AT-REST VALIDATION
-- Layer: BRONZE (Raw Ingested Data)

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
    'Bronze table should contain at least 1 record' AS description
FROM oulad.oulad_bronze.vle_bronze;

-- CHECK 1.2: COMPLETENESS - Null Value Assessment
-- Purpose: Identify missing values in critical columns from source data
SELECT
    'COMPLETENESS' AS check_category,
    'Null Value Assessment' AS check_name,
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
        ELSE 'WARNING'
    END AS status,
    'Critical columns should be reviewed for missing values' AS description
FROM oulad.oulad_bronze.vle_bronze;

-- CHECK 1.3: UNIQUENESS - Duplicate Site IDs
-- Purpose: Detect duplicate VLE site identifiers in raw data
WITH duplicate_check AS (
    SELECT
        id_site,
        COUNT(*) AS duplicate_count
    FROM oulad.oulad_bronze.vle_bronze
    GROUP BY id_site
    HAVING COUNT(*) > 1
)
SELECT
    'UNIQUENESS' AS check_category,
    'Duplicate Site IDs' AS check_name,
    COUNT(*) AS duplicate_ids,
    COALESCE(SUM(duplicate_count), 0) AS total_duplicate_records,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'WARNING'
    END AS status,
    'Duplicates may exist in bronze and should be handled in silver' AS description
FROM duplicate_check;

-- CHECK 1.4: VALIDITY - Week Value Format
-- Purpose: Week values should be convertible to integers
SELECT
    'VALIDITY' AS check_category,
    'Week Value Format' AS check_name,
    COUNT(*) AS total_records,
    SUM(
        CASE
            WHEN TRY_CAST(week_from AS INT) IS NULL
              OR TRY_CAST(week_to AS INT) IS NULL
            THEN 1 ELSE 0
        END
    ) AS malformed_week_records,
    CASE
        WHEN SUM(
            CASE
                WHEN TRY_CAST(week_from AS INT) IS NULL
                  OR TRY_CAST(week_to AS INT) IS NULL
                THEN 1 ELSE 0
            END
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Week values should contain valid integers' AS description
FROM oulad.oulad_bronze.vle_bronze;

-- CHECK 1.5: VALIDITY - Week Range Logic
-- Purpose: Start week should not be greater than end week
SELECT
    'VALIDITY' AS check_category,
    'Week Range Logic' AS check_name,
    COUNT(*) AS total_records,
    SUM(
        CASE
            WHEN TRY_CAST(week_from AS INT) > TRY_CAST(week_to AS INT)
            THEN 1 ELSE 0
        END
    ) AS invalid_week_range_records,
    CASE
        WHEN SUM(
            CASE
                WHEN TRY_CAST(week_from AS INT) > TRY_CAST(week_to AS INT)
                THEN 1 ELSE 0
            END
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Week from should be less than or equal to week to' AS description
FROM oulad.oulad_bronze.vle_bronze;

-- CHECK 1.6: VALIDITY - Non-Negative Week Values
-- Purpose: Week values should be zero or positive
SELECT
    'VALIDITY' AS check_category,
    'Non-Negative Week Values' AS check_name,
    COUNT(*) AS total_records,
    SUM(
        CASE
            WHEN TRY_CAST(week_from AS INT) < 0
              OR TRY_CAST(week_to AS INT) < 0
            THEN 1 ELSE 0
        END
    ) AS negative_week_records,
    CASE
        WHEN SUM(
            CASE
                WHEN TRY_CAST(week_from AS INT) < 0
                  OR TRY_CAST(week_to AS INT) < 0
                THEN 1 ELSE 0
            END
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Week values should be greater than or equal to zero' AS description
FROM oulad.oulad_bronze.vle_bronze;

-- SECTION 2: REFERENCE DATA PROFILING

-- CHECK 2.1: PROFILE - Distinct Module Codes
-- Purpose: Review available course modules from source system
SELECT DISTINCT
    code_module
FROM oulad.oulad_bronze.vle_bronze
ORDER BY code_module;

-- CHECK 2.2: PROFILE - Distinct Presentation Codes
-- Purpose: Review available presentation periods from source system
SELECT DISTINCT
    code_presentation
FROM oulad.oulad_bronze.vle_bronze
ORDER BY code_presentation;

-- CHECK 2.3: PROFILE - Distinct Activity Types
-- Purpose: Review available VLE activity categories from source system
SELECT DISTINCT
    activity_type
FROM oulad.oulad_bronze.vle_bronze
ORDER BY activity_type;

-- CHECK 2.4: PROFILE - Ingestion Dates
-- Purpose: Review ingestion batches loaded into bronze layer
SELECT DISTINCT
    ingestion_date
FROM oulad.oulad_bronze.vle_bronze
ORDER BY ingestion_date;

-- SECTION 3: SUMMARY REPORT

-- CHECK 3.1: Overall Table Quality Summary
-- Purpose: High-level overview of data quality issues detected in bronze layer
SELECT
    'SUMMARY' AS check_category,
    'Table Profile' AS check_name,
    COUNT(*) AS row_count,
    COUNT(*) - COUNT(DISTINCT id_site) AS duplicate_records,
    SUM(CASE WHEN id_site IS NULL THEN 1 ELSE 0 END) AS null_id_site,
    SUM(CASE WHEN code_module IS NULL THEN 1 ELSE 0 END) AS null_code_module,
    SUM(CASE WHEN code_presentation IS NULL THEN 1 ELSE 0 END) AS null_code_presentation,
    SUM(CASE WHEN activity_type IS NULL THEN 1 ELSE 0 END) AS null_activity_type,
    SUM(
        CASE
            WHEN TRY_CAST(week_from AS INT) IS NULL
              OR TRY_CAST(week_to AS INT) IS NULL
            THEN 1 ELSE 0
        END
    ) AS malformed_week_records,
    SUM(
        CASE
            WHEN TRY_CAST(week_from AS INT) > TRY_CAST(week_to AS INT)
            THEN 1 ELSE 0
        END
    ) AS invalid_week_range_records,
    SUM(
        CASE
            WHEN TRY_CAST(week_from AS INT) < 0
              OR TRY_CAST(week_to AS INT) < 0
            THEN 1 ELSE 0
        END
    ) AS negative_week_records,
    MIN(ingestion_date) AS earliest_ingestion,
    MAX(ingestion_date) AS latest_ingestion,
    'INFO' AS status,
    'Bronze layer overview statistics' AS description
FROM oulad.oulad_bronze.vle_bronze;
 