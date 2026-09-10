
-- DATA QUALITY VALIDATION: oulad.oulad_silver.student_registration_silver
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
FROM oulad.oulad_silver.student_registration_silver;

-- CHECK 1.2: COMPLETENESS - NO NULL Primary Key Components
SELECT 
    'COMPLETENESS' AS check_category,
    'Primary Key Completeness' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN code_module IS NULL THEN 1 ELSE 0 END) AS null_code_module,
    SUM(CASE WHEN code_presentation IS NULL THEN 1 ELSE 0 END) AS null_code_presentation,
    SUM(CASE WHEN id_student IS NULL THEN 1 ELSE 0 END) AS null_id_student,
    CASE 
        WHEN SUM(CASE WHEN code_module IS NULL OR code_presentation IS NULL OR id_student IS NULL THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Primary key fields must not be NULL in silver layer' AS description
FROM oulad.oulad_silver.student_registration_silver;

-- CHECK 1.3: COMPLETENESS - Registration Date Required
SELECT 
    'COMPLETENESS' AS check_category,
    'Registration Date Required' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN date_registration IS NULL THEN 1 ELSE 0 END) AS null_registration_dates,
    CASE 
        WHEN SUM(CASE WHEN date_registration IS NULL THEN 1 ELSE 0 END) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'date_registration must not be NULL in silver layer' AS description
FROM oulad.oulad_silver.student_registration_silver;

-- CHECK 1.4: UNIQUENESS - NO Duplicates (PRIMARY KEY)
WITH duplicate_check AS (
    SELECT 
        code_module,
        code_presentation,
        id_student,
        COUNT(*) AS duplicate_count
    FROM oulad.oulad_silver.student_registration_silver
    GROUP BY code_module, code_presentation, id_student
    HAVING COUNT(*) > 1
)
SELECT 
    'UNIQUENESS' AS check_category,
    'No Duplicate Primary Keys' AS check_name,
    COUNT(*) AS duplicate_combinations,
    COALESCE(SUM(duplicate_count), 0) AS total_duplicate_records,
    CASE 
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Primary key must be unique in silver layer (no duplicates allowed)' AS description
FROM duplicate_check;

-- CHECK 1.5: VALIDITY - Cleaned & Standardized Data
SELECT 
    'VALIDITY' AS check_category,
    'Data Standardization' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN code_module != UPPER(TRIM(code_module)) THEN 1 ELSE 0 END) AS unstandardized_module,
    SUM(CASE WHEN code_presentation != UPPER(TRIM(code_presentation)) THEN 1 ELSE 0 END) AS unstandardized_presentation,
    CASE 
        WHEN SUM(CASE WHEN code_module != UPPER(TRIM(code_module)) 
                      OR code_presentation != UPPER(TRIM(code_presentation)) THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Code fields should be uppercase and trimmed' AS description
FROM oulad.oulad_silver.student_registration_silver;


-- SECTION 2: BUSINESS RULE VALIDATION


-- CHECK 2.1: BUSINESS RULE - Registration Date Validity
SELECT 
    'BUSINESS_RULE' AS check_category,
    'Valid Registration Date' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN DATE_FROM_UNIX_DATE(date_registration) > CURRENT_DATE() THEN 1 ELSE 0 END) AS future_registration_dates,
    MIN(DATE_FROM_UNIX_DATE(date_registration)) AS earliest_registration,
    MAX(DATE_FROM_UNIX_DATE(date_registration)) AS latest_registration,
    CASE 
        WHEN SUM(CASE WHEN DATE_FROM_UNIX_DATE(date_registration) > CURRENT_DATE() THEN 1 ELSE 0 END) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Registration date should not be in the future' AS description
FROM oulad.oulad_silver.student_registration_silver;

-- CHECK 2.2: BUSINESS RULE - Unregistration After Registration (Strict)
SELECT 
    'BUSINESS_RULE' AS check_category,
    'Unregistration After Registration' AS check_name,
    COUNT(*) AS total_records_with_unreg,
    SUM(CASE WHEN DATE_FROM_UNIX_DATE(date_unregistration) < DATE_FROM_UNIX_DATE(date_registration) THEN 1 ELSE 0 END) AS invalid_date_sequence,
    CASE 
        WHEN SUM(CASE WHEN DATE_FROM_UNIX_DATE(date_unregistration) < DATE_FROM_UNIX_DATE(date_registration) THEN 1 ELSE 0 END) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Unregistration date MUST be >= registration date (no exceptions in silver)' AS description
FROM oulad.oulad_silver.student_registration_silver
WHERE date_unregistration IS NOT NULL;

-- CHECK 2.3: BUSINESS RULE - Withdrawal Rate Tracking
WITH withdrawal_stats AS (
    SELECT 
        COUNT(*) AS total_registrations,
        SUM(CASE WHEN date_unregistration IS NOT NULL THEN 1 ELSE 0 END) AS total_withdrawals,
        ROUND(SUM(CASE WHEN date_unregistration IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS withdrawal_rate_pct
    FROM oulad.oulad_silver.student_registration_silver
)
SELECT 
    'BUSINESS_RULE' AS check_category,
    'Withdrawal Rate' AS check_name,
    total_registrations,
    total_withdrawals,
    withdrawal_rate_pct,
    CASE 
        WHEN withdrawal_rate_pct >= 0 AND withdrawal_rate_pct <= 100 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Withdrawal rate should be between 0% and 100% (informational metric)' AS description
FROM withdrawal_stats;


-- SECTION 3: CONSISTENCY CHECKS

-- CHECK 3.1: CONSISTENCY - Compare Bronze to Silver Record Counts
WITH record_counts AS (
    SELECT 
        (SELECT COUNT(*) FROM oulad.oulad_bronze.student_registration_bronze) AS bronze_count,
        (SELECT COUNT(*) FROM oulad.oulad_silver.student_registration_silver) AS silver_count
)
SELECT 
    'CONSISTENCY' AS check_category,
    'Bronze to Silver Record Count' AS check_name,
    bronze_count,
    silver_count,
    bronze_count - silver_count AS records_filtered,
    ROUND((silver_count * 100.0 / bronze_count), 2) AS retention_rate_pct,
    CASE 
        WHEN silver_count <= bronze_count AND silver_count > 0 THEN 'PASS'
        WHEN silver_count > bronze_count THEN 'FAIL'
        ELSE 'WARNING'
    END AS status,
    'Silver should have <= bronze records (due to dedup & filtering). Expect 80-100% retention.' AS description
FROM record_counts;

-- CHECK 3.2: REFERENTIAL INTEGRITY - Students Exist in Student Info
-- Purpose: Verify all registered students exist in student_info table
WITH missing_students AS (
    SELECT 
        sr.id_student,
        sr.code_module,
        sr.code_presentation
    FROM oulad.oulad_silver.student_registration_silver sr
    LEFT JOIN oulad.oulad_silver.student_info_silver si
        ON sr.code_module = si.code_module
        AND sr.code_presentation = si.code_presentation
        AND sr.id_student = si.id_student
    WHERE si.id_student IS NULL
)
SELECT 
    'CONSISTENCY' AS check_category,
    'Referential Integrity to Student Info' AS check_name,
    COUNT(*) AS orphaned_registrations,
    CASE 
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'WARNING'
    END AS status,
    'All registrations should have corresponding student_info records' AS description
FROM missing_students;


-- SECTION 4: SUMMARY REPORT


-- CHECK 4.1: Overall Table Profile
SELECT 
    'SUMMARY' AS check_category,
    'Table Profile' AS check_name,
    COUNT(*) AS total_records,
    COUNT(DISTINCT id_student) AS unique_students,
    COUNT(DISTINCT CONCAT(code_module, '-', code_presentation)) AS unique_course_presentations,
    SUM(CASE WHEN date_unregistration IS NOT NULL THEN 1 ELSE 0 END) AS students_who_withdrew,
    MIN(ingestion_date) AS earliest_ingestion,
    MAX(ingestion_date) AS latest_ingestion,
    'INFO' AS status,
    'Silver layer overview statistics' AS description
FROM oulad.oulad_silver.student_registration_silver;