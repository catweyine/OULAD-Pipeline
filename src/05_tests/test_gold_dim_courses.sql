-- DATA QUALITY VALIDATION: oulad.oulad_gold.dim_course
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
FROM oulad.oulad_gold.dim_course;

-- CHECK 1.2: COMPLETENESS - Null Value Assessment
-- Purpose: Dimension key and attributes should be populated
SELECT
    'COMPLETENESS' AS check_category,
    'Null Value Assessment' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN course_id IS NULL THEN 1 ELSE 0 END) AS null_course_id,
    SUM(CASE WHEN code_module IS NULL THEN 1 ELSE 0 END) AS null_code_module,
    SUM(CASE WHEN code_presentation IS NULL THEN 1 ELSE 0 END) AS null_code_presentation,
    SUM(CASE WHEN module_presentation_length IS NULL THEN 1 ELSE 0 END) AS null_module_presentation_length,
    CASE
        WHEN SUM(
            CASE
                WHEN course_id IS NULL
                  OR code_module IS NULL
                  OR code_presentation IS NULL
                  OR module_presentation_length IS NULL
                THEN 1 ELSE 0
            END
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Dimension key and attributes should not be NULL' AS description
FROM oulad.oulad_gold.dim_course;

-- CHECK 1.3: UNIQUENESS - Duplicate Dimension Keys
-- Purpose: Course ID should be unique
SELECT
    'UNIQUENESS' AS check_category,
    'Duplicate Dimension Keys' AS check_name,
    COUNT(*) - COUNT(DISTINCT course_id) AS duplicate_course_id,
    CASE
        WHEN COUNT(*) = COUNT(DISTINCT course_id)
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Course ID should be unique within the dimension table' AS description
FROM oulad.oulad_gold.dim_course;

-- SECTION 2: CONSISTENCY CHECKS

-- CHECK 2.1: CONSISTENCY - Source to Target Record Count
-- Purpose: Verify all unique courses from silver are loaded into gold
SELECT
    'CONSISTENCY' AS check_category,
    'Source to Target Record Count' AS check_name,
    COUNT(DISTINCT CONCAT(code_module, '_', code_presentation)) AS source_count,
    (SELECT COUNT(*) FROM oulad.oulad_gold.dim_course) AS target_count,
    CASE
        WHEN COUNT(DISTINCT CONCAT(code_module, '_', code_presentation))
             = (SELECT COUNT(*) FROM oulad.oulad_gold.dim_course)
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Gold dimension should 