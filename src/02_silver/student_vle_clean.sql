-- Create the clean (silver) table for student_vle
CREATE TABLE IF NOT EXISTS oulad.oulad_silver.student_vle_silver (
    code_module        STRING,
    code_presentation   STRING,
    id_student           INT,
    id_site              INT,
    date                 INT,
    sum_click            INT,
    ingestion_timestamp  TIMESTAMP,
    ingestion_date       DATE,
    CONSTRAINT student_vle_silver_pk PRIMARY KEY (code_module, code_presentation, id_student, id_site, date)
)
USING DELTA;

-- Merge cleaned data from bronze to capture idempotency
-- CHANGED: multiple Bronze rows sharing the same key represent separate visits
-- to the same resource on the same day (confirmed: they share one ingestion_timestamp,
-- meaning they were loaded together as distinct source rows, not re-ingested copies
-- from separate pipeline runs). sum_click is now SUMMED across all visits to get the
-- true daily total, instead of picking one row via ROW_NUMBER and discarding the rest.
MERGE INTO oulad.oulad_silver.student_vle_silver AS target
USING (
    SELECT
        UPPER(TRIM(code_module))       AS code_module,
        UPPER(TRIM(code_presentation)) AS code_presentation,
        id_student,
        id_site,
        date,
        SUM(sum_click)                 AS sum_click,
        MAX(ingestion_timestamp)       AS ingestion_timestamp,
        CAST(MAX(ingestion_timestamp) AS DATE) AS ingestion_date
    FROM oulad.oulad_bronze.student_vle_bronze
    WHERE code_module IS NOT NULL
      AND code_presentation IS NOT NULL
      AND id_student IS NOT NULL
      AND id_site IS NOT NULL
      AND date IS NOT NULL
      AND sum_click > 0
      AND ingestion_timestamp IS NOT NULL
    GROUP BY
        UPPER(TRIM(code_module)),
        UPPER(TRIM(code_presentation)),
        id_student,
        id_site,
        date
) AS source
ON  target.code_module = source.code_module
AND target.code_presentation = source.code_presentation
AND target.id_student = source.id_student
AND target.id_site = source.id_site
AND target.date = source.date
WHEN MATCHED THEN
    UPDATE SET
        target.sum_click           = source.sum_click,
        target.ingestion_timestamp = source.ingestion_timestamp,
        target.ingestion_date      = source.ingestion_date
WHEN NOT MATCHED THEN
    INSERT (code_module, code_presentation, id_student, id_site, date, sum_click, ingestion_timestamp, ingestion_date)
    VALUES (source.code_module, source.code_presentation, source.id_student, source.id_site, source.date, source.sum_click, source.ingestion_timestamp, source.ingestion_date);