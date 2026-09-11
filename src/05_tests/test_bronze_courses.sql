-- DATA QUALITY VALIDATION: oulad.oulad_bronze.courses_bronze
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
FROM oulad.oulad_bronze.courses_bronze;

-- CHECK 1.2: COMPLETENESS - Null Value Assessment
-- Purpose: Identify missing values in critical columns from source data
SELECT
    'COMPLETENESS' AS check_category,
    'Null Value Assessment' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN code_module IS NULL THEN 1 ELSE 0 END) AS null_code_module,
    SUM(CASE WHEN code_presentation IS NULL THEN 1 ELSE 0 END) AS null_code_presentation,
    SUM(CASE WHEN module_presentation_length IS NULL THEN 1 ELSE 0 END) AS null_module_presentation_length,
    CASE
        WHEN SUM(
            CASE
                WHEN code_module IS NULL
                  OR code_presentation IS NULL
                  OR module_presentation_length IS NULL
                THEN 1 ELSE 0
            END
        ) = 0
        THEN 'PASS'
        ELSE 'WARNING'
    END AS status,
    'Critical columns should be reviewed for missing values' AS description
FROM oulad.oulad_bronze.courses_bronze;

-- CHECK 1.3: UNIQUENESS - Duplicate Business Keys
-- Purpose: Detect duplicate course-presentation combinations in raw data
WITH duplicate_check AS (
    SELECT
        code_module,
        code_presentation,
        COUNT(*) AS duplicate_count
    FROM oulad.oulad_bronze.courses_bronze
    GROUP BY code_module, code_presentation
    HAVING COUNT(*) > 1
)
SELECT
    'UNIQUENESS' AS check_category,
    'Duplicate Business Keys' AS check_name,
    COUNT(*) AS duplicate_combinations,
    COALESCE(SUM(duplicate_count), 0) AS total_duplicate_records,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'WARNING'
    END AS status,
    'Duplicates may exist in bronze and should be handled in silver' AS description
FROM duplicate_check;

-- CHECK 1.4: VALIDITY - Presentation Length Range
-- Purpose: Module presentation length should be greater than zero
SELECT
    'VALIDITY' AS check_category,
    'Presentation Length Range' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN module_presentation_length <= 0 THEN 1 ELSE 0 END) AS invalid_presentation_length_records,
    MIN(module_presentation_length) AS min_length,
    MAX(module_presentation_length) AS max_length,
    CASE
        WHEN SUM(CASE WHEN module_presentation_length <= 0 THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Module presentation length should be greater than zero' AS description
FROM oulad.oulad_bronze.courses_bronze;

-- SECTION 2: REFERENCE DATA PROFILING

-- CHECK 2.1: PROFILE - Distinct Module Codes
-- Purpose: Review available course modules from source system
SELECT DISTINCT
    code_module
FROM oulad.oulad_bronze.courses_bronze
ORDER BY code_module;

-- CHECK 2.2: PROFILE - Distinct Presentation Codes
-- Purpose: Review available presentation periods from source system
SELECT DISTINCT
    code_presentation
FROM oulad.oulad_bronze.courses_bronze
ORDER BY code_presentation;

-- SECTION 3: SUMMARY REPORT

-- CHECK 3.1: Overall Table Quality Summary
-- Purpose: High-level overview of data quality issues detected in bronze layer
SELECT
    'SUMMARY' AS check_category,
    'Table Profile' AS check_name,
    COUNT(*) AS row_count,
    COUNT(*) - COUNT(DISTINCT CONCAT(code_module, '_', code_presentation)) AS duplicate_records,
    SUM(CASE WHEN code_module IS NULL THEN 1 ELSE 0 END) AS null_code_module,
    SUM(CASE WHEN code_presentation IS NULL THEN 1 ELSE 0 END) AS null_code_presentation,
    SUM(CASE WHEN module_presentation_length IS NULL THEN 1 ELSE 0 END) AS null_module_presentation_length,
    SUM(CASE WHEN module_presentation_length <= 0 THEN 1 ELSE 0 END) AS invalid_presentation_length_records,
    MIN(ingestion_date) AS earliest_ingestion,
    MAX(ingestion_date) AS latest_ingestion,
    'INFO' AS status,
    'Bronze layer overview statistics' AS description
FROM oulad.oulad_bronze.courses_bronze;