--============================
-- Bronze DQ: Assessments
--=============================
/* CREATE TABLE IF NOT EXISTS oulad.oulad_quality.dq_check_results_bronze1 (
    layer_name          STRING NOT NULL,
    table_name          STRING NOT NULL,
    check_category      STRING NOT NULL,
    check_name          STRING NOT NULL,
    check_level         STRING NOT NULL,
    status              STRING NOT NULL,
    total_records       BIGINT,
    violation_count     BIGINT,
    violation_rate      DOUBLE,
    warning_threshold   DOUBLE,
    fail_threshold      DOUBLE,
    description         STRING,
    checked_at          TIMESTAMP NOT NULL
)
USING DELTA; 
*/


-- Normalize and parse Bronze assessments
CREATE OR REPLACE TEMP VIEW tmp_assessments_parsed AS
WITH normalized AS (
    SELECT NULLIF(
            REGEXP_REPLACE(CAST(id_assessment AS STRING), r'^\s+|\s+$', ''),
            ''
        ) AS id_text,
        NULLIF(
            UPPER(REGEXP_REPLACE(CAST(code_module AS STRING), r'^\s+|\s+$', '')),
            ''
        ) AS module_text,
        NULLIF(
            UPPER(REGEXP_REPLACE(CAST(code_presentation AS STRING), r'^\s+|\s+$', '')),
            ''
        ) AS presentation_text,
        NULLIF(
            UPPER(REGEXP_REPLACE(CAST(assessment_type AS STRING), r'^\s+|\s+$', '')),
            ''
        ) AS type_text,
        NULLIF(
            REGEXP_REPLACE(CAST(`date` AS STRING), r'^\s+|\s+$', ''),
            ''
        ) AS date_text,
        NULLIF(
            REGEXP_REPLACE(CAST(weight AS STRING), r'^\s+|\s+$', ''),
            ''
        ) AS weight_text,
        ingestion_timestamp,
        ingestion_date
    FROM oulad.oulad_bronze.assessments_bronze)
SELECT
    *,
    TRY_CAST(id_text AS BIGINT) AS assessment_id,
    TRY_CAST(date_text AS INT) AS assessment_day,
    TRY_CAST(weight_text AS DOUBLE) AS weight_num
FROM normalized;

-- course parent keys for RI checks
CREATE OR REPLACE TEMP VIEW tmp_assessment_parent_keys AS
SELECT DISTINCT NULLIF(
        UPPER(REGEXP_REPLACE(CAST(code_module AS STRING), r'^\s+|\s+$', '')),
        ''
    ) AS module_text,
    NULLIF(
        UPPER(REGEXP_REPLACE(CAST(code_presentation AS STRING), r'^\s+|\s+$', '')),
        ''
    ) AS presentation_text
FROM oulad.oulad_bronze.courses_bronze
WHERE  NULLIF(
        UPPER(REGEXP_REPLACE(CAST(code_module AS STRING), r'^\s+|\s+$', '')),
        ''
    ) IS NOT NULL
AND NULLIF(
        UPPER(REGEXP_REPLACE(CAST(code_presentation AS STRING), r'^\s+|\s+$', '')),
        ''
    ) IS NOT NULL;


-- Calculate Bronze assessment DQ statistics
-- Grain: exactly one row for this DQ evaluation
CREATE OR REPLACE TEMP VIEW tmp_assessment_dq_stats AS
WITH evaluated AS (
    SELECT
        a.*,
        c.module_text AS matched_module
    FROM tmp_assessments_parsed a
    LEFT JOIN tmp_assessment_parent_keys c
        ON  a.module_text = c.module_text
        AND a.presentation_text = c.presentation_text),
row_metrics AS (
    SELECT COUNT(*) AS total_records,
        COUNT_IF(id_text IS NULL)
            AS missing_ids,
        COUNT_IF(
            id_text IS NOT NULL
            AND assessment_id IS NULL
        ) AS invalid_ids,
        COUNT_IF(module_text IS NULL)
            AS missing_modules,
        COUNT_IF(presentation_text IS NULL)
            AS missing_presentations,
        COUNT_IF(
            ingestion_timestamp IS NULL
            OR ingestion_date IS NULL
        ) AS missing_metadata,
        COUNT_IF(
            type_text IS NULL
            OR type_text NOT IN ('TMA', 'CMA', 'EXAM')
        ) AS invalid_types,
        COUNT_IF(
            date_text IS NULL
            OR date_text = '?'
        ) AS missing_dates,
        COUNT_IF(
            date_text IS NOT NULL
            AND date_text <> '?'
            AND assessment_day IS NULL
        ) AS invalid_dates,
        COUNT_IF(weight_text IS NULL)
            AS missing_weights,
        COUNT_IF(
            weight_text IS NOT NULL
            AND weight_num IS NULL
        ) AS invalid_weights,
        COUNT_IF(
            ISNAN(weight_num)
            OR weight_num < 0
            OR weight_num > 100
        ) AS out_of_range_weights,
        COUNT_IF(
            module_text IS NOT NULL
            AND presentation_text IS NOT NULL
            AND matched_module IS NULL
        ) AS unknown_courses
    FROM evaluated),

duplicate_stats AS (
    SELECT
        COALESCE(SUM(record_count - 1), 0) AS duplicate_excess_rows
    FROM (SELECT
            assessment_id,
            COUNT(*) AS record_count
        FROM tmp_assessments_parsed
        WHERE assessment_id IS NOT NULL
        GROUP BY assessment_id
        HAVING COUNT(*) > 1
    ))
SELECT r.*,
    -- scalar aggregate: exactly one value
    ( SELECT duplicate_excess_rows
        FROM duplicate_stats
    ) AS duplicate_excess_rows,

    -- number of available parent keys
    (SELECT COUNT(*)
        FROM tmp_assessment_parent_keys
    ) AS parent_keys
FROM row_metrics r;
SELECT *
FROM tmp_assessment_dq_stats;

/* INSERT INTO oulad.oulad_quality.dq_check_results_bronze1 (
    layer_name,
    table_name,
    check_category,
    check_name,
    check_level,
    status,
    total_records,
    violation_count,
    violation_rate,
    warning_threshold,
    fail_threshold,
    description,
    checked_at) */

WITH all_checks AS (
    SELECT
        'COMPLETENESS' AS check_category,
        'Record Count' AS check_name,
        'TABLE' AS check_level,
        s.total_records,
        IF(s.total_records = 0, 1, 0) AS violation_count,
        CAST(NULL AS DOUBLE) AS warning_threshold,
        CAST(0 AS DOUBLE) AS fail_threshold,
        'Bronze assessments must contain at least one record.' AS description,
        s.parent_keys
    FROM tmp_assessment_dq_stats s
    UNION ALL SELECT
        'COMPLETENESS',
        'Missing id_assessment',
        'ROW',
        s.total_records,
        s.missing_ids,
        CAST(NULL AS DOUBLE),
        CAST(0 AS DOUBLE),
        'Assessment IDs must not be NULL or blank; missing IDs prevent reliable identification.',
        s.parent_keys
    FROM tmp_assessment_dq_stats s
    UNION ALL SELECT
        'VALIDITY',
        'Invalid id_assessment Format',
        'ROW',
        s.total_records,
        s.invalid_ids,
        CAST(NULL AS DOUBLE),
        CAST(0 AS DOUBLE),
        'Supplied assessment IDs must parse as BIGINT.',
        s.parent_keys
    FROM tmp_assessment_dq_stats s
    UNION ALL SELECT
        'COMPLETENESS',
        'Missing code_module',
        'ROW',
        s.total_records,
        s.missing_modules,
        CAST(NULL AS DOUBLE),
        CAST(0 AS DOUBLE),
        'Module code must be supplied so the assessment can be assigned to a module.',
        s.parent_keys
    FROM tmp_assessment_dq_stats s
    UNION ALL SELECT
        'COMPLETENESS',
        'Missing code_presentation',
        'ROW',
        s.total_records,
        s.missing_presentations,
        CAST(NULL AS DOUBLE),
        CAST(0 AS DOUBLE),
        'Presentation code must be supplied so the assessment can be assigned to the correct presentation.',
        s.parent_keys
    FROM tmp_assessment_dq_stats s
    UNION ALL SELECT
        'COMPLETENESS',
        'Missing Ingestion Metadata',
        'ROW',
        s.total_records,
        s.missing_metadata,
        CAST(NULL AS DOUBLE),
        CAST(0 AS DOUBLE),
        'Each record must contain ingestion_timestamp and ingestion_date for source tracing.',
        s.parent_keys
    FROM tmp_assessment_dq_stats s
    UNION ALL SELECT
        'UNIQUENESS',
        'Duplicate Assessment IDs',
        'ROW',
        s.total_records,
        s.duplicate_excess_rows,
        CAST(0 AS DOUBLE),
        CAST(NULL AS DOUBLE),
        'Counts excess rows per parsed assessment ID.',
        s.parent_keys
    FROM tmp_assessment_dq_stats s
    UNION ALL SELECT
        'VALIDITY',
        'Assessment Type Domain',
        'ROW',
        s.total_records,
        s.invalid_types,
        CAST(0 AS DOUBLE),
        CAST(NULL AS DOUBLE),
        'Assessment types should be TMA, CMA or EXAM after normalization.',
        s.parent_keys
    FROM tmp_assessment_dq_stats s
    UNION ALL
    SELECT
        'VALIDITY',
        'Invalid Assessment Date Format',
        'ROW',
        s.total_records,
        s.invalid_dates,
        CAST(0 AS DOUBLE),
        CAST(NULL AS DOUBLE),
        'Supplied assessment dates must parse as integer day offsets.',
        s.parent_keys
    FROM tmp_assessment_dq_stats s
    UNION ALL SELECT
        'COMPLETENESS',
        'Missing Assessment Date',
        'ROW',
        s.total_records,
        s.missing_dates,
        CAST(0 AS DOUBLE),
        CAST(NULL AS DOUBLE),
        'Missing assessment deadlines prevent lateness calculations.',
        s.parent_keys
    FROM tmp_assessment_dq_stats s
    UNION ALL  SELECT
        'COMPLETENESS',
        'Missing Assessment Weight',
        'ROW',
        s.total_records,
        s.missing_weights,
        CAST(NULL AS DOUBLE),
        CAST(0 AS DOUBLE),
        'Assessment weight is required for complete weighted calculations.',
        s.parent_keys
    FROM tmp_assessment_dq_stats s
    UNION ALL SELECT
        'VALIDITY',
        'Invalid Assessment Weight Format',
        'ROW',
        s.total_records,
        s.invalid_weights,
        CAST(NULL AS DOUBLE),
        CAST(0 AS DOUBLE),
        'Supplied weight must parse as DOUBLE.',
        s.parent_keys

    FROM tmp_assessment_dq_stats 
    UNION ALL SELECT
        'BUSINESS_RULE',
        'Assessment Weight Range',
        'ROW',
        s.total_records,
        s.out_of_range_weights,
        CAST(NULL AS DOUBLE),
        CAST(0 AS DOUBLE),
        'Assessment weight must be finite and between 0 and 100.',
        s.parent_keys

    FROM tmp_assessment_dq_stats s
    UNION ALL SELECT
        'COMPLETENESS',
        'Course Reference Available',
        'TABLE',
        s.parent_keys AS total_records,
        IF(s.parent_keys = 0, 1, 0),
        CAST(NULL AS DOUBLE),
        CAST(0 AS DOUBLE),
        'At least one complete module-presentation key must exist before checking RI.',
        s.parent_keys
    FROM tmp_assessment_dq_stats s
    UNION ALL
    SELECT
        'REFERENTIAL_INTEGRITY',
        'Unknown Module Presentation',
        'ROW',
        s.total_records,
        s.unknown_courses,
        CAST(0 AS DOUBLE),
        CAST(NULL AS DOUBLE),
        'Complete assessment module-presentation keys must match a Bronze course key.',
        s.parent_keys

    FROM tmp_assessment_dq_stats s
),
measured AS (
    SELECT c.*,
        ROUND( CASE WHEN check_level = 'ROW'
                    AND total_records > 0
                    AND NOT (
                        check_name = 'Unknown Module Presentation'
                        AND parent_keys = 0)
                THEN CAST(violation_count AS DOUBLE) / total_records
            END,4) AS violation_rate,

        CASE WHEN check_name = 'Unknown Module Presentation'
       AND parent_keys = 0
            THEN FALSE
            ELSE TRUE
        END AS reference_ready
    FROM all_checks c)
SELECT 'BRONZE' AS layer_name,
    'assessments' AS table_name,
    check_category,
    check_name,
    check_level,
    CASE WHEN check_level = 'TABLE'
            THEN IF(violation_count > 0, 'FAIL', 'PASS')
        WHEN total_records = 0
             OR NOT reference_ready
            THEN 'NOT_EVALUATED'
        WHEN fail_threshold IS NOT NULL
             AND violation_rate > fail_threshold
            THEN 'FAIL'
        WHEN warning_threshold IS NOT NULL
             AND violation_rate > warning_threshold
            THEN 'WARNING'
        ELSE 'PASS'
    END AS status,
    total_records,
    CASE
        WHEN NOT reference_ready
        THEN CAST(NULL AS BIGINT)
        ELSE violation_count
    END AS violation_count,
    violation_rate,
    warning_threshold,
    fail_threshold,
    description,
    CURRENT_TIMESTAMP() AS checked_at
FROM measured;