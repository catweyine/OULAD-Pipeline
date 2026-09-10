
-- DATA QUALITY VALIDATION: oulad.oulad_bronze.student_registration_bronze
-- Test Type: POST-LOAD / AT-REST VALIDATION
-- Layer: BRONZE (Raw/Ingestion)


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
FROM oulad.oulad_bronze.student_registration_bronze;

-- CHECK 1.2: COMPLETENESS - Required Columns Populated
-- Purpose: Verify critical columns are not NULL
SELECT 
    'COMPLETENESS' AS check_category,
    'Required Columns' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN code_module IS NULL THEN 1 ELSE 0 END) AS null_code_module,
    SUM(CASE WHEN code_presentation IS NULL THEN 1 ELSE 0 END) AS null_code_presentation,
    SUM(CASE WHEN id_student IS NULL THEN 1 ELSE 0 END) AS null_id_student,
    SUM(CASE WHEN date_registration IS NULL THEN 1 ELSE 0 END) AS null_date_registration,
    SUM(CASE WHEN ingestion_timestamp IS NULL THEN 1 ELSE 0 END) AS null_ingestion_timestamp,
    CASE 
        WHEN SUM(CASE WHEN code_module IS NULL OR code_presentation IS NULL 
                      OR id_student IS NULL OR date_registration IS NULL 
                      OR ingestion_timestamp IS NULL THEN 1 ELSE 0 END) = 0 
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'No NULLs allowed in: code_module, code_presentation, id_student, date_registration, ingestion_timestamp' AS description
FROM oulad.oulad_bronze.student_registration_bronze;

-- CHECK 1.3: COMPLETENESS - Unregistration Date (Optional Field)
-- Purpose: Track how many students have unregistered (NULL is valid)
SELECT 
    'COMPLETENESS' AS check_category,
    'Unregistration Date Distribution' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN date_unregistration IS NULL THEN 1 ELSE 0 END) AS null_unregistration,
    SUM(CASE WHEN date_unregistration IS NOT NULL THEN 1 ELSE 0 END) AS has_unregistration,
    ROUND(SUM(CASE WHEN date_unregistration IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS unregistration_rate_pct,
    'INFO' AS status,
    'Unregistration date is optional (NULL = student did not withdraw)' AS description
FROM oulad.oulad_bronze.student_registration_bronze;

-- CHECK 1.4: UNIQUENESS - Duplicate Primary Key Check
-- Purpose: Detect duplicate registrations (expected in bronze)
WITH duplicate_check AS (
    SELECT 
        code_module,
        code_presentation,
        id_student,
        COUNT(*) AS duplicate_count
    FROM oulad.oulad_bronze.student_registration_bronze
    GROUP BY code_module, code_presentation, id_student
    HAVING COUNT(*) > 1
)
SELECT 
    'UNIQUENESS' AS check_category,
    'Duplicate Primary Keys' AS check_name,
    COUNT(*) AS duplicate_combinations,
    COALESCE(SUM(duplicate_count), 0) AS total_duplicate_records,
    CASE 
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'WARNING'
    END AS status,
    'Duplicates expected in bronze; should be deduped in silver layer' AS description
FROM duplicate_check;

-- CHECK 1.5: TIMELINESS - Data Freshness
SELECT 
    'TIMELINESS' AS check_category,
    'Data Freshness' AS check_name,
    MAX(ingestion_date) AS latest_ingestion_date,
    DATEDIFF(CURRENT_DATE(), MAX(ingestion_date)) AS days_since_last_ingestion,
    CASE 
        WHEN DATEDIFF(CURRENT_DATE(), MAX(ingestion_date)) <= 7 THEN 'PASS'
        WHEN DATEDIFF(CURRENT_DATE(), MAX(ingestion_date)) <= 30 THEN 'WARNING'
        ELSE 'FAIL'
    END AS status,
    'Data should be ingested within the last 7 days (warning if > 7 days, fail if > 30 days)' AS description
FROM oulad.oulad_bronze.student_registration_bronze;


-- SECTION 2: BUSINESS RULE VALIDATION


-- CHECK 2.1: BUSINESS RULE - Registration Date Should Be Valid
-- Purpose: Detect any invalid or future registration dates
SELECT 
    'BUSINESS_RULE' AS check_category,
    'Valid Registration Date' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN TRY_CAST(date_registration AS DATE) > CURRENT_DATE() THEN 1 ELSE 0 END) AS future_registration_dates,
    MIN(TRY_CAST(date_registration AS DATE)) AS earliest_registration,
    MAX(TRY_CAST(date_registration AS DATE)) AS latest_registration,
    CASE 
        WHEN SUM(CASE WHEN TRY_CAST(date_registration AS DATE) > CURRENT_DATE() THEN 1 ELSE 0 END) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Registration date should not be in the future' AS description
FROM oulad.oulad_bronze.student_registration_bronze;

-- CHECK 2.2: BUSINESS RULE - Unregistration After Registration
-- Purpose: Unregistration date must be >= registration date
SELECT 
    'BUSINESS_RULE' AS check_category,
    'Unregistration After Registration' AS check_name,
    COUNT(*) AS total_records_with_unreg,
    SUM(CASE WHEN TRY_CAST(date_unregistration AS DATE) < TRY_CAST(date_registration AS DATE) THEN 1 ELSE 0 END) AS invalid_date_sequence,
    CASE 
        WHEN SUM(CASE WHEN TRY_CAST(date_unregistration AS DATE) < TRY_CAST(date_registration AS DATE) THEN 1 ELSE 0 END) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Unregistration date must be >= registration date' AS description
FROM oulad.oulad_bronze.student_registration_bronze
WHERE date_unregistration IS NOT NULL;

-- CHECK 2.3: BUSINESS RULE - Registration Duration Distribution
-- Purpose: Understand how long students stay registered
SELECT 
    'BUSINESS_RULE' AS check_category,
    'Registration Duration' AS check_name,
    COUNT(*) AS total_with_duration,
    ROUND(AVG(DATEDIFF(TRY_CAST(date_unregistration AS DATE), TRY_CAST(date_registration AS DATE))), 2) AS avg_days_registered,
    MIN(DATEDIFF(TRY_CAST(date_unregistration AS DATE), TRY_CAST(date_registration AS DATE))) AS min_days_registered,
    MAX(DATEDIFF(TRY_CAST(date_unregistration AS DATE), TRY_CAST(date_registration AS DATE))) AS max_days_registered,
    SUM(CASE WHEN DATEDIFF(TRY_CAST(date_unregistration AS DATE), TRY_CAST(date_registration AS DATE)) = 0 THEN 1 ELSE 0 END) AS same_day_unregistrations,
    'INFO' AS status,
    'Distribution of registration duration for students who unregistered' AS description
FROM oulad.oulad_bronze.student_registration_bronze
WHERE date_unregistration IS NOT NULL;


-- SECTION 3: SUMMARY REPORT


-- CHECK 3.1: Overall Table Profile
SELECT 
    'SUMMARY' AS check_category,
    'Table Profile' AS check_name,
    COUNT(*) AS total_records,
    COUNT(DISTINCT id_student) AS unique_students,
    COUNT(DISTINCT CONCAT(code_module, '-', code_presentation)) AS unique_course_presentations,
    MIN(ingestion_date) AS earliest_ingestion,
    MAX(ingestion_date) AS latest_ingestion,
    'INFO' AS status,
    'Bronze layer overview statistics' AS description
FROM oulad.oulad_bronze.student_registration_bronze;