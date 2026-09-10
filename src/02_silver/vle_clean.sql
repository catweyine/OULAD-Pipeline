CREATE TABLE IF NOT EXISTS oulad.oulad_silver.vle_silver (
    id_site INT,
    code_module STRING,
    code_presentation STRING,
    activity_type STRING,
    week_from INT,
    week_to INT,
    ingestion_timestamp TIMESTAMP,
    ingestion_date DATE
)
USING DELTA;

MERGE INTO oulad.oulad_silver.vle_silver AS target
USING (
    SELECT
        CAST(id_site AS INT) AS id_site,
        UPPER(TRIM(code_module)) AS code_module,
        UPPER(TRIM(code_presentation)) AS code_presentation,
        LOWER(TRIM(activity_type)) AS activity_type,
        TRY_CAST(NULLIF(week_from, '?') AS INT) AS week_from,
        TRY_CAST(NULLIF(week_to, '?') AS INT) AS week_to,
        ingestion_timestamp,
        ingestion_date
    FROM oulad.oulad_bronze.vle_bronze
    WHERE id_site IS NOT NULL
      AND code_module IS NOT NULL
      AND code_presentation IS NOT NULL
      AND activity_type IS NOT NULL
) AS source
ON target.id_site = source.id_site

WHEN MATCHED THEN
UPDATE SET
    target.code_module = source.code_module,
    target.code_presentation = source.code_presentation,
    target.activity_type = source.activity_type,
    target.week_from = source.week_from,
    target.week_to = source.week_to,
    target.ingestion_timestamp = source.ingestion_timestamp,
    target.ingestion_date = source.ingestion_date

WHEN NOT MATCHED THEN
INSERT (
    id_site,
    code_module,
    code_presentation,
    activity_type,
    week_from,
    week_to,
    ingestion_timestamp,
    ingestion_date
)
VALUES (
    source.id_site,
    source.code_module,
    source.code_presentation,
    source.activity_type,
    source.week_from,
    source.week_to,
    source.ingestion_timestamp,
    source.ingestion_date
);