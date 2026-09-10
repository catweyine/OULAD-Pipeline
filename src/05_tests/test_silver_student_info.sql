
-- DATA QUALITY VALIDATION: oulad.oulad_silver.student_info_silver
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
FROM oulad.oulad_silver.student_info_silver;

-- CHECK 1.2: COMPLETENESS - NO NULL Primary Key Components
-- Purpose: Primary key should be fully populated (enforced by constraint)
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
FROM oulad.oulad_silver.student_info_silver;

-- CHECK 1.3: UNIQUENESS - NO Duplicates (PRIMARY KEY)
-- Purpose: Silver layer must have unique records after deduplication
WITH duplicate_check AS (
    SELECT 
        code_module,
        code_presentation,
        id_student,
        COUNT(*) AS duplicate_count
    FROM oulad.oulad_silver.student_info_silver
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

-- CHECK 1.4: VALIDITY - Cleaned & Standardized Data
-- Purpose: Data should be cleaned and standardized (upper-cased, trimmed)
SELECT 
    'VALIDITY' AS check_category,
    'Data Standardization' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN code_module != UPPER(TRIM(code_module)) THEN 1 ELSE 0 END) AS unstandardized_module,
    SUM(CASE WHEN code_presentation != UPPER(TRIM(code_presentation)) THEN 1 ELSE 0 END) AS unstandardized_presentation,
    SUM(CASE WHEN gender NOT IN ('M', 'F') THEN 1 ELSE 0 END) AS invalid_gender,
    SUM(CASE WHEN disability NOT IN (TRUE, FALSE) THEN 1 ELSE 0 END) AS invalid_disability,
    CASE 
        WHEN SUM(CASE WHEN code_module != UPPER(TRIM(code_module)) 
                      OR code_presentation != UPPER(TRIM(code_presentation))
                      OR gender NOT IN ('M', 'F')
                      OR disability NOT IN (TRUE, FALSE) THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'All data should be cleaned, standardized (uppercase), and boolean values properly converted' AS description
FROM oulad.oulad_silver.student_info_silver;

-- CHECK 1.5: COMPLETENESS - Required Business Columns
-- Purpose: Critical business columns should not be NULL after cleaning
SELECT 
    'COMPLETENESS' AS check_category,
    'Required Business Columns' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN gender IS NULL THEN 1 ELSE 0 END) AS null_gender,
    SUM(CASE WHEN region IS NULL THEN 1 ELSE 0 END) AS null_region,
    SUM(CASE WHEN highest_education IS NULL THEN 1 ELSE 0 END) AS null_education,
    SUM(CASE WHEN imd_band IS NULL THEN 1 ELSE 0 END) AS null_imd_band,
    SUM(CASE WHEN age_band IS NULL THEN 1 ELSE 0 END) AS null_age_band,
    SUM(CASE WHEN disability IS NULL THEN 1 ELSE 0 END) AS null_disability,
    SUM(CASE WHEN final_result IS NULL THEN 1 ELSE 0 END) AS null_final_result,
    CASE 
        WHEN SUM(CASE WHEN gender IS NULL OR region IS NULL OR highest_education IS NULL 
                      OR imd_band IS NULL OR age_band IS NULL OR disability IS NULL 
                      OR final_result IS NULL THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'All business columns should be populated (no NULLs)' AS description
FROM oulad.oulad_silver.student_info_silver;


-- SECTION 2: BUSINESS RULE VALIDATION


-- CHECK 2.1: BUSINESS RULE - IMD Band Should Not Contain "?"
-- Purpose: Unknown IMD values should be filtered out in silver layer
SELECT 
    'BUSINESS_RULE' AS check_category,
    'IMD Band Valid Values Only' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN imd_band = '?' THEN 1 ELSE 0 END) AS records_with_unknown_imd,
    CASE 
        WHEN SUM(CASE WHEN imd_band = '?' THEN 1 ELSE 0 END) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Silver layer should not contain "?" in imd_band (must be filtered)' AS description
FROM oulad.oulad_silver.student_info_silver;

-- CHECK 2.2: BUSINESS RULE - Valid Credits Range
-- Purpose: Only valid credit values should pass silver layer filters
SELECT 
    'BUSINESS_RULE' AS check_category,
    'Valid Credit Range' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN studied_credits <= 0 THEN 1 ELSE 0 END) AS zero_or_negative_credits,
    SUM(CASE WHEN studied_credits > 300 THEN 1 ELSE 0 END) AS excessive_credits,
    MIN(studied_credits) AS min_credits,
    MAX(studied_credits) AS max_credits,
    CASE 
        WHEN SUM(CASE WHEN studied_credits <= 0 OR studied_credits > 300 THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Credits should be > 0 and <= 300 in silver layer' AS description
FROM oulad.oulad_silver.student_info_silver;

-- CHECK 2.3: BUSINESS RULE - Previous Attempts Should Be Non-Negative
SELECT 
    'BUSINESS_RULE' AS check_category,
    'Previous Attempts Non-Negative' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN num_of_prev_attempts < 0 THEN 1 ELSE 0 END) AS negative_attempts,
    MIN(num_of_prev_attempts) AS min_attempts,
    MAX(num_of_prev_attempts) AS max_attempts,
    CASE 
        WHEN SUM(CASE WHEN num_of_prev_attempts < 0 THEN 1 ELSE 0 END) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Previous attempts must be >= 0' AS description
FROM oulad.oulad_silver.student_info_silver;


-- SECTION 3: CONSISTENCY CHECKS


-- CHECK 3.1: CONSISTENCY - Compare Bronze to Silver Record Counts
-- Purpose: Ensure expected record filtering (duplicates & invalid records removed)
WITH record_counts AS (
    SELECT 
        (SELECT COUNT(*) FROM oulad.oulad_bronze.student_info_bronze) AS bronze_count,
        (SELECT COUNT(*) FROM oulad.oulad_silver.student_info_silver) AS silver_count
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

-- CHECK 3.2: CONSISTENCY - Valid Categorical Values
-- Purpose: Ensure all categorical values are within expected domains
WITH invalid_domains AS (
    SELECT 
        SUM(CASE WHEN gender NOT IN ('M', 'F') THEN 1 ELSE 0 END) AS invalid_gender,
        SUM(CASE WHEN imd_band NOT IN ('0-10%', '10-20%', '20-30%', '30-40%', '40-50%', 
                                       '50-60%', '60-70%', '70-80%', '80-90%', '90-100%') THEN 1 ELSE 0 END) AS invalid_imd,
        SUM(CASE WHEN final_result NOT IN ('Pass', 'Fail', 'Distinction', 'Withdrawn') THEN 1 ELSE 0 END) AS invalid_result
    FROM oulad.oulad_silver.student_info_silver
)
SELECT 
    'CONSISTENCY' AS check_category,
    'Categorical Domain Values' AS check_name,
    invalid_gender,
    invalid_imd,
    invalid_result,
    CASE 
        WHEN invalid_gender + invalid_imd + invalid_result = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'All categorical values should be within expected domains' AS description
FROM invalid_domains;


-- SECTION 4: SUMMARY REPORT


-- CHECK 4.1: Overall Table Profile
SELECT 
    'SUMMARY' AS check_category,
    'Table Profile' AS check_name,
    COUNT(*) AS total_records,
    COUNT(DISTINCT id_student) AS unique_students,
    COUNT(DISTINCT CONCAT(code_module, '-', code_presentation)) AS unique_course_presentations,
    COUNT(DISTINCT gender) AS unique_genders,
    COUNT(DISTINCT highest_education) AS unique_education_levels,
    MIN(ingestion_date) AS earliest_ingestion,
    MAX(ingestion_date) AS latest_ingestion,
    'INFO' AS status,
    'Silver layer overview statistics' AS description
FROM oulad.oulad_silver.student_info_silver;