
-- Create the clean table for student_registration
CREATE TABLE IF NOT EXISTS oulad.oulad_silver.student_registration_silver (
    code_module STRING,
    code_presentation VARCHAR(50),
    id_student INT,
    date_registration DATE,
    date_unregistration DATE,
    ingestion_timestamp TIMESTAMP,
    ingestion_date DATE,
    PRIMARY KEY (code_module, code_presentation, id_student)
)
USING DELTA;


-- Merge cleaned data from raw table to capture idempotency
MERGE INTO oulad.oulad_silver.student_registration_silver AS target
USING (
    SELECT 
        UPPER(TRIM(code_module)) AS code_module,
        UPPER(TRIM(code_presentation)) AS code_presentation,
        id_student,
        TRY_CAST(date_registration AS DATE) AS date_registration,
        TRY_CAST(date_unregistration AS DATE) AS date_unregistration,
        ingestion_timestamp,
        CAST(ingestion_timestamp AS DATE) AS ingestion_date
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (PARTITION BY code_module, code_presentation, id_student ORDER BY ingestion_timestamp DESC) AS row_num
        FROM oulad.oulad_bronze.student_registration_bronze
        WHERE code_module IS NOT NULL
          AND code_presentation IS NOT NULL
          AND id_student IS NOT NULL
          AND date_registration IS NOT NULL
          AND ingestion_timestamp IS NOT NULL
    )
    WHERE row_num = 1
) AS source
ON target.code_module = source.code_module 
   AND target.code_presentation = source.code_presentation 
   AND target.id_student = source.id_student
WHEN MATCHED THEN
    UPDATE SET
        target.date_registration = source.date_registration,
        target.date_unregistration = source.date_unregistration,
        target.ingestion_timestamp = source.ingestion_timestamp,
        target.ingestion_date = source.ingestion_date
WHEN NOT MATCHED THEN
    INSERT (code_module, code_presentation, id_student, date_registration, date_unregistration, ingestion_timestamp, ingestion_date)
    VALUES (source.code_module, source.code_presentation, source.id_student, source.date_registration, source.date_unregistration, source.ingestion_timestamp, source.ingestion_date);
