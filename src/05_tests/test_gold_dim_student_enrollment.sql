
-- DATA QUALITY VALIDATION: oulad.oulad_gold.dim_student_enrollment
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
    'Gold enrollment dimension should contain at least 1 record' AS description
FROM oulad.oulad_gold.dim_student_enrollment;

-- CHECK 1.2: UNIQUENESS - NO Duplicate student_enrollment_id
WITH duplicate_check AS (
    SELECT 
        student_enrollment_id,
        COUNT(*) AS duplicate_count
    FROM oulad.oulad_gold.dim_student_enrollment
    GROUP BY student_enrollment_id
    HAVING COUNT(*) > 1
)
SELECT 
    'UNIQUENESS' AS check_category,
    'No Duplicate student_enrollment_id' AS check_name,
    COUNT(*) AS duplicate_enrollment_ids,
    COALESCE(SUM(duplicate_count), 0) AS total_duplicate_records,
    CASE 
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'student_enrollment_id must be unique in dimension table' AS description
FROM duplicate_check;

-- CHECK 1.3: COMPLETENESS - Required Enrollment Attributes
SELECT 
    'COMPLETENESS' AS check_category,
    'Required Enrollment Attributes' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN student_enrollment_id IS NULL THEN 1 ELSE 0 END) AS null_enrollment_id,
    SUM(CASE WHEN student_id IS NULL THEN 1 ELSE 0 END) AS null_student_id,
    SUM(CASE WHEN course_id IS NULL THEN 1 ELSE 0 END) AS null_course_id,
    SUM(CASE WHEN num_of_prev_attempts IS NULL THEN 1 ELSE 0 END) AS null_prev_attempts,
    SUM(CASE WHEN studied_credits IS NULL THEN 1 ELSE 0 END) AS null_credits,
    SUM(CASE WHEN final_result IS NULL THEN 1 ELSE 0 END) AS null_final_result,
    CASE 
        WHEN SUM(CASE WHEN student_enrollment_id IS NULL OR student_id IS NULL 
                      OR course_id IS NULL OR num_of_prev_attempts IS NULL 
                      OR studied_credits IS NULL OR final_result IS NULL THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'All enrollment attributes should be populated (no NULLs)' AS description
FROM oulad.oulad_gold.dim_student_enrollment;

-- CHECK 1.4: VALIDITY - Data Value Ranges
SELECT 
    'VALIDITY' AS check_category,
    'Value Range Validation' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN num_of_prev_attempts < 0 THEN 1 ELSE 0 END) AS negative_attempts,
    SUM(CASE WHEN studied_credits <= 0 THEN 1 ELSE 0 END) AS zero_or_negative_credits,
    SUM(CASE WHEN studied_credits > 300 THEN 1 ELSE 0 END) AS excessive_credits,
    MIN(num_of_prev_attempts) AS min_attempts,
    MAX(num_of_prev_attempts) AS max_attempts,
    MIN(studied_credits) AS min_credits,
    MAX(studied_credits) AS max_credits,
    CASE 
        WHEN SUM(CASE WHEN num_of_prev_attempts < 0 OR studied_credits <= 0 OR studied_credits > 300 THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'num_of_prev_attempts >= 0, studied_credits > 0 and <= 300' AS description
FROM oulad.oulad_gold.dim_student_enrollment;


-- SECTION 2: BUSINESS RULE VALIDATION


-- CHECK 2.1: BUSINESS RULE - Final Result Domain
SELECT 
    'BUSINESS_RULE' AS check_category,
    'Final Result Domain' AS check_name,
    COUNT(*) AS total_records,
    COUNT(DISTINCT final_result) AS distinct_results,
    CONCAT_WS(', ', COLLECT_SET(final_result)) AS unique_final_results,
    SUM(CASE WHEN UPPER(TRIM(final_result)) NOT IN ('PASS', 'FAIL', 'DISTINCTION', 'WITHDRAWN') THEN 1 ELSE 0 END) AS invalid_results,
    CASE 
        WHEN SUM(CASE WHEN UPPER(TRIM(final_result)) NOT IN ('PASS', 'FAIL', 'DISTINCTION', 'WITHDRAWN') THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'final_result should be: Pass, Fail, Distinction, or Withdrawn' AS description
FROM oulad.oulad_gold.dim_student_enrollment;

-- CHECK 2.2: BUSINESS RULE - Enrollment Outcome Distribution
SELECT 
    'BUSINESS_RULE' AS check_category,
    'Enrollment Outcome Distribution' AS check_name,
    COUNT(*) AS total_enrollments,
    SUM(CASE WHEN UPPER(TRIM(final_result)) = 'PASS' THEN 1 ELSE 0 END) AS pass_count,
    SUM(CASE WHEN UPPER(TRIM(final_result)) = 'FAIL' THEN 1 ELSE 0 END) AS fail_count,
    SUM(CASE WHEN UPPER(TRIM(final_result)) = 'DISTINCTION' THEN 1 ELSE 0 END) AS distinction_count,
    SUM(CASE WHEN UPPER(TRIM(final_result)) = 'WITHDRAWN' THEN 1 ELSE 0 END) AS withdrawn_count,
    ROUND(SUM(CASE WHEN UPPER(TRIM(final_result)) = 'WITHDRAWN' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS withdrawal_rate_pct,
    'INFO' AS status,
    'Distribution of enrollment outcomes (informational)' AS description
FROM oulad.oulad_gold.dim_student_enrollment;

-- CHECK 2.3: BUSINESS RULE - Repeat Student Analysis
-- Purpose: Track students with multiple previous attempts
SELECT 
    'BUSINESS_RULE' AS check_category,
    'Previous Attempts Distribution' AS check_name,
    COUNT(*) AS total_enrollments,
    SUM(CASE WHEN num_of_prev_attempts = 0 THEN 1 ELSE 0 END) AS first_attempt,
    SUM(CASE WHEN num_of_prev_attempts = 1 THEN 1 ELSE 0 END) AS second_attempt,
    SUM(CASE WHEN num_of_prev_attempts >= 2 THEN 1 ELSE 0 END) AS three_or_more_attempts,
    ROUND(AVG(num_of_prev_attempts), 2) AS avg_prev_attempts,
    MAX(num_of_prev_attempts) AS max_prev_attempts,
    'INFO' AS status,
    'Distribution of student retake patterns (informational)' AS description
FROM oulad.oulad_gold.dim_student_enrollment;

-- CHECK 2.4: BUSINESS RULE - Credit Load Analysis
SELECT 
    'BUSINESS_RULE' AS check_category,
    'Credit Load Distribution' AS check_name,
    COUNT(*) AS total_enrollments,
    SUM(CASE WHEN studied_credits < 60 THEN 1 ELSE 0 END) AS light_load,
    SUM(CASE WHEN studied_credits BETWEEN 60 AND 120 THEN 1 ELSE 0 END) AS medium_load,
    SUM(CASE WHEN studied_credits > 120 THEN 1 ELSE 0 END) AS heavy_load,
    ROUND(AVG(studied_credits), 2) AS avg_credits,
    'INFO' AS status,
    'Distribution of credit loads (< 60, 60-120, > 120)' AS description
FROM oulad.oulad_gold.dim_student_enrollment;


-- SECTION 3: CONSISTENCY & REFERENTIAL INTEGRITY CHECKS


-- CHECK 3.1: REFERENTIAL INTEGRITY - All Enrollments Have Valid Students
-- Purpose: Every enrollment should reference an existing student in dim_student
WITH orphaned_enrollments AS (
    SELECT 
        e.student_enrollment_id,
        e.student_id
    FROM oulad.oulad_gold.dim_student_enrollment e
    LEFT JOIN oulad.oulad_gold.dim_student s
        ON e.student_id = s.student_id
    WHERE s.student_id IS NULL
)
SELECT 
    'REFERENTIAL_INTEGRITY' AS check_category,
    'Valid Student Foreign Keys' AS check_name,
    COUNT(*) AS orphaned_enrollments,
    CASE 
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'All enrollments must reference existing students in dim_student' AS description
FROM orphaned_enrollments;

-- CHECK 3.2: CONSISTENCY - Enrollment Count vs Silver Layer
WITH layer_comparison AS (
    SELECT 
        (SELECT COUNT(*) FROM oulad.oulad_silver.student_info_silver) AS silver_enrollments,
        (SELECT COUNT(*) FROM oulad.oulad_gold.dim_student_enrollment) AS gold_enrollments
)
SELECT 
    'CONSISTENCY' AS check_category,
    'Enrollment Count - Silver vs Gold' AS check_name,
    silver_enrollments,
    gold_enrollments,
    silver_enrollments - gold_enrollments AS missing_in_gold,
    ROUND((gold_enrollments * 100.0 / silver_enrollments), 2) AS retention_rate_pct,
    CASE 
        WHEN gold_enrollments >= silver_enrollments * 0.95 THEN 'PASS'
        WHEN gold_enrollments >= silver_enrollments * 0.90 THEN 'WARNING'
        ELSE 'FAIL'
    END AS status,
    'Gold enrollments should match at least 95% of silver enrollments' AS description
FROM layer_comparison;

-- CHECK 3.3: CONSISTENCY - Student Enrollments per Student
-- Purpose: Analyze enrollment patterns
WITH enrollments_per_student AS (
    SELECT 
        student_id,
        COUNT(*) AS enrollment_count
    FROM oulad.oulad_gold.dim_student_enrollment
    GROUP BY student_id
)
SELECT 
    'CONSISTENCY' AS check_category,
    'Enrollments per Student' AS check_name,
    COUNT(DISTINCT student_id) AS unique_students,
    ROUND(AVG(enrollment_count), 2) AS avg_enrollments_per_student,
    MIN(enrollment_count) AS min_enrollments,
    MAX(enrollment_count) AS max_enrollments,
    SUM(CASE WHEN enrollment_count = 1 THEN 1 ELSE 0 END) AS students_with_one_enrollment,
    SUM(CASE WHEN enrollment_count > 1 THEN 1 ELSE 0 END) AS students_with_multiple_enrollments,
    'INFO' AS status,
    'Distribution of enrollments per student (informational)' AS description
FROM enrollments_per_student;


-- SECTION 4: SUMMARY REPORT


-- CHECK 4.1: Overall Enrollment Dimension Profile
SELECT 
    'SUMMARY' AS check_category,
    'Dimension Profile' AS check_name,
    COUNT(*) AS total_enrollments,
    COUNT(DISTINCT student_enrollment_id) AS unique_enrollment_ids,
    COUNT(DISTINCT student_id) AS unique_students,
    COUNT(DISTINCT course_id) AS unique_courses,
    'INFO' AS status,
    'Gold enrollment dimension overview statistics' AS description
FROM oulad.oulad_gold.dim_student_enrollment;

-- CHECK 4.2: Attribute Completeness Summary
SELECT 
    'SUMMARY' AS check_category,
    'Attribute Completeness %' AS check_name,
    ROUND(COUNT(student_enrollment_id) * 100.0 / COUNT(*), 2) AS enrollment_id_completeness,
    ROUND(COUNT(student_id) * 100.0 / COUNT(*), 2) AS student_id_completeness,
    ROUND(COUNT(course_id) * 100.0 / COUNT(*), 2) AS course_id_completeness,
    ROUND(COUNT(num_of_prev_attempts) * 100.0 / COUNT(*), 2) AS prev_attempts_completeness,
    ROUND(COUNT(studied_credits) * 100.0 / COUNT(*), 2) AS credits_completeness,
    ROUND(COUNT(final_result) * 100.0 / COUNT(*), 2) AS final_result_completeness,
    'INFO' AS status,
    'Percentage of non-NULL values for each attribute' AS description
FROM oulad.oulad_gold.dim_student_enrollment;