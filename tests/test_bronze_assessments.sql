--============================
-- Bronze DQ: Assessments
--=============================


--Note: Remove /* */ if you want to save the query results in a table
-- Both DQ (bronze) for assessments and student assessments can be stored in 1 table.
-- When the table is created, it saves the results every run.
-- The only issue here is that the distinction of each run can be based only in timestamp/checked_at [last column]. Suggested fix: Add another column, run_id, before layer_name and use parameter in Jobs to track the run_id.


-- Create DQ Check Bronze Table
/*CREATE TABLE IF NOT EXISTS oulad.oulad_quality.dq_check_results_bronze1 (
    layer_name STRING NOT NULL,
    table_name STRING NOT NULL,
    check_category STRING NOT NULL,
    check_name STRING NOT NULL,
    check_level STRING NOT NULL,
    status STRING NOT NULL,
    total_records BIGINT,
    violation_count BIGINT,
    violation_rate DOUBLE COMMENT 'Fraction 0-1 for ROW checks; NULL for TABLE or unevaluated checks',
    warning_threshold DOUBLE COMMENT 'Fraction 0-1; NULL means no warning threshold for this check',
    fail_threshold DOUBLE COMMENT 'Fraction 0-1; NULL means no failure threshold for this check',
    description STRING,
    checked_at TIMESTAMP NOT NULL
)
USING DELTA
TBLPROPERTIES ('delta.appendOnly' = 'true');


-- Count each issue once, then construct the check results from those counts.
-- Failures overlap between checks: do not sum them to obtain distinct bad rows.
INSERT INTO oulad.oulad_quality.dq_check_results_bronze1
  ( layer_name, table_name, check_category, check_name, check_level,
   status, total_records, violation_count, violation_rate,
   warning_threshold, fail_threshold, description, checked_at)
*/
WITH base AS (
    SELECT * FROM oulad.oulad_bronze.assessments_bronze
    -- Add a filter here only if evaluating a specific ingestion batch.
), normalized AS (
    -- Normalization affects this query only. Raw Bronze values remain intact.
    -- The regex trims tabs/newlines as well as ordinary surrounding spaces.
    SELECT
        NULLIF(REGEXP_REPLACE(CAST(id_assessment AS STRING), r'^\s+|\s+$', ''), '') AS id_text,
        NULLIF(UPPER(REGEXP_REPLACE(CAST(code_module AS STRING), r'^\s+|\s+$', '')), '') AS module_text,
        NULLIF(UPPER(REGEXP_REPLACE(CAST(code_presentation AS STRING), r'^\s+|\s+$', '')), '') AS presentation_text,
        NULLIF(UPPER(REGEXP_REPLACE(CAST(assessment_type AS STRING), r'^\s+|\s+$', '')), '') AS type_text,
        NULLIF(REGEXP_REPLACE(CAST(`date` AS STRING), r'^\s+|\s+$', ''), '') AS date_text,
        NULLIF(REGEXP_REPLACE(CAST(weight AS STRING), r'^\s+|\s+$', ''), '') AS weight_text,
        ingestion_timestamp, ingestion_date
    FROM base
), parsed AS (
    SELECT *,
        TRY_CAST(id_text AS BIGINT) AS assessment_id,
        TRY_CAST(date_text AS INT) AS assessment_day,
        TRY_CAST(weight_text AS DOUBLE) AS weight_num
    FROM normalized
), normalized_parents AS (
    SELECT
        NULLIF(UPPER(REGEXP_REPLACE(CAST(code_module AS STRING), r'^\s+|\s+$', '')), '') AS module_text,
        NULLIF(UPPER(REGEXP_REPLACE(CAST(code_presentation AS STRING), r'^\s+|\s+$', '')), '') AS presentation_text
    FROM oulad.oulad_bronze.courses_bronze
), parent_keys AS (
    -- DISTINCT prevents repeated parent keys from multiplying assessment rows.
    SELECT DISTINCT module_text, presentation_text
    FROM normalized_parents
    WHERE module_text IS NOT NULL AND presentation_text IS NOT NULL
), parent_stats AS (
    SELECT COUNT(*) AS parent_keys FROM parent_keys
), evaluated AS (
    SELECT a.*, c.module_text AS matched_module
    FROM parsed a
    LEFT JOIN parent_keys c
      ON a.module_text = c.module_text
     AND a.presentation_text = c.presentation_text
), metrics AS (
    SELECT
        COUNT(*) AS total_records,
        COUNT_IF(id_text IS NULL) AS missing_ids,
        COUNT_IF(id_text IS NOT NULL AND assessment_id IS NULL) AS invalid_ids,
        COUNT_IF(module_text IS NULL) AS missing_modules,
        COUNT_IF(presentation_text IS NULL) AS missing_presentations,
        COUNT_IF(ingestion_timestamp IS NULL OR ingestion_date IS NULL) AS missing_metadata,
        COUNT_IF(type_text IS NULL OR type_text NOT IN ('TMA', 'CMA', 'EXAM')) AS invalid_types,
        COUNT_IF(date_text IS NULL OR date_text = '?') AS missing_dates,
        COUNT_IF(date_text IS NOT NULL AND date_text <> '?' AND assessment_day IS NULL) AS invalid_dates,
        COUNT_IF(weight_text IS NULL) AS missing_weights,
        COUNT_IF(weight_text IS NOT NULL AND weight_num IS NULL) AS invalid_weights,
        COUNT_IF(ISNAN(weight_num) OR weight_num < 0 OR weight_num > 100) AS out_of_range_weights,
        COUNT_IF(module_text IS NOT NULL AND presentation_text IS NOT NULL
                 AND matched_module IS NULL) AS unknown_courses
    FROM evaluated
), duplicate_groups AS (
    -- Only parseable IDs enter the duplicate-key check. Invalid/missing IDs
    -- are already recorded by their own checks.
    SELECT assessment_id, COUNT(*) AS record_count
    FROM parsed
    WHERE assessment_id IS NOT NULL
    GROUP BY assessment_id
    HAVING COUNT(*) > 1
), duplicate_stats AS (
    SELECT COALESCE(SUM(record_count - 1), 0) AS excess_rows
    FROM duplicate_groups
), all_checks AS (
    SELECT 'COMPLETENESS' AS check_category,
           'Record Count' AS check_name,
           'TABLE' AS check_level,
           m.total_records AS total_records,
           IF(m.total_records = 0, 1, 0) AS violation_count,
           CAST(NULL AS DOUBLE) AS warning_threshold,
           CAST(0 AS DOUBLE) AS fail_threshold,
           'Bronze assessments must contain at least one record.' AS description
    FROM metrics m CROSS JOIN duplicate_stats d CROSS JOIN parent_stats p
    UNION ALL
    SELECT 'COMPLETENESS',
           'Missing id_assessment',
           'ROW',
           m.total_records,
           m.missing_ids,
           CAST(NULL AS DOUBLE),
           CAST(0 AS DOUBLE),
           'Assessment IDs must not be NULL or blank; missing IDs prevent reliable identification.'
    FROM metrics m CROSS JOIN duplicate_stats d CROSS JOIN parent_stats p
    UNION ALL
    SELECT 'VALIDITY',
           'Invalid id_assessment Format',
           'ROW',
           m.total_records,
           m.invalid_ids,
           CAST(NULL AS DOUBLE),
           CAST(0 AS DOUBLE),
           'Supplied assessment IDs must parse as BIGINT; this does not enforce an observed minimum or maximum ID.'
    FROM metrics m CROSS JOIN duplicate_stats d CROSS JOIN parent_stats p
    UNION ALL
    SELECT 'COMPLETENESS',
           'Missing code_module',
           'ROW',
           m.total_records,
           m.missing_modules,
           CAST(NULL AS DOUBLE),
           CAST(0 AS DOUBLE),
           'Module code must be supplied so the assessment can be assigned to a module.'
    FROM metrics m CROSS JOIN duplicate_stats d CROSS JOIN parent_stats p
    UNION ALL
    SELECT 'COMPLETENESS',
           'Missing code_presentation',
           'ROW',
           m.total_records,
           m.missing_presentations,
           CAST(NULL AS DOUBLE),
           CAST(0 AS DOUBLE),
           'Presentation code must be supplied so the assessment can be assigned to the correct presentation.'
    FROM metrics m CROSS JOIN duplicate_stats d CROSS JOIN parent_stats p
    UNION ALL
    SELECT 'COMPLETENESS',
           'Missing Ingestion Metadata',
           'ROW',
           m.total_records,
           m.missing_metadata,
           CAST(NULL AS DOUBLE),
           CAST(0 AS DOUBLE),
           'Each record must contain ingestion_timestamp and ingestion_date for source tracing.'
    FROM metrics m CROSS JOIN duplicate_stats d CROSS JOIN parent_stats p
    UNION ALL
    SELECT 'UNIQUENESS',
           'Duplicate Assessment IDs',
           'ROW',
           m.total_records,
           d.excess_rows,
           CAST(0 AS DOUBLE),
           CAST(NULL AS DOUBLE),
           'Counts excess rows per parsed assessment ID, not duplicate groups. Silver must resolve duplicates; repeated deliveries can also cause this count.'
    FROM metrics m CROSS JOIN duplicate_stats d CROSS JOIN parent_stats p
    UNION ALL
    SELECT 'VALIDITY',
           'Assessment Type Domain',
           'ROW',
           m.total_records,
           m.invalid_types,
           CAST(0 AS DOUBLE),
           CAST(NULL AS DOUBLE),
           'After case and whitespace normalization, types should be TMA, CMA or Exam. Unknown types affect assessment grouping.'
    FROM metrics m CROSS JOIN duplicate_stats d CROSS JOIN parent_stats p
    UNION ALL
    SELECT 'VALIDITY',
           'Invalid Assessment Date Format',
           'ROW',
           m.total_records,
           m.invalid_dates,
           CAST(0 AS DOUBLE),
           CAST(NULL AS DOUBLE),
           'Supplied dates must parse as integer day offsets. NULL, blank and ? are recognized as missing; negative offsets are not rejected by this format check.'
    FROM metrics m CROSS JOIN duplicate_stats d CROSS JOIN parent_stats p
    UNION ALL
    SELECT 'COMPLETENESS',
           'Missing Assessment Date',
           'ROW',
           m.total_records,
           m.missing_dates,
           CAST(0 AS DOUBLE),
           CAST(NULL AS DOUBLE),
           'Missing deadlines prevent lateness calculation but do not make the entire assessment unusable. Missing final-exam deadlines are a documented source case.'
    FROM metrics m CROSS JOIN duplicate_stats d CROSS JOIN parent_stats p
    UNION ALL
    SELECT 'COMPLETENESS',
           'Missing Assessment Weight',
           'ROW',
           m.total_records,
           m.missing_weights,
           CAST(NULL AS DOUBLE),
           CAST(0 AS DOUBLE),
           'Project policy: weight is required for complete weighted calculations. This severity is a project decision, not proof that missing weights never occur.'
    FROM metrics m CROSS JOIN duplicate_stats d CROSS JOIN parent_stats p
    UNION ALL
    SELECT 'VALIDITY',
           'Invalid Assessment Weight Format',
           'ROW',
           m.total_records,
           m.invalid_weights,
           CAST(NULL AS DOUBLE),
           CAST(0 AS DOUBLE),
           'Supplied weight must parse as DOUBLE; parsing failures cannot be used in weighted calculations.'
    FROM metrics m CROSS JOIN duplicate_stats d CROSS JOIN parent_stats p
    UNION ALL
    SELECT 'BUSINESS_RULE',
           'Assessment Weight Range',
           'ROW',
           m.total_records,
           m.out_of_range_weights,
           CAST(NULL AS DOUBLE),
           CAST(0 AS DOUBLE),
           'Percentage weights must be finite and between 0 and 100 inclusive; invalid values distort weighted calculations. This is not a check that all weights sum to 100.'
    FROM metrics m CROSS JOIN duplicate_stats d CROSS JOIN parent_stats p
    UNION ALL
    SELECT 'COMPLETENESS',
           'Course Reference Available',
           'TABLE',
           p.parent_keys,
           IF(p.parent_keys = 0, 1, 0),
           CAST(NULL AS DOUBLE),
           CAST(0 AS DOUBLE),
           'At least one complete module-presentation key must be available in courses_bronze before checking relationships.'
    FROM metrics m CROSS JOIN duplicate_stats d CROSS JOIN parent_stats p
    UNION ALL
    SELECT 'REFERENTIAL_INTEGRITY',
           'Unknown Module Presentation',
           'ROW',
           m.total_records,
           m.unknown_courses,
           CAST(0 AS DOUBLE),
           CAST(NULL AS DOUBLE),
           'Complete assessment module-presentation keys must match a normalized Bronze course key. Missing assessment key fields are counted separately.'
    FROM metrics m CROSS JOIN duplicate_stats d CROSS JOIN parent_stats p
), measured AS (
    SELECT c.*,
        ROUND(CASE WHEN check_level = 'ROW' AND total_records > 0
                  AND NOT (check_name = 'Unknown Module Presentation' AND p.parent_keys = 0)
             THEN CAST(violation_count AS DOUBLE) / total_records
        END,4) AS violation_rate,
        CASE WHEN check_name = 'Unknown Module Presentation' AND p.parent_keys = 0
             THEN false ELSE true END AS reference_ready
    FROM all_checks c CROSS JOIN parent_stats p)
SELECT  'BRONZE', 'assessments', check_category, check_name, check_level,
    CASE
        WHEN check_level = 'TABLE' THEN IF(violation_count > 0, 'FAIL', 'PASS')
        WHEN total_records = 0 OR NOT reference_ready THEN 'NOT_EVALUATED'
        WHEN fail_threshold IS NOT NULL AND violation_rate > fail_threshold THEN 'FAIL'
        WHEN warning_threshold IS NOT NULL AND violation_rate > warning_threshold THEN 'WARNING'
        ELSE 'PASS'
    END AS status,
    total_records,
    CASE WHEN NOT reference_ready THEN CAST(NULL AS BIGINT) ELSE violation_count END,
    violation_rate, warning_threshold, fail_threshold, description,
    CURRENT_TIMESTAMP()
FROM measured;