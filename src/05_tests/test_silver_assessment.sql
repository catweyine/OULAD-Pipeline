--====================================
-- Silver DQ: Assessments
--====================================
-- Silver is built by FILTERING and the table carries no constraints, so the
-- MERGE's WHERE clause is the only thing standing between bad data and Silver.
-- That gives this script three jobs:
--   TRANSFORM   did the filter hold? Nothing else enforces these.
--   LIVE        rules no filter covers: the orphan check is commented out of
--               the MERGE, and no weight total is checked anywhere.
--   REFUSED     a filter drops rows with no record. tmp_assessments_refused
--               reconstructs what a quarantine table would have held.
--====================================


-- Rows that ARE in Silver, with their parent lookups attached.
CREATE OR REPLACE TEMP VIEW tmp_assessments_silver_eval AS
WITH course_keys AS (
    -- DISTINCT prevents repeated parent keys from multiplying assessment rows.
    SELECT DISTINCT code_module, code_presentation, module_presentation_length
    FROM oulad.oulad_silver.courses_silver),
coursework_totals AS (
    -- One row per presentation, so the join below cannot multiply rows.
    -- Exams excluded: they carry their own weight of 100, separate from the
    -- coursework total.
    SELECT code_module, code_presentation, SUM(weight) AS coursework_total
    FROM oulad.oulad_silver.assessments_silver
    WHERE assessment_type <> 'Exam'
    GROUP BY code_module, code_presentation)

SELECT a.*,
    COUNT(*) OVER (PARTITION BY a.id_assessment) AS key_occurrences,
    c.code_module AS matched_module,
    c.module_presentation_length,
    w.coursework_total
FROM oulad.oulad_silver.assessments_silver a
LEFT JOIN course_keys c
    ON  a.code_module = c.code_module
    AND a.code_presentation = c.code_presentation
LEFT JOIN coursework_totals w
    ON  a.code_module = w.code_module
    AND a.code_presentation = w.code_presentation;


-- Rows that did NOT reach Silver. This replaces a quarantine table.
--
-- The membership test is derived from the OUTCOME, not the rules: a Bronze key
-- absent from Silver was refused, whatever the reason, and that cannot drift
-- from the MERGE. The reason column DOES restate the MERGE's WHERE clause and
-- can drift; 'other_unspecified' is the alarm for that.
CREATE OR REPLACE TEMP VIEW tmp_assessments_refused AS
WITH ranked AS (
    SELECT b.*,
        CAST(b.`date` AS STRING) AS date_source,
        ROW_NUMBER() OVER (
            PARTITION BY b.id_assessment
            -- TRY_CAST so the tiebreak sorts numerically. On STRING Bronze a raw
            -- sort puts '9' above '10', which would keep a different row than
            -- the MERGE did. Accounting balances either way, but the row named
            -- as the survivor should be the row that actually survived.
            ORDER BY b.ingestion_timestamp DESC,
                     TRY_CAST(b.weight AS DOUBLE) DESC NULLS LAST,
                     TRY_CAST(b.`date` AS INT) DESC NULLS LAST
        ) AS row_num,
        MIN(CONCAT_WS('|',
                COALESCE(UPPER(TRIM(b.code_module)), '~'),
                COALESCE(UPPER(TRIM(b.code_presentation)), '~'),
                COALESCE(UPPER(TRIM(b.assessment_type)), '~'),
                COALESCE(CAST(b.`date` AS STRING), '~'),
                COALESCE(CAST(b.weight AS STRING), '~'))) OVER (PARTITION BY b.id_assessment)
          <>
        MAX(CONCAT_WS('|',
                COALESCE(UPPER(TRIM(b.code_module)), '~'),
                COALESCE(UPPER(TRIM(b.code_presentation)), '~'),
                COALESCE(UPPER(TRIM(b.assessment_type)), '~'),
                COALESCE(CAST(b.`date` AS STRING), '~'),
                COALESCE(CAST(b.weight AS STRING), '~'))) OVER (PARTITION BY b.id_assessment)
          AS key_conflict
    FROM oulad.oulad_bronze.assessments_bronze b)

-- TRY_CAST throughout, because Bronze holds these columns as STRING. Comparing
-- the raw '?' to a number yields NULL, not FALSE, so an unparseable value would
-- fall past every WHEN and land on 'other_unspecified' — the drift alarm firing
-- for a cause we already know. TRY_CAST turns it into the NULL the MERGE saw,
-- so the reason reported is the reason the row was actually refused.
SELECT r.id_assessment,
    r.code_module,
    r.code_presentation,
    r.assessment_type,
    r.date_source,
    r.weight,
    r.ingestion_timestamp,
    r.row_num,
    r.key_conflict,
    COALESCE(
        CASE WHEN TRY_CAST(r.id_assessment AS BIGINT) IS NULL    THEN 'id_missing_or_unparseable'
             WHEN TRY_CAST(r.id_assessment AS BIGINT) <= 0       THEN 'id_not_positive'
             WHEN r.key_conflict                                 THEN 'key_conflict'
             WHEN r.row_num > 1                                  THEN 'duplicate_key_dropped'
             WHEN NULLIF(TRIM(r.code_module), '') IS NULL        THEN 'module_missing'
             WHEN NULLIF(TRIM(r.code_presentation), '') IS NULL  THEN 'presentation_missing'
             WHEN UPPER(TRIM(COALESCE(r.assessment_type, ''))) NOT IN ('TMA', 'CMA', 'EXAM')
                                                                 THEN 'type_missing_or_invalid'
             WHEN TRY_CAST(r.weight AS DOUBLE) IS NULL           THEN 'weight_missing_or_unparseable'
             WHEN TRY_CAST(r.weight AS DOUBLE) < 0
                  OR TRY_CAST(r.weight AS DOUBLE) > 100          THEN 'weight_out_of_range'
             WHEN TRY_CAST(r.`date` AS INT) IS NOT NULL
                  AND (TRY_CAST(r.`date` AS INT) < 0
                       OR TRY_CAST(r.`date` AS INT) > 1000)      THEN 'date_out_of_range'
             WHEN r.ingestion_timestamp IS NULL                  THEN 'ingestion_timestamp_missing'
        END,
        'other_unspecified') AS refusal_reason
FROM ranked r
LEFT JOIN oulad.oulad_silver.assessments_silver s
    ON r.id_assessment = s.id_assessment
WHERE s.id_assessment IS NULL
   OR r.row_num > 1;


-- Calculate Silver assessment DQ statistics
-- Grain: EXACTLY ONE ROW for this DQ evaluation.
CREATE OR REPLACE TEMP VIEW tmp_assessments_silver_dq_stats AS
WITH row_metrics AS (
    SELECT COUNT(*) AS total_records,
-- TRANSFORM: the filter is the only enforcement now that the constraints
-- are gone. Six former NOT NULL columns collapse into one rule because a
-- NULL in any of them means the same thing: the filter leaked.
        COUNT_IF(
            id_assessment IS NULL
            OR code_module IS NULL
            OR code_presentation IS NULL
            OR assessment_type IS NULL
            OR weight IS NULL
            OR ingestion_timestamp IS NULL
        ) AS required_nulls,
        COUNT_IF(id_assessment <= 0)
            AS id_not_positive,
        COUNT_IF(key_occurrences > 1)
            AS duplicate_keys,
        COUNT_IF(
            assessment_type NOT IN ('TMA', 'CMA', 'Exam')
        ) AS invalid_types,
        COUNT_IF(
            ISNAN(weight)
            OR weight < 0
            OR weight > 100
        ) AS weight_out_of_range,
        COUNT_IF(
            `date` IS NOT NULL
            AND (`date` < 0 OR `date` > 1000)
        ) AS date_out_of_range,
-- LIVE: nothing upstream covers these.
        COUNT_IF(matched_module IS NULL)
            AS orphan_courses,
        COUNT_IF(
            assessment_type <> 'Exam'
            AND coursework_total IS NOT NULL
            AND ROUND(coursework_total, 6) <> 100
        ) AS weight_total_violations,
        COUNT_IF(
            assessment_type = 'Exam'
            AND weight <> 100
        ) AS exam_weight_violations,
-- EXPECTED STATES
        COUNT_IF(`date` IS NULL)
            AS date_missing,
        COUNT_IF(
            `date` IS NULL
            AND date_source IS NULL
        ) AS date_source_missing
    FROM tmp_assessments_silver_eval)

SELECT r.*,
    -- Scalar value: available course parents
    (SELECT COUNT(*)
        FROM oulad.oulad_silver.courses_silver
    ) AS course_parent_count,
    -- Scalar value: Bronze rows, for the accounting check
    (SELECT COUNT(*)
        FROM oulad.oulad_bronze.assessments_bronze
    ) AS bronze_records,
    -- Scalar value: rows the filter refused
    (SELECT COUNT(*)
        FROM tmp_assessments_refused
    ) AS refused_records
FROM row_metrics r;


-- DQ result rows
WITH all_checks AS (
    -- RECORD COUNT
    SELECT
        'COMPLETENESS' AS check_category,
        'Record Count' AS check_name,
        'TABLE' AS check_level,
        s.total_records,
        CAST(CASE WHEN s.total_records = 0 THEN 1 ELSE 0 END AS BIGINT) AS violation_count,
        'FAIL' AS severity,
        TRUE AS can_evaluate,
        'Silver assessments should contain at least one record.' AS description
    FROM tmp_assessments_silver_dq_stats s
    UNION ALL
    -- ACCOUNTING. Rows may legitimately be refused; rows may not legitimately
    -- VANISH. If this fires, rows left Bronze without reaching Silver and
    -- without appearing in the refused view, so nothing can see them.
    SELECT
        'COMPLETENESS',
        'Row Accounting Balances',
        'TABLE',
        s.bronze_records,
        CAST(CASE WHEN s.bronze_records - s.total_records - s.refused_records <> 0
                  THEN 1 ELSE 0 END AS BIGINT),
        'FAIL',
        TRUE,
        'Bronze rows must equal Silver rows plus refused rows. An imbalance means rows disappeared with no record.'
    FROM tmp_assessments_silver_dq_stats s
    UNION ALL
-- TRANSFORM: the filter held, or it did not
    SELECT
        'TRANSFORM',
        'Required Column NULL',
        'ROW',
        s.total_records,
        CAST(s.required_nulls AS BIGINT),
        'FAIL',
        TRUE,
        'id_assessment, code_module, code_presentation, assessment_type, weight and ingestion_timestamp are all required by the MERGE filter. With the NOT NULL constraints removed, that filter is the only enforcement.'
    FROM tmp_assessments_silver_dq_stats s
    UNION ALL
    SELECT
        'TRANSFORM',
        'Non-Positive id_assessment',
        'ROW',
        s.total_records,
        CAST(s.id_not_positive AS BIGINT),
        'FAIL',
        TRUE,
        'The MERGE filter requires id_assessment > 0.'
    FROM tmp_assessments_silver_dq_stats s
    UNION ALL
    SELECT
        'UNIQUENESS',
        'Duplicate id_assessment',
        'ROW',
        s.total_records,
        CAST(s.duplicate_keys AS BIGINT),
        'FAIL',
        TRUE,
        'The Silver grain is one row per assessment. No PRIMARY KEY backs this any more; the dedup in the MERGE is the only enforcement.'
    FROM tmp_assessments_silver_dq_stats s
    UNION ALL
    SELECT
        'VALIDITY',
        'Invalid Assessment Type',
        'ROW',
        s.total_records,
        CAST(s.invalid_types AS BIGINT),
        'FAIL',
        TRUE,
        'Type must be TMA, CMA or Exam after the MERGE normalises it. No CHECK constraint backs this any more.'
    FROM tmp_assessments_silver_dq_stats s
    UNION ALL
    SELECT
        'VALIDITY',
        'Weight Out of Range',
        'ROW',
        s.total_records,
        CAST(s.weight_out_of_range AS BIGINT),
        'FAIL',
        TRUE,
        'Weight must be finite and between 0 and 100. NaN is tested explicitly because it survives TRY_CAST and would pass a BETWEEN test.'
    FROM tmp_assessments_silver_dq_stats s
    UNION ALL
    SELECT
        'VALIDITY',
        'Assessment Date Out of Range',
        'ROW',
        s.total_records,
        CAST(s.date_out_of_range AS BIGINT),
        'FAIL',
        TRUE,
        'A non-NULL date must fall between 0 and 1000. These are loose corruption guards, not validated business bounds.'
    FROM tmp_assessments_silver_dq_stats s
    UNION ALL
-- LIVE: no filter, no constraint
    SELECT
        'REFERENTIAL_INTEGRITY',
        'Orphan Module Presentation',
        'ROW',
        s.total_records,
        CAST(s.orphan_courses AS BIGINT),
        'FAIL',
        s.course_parent_count > 0,
        'LIVE CHECK: the EXISTS test against courses_silver is commented out of the MERGE, so orphan assessments really do reach Silver.'
    FROM tmp_assessments_silver_dq_stats s
    UNION ALL
    SELECT
        'BUSINESS_RULE',
        'Coursework Weight Total',
        'ROW',
        s.total_records,
        CAST(s.weight_total_violations AS BIGINT),
        'WARNING',
        TRUE,
        'Coursework weights should total 100 per module presentation, exams excluded. Every weight can pass the range check while the presentation totals 87, and then every weighted score built from it is wrong with no bad value to find. Counts affected rows, not presentations.'
    FROM tmp_assessments_silver_dq_stats s
    UNION ALL
    SELECT
        'BUSINESS_RULE',
        'Exam Weight Not 100',
        'ROW',
        s.total_records,
        CAST(s.exam_weight_violations AS BIGINT),
        'WARNING',
        TRUE,
        'An assessment of type Exam should carry weight 100. A mis-typed exam dilutes every weighted score on the module.'
    FROM tmp_assessments_silver_dq_stats s
    UNION ALL
-- EXPECTED STATES
    SELECT
        'COMPLETENESS',
        'Missing Assessment Date',
        'ROW',
        s.total_records,
        CAST(s.date_missing AS BIGINT),
        'WARNING',
        TRUE,
        'Exams carry no published deadline; the source writes a question mark. Retained as NULL and never imputed, so this is expected rather than a defect.'
    FROM tmp_assessments_silver_dq_stats s
    UNION ALL
    SELECT
        'CONSISTENCY',
        'Date Source Not Captured',
        'ROW',
        s.total_records,
        CAST(s.date_source_missing AS BIGINT),
        'FAIL',
        TRUE,
        'date_source exists to tell a question mark from a blank cell after TRY_CAST has turned both into NULL. A NULL there defeats the only reason the column exists.'
    FROM tmp_assessments_silver_dq_stats s
),
-- Determine PASS / WARNING / FAIL / NOT_EVALUATED
results AS (
    SELECT *,
        CASE WHEN check_level = 'ROW' AND total_records = 0 THEN 'NOT_EVALUATED'
             WHEN NOT can_evaluate                          THEN 'NOT_EVALUATED'
             WHEN violation_count = 0                       THEN 'PASS'
             ELSE severity
        END AS status
    FROM all_checks)
-- Final standardized DQ output
SELECT
    'SILVER' AS layer_name,
    'assessments_silver' AS table_name,
    check_category,
    check_name,
    check_level,
    status,
    total_records,
    CASE WHEN status = 'NOT_EVALUATED' THEN CAST(NULL AS BIGINT)
         ELSE violation_count END AS violation_count,
    ROUND(CASE WHEN check_level = 'ROW'
                    AND status <> 'NOT_EVALUATED'
                    AND total_records > 0
               THEN CAST(violation_count AS DOUBLE) / total_records
               ELSE CAST(NULL AS DOUBLE)
          END, 4) AS violation_rate,
    CASE WHEN check_level = 'ROW' AND severity = 'WARNING' THEN CAST(0 AS DOUBLE)
         ELSE CAST(NULL AS DOUBLE) END AS warning_threshold,
    CASE WHEN check_level = 'ROW' AND severity = 'FAIL' THEN CAST(0 AS DOUBLE)
         ELSE CAST(NULL AS DOUBLE) END AS fail_threshold,
    description,
    CURRENT_TIMESTAMP() AS checked_at
FROM results;


--====================================
-- REJECTED ROWS
--====================================

-- Silver rows that break a rule. They stay in Silver; nothing here deletes.
-- One row per source row however many rules it broke, so do not add up the
-- violation counts above to predict this number.
SELECT id_assessment, code_module, code_presentation, assessment_type,
    `date`, date_source, weight, module_presentation_length, coursework_total,
    ARRAY_COMPACT(ARRAY(
        CASE WHEN id_assessment IS NULL OR code_module IS NULL
                  OR code_presentation IS NULL OR assessment_type IS NULL
                  OR weight IS NULL OR ingestion_timestamp IS NULL THEN 'required_column_null' END,
        CASE WHEN id_assessment <= 0                               THEN 'id_not_positive' END,
        CASE WHEN key_occurrences > 1                              THEN 'duplicate_id' END,
        CASE WHEN assessment_type NOT IN ('TMA','CMA','Exam')      THEN 'invalid_type' END,
        CASE WHEN ISNAN(weight) OR weight < 0 OR weight > 100      THEN 'weight_out_of_range' END,
        CASE WHEN `date` IS NOT NULL AND (`date` < 0 OR `date` > 1000) THEN 'date_out_of_range' END,
        CASE WHEN matched_module IS NULL                           THEN 'orphan_course' END,
        CASE WHEN assessment_type <> 'Exam' AND coursework_total IS NOT NULL
                  AND ROUND(coursework_total, 6) <> 100            THEN 'coursework_weight_total' END,
        CASE WHEN assessment_type = 'Exam' AND weight <> 100       THEN 'exam_weight_not_100' END,
        CASE WHEN `date` IS NULL AND date_source IS NULL           THEN 'date_source_not_captured' END
    )) AS reject_reasons
FROM tmp_assessments_silver_eval
WHERE id_assessment IS NULL OR code_module IS NULL OR code_presentation IS NULL
   OR assessment_type IS NULL OR weight IS NULL OR ingestion_timestamp IS NULL
   OR id_assessment <= 0
   OR key_occurrences > 1
   OR assessment_type NOT IN ('TMA','CMA','Exam')
   OR ISNAN(weight) OR weight < 0 OR weight > 100
   OR (`date` IS NOT NULL AND (`date` < 0 OR `date` > 1000))
   OR matched_module IS NULL
   OR (assessment_type <> 'Exam' AND coursework_total IS NOT NULL AND ROUND(coursework_total,6) <> 100)
   OR (assessment_type = 'Exam' AND weight <> 100)
   OR (`date` IS NULL AND date_source IS NULL)
ORDER BY id_assessment;


-- Rows the filter refused. This is what a quarantine table would have held.
-- other_unspecified MUST be 0: anything else means a row was refused for a
-- reason tmp_assessments_refused does not know about, so the diagnosis has
-- drifted from the MERGE's WHERE clause.
SELECT refusal_reason, COUNT(*) AS rows_refused
FROM tmp_assessments_refused
GROUP BY refusal_reason
ORDER BY rows_refused DESC;

-- The refused rows themselves, so they can be corrected at source.
SELECT * FROM tmp_assessments_refused
ORDER BY refusal_reason, id_assessment
LIMIT 200;
