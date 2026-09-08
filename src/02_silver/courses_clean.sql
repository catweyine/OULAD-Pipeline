CREATE OR REPLACE TABLE oulad.oulad_silver.courses_silver AS
SELECT DISTINCT
    UPPER(TRIM(code_module)) AS code_module,
    UPPER(TRIM(code_presentation)) AS code_presentation,
    CAST(module_presentation_length AS INT) AS module_presentation_length,
    ingestion_timestamp,
    ingestion_date
FROM oulad.oulad_bronze.courses_bronze;

