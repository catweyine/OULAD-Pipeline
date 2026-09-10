
-- DATA QUALITY VALIDATION: oulad.oulad_bronze.student_info_bronze
-- Test Type: POST-LOAD / AT-REST VALIDATION
-- Layer: BRONZE (Raw/Ingestion)



-- SECTION 1: DATA INTEGRITY CHECKS


-- CHECK 1.1: COMPLETENESS - Record Count
-- Purpose: Verify table has records and track volume trends
SELECT 
    'COMPLETENESS' AS check_category,
    'Record Count' AS check_name,
    COUNT(*) AS actual_count,
    CASE 
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Bronze table should contain at least 1 record' AS description
FROM oulad.oulad_bronze.student_info_bronze;

-- CHECK 1.2: COMPLETENESS - Required Columns Populated
-- Purpose: Verify critical columns are not NULL
SELECT 
    'COMPLETENESS' AS check_category,
    'Required Columns' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN code_module IS NULL THEN 1 ELSE 0 END) AS null_code_module,
    SUM(CASE WHEN code_presentation IS NULL THEN 1 ELSE 0 END) AS null_code_presentation,
    SUM(CASE WHEN id_student IS NULL THEN 1 ELSE 0 END) AS null_id_student,
    SUM(CASE WHEN ingestion_timestamp IS NULL THEN 1 ELSE 0 END) AS null_ingestion_timestamp,
    SUM(CASE WHEN ingestion_date IS NULL THEN 1 ELSE 0 END) AS null_ingestion_date,
    CASE 
        WHEN SUM(CASE WHEN code_module IS NULL OR code_presentation IS NULL 
                      OR id_student IS NULL OR ingestion_timestamp IS NULL 
                      OR ingestion_date IS NULL THEN 1 ELSE 0 END) = 0 
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'No NULLs allowed in: code_module, code_presentation, id_student, ingestion_timestamp, ingestion_date' AS description
FROM oulad.oulad_bronze.student_info_bronze;

-- CHECK 1.3: UNIQUENESS - Duplicate Primary Key Check
-- Purpose: Detect duplicate student enrollments (expected in bronze layer)
WITH duplicate_check AS (
    SELECT 
        code_module,
        code_presentation,
        id_student,
        COUNT(*) AS duplicate_count
    FROM oulad.oulad_bronze.student_info_bronze
    GROUP BY code_module, code_presentation, id_student
    HAVING COUNT(*) > 1
)
SELECT 
    'UNIQUENESS' AS check_category,
    'Duplicate Primary Keys' AS check_name,
    COUNT(*) AS duplicate_combinations,
    SUM(duplicate_count) AS total_duplicate_records,
    CASE 
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'WARNING'
    END AS status,
    'Duplicates expected in bronze; should be deduped in silver layer' AS description
FROM duplicate_check;

-- CHECK 1.4: VALIDITY - Data Type and Format Check
-- Purpose: Verify data conforms to expected formats
SELECT 
    'VALIDITY' AS check_category,
    'Data Type Conformance' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN gender NOT IN ('M', 'F', 'm', 'f', NULL) THEN 1 ELSE 0 END) AS invalid_gender,
    SUM(CASE WHEN num_of_prev_attempts < 0 THEN 1 ELSE 0 END) AS negative_prev_attempts,
    SUM(CASE WHEN studied_credits < 0 THEN 1 ELSE 0 END) AS negative_credits,
    SUM(CASE WHEN disability NOT IN ('Y', 'N', 'y', 'n', NULL) THEN 1 ELSE 0 END) AS invalid_disability,
    CASE 
        WHEN SUM(CASE WHEN gender NOT IN ('M', 'F', 'm', 'f', NULL) 
                      OR num_of_prev_attempts < 0 
                      OR studied_credits < 0 
                      OR disability NOT IN ('Y', 'N', 'y', 'n', NULL) THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Values should conform to expected domains and ranges' AS description
FROM oulad.oulad_bronze.student_info_bronze;

-- CHECK 1.5: TIMELINESS - Data Freshness
-- Purpose: Verify data was ingested recently
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
FROM oulad.oulad_bronze.student_info_bronze;


-- SECTION 2: BUSINESS RULE VALIDATION


-- CHECK 2.1: BUSINESS RULE - Valid IMD Band Values
-- Purpose: Verify deprivation band contains expected values or placeholder
SELECT 
    'BUSINESS_RULE' AS check_category,
    'IMD Band Domain Values' AS check_name,
    COUNT(DISTINCT imd_band) AS distinct_values,
    CONCAT_WS(', ', COLLECT_SET(imd_band)) AS unique_imd_values,
    CASE 
        WHEN SUM(CASE WHEN imd_band NOT IN ('0-10%', '10-20%', '20-30%', '30-40%', '40-50%', 
                                             '50-60%', '60-70%', '70-80%', '80-90%', '90-100%', '?', NULL) 
                      THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'IMD band should be valid percentile range or "?" for unknown' AS description
FROM oulad.oulad_bronze.student_info_bronze;

-- CHECK 2.2: BUSINESS RULE - Final Result Domain
-- Purpose: Verify final_result contains only expected values
SELECT 
    'BUSINESS_RULE' AS check_category,
    'Final Result Domain' AS check_name,
    COUNT(*) AS total_records,
    COUNT(DISTINCT final_result) AS distinct_values,
    CONCAT_WS(', ', COLLECT_SET(final_result)) AS unique_final_results,
    CASE 
        WHEN SUM(CASE WHEN UPPER(TRIM(final_result)) NOT IN ('PASS', 'FAIL', 'DISTINCTION', 'WITHDRAWN', NULL) 
                      THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Final result should be: Pass, Fail, Distinction, or Withdrawn' AS description
FROM oulad.oulad_bronze.student_info_bronze;

-- CHECK 2.3: BUSINESS RULE - Reasonable Credit Load
-- Purpose: Verify studied_credits falls within reasonable range
SELECT 
    'BUSINESS_RULE' AS check_category,
    'Reasonable Credit Load' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN studied_credits = 0 THEN 1 ELSE 0 END) AS zero_credits,
    SUM(CASE WHEN studied_credits > 300 THEN 1 ELSE 0 END) AS excessive_credits,
    MIN(studied_credits) AS min_credits,
    MAX(studied_credits) AS max_credits,
    ROUND(AVG(studied_credits), 2) AS avg_credits,
    CASE 
        WHEN SUM(CASE WHEN studied_credits = 0 OR studied_credits > 300 THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        WHEN SUM(CASE WHEN studied_credits = 0 OR studied_credits > 300 THEN 1 ELSE 0 END) < COUNT(*) * 0.01
        THEN 'WARNING'
        ELSE 'FAIL'
    END AS status,
    'Credits should be > 0 and <= 300 (warning if < 1% violations)' AS description
FROM oulad.oulad_bronze.student_info_bronze;

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
FROM oulad.oulad_bronze.student_info_bronze;