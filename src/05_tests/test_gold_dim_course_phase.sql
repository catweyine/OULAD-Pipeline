-- DATA QUALITY VALIDATION: oulad.oulad_gold.dim_course_phase
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
FROM oulad.oulad_gold.dim_course_phase;

-- CHECK 1.2: COMPLETENESS - Null Value Assessment
-- Purpose: Dimension key and descriptive attributes should be populated
SELECT
    'COMPLETENESS' AS check_category,
    'Null Value Assessment' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN phase_id IS NULL THEN 1 ELSE 0 END) AS null_phase_id,
    SUM(CASE WHEN phase_name IS NULL THEN 1 ELSE 0 END) AS null_phase_name,
    CASE
        WHEN SUM(
            CASE
                WHEN phase_id IS NULL
                  OR phase_name IS NULL
                THEN 1 ELSE 0
            END
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Dimension key and attributes should not be NULL' AS description
FROM oulad.oulad_gold.dim_course_phase;

-- CHECK 1.3: UNIQUENESS - Duplicate Dimension Keys
-- Purpose: Dimension key should be unique
SELECT
    'UNIQUENESS' AS check_category,
    'Duplicate Dimension Keys' AS check_name,
    COUNT(*) - COUNT(DISTINCT phase_id) AS duplicate_phase_id,
    CASE
        WHEN COUNT(*) = COUNT(DISTINCT phase_id)
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Phase ID should be unique within the dimension table' AS description
FROM oulad.oulad_gold.dim_course_phase;

-- SECTION 2: BUSINESS RULE VALIDATION

-- CHECK 2.1: BUSINESS RULE - Valid Phase Names
-- Purpose: Phase names should be populated for reporting and analysis
SELECT
    'BUSINESS_RULE' AS check_category,
    'Valid Phase Names' AS check_name,
    COUNT(*) AS total_records,
    SUM(
        CASE
            WHEN TRIM(phase_name) = ''
            THEN 1 ELSE 0
        END
    ) AS blank_phase_names,
    CASE
        WHEN SUM(
            CASE
                WHEN TRIM(phase_name) = ''
                THEN 1 ELSE 0
            END
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Phase names should not be blank' AS description
FROM oulad.oulad_gold.dim_course_phase;

-- SECTION 3: SUMMARY REPORT

-- CHECK 3.1: Overall Table Profile
-- Purpose: High-level overview of dimension quality
SELECT
    'SUMMARY' AS check_category,
    'Table Profile' AS check_name,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT phase_id) AS distinct_phase_id,
    COUNT(*) - COUNT(DISTINCT phase_id) AS duplicate_phase_id,
    SUM(CASE WHEN phase_id IS NULL THEN 1 ELSE 0 END) AS null_phase_id,
    SUM(CASE WHEN phase_name IS NULL THEN 1 ELSE 0 END) AS null_phase_name,
    'INFO' AS status,
    'Gold dimension overview statistics' AS description
FROM oulad.oulad_gold.dim_course_phase;