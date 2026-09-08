CREATE OR REPLACE TABLE oulad.oulad_silver.vle_silver AS
SELECT DISTINCT
    CAST(id_site AS INT) AS id_site,
    UPPER(TRIM(code_module)) AS code_module,
    UPPER(TRIM(code_presentation)) AS code_presentation,
    LOWER(TRIM(activity_type)) AS activity_type,
    TRY_CAST(NULLIF(week_from, '?') AS INT) AS week_from,
    TRY_CAST(NULLIF(week_to, '?') AS INT) AS week_to,
    ingestion_timestamp,
    ingestion_date
FROM oulad.oulad_bronze.vle_bronze;

