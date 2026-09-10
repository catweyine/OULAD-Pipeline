
-- DATA QUALITY VALIDATION: oulad.oulad_gold.dim_student
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
    'Gold dimension should contain at least 1 record' AS description
FROM oulad.oulad_gold.dim_student;

-- CHECK 1.2: UNIQUENESS - NO Duplicate student_id (Dimension Primary Key)
WITH duplicate_check AS (
    SELECT 
        student_id,
        COUNT(*) AS duplicate_count
    FROM oulad.oulad_gold.dim_student
    GROUP BY student_id
    HAVING COUNT(*) > 1
)
SELECT 
    'UNIQUENESS' AS check_category,
    'No Duplicate student_id' AS check_name,
    COUNT(*) AS duplicate_student_ids,
    COALESCE(SUM(duplicate_count), 0) AS total_duplicate_records,
    CASE 
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'student_id must be unique in dimension table' AS description
FROM duplicate_check;

-- CHECK 1.3: COMPLETENESS - Required Dimension Attributes
-- Purpose: All dimensional attributes should be populated
SELECT 
    'COMPLETENESS' AS check_category,
    'Required Dimension Attributes' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN student_id IS NULL THEN 1 ELSE 0 END) AS null_student_id,
    SUM(CASE WHEN gender IS NULL THEN 1 ELSE 0 END) AS null_gender,
    SUM(CASE WHEN region IS NULL THEN 1 ELSE 0 END) AS null_region,
    SUM(CASE WHEN highest_education IS NULL THEN 1 ELSE 0 END) AS null_education,
    SUM(CASE WHEN imd_band IS NULL THEN 1 ELSE 0 END) AS null_imd_band,
    SUM(CASE WHEN age_band IS NULL THEN 1 ELSE 0 END) AS null_age_band,
    SUM(CASE WHEN disability IS NULL THEN 1 ELSE 0 END) AS null_disability,
    CASE 
        WHEN SUM(CASE WHEN student_id IS NULL OR gender IS NULL OR region IS NULL 
                      OR highest_education IS NULL OR imd_band IS NULL 
                      OR age_band IS NULL OR disability IS NULL THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'All dimension attributes should be populated (no NULLs)' AS description
FROM oulad.oulad_gold.dim_student;

-- CHECK 1.4: VALIDITY - Standardized Dimension Values
SELECT 
    'VALIDITY' AS check_category,
    'Standardized Dimension Values' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN gender NOT IN ('M', 'F') THEN 1 ELSE 0 END) AS invalid_gender,
    SUM(CASE WHEN disability NOT IN (TRUE, FALSE) THEN 1 ELSE 0 END) AS invalid_disability,
    CASE 
        WHEN SUM(CASE WHEN gender NOT IN ('M', 'F') OR disability NOT IN (TRUE, FALSE) THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'All dimension values should be standardized and valid' AS description
FROM oulad.oulad_gold.dim_student;


-- SECTION 2: BUSINESS RULE VALIDATION


-- CHECK 2.1: BUSINESS RULE - Valid Categorical Domains
SELECT 
    'BUSINESS_RULE' AS check_category,
    'Categorical Domain Values' AS check_name,
    COUNT(*) AS total_records,
    SUM(CASE WHEN imd_band NOT IN ('0-10%', '10-20%', '20-30%', '30-40%', '40-50%', 
                                   '50-60%', '60-70%', '70-80%', '80-90%', '90-100%') THEN 1 ELSE 0 END) AS invalid_imd_band,
    COUNT(DISTINCT gender) AS distinct_genders,
    COUNT(DISTINCT highest_education) AS distinct_education_levels,
    COUNT(DISTINCT age_band) AS distinct_age_bands,
    COUNT(DISTINCT imd_band) AS distinct_imd_bands,
    COUNT(DISTINCT region) AS distinct_regions,
    CASE 
        WHEN SUM(CASE WHEN imd_band NOT IN ('0-10%', '10-20%', '20-30%', '30-40%', '40-50%', 
                                            '50-60%', '60-70%', '70-80%', '80-90%', '90-100%') THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'All categorical values should be within expected domains' AS description
FROM oulad.oulad_gold.dim_student;

-- CHECK 2.2: BUSINESS RULE - Dimension Cardinality
-- Purpose: Ensure dimension has reasonable number of unique students
WITH cardinality_check AS (
    SELECT 
        COUNT(DISTINCT student_id) AS unique_students,
        COUNT(*) AS total_records
    FROM oulad.oulad_gold.dim_student
)
SELECT 
    'BUSINESS_RULE' AS check_category,
    'Dimension Cardinality' AS check_name,
    unique_students,
    total_records,
    CASE 
        WHEN unique_students = total_records THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Dimension should have one record per unique student (no duplicates)' AS description
FROM cardinality_check;


-- SECTION 3: CONSISTENCY CHECKS


-- CHECK 3.1: CONSISTENCY - Student Count vs Silver Layer
-- Purpose: Dimension should contain all unique students from silver
WITH layer_comparison AS (
    SELECT 
        (SELECT COUNT(DISTINCT id_student) FROM oulad.oulad_silver.student_info_silver) AS silver_students,
        (SELECT COUNT(DISTINCT student_id) FROM oulad.oulad_gold.dim_student) AS gold_students
)
SELECT 
    'CONSISTENCY' AS check_category,
    'Student Count - Silver vs Gold' AS check_name,
    silver_students,
    gold_students,
    silver_students - gold_students AS missing_in_gold,
    CASE 
        WHEN gold_students >= silver_students * 0.95 THEN 'PASS'
        WHEN gold_students >= silver_students * 0.90 THEN 'WARNING'
        ELSE 'FAIL'
    END AS status,
    'Gold dimension should contain at least 95% of silver unique students' AS description
FROM layer_comparison;

-- CHECK 3.2: CONSISTENCY - Demographic Distribution
-- Purpose: Verify demographic breakdowns are reasonable
SELECT 
    'CONSISTENCY' AS check_category,
    'Demographic Distribution' AS check_name,
    COUNT(*) AS total_students,
    ROUND(SUM(CASE WHEN gender = 'F' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS female_pct,
    ROUND(SUM(CASE WHEN gender = 'M' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS male_pct,
    ROUND(SUM(CASE WHEN disability = TRUE THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS disability_pct,
    CASE 
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Demographic distribution summary (informational)' AS description
FROM oulad.oulad_gold.dim_student;


-- SECTION 4: SUMMARY REPORT


-- CHECK 4.1: Dimension Profile
SELECT 
    'SUMMARY' AS check_category,
    'Dimension Profile' AS check_name,
    COUNT(*) AS total_students,
    COUNT(DISTINCT student_id) AS unique_student_ids,
    COUNT(DISTINCT region) AS unique_regions,
    COUNT(DISTINCT highest_education) AS unique_education_levels,
    COUNT(DISTINCT age_band) AS unique_age_bands,
    COUNT(DISTINCT imd_band) AS unique_imd_bands,
    'INFO' AS status,
    'Gold dimension overview statistics' AS description
FROM oulad.oulad_gold.dim_student;

-- CHECK 4.2: Dimension Completeness by Attribute
SELECT 
    'SUMMARY' AS check_category,
    'Attribute Completeness %' AS check_name,
    ROUND(COUNT(student_id) * 100.0 / COUNT(*), 2) AS student_id_completeness,
    ROUND(COUNT(gender) * 100.0 / COUNT(*), 2) AS gender_completeness,
    ROUND(COUNT(region) * 100.0 / COUNT(*), 2) AS region_completeness,
    ROUND(COUNT(highest_education) * 100.0 / COUNT(*), 2) AS education_completeness,
    ROUND(COUNT(imd_band) * 100.0 / COUNT(*), 2) AS imd_band_completeness,
    ROUND(COUNT(age_band) * 100.0 / COUNT(*), 2) AS age_band_completeness,
    ROUND(COUNT(disability) * 100.0 / COUNT(*), 2) AS disability_completeness,
    'INFO' AS status,
    'Percentage of non-NULL values for each attribute' AS description
FROM oulad.oulad_gold.dim_student;