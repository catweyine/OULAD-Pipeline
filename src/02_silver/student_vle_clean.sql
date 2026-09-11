-- ============================================================================
-- STEP 1: Create the Silver Table with sum_click in the Composite Primary Key
-- ============================================================================

-- Drop table to ensure schema matches current definition (removes old duplicate_rank column)
DROP TABLE IF EXISTS oulad.oulad_silver.student_vle_silver;

CREATE TABLE IF NOT EXISTS oulad.oulad_silver.student_vle_silver (
    code_module              STRING,
    code_presentation         STRING,
    id_student                INT,
    id_site                   INT,
    date                      INT,
    sum_click                  INT,
    ingestion_timestamp        TIMESTAMP,
    ingestion_date             DATE,

    -- Column Quality Flags
    is_code_module_null         BOOLEAN,
    is_code_presentation_null    BOOLEAN,
    is_id_student_null           BOOLEAN,
    is_id_site_null               BOOLEAN,
    is_date_null                  BOOLEAN,
    is_sum_click_null           BOOLEAN,
    is_ingestion_timestamp_null    BOOLEAN,

    -- Business Rule Flags
    is_sum_click_negative       BOOLEAN,
    has_null_primary_key        BOOLEAN,

    -- Duplicate & Validity Flags
    duplicate_occurrence_count  INT,       -- Number of identical 6-column records in Bronze
    is_row_valid                    BOOLEAN,   -- TRUE if fully clean and non-negative
    dq_flags                         STRING,    -- Summary string of all triggered flags

    -- Primary Key constraint includes sum_click to prevent dropping distinct click events
    CONSTRAINT student_vle_silver_pk 
        PRIMARY KEY (code_module, code_presentation, id_student, id_site, date, sum_click)
)
USING DELTA;


-- ============================================================================
-- STEP 2: MERGE Execution with sum_click in Deduplication & Join Conditions
-- ============================================================================
MERGE INTO oulad.oulad_silver.student_vle_silver AS target
USING (
    WITH normalized_bronze AS (
        -- Clean string casing and whitespace prior to deduplication
        SELECT 
            UPPER(TRIM(code_module))       AS code_module,
            UPPER(TRIM(code_presentation)) AS code_presentation,
            id_student,
            id_site,
            date,
            sum_click,
            ingestion_timestamp,
            CAST(ingestion_timestamp AS DATE) AS ingestion_date
        FROM oulad.oulad_bronze.student_vle_bronze
    ),
    deduplicated_bronze AS (
        SELECT 
            *,
            -- Count exact duplicate occurrences across ALL 6 attributes (including sum_click)
            COUNT(*) OVER (
                PARTITION BY 
                    COALESCE(code_module, 'MISSING'), 
                    COALESCE(code_presentation, 'MISSING'), 
                    COALESCE(id_student, -1), 
                    COALESCE(id_site, -1), 
                    COALESCE(date, -999),
                    COALESCE(sum_click, -999999)
            ) AS duplicate_occurrence_count,
            
            -- Deduplicate exact re-ingestions by ordering by latest ingestion timestamp
            ROW_NUMBER() OVER (
                PARTITION BY 
                    COALESCE(code_module, 'MISSING'), 
                    COALESCE(code_presentation, 'MISSING'), 
                    COALESCE(id_student, -1), 
                    COALESCE(id_site, -1), 
                    COALESCE(date, -999),
                    COALESCE(sum_click, -999999)
                ORDER BY ingestion_timestamp DESC
            ) AS row_num
        FROM normalized_bronze
    )
    SELECT
        code_module,
        code_presentation,
        id_student,
        id_site,
        date,
        sum_click,
        ingestion_timestamp,
        ingestion_date,
        duplicate_occurrence_count,

        -- Column NULL Flags
        code_module IS NULL             AS is_code_module_null,
        code_presentation IS NULL       AS is_code_presentation_null,
        id_student IS NULL              AS is_id_student_null,
        id_site IS NULL                 AS is_id_site_null,
        date IS NULL                    AS is_date_null,
        sum_click IS NULL               AS is_sum_click_null,
        ingestion_timestamp IS NULL     AS is_ingestion_timestamp_null,

        -- Business Rule Checks
        (sum_click IS NOT NULL AND sum_click < 0) AS is_sum_click_negative,
        (code_module IS NULL OR code_presentation IS NULL OR id_student IS NULL OR id_site IS NULL OR date IS NULL OR sum_click IS NULL) AS has_null_primary_key,

        -- Master Row Validity Flag
        NOT (
            code_module IS NULL
            OR code_presentation IS NULL
            OR id_student IS NULL
            OR id_site IS NULL
            OR date IS NULL
            OR sum_click IS NULL
            OR sum_click < 0
            OR ingestion_timestamp IS NULL
        ) AS is_row_valid,

        -- Aggregated Quality Audit String
        concat_ws(', ',
            CASE WHEN code_module IS NULL THEN 'code_module_null' END,
            CASE WHEN code_presentation IS NULL THEN 'code_presentation_null' END,
            CASE WHEN id_student IS NULL THEN 'id_student_null' END,
            CASE WHEN id_site IS NULL THEN 'id_site_null' END,
            CASE WHEN date IS NULL THEN 'date_null' END,
            CASE WHEN sum_click IS NULL THEN 'sum_click_null' END,
            CASE WHEN sum_click < 0 THEN 'sum_click_negative' END,
            CASE WHEN ingestion_timestamp IS NULL THEN 'ingestion_timestamp_null' END,
            CASE WHEN duplicate_occurrence_count > 1 THEN 'exact_duplicate_found' END
        ) AS dq_flags
    FROM deduplicated_bronze
    WHERE row_num = 1
) AS source

-- NULL-safe join condition (<=>) across all key columns including sum_click
ON  target.code_module <=> source.code_module
AND target.code_presentation <=> source.code_presentation
AND target.id_student <=> source.id_student
AND target.id_site <=> source.id_site
AND target.date <=> source.date
AND target.sum_click <=> source.sum_click

WHEN MATCHED THEN
    UPDATE SET
        target.ingestion_timestamp         = source.ingestion_timestamp,
        target.ingestion_date              = source.ingestion_date,
        target.duplicate_occurrence_count  = source.duplicate_occurrence_count,
        target.is_code_module_null         = source.is_code_module_null,
        target.is_code_presentation_null   = source.is_code_presentation_null,
        target.is_id_student_null          = source.is_id_student_null,
        target.is_id_site_null             = source.is_id_site_null,
        target.is_date_null                = source.is_date_null,
        target.is_sum_click_null           = source.is_sum_click_null,
        target.is_ingestion_timestamp_null = source.is_ingestion_timestamp_null,
        target.is_sum_click_negative       = source.is_sum_click_negative,
        target.has_null_primary_key        = source.has_null_primary_key,
        target.is_row_valid                = source.is_row_valid,
        target.dq_flags                    = source.dq_flags

WHEN NOT MATCHED THEN
    INSERT (
        code_module, code_presentation, id_student, id_site, date, sum_click,
        ingestion_timestamp, ingestion_date, duplicate_occurrence_count,
        is_code_module_null, is_code_presentation_null, is_id_student_null,
        is_id_site_null, is_date_null, is_sum_click_null,
        is_ingestion_timestamp_null, is_sum_click_negative, has_null_primary_key, 
        is_row_valid, dq_flags
    )
    VALUES (
        source.code_module, source.code_presentation, source.id_student, source.id_site, source.date, source.sum_click,
        source.ingestion_timestamp, source.ingestion_date, source.duplicate_occurrence_count,
        source.is_code_module_null, source.is_code_presentation_null, source.is_id_student_null,
        source.is_id_site_null, source.is_date_null, source.is_sum_click_null,
        source.is_ingestion_timestamp_null, source.is_sum_click_negative, source.has_null_primary_key,
        source.is_row_valid, source.dq_flags
    );

 SELECT * 
FROM oulad.oulad_silver.student_vle_silver 
WHERE is_row_valid = TRUE
LIMIT 1000;

SELECT * 
FROM oulad.oulad_silver.student_vle_silver 
WHERE duplicate_occurrence_count > 1
LIMIT 1000;

SELECT 
    code_module,
    COUNT(*) AS total_records,
    SUM(CASE WHEN duplicate_occurrence_count > 1 THEN 1 ELSE 0 END) AS duplicate_records,
    SUM(CASE WHEN is_row_valid THEN 1 ELSE 0 END) AS valid_primary_records
FROM oulad.oulad_silver.student_vle_silver
GROUP BY code_module
LIMIT 1000;