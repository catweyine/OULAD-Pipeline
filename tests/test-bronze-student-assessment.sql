--====================================
-- Bronze DQ: Student Assessments
--====================================
/*CREATE TABLE IF NOT EXISTS oulad.oulad_quality.dq_check_results_bronze1 (
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
-- STEP 1Normalize and parse Bronze student assessments

CREATE OR REPLACE TEMP VIEW tmp_student_assessment_parsed AS
WITH normalized AS ( SELECT NULLIF(
            REGEXP_REPLACE(
                CAST(id_assessment AS STRING),
                r'^\s+|\s+$',''), '') AS assessment_id_text,
        NULLIF( REGEXP_REPLACE(
                CAST(id_student AS STRING),
                r'^\s+|\s+$', '' ),'') AS student_id_text,
        NULLIF( REGEXP_REPLACE(
                CAST(date_submitted AS STRING),
                r'^\s+|\s+$','' ),'' ) AS date_text,
        NULLIF(REGEXP_REPLACE(
                CAST(is_banked AS STRING),
                r'^\s+|\s+$',''),  '' ) AS banked_text,
        NULLIF( REGEXP_REPLACE(
                CAST(score AS STRING),
                r'^\s+|\s+$',''),'') AS score_text,
        ingestion_timestamp,
        ingestion_date
    FROM oulad.oulad_bronze.student_assessment_bronze)

SELECT *,
    TRY_CAST(assessment_id_text AS BIGINT) AS assessment_id,
    TRY_CAST(student_id_text AS BIGINT) AS student_id,
    TRY_CAST(date_text AS INT) AS submitted_day,
    TRY_CAST(banked_text AS INT) AS banked_value,
    TRY_CAST(score_text AS DOUBLE) AS score_value
FROM normalized;

-- assessment parent mappings
-- Grain:
-- One row per assessment_id

CREATE OR REPLACE TEMP VIEW tmp_student_assessment_assessment_keys AS
WITH assessment_parent_values AS (
    SELECT DISTINCT
        TRY_CAST(REGEXP_REPLACE(
                CAST(id_assessment AS STRING),
                r'^\s+|\s+$','') AS BIGINT) AS assessment_id,
        UPPER(  NULLIF( REGEXP_REPLACE(
                    CAST(code_module AS STRING),
                    r'^\s+|\s+$','' ),'')) AS code_module,
        UPPER( NULLIF( REGEXP_REPLACE(
                    CAST(code_presentation AS STRING),
                    r'^\s+|\s+$', ''),'')) AS code_presentation
    FROM oulad.oulad_bronze.assessments_bronze)

SELECT assessment_id,
    COUNT(*) AS mapping_count,
    -- Used only when mapping_count = 1
    MIN(code_module) AS code_module,
    MIN(code_presentation) AS code_presentation
FROM assessment_parent_values
WHERE assessment_id IS NOT NULL
GROUP BY assessment_id;

-- valid enrollment keys
-- Grain:One row per student + module + presentation
CREATE OR REPLACE TEMP VIEW tmp_student_assessment_student_keys AS
WITH student_parent_values AS (
    SELECT DISTINCT TRY_CAST( REGEXP_REPLACE(
                CAST(id_student AS STRING),
                r'^\s+|\s+$','') AS BIGINT) AS student_id,
        UPPER(NULLIF(REGEXP_REPLACE(
                    CAST(code_module AS STRING),
                    r'^\s+|\s+$', '' ),'')) AS code_module,
        UPPER( NULLIF( REGEXP_REPLACE(
                    CAST(code_presentation AS STRING),
                    r'^\s+|\s+$',''),'')) AS code_presentation
    FROM oulad.oulad_bronze.student_info_bronze)

SELECT student_id, code_module, code_presentation
FROM student_parent_values
WHERE student_id IS NOT NULL
  AND code_module IS NOT NULL
  AND code_presentation IS NOT NULL;


--Calculate Student Assessment DQ statistics
-- Grain: EXACTLY ONE ROW for this DQ evaluation.
--   - completeness metrics
--   - validity metrics
--   - business-rule metrics
--   - RI metrics
--   - duplicate metrics
--   - parent reference counts

CREATE OR REPLACE TEMP VIEW tmp_student_assessment_dq_stats AS
WITH evaluated AS (
    SELECT  p.*,
        -- Assessment parent match
        a.assessment_id AS matched_assessment_id,
        a.mapping_count,
        a.code_module,
        a.code_presentation,
        -- Student enrollment match
        si.student_id AS matched_student_id
    FROM tmp_student_assessment_parsed p
    LEFT JOIN tmp_student_assessment_assessment_keys a
        ON p.assessment_id = a.assessment_id
    LEFT JOIN tmp_student_assessment_student_keys si
        ON p.student_id = si.student_id
       AND a.code_module = si.code_module
       AND a.code_presentation = si.code_presentation
       AND a.mapping_count = 1),

row_metrics AS (
    SELECT
        COUNT(*) AS total_records,
-- COMPLETENESS / VALIDITY: Assessment ID
        COUNT_IF(
            assessment_id_text IS NULL
        ) AS assessment_id_missing,
        COUNT_IF(
            assessment_id_text IS NOT NULL
            AND assessment_id IS NULL
        ) AS assessment_id_invalid,

-- COMPLETENESS / VALIDITY: Student ID
        COUNT_IF(
            student_id_text IS NULL
        ) AS student_id_missing,
        COUNT_IF(
            student_id_text IS NOT NULL
            AND student_id IS NULL
        ) AS student_id_invalid,

-- INGESTION METADATA
        COUNT_IF(
            ingestion_timestamp IS NULL
            OR ingestion_date IS NULL
        ) AS metadata_missing,
 -- DATE SUBMITTED
        COUNT_IF(
            date_text IS NULL
        ) AS date_missing,
        COUNT_IF(
            date_text IS NOT NULL
            AND submitted_day IS NULL
        ) AS date_invalid,
 -- IS_BANKED
        COUNT_IF(
            banked_text IS NULL
            OR banked_value IS NULL
            OR banked_value NOT IN (0, 1)
        ) AS banked_invalid,
        -- SCORE
        COUNT_IF(
            score_text IS NULL
        ) AS score_missing,
        COUNT_IF(
            score_text IS NOT NULL
            AND score_value IS NULL
        ) AS score_invalid,
        COUNT_IF(
            ISNAN(score_value)
            OR score_value < 0
            OR score_value > 100
        ) AS score_out_of_range,
        -- REFERENTIAL INTEGRITY
        -- Assessment ID exists in child but not in assessments
        COUNT_IF(
            assessment_id IS NOT NULL
            AND matched_assessment_id IS NULL
        ) AS assessment_orphans,
        -- Assessment exists, but module/presentation mapping
        -- cannot safely be used.
        COUNT_IF(
            matched_assessment_id IS NOT NULL
            AND (
                mapping_count <> 1
                OR code_module IS NULL
                OR code_presentation IS NULL )) AS mapping_unusable,
        -- Number of rows where enrollment matching is possible.
        COUNT_IF(
            student_id IS NOT NULL
            AND matched_assessment_id IS NOT NULL
            AND mapping_count = 1
            AND code_module IS NOT NULL
            AND code_presentation IS NOT NULL
        ) AS enrollment_evaluable,
        -- Student does not exist in corresponding module/presentation.
        COUNT_IF(
            student_id IS NOT NULL
            AND matched_assessment_id IS NOT NULL
            AND mapping_count = 1
            AND code_module IS NOT NULL
            AND code_presentation IS NOT NULL
            AND matched_student_id IS NULL
        ) AS enrollment_orphans
    FROM evaluated),

duplicate_stats AS (
    SELECT COALESCE(
            SUM(record_count - 1), 0
        ) AS excess_duplicate_rows
    FROM ( SELECT assessment_id,
            student_id,
            COUNT(*) AS record_count
        FROM tmp_student_assessment_parsed
        WHERE assessment_id IS NOT NULL
          AND student_id IS NOT NULL
        GROUP BY
            assessment_id,
            student_id
        HAVING COUNT(*) > 1 ))

SELECT r.*,
    -- Scalar value: duplicate excess rows
    (SELECT excess_duplicate_rows
        FROM duplicate_stats
    ) AS excess_duplicate_rows,
    -- Scalar value: available assessment parents
    (SELECT COUNT(*)
        FROM tmp_student_assessment_assessment_keys
    ) AS assessment_parent_count,
    -- Scalar value: available student enrollment parents
    (SELECT COUNT(*)
        FROM tmp_student_assessment_student_keys
    ) AS student_parent_count
FROM row_metrics r;

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


-- DQ result rows
WITH all_checks AS (
    -- RECORD COUNT
    SELECT
        'COMPLETENESS' AS check_category,
        'Record Count' AS check_name,
        'TABLE' AS check_level,
        s.total_records,
        CAST( CASE
                WHEN s.total_records = 0 THEN 1
                ELSE 0
            END
            AS BIGINT
        ) AS violation_count,
        'FAIL' AS severity,
        TRUE AS can_evaluate,
        'Bronze student_assessment should contain at least one record.'
            AS description
    FROM tmp_student_assessment_dq_stats s
    UNION ALL
    -- ASSESSMENT ID
    SELECT
        'COMPLETENESS',
        'Missing id_assessment',
        'ROW',
        s.total_records,
        CAST(s.assessment_id_missing AS BIGINT),
        'FAIL',
        TRUE,
        'id_assessment must not be NULL or whitespace-only.'
    FROM tmp_student_assessment_dq_stats s
    UNION ALL
    SELECT
        'VALIDITY',
        'Invalid id_assessment Format',
        'ROW',
        s.total_records,
        CAST(s.assessment_id_invalid AS BIGINT),
        'FAIL',
        TRUE,
        'A supplied id_assessment must parse as BIGINT; missing values are counted separately.'
    FROM tmp_student_assessment_dq_stats s
    UNION ALL
    -- STUDENT ID
    SELECT
        'COMPLETENESS',
        'Missing id_student',
        'ROW',
        s.total_records,
        CAST(s.student_id_missing AS BIGINT),
        'FAIL',
        TRUE,
        'id_student must not be NULL or whitespace-only.'
    FROM tmp_student_assessment_dq_stats s
    UNION ALL
    SELECT
        'VALIDITY',
        'Invalid id_student Format',
        'ROW',
        s.total_records,
        CAST(s.student_id_invalid AS BIGINT),
        'FAIL',
        TRUE,
        'A supplied id_student must parse as BIGINT; missing values are counted separately.'
    FROM tmp_student_assessment_dq_stats s
    UNION ALL
    -- INGESTION METADATA
    SELECT 'COMPLETENESS',
        'Missing Ingestion Metadata',
        'ROW',
        s.total_records,
        CAST(s.metadata_missing AS BIGINT),
        'FAIL',
        TRUE,
        'Every Bronze row must have ingestion_timestamp and ingestion_date.'
    FROM tmp_student_assessment_dq_stats s
    UNION ALL
--uniqueness
    SELECT 'UNIQUENESS',
        'Duplicate Student-Assessment Keys',
        'ROW',
        s.total_records,
        CAST(s.excess_duplicate_rows AS BIGINT),
        'WARNING',
        TRUE,
        'Excess rows for parsed (id_assessment, id_student) keys; resolve exact repeats and conflicting records under separate Silver policies.'
    FROM tmp_student_assessment_dq_stats s
    UNION ALL
--date submitted
    SELECT 'COMPLETENESS',
        'Missing date_submitted',
        'ROW',
        s.total_records,
        CAST(s.date_missing AS BIGINT),
        'WARNING',
        TRUE,
        'date_submitted should be present; do not invent a date for a missing value.'
    FROM tmp_student_assessment_dq_stats s
    UNION ALL
    SELECT 'VALIDITY',
        'Invalid date_submitted Format',
        'ROW',
        s.total_records,
        CAST(s.date_invalid AS BIGINT),
        'WARNING',
        TRUE,
        'A supplied date_submitted must parse as an integer relative day. Negative offsets and late submissions are not automatically errors.'
    FROM tmp_student_assessment_dq_stats s
    UNION ALL
    SELECT
        'VALIDITY',
        'Invalid is_banked Value',
        'ROW',
        s.total_records,
        CAST(s.banked_invalid AS BIGINT),
        'FAIL',
        TRUE,
        'is_banked must be present, parse as an integer, and equal 0 or 1.'
    FROM tmp_student_assessment_dq_stats s
    UNION ALL
    SELECT
        'COMPLETENESS',
        'Missing Score',
        'ROW',
        s.total_records,
        CAST(s.score_missing AS BIGINT),
        'FAIL',
        TRUE,
        'Score must be present under the chosen project policy; missing is not equivalent to zero.'
    FROM tmp_student_assessment_dq_stats s
    UNION ALL
    SELECT
        'VALIDITY',
        'Invalid Score Format',
        'ROW',
        s.total_records,
        CAST(s.score_invalid AS BIGINT),
        'FAIL',
        TRUE,
        'A supplied score must parse as DOUBLE; missing scores are counted separately.'
    FROM tmp_student_assessment_dq_stats s
    UNION ALL
    SELECT
        'BUSINESS_RULE',
        'Score Out of Range',
        'ROW',
        s.total_records,
        CAST(s.score_out_of_range AS BIGINT),
        'FAIL',
        TRUE,
        'A parsed score must be finite and between 0 and 100 inclusive; rejects NaN and positive/negative infinity.'
    FROM tmp_student_assessment_dq_stats s
    UNION ALL
-- REFERENCE READINESS
    SELECT   'REFERENTIAL_INTEGRITY',
        'Assessment Reference Available',
        'TABLE',
        s.total_records,
        CAST(  CASE
                WHEN s.assessment_parent_count = 0 THEN 1
                ELSE 0
            END
            AS BIGINT),'FAIL',TRUE,
        'Bronze assessments must provide at least one parseable assessment ID before reference checks can run.'
    FROM tmp_student_assessment_dq_stats s
    UNION ALL
    SELECT 'REFERENTIAL_INTEGRITY',
        'Student Enrollment Reference Available',
        'TABLE',
        s.total_records,
        CAST( CASE
                WHEN s.student_parent_count = 0 THEN 1
                ELSE 0
            END
            AS BIGINT  ), 'FAIL', TRUE,
'Bronze student_info must provide at least one complete (student, module, presentation) key.'
    FROM tmp_student_assessment_dq_stats s
    UNION ALL
    -- ASSESSMENT FK
    SELECT  'REFERENTIAL_INTEGRITY',
        'Orphan Assessment Reference',
        'ROW',
        s.total_records,
        CAST(s.assessment_orphans AS BIGINT),
        'FAIL',
        s.assessment_parent_count > 0,
        'Each parseable assessment ID must exist in Bronze assessments. Missing or invalid child IDs are counted separately.'
    FROM tmp_student_assessment_dq_stats s
    UNION ALL
    -- ASSESSMENT → MODULE/PRESENTATION MAPPING
    SELECT 'REFERENTIAL_INTEGRITY',
        'Unusable Assessment Module Mapping',
        'ROW',
        s.total_records,
        CAST(s.mapping_unusable AS BIGINT),
        'FAIL',
        s.assessment_parent_count > 0,
        'Each referenced existing assessment ID must map to exactly one complete module/presentation pair; otherwise enrollment matching is skipped for that row.'
    FROM tmp_student_assessment_dq_stats s
    UNION ALL
    -- STUDENT ENROLLMENT FK
    SELECT 'REFERENTIAL_INTEGRITY',
        'Orphan Student Enrollment Reference',
        'ROW',
        s.total_records,
        CAST(s.enrollment_orphans AS BIGINT),
        'FAIL',
        (  s.assessment_parent_count > 0
            AND s.student_parent_count > 0
            AND s.enrollment_evaluable > 0 ),
        'For rows with a parseable student ID and an unambiguous complete assessment mapping, the student must exist in that module presentation. Other key/mapping failures are reported separately.'
    FROM tmp_student_assessment_dq_stats s
),
-- Determine PASS / WARNING / FAIL / NOT_EVALUATED
results AS (
    SELECT *,
        CASE WHEN check_level = 'ROW'
                 AND total_records = 0
                THEN 'NOT_EVALUATED'
            WHEN NOT can_evaluate
                THEN 'NOT_EVALUATED'
            WHEN violation_count = 0
                THEN 'PASS'
            ELSE severity
        END AS status
    FROM all_checks)
-- STEP 7: Final standardized DQ output
SELECT
    'BRONZE' AS layer_name,
    'student_assessment_bronze' AS table_name,
    check_category,
    check_name,
    check_level,
    status,
    total_records,
    CASE WHEN status = 'NOT_EVALUATED'
            THEN CAST(NULL AS BIGINT)
        ELSE violation_count
    END AS violation_count,
    ROUND( CASE  WHEN check_level = 'ROW'
                 AND status <> 'NOT_EVALUATED'
                 AND total_records > 0
            THEN CAST(violation_count AS DOUBLE) / total_records
            ELSE CAST(NULL AS DOUBLE)
        END, 4  ) AS violation_rate,
    CASE  WHEN check_level = 'ROW'
             AND severity = 'WARNING'
            THEN CAST(0 AS DOUBLE)
        ELSE CAST(NULL AS DOUBLE)
    END AS warning_threshold,
    CASE WHEN check_level = 'ROW'
             AND severity = 'FAIL'
            THEN CAST(0 AS DOUBLE)
        ELSE CAST(NULL AS DOUBLE)
    END AS fail_threshold,
    description,
    CURRENT_TIMESTAMP() AS checked_at

FROM results;