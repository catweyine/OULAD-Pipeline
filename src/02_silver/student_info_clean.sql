SELECT *
FROM oulad.oulad_bronze.student_info_bronze
LIMIT 10;

-- Create the clean table for student_info
CREATE TABLE IF NOT EXISTS oulad.oulad_silver.student_info_silver (
    code_module STRING,
    code_presentation VARCHAR(50), 
    id_student INT, 
    gender CHAR(1),
    region STRING, 
    highest_education STRING,
    imd_band STRING,
    age_band STRING,
    num_of_prev_attempts INT,
    studied_credits INT,
    disability BOOLEAN,
    final_result STRING,
    ingestion_timestamp TIMESTAMP,
    ingestion_date DATE,
    PRIMARY KEY (code_module, code_presentation, id_student)
)
USING DELTA;


-- Merge cleaned data from raw table to capture idempotency
MERGE INTO oulad.oulad_silver.student_info_silver AS target
USING (
    SELECT 
        UPPER(TRIM(code_module)) AS code_module,
        UPPER(TRIM(code_presentation)) AS code_presentation,
        id_student,
        UPPER(TRIM(gender)) AS gender,
        TRIM(region) AS region,
        TRIM(highest_education) AS highest_education,
        TRIM(imd_band) AS imd_band,
        TRIM(age_band) AS age_band,
        num_of_prev_attempts,
        studied_credits,
        CASE 
            WHEN UPPER(TRIM(disability)) = 'Y' THEN TRUE
            WHEN UPPER(TRIM(disability)) = 'N' THEN FALSE
            ELSE NULL
        END AS disability,
        TRIM(final_result) AS final_result,
        ingestion_timestamp,
        CAST(ingestion_timestamp AS DATE) AS ingestion_date
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (PARTITION BY id_student ORDER BY ingestion_timestamp DESC) AS row_num
        FROM oulad.oulad_bronze.student_info_bronze
        WHERE code_module IS NOT NULL
          AND code_presentation IS NOT NULL
          AND id_student IS NOT NULL
          AND gender IS NOT NULL
          AND gender IN ('M', 'F', 'm', 'f')
          AND region IS NOT NULL
          AND highest_education IS NOT NULL
          AND imd_band IS NOT NULL
          AND imd_band != '?'
          AND age_band IS NOT NULL
          AND num_of_prev_attempts IS NOT NULL
          AND num_of_prev_attempts >= 0
          AND studied_credits IS NOT NULL
          AND studied_credits > 0
          AND disability IS NOT NULL
          AND final_result IS NOT NULL
          AND ingestion_timestamp IS NOT NULL
    )
    WHERE row_num = 1
) AS source
ON target.code_module = source.code_module 
   AND target.code_presentation = source.code_presentation 
   AND target.id_student = source.id_student
WHEN MATCHED THEN
    UPDATE SET
        target.code_module = source.code_module,
        target.code_presentation = source.code_presentation,
        target.gender = source.gender,
        target.region = source.region,
        target.highest_education = source.highest_education,
        target.imd_band = source.imd_band,
        target.age_band = source.age_band,
        target.num_of_prev_attempts = source.num_of_prev_attempts,
        target.studied_credits = source.studied_credits,
        target.disability = source.disability,
        target.final_result = source.final_result,
        target.ingestion_timestamp = source.ingestion_timestamp,
        target.ingestion_date = source.ingestion_date
WHEN NOT MATCHED THEN
    INSERT (code_module, code_presentation, id_student, gender, region, highest_education, imd_band, age_band, num_of_prev_attempts, studied_credits, disability, final_result, ingestion_timestamp, ingestion_date)
    VALUES (source.code_module, source.code_presentation, source.id_student, source.gender, source.region, source.highest_education, source.imd_band, source.age_band, source.num_of_prev_attempts, source.studied_credits, source.disability, source.final_result, source.ingestion_timestamp, source.ingestion_date);

-- Check the table
SELECT *
FROM oulad.oulad_silver.student_info_silver
LIMIT 10;


