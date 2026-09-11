-- Create Student Info Dimension Table for Gold Layer
-- This dimension combines student demographics with their course registrations
-- Grain: One row per student per course enrollment

CREATE OR REPLACE TABLE oulad.oulad_gold.dim_student_info AS
SELECT 
    -- Surrogate Key
    CONCAT(si.id_student, '_', si.code_module, '_', si.code_presentation) AS student_course_key,
    
    -- Natural Keys
    si.id_student,
    si.code_module,
    si.code_presentation,
    
    -- Student Demographics
    si.gender,
    si.region,
    si.highest_education,
    si.imd_band,
    si.age_band,
    
    -- Academic Information
    si.num_of_prev_attempts,
    si.studied_credits,
    si.disability,
    si.final_result,
    
    -- Registration Information
    sr.date_registration,
    sr.date_unregistration,
    CASE 
        WHEN sr.date_unregistration IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS is_unregistered,
    
    -- Audit Fields
    GREATEST(si.ingestion_timestamp, sr.ingestion_timestamp) AS last_updated_timestamp,
    CURRENT_TIMESTAMP() AS dimension_created_at

FROM oulad.oulad_silver.student_info_silver AS si
INNER JOIN oulad.oulad_silver.student_registration_silver AS sr
    ON si.id_student = sr.id_student
    AND si.code_module = sr.code_module
    AND si.code_presentation = sr.code_presentation;

/*
-- Verify the dimension table
SELECT 
    COUNT(*) AS total_records,
    COUNT(DISTINCT id_student) AS unique_students,
    COUNT(DISTINCT code_module) AS unique_courses,
    COUNT(DISTINCT CONCAT(code_module, code_presentation)) AS unique_presentations,
    SUM(CASE WHEN is_unregistered THEN 1 ELSE 0 END) AS unregistered_count,
    COUNT(DISTINCT gender) AS gender_categories,
    COUNT(DISTINCT region) AS regions
FROM oulad.oulad_gold.dim_student_info;


-- Sample records
SELECT *
FROM oulad.oulad_gold.dim_student_info
LIMIT 10;

*/