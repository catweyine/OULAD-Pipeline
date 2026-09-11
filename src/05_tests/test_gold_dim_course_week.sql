-- DATA QUALITY VALIDATION: oulad.oulad_gold.dim_course_week
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
FROM oulad.oulad_gold.dim_course_week;

-- CHECK 1.2: COMPLETENESS - Null Value Assessment
-- Purpose: Dimension keys and attributes should be populated
SELECT
    'COMPLETENESS' AS check_category,
    'Null Value Assessment' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN course_id IS NULL THEN 1 ELSE 0 END) AS null_course_id,
    SUM(CASE WHEN week_id IS NULL THEN 1 ELSE 0 END) AS null_week_id,
    SUM(CASE WHEN week_number IS NULL THEN 1 ELSE 0 END) AS null_week_number,
    SUM(CASE WHEN phase_id IS NULL THEN 1 ELSE 0 END) AS null_phase_id,
    CASE
        WHEN SUM(
            CASE
                WHEN course_id IS NULL
                  OR week_id IS NULL
                  OR week_number IS NULL
                  OR phase_id IS NULL
                THEN 1 ELSE 0
            END
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Dimension keys and attributes should not be NULL' AS description
FROM oulad.oulad_gold.dim_course_week;

-- CHECK 1.3: UNIQUENESS - Duplicate Course Week Keys
-- Purpose: Each course-week combination should be unique
SELECT
    'UNIQUENESS' AS check_category,
    'Duplicate Course Week Keys' AS check_name,
    COUNT(*) - COUNT(DISTINCT CONCAT(course_id, '_', week_id)) AS duplicate_course_week,
    CASE
        WHEN COUNT(*) = COUNT(DISTINCT CONCAT(course_id, '_', week_id))
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Course ID and Week ID combination should be unique' AS description
FROM oulad.oulad_gold.dim_course_week;

-- CHECK 1.4: VALIDITY - Week Number Range
-- Purpose: Week numbers should be positive integers
SELECT
    'VALIDITY' AS check_category,
    'Week Number Range' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN week_number <= 0 THEN 1 ELSE 0 END) AS invalid_week_number,
    MIN(week_number) AS min_week_number,
    MAX(week_number) AS max_week_number,
    CASE
        WHEN SUM(CASE WHEN week_number <= 0 THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Week number should be greater than zero' AS description
FROM oulad.oulad_gold.dim_course_week;

-- SECTION 2: CONSISTENCY CHECKS

-- CHECK 2.1: CONSISTENCY - Phase Dimension Referential Integrity
-- Purpose: Every phase_id should exist in dim_course_phase
SELECT
    'CONSISTENCY' AS check_category,
    'Phase Referential Integrity' AS check_name,
    COUNT(*) AS orphan_phase_records,
    CASE
        WHEN COUNT(*) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Every phase_id should reference a valid record in dim_course_phase' AS description
FROM oulad.oulad_gold.dim_course_week cw
LEFT JOIN oulad.oulad_gold.dim_course_phase cp
    ON cw.phase_id = cp.phase_id
WHERE cp.phase_id IS NULL;

-- CHECK 2.2: CONSISTENCY - Course Dimension Referential Integrity
-- Purpose: Every course_id should exist in dim_course
SELECT
    'CONSISTENCY' AS check_category,
    'Course Referential Integrity' AS check_name,
    COUNT(*) AS orphan_course_records,
    CASE
        WHEN COUNT(*) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Every course_id should reference a valid record in dim_course' AS description
FROM oulad.oulad_gold.dim_course_week cw
LEFT JOIN oulad.oulad_gold.dim_course c
    ON cw.course_id = c.course_id
WHERE c.course_id IS NULL;

-- SECTION 3: SUMMARY REPORT

-- CHECK 3.1: Overall Table Profile
-- Purpose: High-level overview of dimension quality
SELECT
    'SUMMARY' AS check_category,
    'Table Profile' AS check_name,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT CONCAT(course_id, '_', week_id)) AS distinct_course_week,
    COUNT(*) - COUNT(DISTINCT CONCAT(course_id, '_', week_id)) AS duplicate_course_week,
    SUM(CASE WHEN course_id IS NULL THEN 1 ELSE 0 END) AS null_course_id,
    SUM(CASE WHEN week_id IS NULL THEN 1 ELSE 0 END) AS null_week_id,
    SUM(CASE WHEN week_number IS NULL THEN 1 ELSE 0 END) AS null_week_number,
    SUM(CASE WHEN phase_id IS NULL THEN 1 ELSE 0 END) AS null_phase_id,
    SUM(CASE WHEN week_number <= 0 THEN 1 ELSE 0 END) AS invalid_week_number,
    'INFO' AS status,
    'Gold dimension overview statistics' AS description
FROM oulad.oulad_gold.dim_course_week;