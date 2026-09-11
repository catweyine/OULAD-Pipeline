-- Create dimension table for student module enrollment
CREATE TABLE IF NOT EXISTS oulad.oulad_gold.dim_student_enrollment (
    student_enrollment_id INT,
    student_id INT,
    course_id VARCHAR(100),
    num_of_prev_attempts INT,
    studied_credits INT,
    final_result VARCHAR(50),
    date_registration INT,
    ingestion_timestamp TIMESTAMP,
    PRIMARY KEY (student_enrollment_id)
)
USING DELTA;

-- Merge enrollment performance and registration attributes
MERGE INTO oulad.oulad_gold.dim_student_enrollment AS target
USING (
    SELECT 
        ABS(HASH(si.code_module, si.code_presentation, si.id_student)) AS student_enrollment_id,
        si.id_student AS student_id,
        CONCAT(UPPER(TRIM(si.code_module)), '_', UPPER(TRIM(si.code_presentation))) AS course_id,
        CAST(si.num_of_prev_attempts AS INT) AS num_of_prev_attempts,
        CAST(si.studied_credits AS INT) AS studied_credits,
        TRIM(si.final_result) AS final_result,
        UNIX_DATE(sr.date_registration) AS date_registration,
        GREATEST(si.ingestion_timestamp, sr.ingestion_timestamp) AS ingestion_timestamp
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (
                   PARTITION BY code_module, code_presentation, id_student 
                   ORDER BY ingestion_timestamp DESC
               ) AS row_num
        FROM oulad.oulad_silver.student_info_silver
        WHERE code_module IS NOT NULL 
          AND code_presentation IS NOT NULL 
          AND id_student IS NOT NULL
    ) si
    INNER JOIN (
        SELECT *,
               ROW_NUMBER() OVER (
                   PARTITION BY code_module, code_presentation, id_student 
                   ORDER BY ingestion_timestamp DESC
               ) AS row_num
        FROM oulad.oulad_silver.student_registration_silver
        WHERE code_module IS NOT NULL 
          AND code_presentation IS NOT NULL 
          AND id_student IS NOT NULL
    ) sr
        ON si.code_module = sr.code_module
       AND si.code_presentation = sr.code_presentation
       AND si.id_student = sr.id_student
    WHERE si.row_num = 1 
      AND sr.row_num = 1
) AS source
ON target.student_enrollment_id = source.student_enrollment_id
WHEN MATCHED THEN
    UPDATE SET
        target.student_id = source.student_id,
        target.course_id = source.course_id,
        target.num_of_prev_attempts = source.num_of_prev_attempts,
        target.studied_credits = source.studied_credits,
        target.final_result = source.final_result,
        target.date_registration = source.date_registration,
        target.ingestion_timestamp = source.ingestion_timestamp
WHEN NOT MATCHED THEN
    INSERT (
        student_enrollment_id, 
        student_id, 
        course_id, 
        num_of_prev_attempts, 
        studied_credits, 
        final_result, 
        date_registration, 
        ingestion_timestamp
    )
    VALUES (
        source.student_enrollment_id, 
        source.student_id, 
        source.course_id, 
        source.num_of_prev_attempts, 
        source.studied_credits, 
        source.final_result, 
        source.date_registration, 
        source.ingestion_timestamp
    );

-- Verify dim_student_enrollment
SELECT *
FROM oulad.oulad_gold.dim_student_enrollment
LIMIT 10;