SELECT *
FROM oulad.oulad_bronze.student_registration_bronze
LIMIT 10;

-- Create the clean table for student_registration
CREATE TABLE IF NOT EXISTS oulad.oulad_silver.student_registration_silver (
    id_student INT,
    code_module STRING,
    code_presentation STRING,
    date_registration INT,
    date_unregistration INT,
    ingestion_timestamp TIMESTAMP,
    ingestion_date DATE
)
USING DELTA;


-- Merge cleaned data from raw table to capture idempotency
MERGE INTO oulad.oulad_silver.student_registration_silver AS target
USING (
    SELECT 
        id_student,
        UPPER(TRIM(code_module)) AS code_module,
        UPPER(TRIM(code_presentation)) AS code_presentation,
        TRY_CAST(date_registration AS INT) AS date_registration,
        TRY_CAST(date_unregistration AS INT) AS date_unregistration,
        ingestion_timestamp,
        CAST(ingestion_timestamp AS DATE) AS ingestion_date
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (PARTITION BY id_student, code_module, code_presentation ORDER BY ingestion_timestamp DESC) AS row_num
        FROM oulad.oulad_bronze.student_registration_bronze
        WHERE code_module IS NOT NULL
          AND code_presentation IS NOT NULL
          AND id_student IS NOT NULL
          AND date_registration IS NOT NULL
          AND date_registration != '?'
          AND ingestion_timestamp IS NOT NULL
    )
    WHERE row_num = 1
) AS source
ON target.id_student = source.id_student 
   AND target.code_module = source.code_module 
   AND target.code_presentation = source.code_presentation
WHEN MATCHED THEN
    UPDATE SET
        target.date_registration = source.date_registration,
        target.date_unregistration = source.date_unregistration,
        target.ingestion_timestamp = source.ingestion_timestamp,
        target.ingestion_date = source.ingestion_date
WHEN NOT MATCHED THEN
    INSERT (id_student, code_module, code_presentation, date_registration, date_unregistration, ingestion_timestamp, ingestion_date)
    VALUES (source.id_student, source.code_module, source.code_presentation, source.date_registration, source.date_unregistration, source.ingestion_timestamp, source.ingestion_date);

-- Check the table
SELECT *
FROM oulad.oulad_silver.student_registration_silver
LIMIT 10;


