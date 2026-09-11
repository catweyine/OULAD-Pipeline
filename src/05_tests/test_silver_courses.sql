-- DATA QUALITY VALIDATION: oulad.oulad_silver.courses_silver
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
FROM oulad.oulad_silver.courses_silver;

-- CHECK 1.2: COMPLETENESS - Required Columns
-- Purpose: Required business columns should not be NULL after cleaning
SELECT
    'COMPLETENESS' AS check_category,
    'Required Columns' AS check_name,
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
        ELSE 'FAIL'
    END AS status,
    'Required columns should be populated in silver layer' AS description
FROM oulad.oulad_silver.courses_silver;

-- CHECK 1.3: UNIQUENESS - No Duplicate Business Keys
-- Purpose: Silver layer must contain unique course-presentation combinations
WITH duplicate_check AS (
    SELECT
        code_module,
        code_presentation,
        COUNT(*) AS duplicate_count
    FROM oulad.oulad_silver.courses_silver
    GROUP BY code_module, code_presentation
    HAVING COUNT(*) > 1
)
SELECT
    'UNIQUENESS' AS check_category,
    'No Duplicate Business Keys' AS check_name,
    COUNT(*) AS duplicate_combinations,
    COALESCE(SUM(duplicate_count), 0) AS total_duplicate_records,
    CASE
        WHEN COUNT(*) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Course and presentation combination should be unique in silver layer' AS description
FROM duplicate_check;

-- CHECK 1.4: VALIDITY - Presentation Length Range
-- Purpose: Presentation length should be greater than zero
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
FROM oulad.oulad_silver.courses_silver;

-- SECTION 2: BUSINESS RULE VALIDATION

-- CHECK 2.1: BUSINESS RULE - Standardized Course Codes
-- Purpose: Course and presentation codes should be cleaned and standardized
SELECT
    'BUSINESS_RULE' AS check_category,
    'Standardized Course Codes' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN code_module != UPPER(TRIM(code_module)) THEN 1 ELSE 0 END) AS invalid_module_codes,
    SUM(CASE WHEN code_presentation != UPPER(TRIM(code_presentation)) THEN 1 ELSE 0 END) AS invalid_presentation_codes,
    CASE
        WHEN SUM(
            CASE
                WHEN code_module != UPPER(TRIM(code_module))
                  OR code_presentation != UPPER(TRIM(code_presentation))
                THEN 1 ELSE 0
            END
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Course codes should be uppercase and trimmed in silver layer' AS description
FROM oulad.oulad_silver.courses_silver;

-- SECTION 3: SUMMARY REPORT

-- CHECK 3.1: Overall Table Profile
-- Purpose: High-level overview of table quality
SELECT
    'SUMMARY' AS check_category,
    'Table Profile' AS check_name,
    COUNT(*) AS row_count,
    COUNT(*) - COUNT(DISTINCT CONCAT(code_module, '_', code_presentation)) AS duplicate_records,
    SUM(CASE WHEN code_module IS NULL THEN 1 ELSE 0 END) AS null_code_module,
    SUM(CASE WHEN code_presentation IS NULL THEN 1 ELSE 0 END) AS null_code_presentation,
    SUM(CASE WHEN module_presentation_length IS NULL THEN 1 ELSE 0 END) AS null_module_presentation_length,
    SUM(CASE WHEN module_presentation_length <= 0 THEN 1 ELSE 0 END) AS invalid_presentation_length_records,
    'INFO' AS status,
    'Silver layer overview statistics' AS description
FROM oulad.oulad_silver.courses_silver;