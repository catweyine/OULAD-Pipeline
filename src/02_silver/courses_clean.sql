CREATE TABLE IF NOT EXISTS oulad.oulad_silver.courses_silver (
    code_module STRING,
    code_presentation STRING,
    module_presentation_length INT,
    ingestion_timestamp TIMESTAMP,
    ingestion_date DATE
)
USING DELTA;

MERGE INTO oulad.oulad_silver.courses_silver AS target
USING (
    SELECT
        UPPER(TRIM(code_module)) AS code_module,
        UPPER(TRIM(code_presentation)) AS code_presentation,
        CAST(module_presentation_length AS INT) AS module_presentation_length,
        ingestion_timestamp,
        ingestion_date
    FROM oulad.oulad_bronze.courses_bronze
    WHERE code_module IS NOT NULL
      AND code_presentation IS NOT NULL
      AND module_presentation_length > 0
) AS source
ON target.code_module = source.code_module
AND target.code_presentation = source.code_presentation

WHEN MATCHED THEN
UPDATE SET
    target.module_presentation_length = source.module_presentation_length,
    target.ingestion_timestamp = source.ingestion_timestamp,
    target.ingestion_date = source.ingestion_date

WHEN NOT MATCHED THEN
INSERT (
    code_module,
    code_presentation,
    module_presentation_length,
    ingestion_timestamp,
    ingestion_date
)
VALUES (
    source.code_module,
    source.code_presentation,
    source.module_presentation_length,
    source.ingestion_timestamp,
    source.ingestion_date
);