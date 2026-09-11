--=========================
-- Bronze DQ: Student Assessments
--=========================

--Note: Remove /* */ if you want to save the query results in a table
/*
CREATE TABLE IF NOT EXISTS oulad.oulad_quality.dq_check_results_bronze1 (
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


-- For a preview without saving results, run only WITH ... SELECT below.
INSERT INTO oulad.oulad_quality.dq_check_results_bronze1 (
    layer_name, table_name, check_category, check_name, check_level,
    status, total_records, violation_count, violation_rate,
    warning_threshold, fail_threshold, description, checked_at)


*/
WITH
base AS (
    SELECT *
    FROM oulad.oulad_bronze.student_assessment_bronze
),


-- Normalize only in the query; Bronze values are not modified.
-- Regex trimming also handles tabs and line breaks, not just ordinary spaces.
normalized AS (
    SELECT
        NULLIF(REGEXP_REPLACE(CAST(id_assessment AS STRING), r'^\s+|\s+$', ''), '') AS assessment_id_text,
        NULLIF(REGEXP_REPLACE(CAST(id_student AS STRING), r'^\s+|\s+$', ''), '') AS student_id_text,
        NULLIF(REGEXP_REPLACE(CAST(date_submitted AS STRING), r'^\s+|\s+$', ''), '') AS date_text,
        NULLIF(REGEXP_REPLACE(CAST(is_banked AS STRING), r'^\s+|\s+$', ''), '') AS banked_text,
        NULLIF(REGEXP_REPLACE(CAST(score AS STRING), r'^\s+|\s+$', ''), '') AS score_text,
        ingestion_timestamp,
        ingestion_date
    FROM base
),
parsed AS (
    SELECT
        n.*,
        TRY_CAST(assessment_id_text AS BIGINT) AS assessment_id,
        TRY_CAST(student_id_text AS BIGINT) AS student_id,
        TRY_CAST(date_text AS INT) AS submitted_day,
        TRY_CAST(banked_text AS INT) AS banked_value,
        TRY_CAST(score_text AS DOUBLE) AS score_value
    FROM normalized n
),


-- DISTINCT prevents repeated identical parent rows from multiplying submissions.
assessment_parent_values AS (
    SELECT DISTINCT
        TRY_CAST(REGEXP_REPLACE(CAST(id_assessment AS STRING), r'^\s+|\s+$', '') AS BIGINT) AS assessment_id,
        UPPER(NULLIF(REGEXP_REPLACE(CAST(code_module AS STRING), r'^\s+|\s+$', ''), '')) AS code_module,
        UPPER(NULLIF(REGEXP_REPLACE(CAST(code_presentation AS STRING), r'^\s+|\s+$', ''), '')) AS code_presentation
    FROM oulad.oulad_bronze.assessments_bronze
),
-- Exactly one row per parent assessment ID, even when its mappings conflict.
-- MIN values are used for enrollment matching ONLY if mapping_count = 1.
assessment_keys AS (
    SELECT
        assessment_id,
        COUNT(*) AS mapping_count,
        MIN(code_module) AS code_module,
        MIN(code_presentation) AS code_presentation
    FROM assessment_parent_values
    WHERE assessment_id IS NOT NULL
    GROUP BY assessment_id
),
student_parent_values AS (
    SELECT DISTINCT
        TRY_CAST(REGEXP_REPLACE(CAST(id_student AS STRING), r'^\s+|\s+$', '') AS BIGINT) AS student_id,
        UPPER(NULLIF(REGEXP_REPLACE(CAST(code_module AS STRING), r'^\s+|\s+$', ''), '')) AS code_module,
        UPPER(NULLIF(REGEXP_REPLACE(CAST(code_presentation AS STRING), r'^\s+|\s+$', ''), '')) AS code_presentation
    FROM oulad.oulad_bronze.student_info_bronze
),
student_keys AS (
    SELECT *
    FROM student_parent_values
    WHERE student_id IS NOT NULL
      AND code_module IS NOT NULL
      AND code_presentation IS NOT NULL
),
parent_stats AS (
    SELECT
        (SELECT COUNT(*) FROM assessment_keys) AS assessment_parent_count,
        (SELECT COUNT(*) FROM student_keys) AS student_parent_count
),
evaluated AS (
    SELECT
        p.*,
        a.assessment_id AS matched_assessment_id,
        a.mapping_count,
        a.code_module,
        a.code_presentation,
        si.student_id AS matched_student_id
    FROM parsed p
    LEFT JOIN assessment_keys a
        ON p.assessment_id = a.assessment_id
    LEFT JOIN student_keys si
        ON p.student_id = si.student_id
       AND a.code_module = si.code_module
       AND a.code_presentation = si.code_presentation
       AND a.mapping_count = 1
),
metrics AS (
    SELECT
        COUNT(*) AS total_records,
        COUNT_IF(assessment_id_text IS NULL) AS assessment_id_missing,
        COUNT_IF(assessment_id_text IS NOT NULL AND assessment_id IS NULL) AS assessment_id_invalid,
        COUNT_IF(student_id_text IS NULL) AS student_id_missing,
        COUNT_IF(student_id_text IS NOT NULL AND student_id IS NULL) AS student_id_invalid,
        COUNT_IF(ingestion_timestamp IS NULL OR ingestion_date IS NULL) AS metadata_missing,
        COUNT_IF(date_text IS NULL) AS date_missing,
        COUNT_IF(date_text IS NOT NULL AND submitted_day IS NULL) AS date_invalid,
        COUNT_IF(banked_text IS NULL OR banked_value IS NULL OR banked_value NOT IN (0, 1)) AS banked_invalid,
        COUNT_IF(score_text IS NULL) AS score_missing,
        COUNT_IF(score_text IS NOT NULL AND score_value IS NULL) AS score_invalid,
        COUNT_IF(ISNAN(score_value) OR score_value < 0 OR score_value > 100) AS score_out_of_range,
        COUNT_IF(assessment_id IS NOT NULL AND matched_assessment_id IS NULL) AS assessment_orphans,
        COUNT_IF(matched_assessment_id IS NOT NULL AND
            (mapping_count <> 1 OR code_module IS NULL OR code_presentation IS NULL)) AS mapping_unusable,
        COUNT_IF(student_id IS NOT NULL AND matched_assessment_id IS NOT NULL
            AND mapping_count = 1 AND code_module IS NOT NULL AND code_presentation IS NOT NULL) AS enrollment_evaluable,
        COUNT_IF(student_id IS NOT NULL AND matched_assessment_id IS NOT NULL
            AND mapping_count = 1 AND code_module IS NOT NULL AND code_presentation IS NOT NULL
            AND matched_student_id IS NULL) AS enrollment_orphans
    FROM evaluated
),
duplicate_groups AS (
    SELECT assessment_id, student_id, COUNT(*) AS record_count
    FROM parsed
    WHERE assessment_id IS NOT NULL AND student_id IS NOT NULL
    GROUP BY assessment_id, student_id
    HAVING COUNT(*) > 1
),
duplicate_stats AS (
    SELECT COALESCE(SUM(record_count - 1), 0) AS excess_duplicate_rows
    FROM duplicate_groups
),


-- These three CTEs each return EXACTLY ONE row. Their CROSS JOIN stays one row.
-- Duplicate counts are excess rows: a key occurring 3 times contributes 2.
-- Other row-level counts below count source rows matching that rule.
all_checks AS (
    SELECT
        'COMPLETENESS' AS check_category,
        'Record Count' AS check_name,
        'TABLE' AS check_level,
        m.total_records,
        CAST(CASE WHEN m.total_records = 0 THEN 1 ELSE 0 END AS BIGINT) AS violation_count,
        'FAIL' AS severity,
        (TRUE) AS can_evaluate,
        'Bronze student_assessment should contain at least one record.' AS description
    FROM metrics m
    CROSS JOIN duplicate_stats d
    CROSS JOIN parent_stats p
    UNION ALL
    SELECT
        'COMPLETENESS' AS check_category,
        'Missing id_assessment' AS check_name,
        'ROW' AS check_level,
        m.total_records,
        CAST(m.assessment_id_missing AS BIGINT) AS violation_count,
        'FAIL' AS severity,
        (TRUE) AS can_evaluate,
        'id_assessment must not be NULL or whitespace-only.' AS description
    FROM metrics m
    CROSS JOIN duplicate_stats d
    CROSS JOIN parent_stats p
    UNION ALL
    SELECT
        'VALIDITY' AS check_category,
        'Invalid id_assessment Format' AS check_name,
        'ROW' AS check_level,
        m.total_records,
        CAST(m.assessment_id_invalid AS BIGINT) AS violation_count,
        'FAIL' AS severity,
        (TRUE) AS can_evaluate,
        'A supplied id_assessment must parse as BIGINT; missing values are counted separately.' AS description
    FROM metrics m
    CROSS JOIN duplicate_stats d
    CROSS JOIN parent_stats p
    UNION ALL
    SELECT
        'COMPLETENESS' AS check_category,
        'Missing id_student' AS check_name,
        'ROW' AS check_level,
        m.total_records,
        CAST(m.student_id_missing AS BIGINT) AS violation_count,
        'FAIL' AS severity,
        (TRUE) AS can_evaluate,
        'id_student must not be NULL or whitespace-only.' AS description
    FROM metrics m
    CROSS JOIN duplicate_stats d
    CROSS JOIN parent_stats p
    UNION ALL
    SELECT
        'VALIDITY' AS check_category,
        'Invalid id_student Format' AS check_name,
        'ROW' AS check_level,
        m.total_records,
        CAST(m.student_id_invalid AS BIGINT) AS violation_count,
        'FAIL' AS severity,
        (TRUE) AS can_evaluate,
        'A supplied id_student must parse as BIGINT; missing values are counted separately.' AS description
    FROM metrics m
    CROSS JOIN duplicate_stats d
    CROSS JOIN parent_stats p
    UNION ALL
    SELECT
        'COMPLETENESS' AS check_category,
        'Missing Ingestion Metadata' AS check_name,
        'ROW' AS check_level,
        m.total_records,
        CAST(m.metadata_missing AS BIGINT) AS violation_count,
        'FAIL' AS severity,
        (TRUE) AS can_evaluate,
        'Every Bronze row must have ingestion_timestamp and ingestion_date.' AS description
    FROM metrics m
    CROSS JOIN duplicate_stats d
    CROSS JOIN parent_stats p
    UNION ALL
    SELECT
        'UNIQUENESS' AS check_category,
        'Duplicate Student-Assessment Keys' AS check_name,
        'ROW' AS check_level,
        m.total_records,
        CAST(d.excess_duplicate_rows AS BIGINT) AS violation_count,
        'WARNING' AS severity,
        (TRUE) AS can_evaluate,
        'Excess rows for parsed (id_assessment, id_student) keys; resolve exact repeats and conflicting records under separate Silver policies.' AS description
    FROM metrics m
    CROSS JOIN duplicate_stats d
    CROSS JOIN parent_stats p
    UNION ALL
    SELECT
        'COMPLETENESS' AS check_category,
        'Missing date_submitted' AS check_name,
        'ROW' AS check_level,
        m.total_records,
        CAST(m.date_missing AS BIGINT) AS violation_count,
        'WARNING' AS severity,
        (TRUE) AS can_evaluate,
        'date_submitted should be present; do not invent a date for a missing value.' AS description
    FROM metrics m
    CROSS JOIN duplicate_stats d
    CROSS JOIN parent_stats p
    UNION ALL
    SELECT
        'VALIDITY' AS check_category,
        'Invalid date_submitted Format' AS check_name,
        'ROW' AS check_level,
        m.total_records,
        CAST(m.date_invalid AS BIGINT) AS violation_count,
        'WARNING' AS severity,
        (TRUE) AS can_evaluate,
        'A supplied date_submitted must parse as an integer relative day. Negative offsets and late submissions are not automatically errors.' AS description
    FROM metrics m
    CROSS JOIN duplicate_stats d
    CROSS JOIN parent_stats p
    UNION ALL
    SELECT
        'VALIDITY' AS check_category,
        'Invalid is_banked Value' AS check_name,
        'ROW' AS check_level,
        m.total_records,
        CAST(m.banked_invalid AS BIGINT) AS violation_count,
        'FAIL' AS severity,
        (TRUE) AS can_evaluate,
        'is_banked must be present, parse as an integer, and equal 0 or 1.' AS description
    FROM metrics m
    CROSS JOIN duplicate_stats d
    CROSS JOIN parent_stats p
    UNION ALL
    SELECT
        'COMPLETENESS' AS check_category,
        'Missing Score' AS check_name,
        'ROW' AS check_level,
        m.total_records,
        CAST(m.score_missing AS BIGINT) AS violation_count,
        'FAIL' AS severity,
        (TRUE) AS can_evaluate,
        'Score must be present under the chosen project policy; missing is not equivalent to zero.' AS description
    FROM metrics m
    CROSS JOIN duplicate_stats d
    CROSS JOIN parent_stats p
    UNION ALL
    SELECT
        'VALIDITY' AS check_category,
        'Invalid Score Format' AS check_name,
        'ROW' AS check_level,
        m.total_records,
        CAST(m.score_invalid AS BIGINT) AS violation_count,
        'FAIL' AS severity,
        (TRUE) AS can_evaluate,
        'A supplied score must parse as DOUBLE; missing scores are counted separately.' AS description
    FROM metrics m
    CROSS JOIN duplicate_stats d
    CROSS JOIN parent_stats p
    UNION ALL
    SELECT
        'BUSINESS_RULE' AS check_category,
        'Score Out of Range' AS check_name,
        'ROW' AS check_level,
        m.total_records,
        CAST(m.score_out_of_range AS BIGINT) AS violation_count,
        'FAIL' AS severity,
        (TRUE) AS can_evaluate,
        'A parsed score must be finite and between 0 and 100 inclusive; rejects NaN and positive/negative infinity.' AS description
    FROM metrics m
    CROSS JOIN duplicate_stats d
    CROSS JOIN parent_stats p
    UNION ALL
    SELECT
        'REFERENTIAL_INTEGRITY' AS check_category,
        'Assessment Reference Available' AS check_name,
        'TABLE' AS check_level,
        m.total_records,
        CAST(CASE WHEN p.assessment_parent_count = 0 THEN 1 ELSE 0 END AS BIGINT) AS violation_count,
        'FAIL' AS severity,
        (TRUE) AS can_evaluate,
        'Bronze assessments must provide at least one parseable assessment ID before reference checks can run.' AS description
    FROM metrics m
    CROSS JOIN duplicate_stats d
    CROSS JOIN parent_stats p
    UNION ALL
    SELECT
        'REFERENTIAL_INTEGRITY' AS check_category,
        'Student Enrollment Reference Available' AS check_name,
        'TABLE' AS check_level,
        m.total_records,
        CAST(CASE WHEN p.student_parent_count = 0 THEN 1 ELSE 0 END AS BIGINT) AS violation_count,
        'FAIL' AS severity,
        (TRUE) AS can_evaluate,
        'Bronze student_info must provide at least one complete (student, module, presentation) key.' AS description
    FROM metrics m
    CROSS JOIN duplicate_stats d
    CROSS JOIN parent_stats p
    UNION ALL
    SELECT
        'REFERENTIAL_INTEGRITY' AS check_category,
        'Orphan Assessment Reference' AS check_name,
        'ROW' AS check_level,
        m.total_records,
        CAST(m.assessment_orphans AS BIGINT) AS violation_count,
        'FAIL' AS severity,
        (p.assessment_parent_count > 0) AS can_evaluate,
        'Each parseable assessment ID must exist in Bronze assessments. Missing or invalid child IDs are counted separately.' AS description
    FROM metrics m
    CROSS JOIN duplicate_stats d
    CROSS JOIN parent_stats p
    UNION ALL
    SELECT
        'REFERENTIAL_INTEGRITY' AS check_category,
        'Unusable Assessment Module Mapping' AS check_name,
        'ROW' AS check_level,
        m.total_records,
        CAST(m.mapping_unusable AS BIGINT) AS violation_count,
        'FAIL' AS severity,
        (p.assessment_parent_count > 0) AS can_evaluate,
        'Each referenced existing assessment ID must map to exactly one complete module/presentation pair; otherwise enrollment matching is skipped for that row.' AS description
    FROM metrics m
    CROSS JOIN duplicate_stats d
    CROSS JOIN parent_stats p
    UNION ALL
    SELECT
        'REFERENTIAL_INTEGRITY' AS check_category,
        'Orphan Student Enrollment Reference' AS check_name,
        'ROW' AS check_level,
        m.total_records,
        CAST(m.enrollment_orphans AS BIGINT) AS violation_count,
        'FAIL' AS severity,
        (p.assessment_parent_count > 0 AND p.student_parent_count > 0 AND m.enrollment_evaluable > 0) AS can_evaluate,
        'For rows with a parseable student ID and an unambiguous complete assessment mapping, the student must exist in that module presentation. Other key/mapping failures are reported separately.' AS description
    FROM metrics m
    CROSS JOIN duplicate_stats d
    CROSS JOIN parent_stats p
),
results AS (
    SELECT
        *,
        CASE
            WHEN check_level = 'ROW' AND total_records = 0 THEN 'NOT_EVALUATED'
            WHEN NOT can_evaluate THEN 'NOT_EVALUATED'
            WHEN violation_count = 0 THEN 'PASS'
            ELSE severity
        END AS status
    FROM all_checks
)
SELECT
    'BRONZE' AS layer_name,
    'student_assessment_bronze' AS table_name,
    check_category,
    check_name,
    check_level,
    status,
    total_records,
    CASE WHEN status = 'NOT_EVALUATED' THEN CAST(NULL AS BIGINT)
         ELSE violation_count END AS violation_count,
    ROUND(CASE
        WHEN check_level = 'ROW' AND status <> 'NOT_EVALUATED' AND total_records > 0
            THEN CAST(violation_count AS DOUBLE) / total_records
        ELSE CAST(NULL AS DOUBLE)
    END,4) AS violation_rate,
    CASE WHEN check_level = 'ROW' AND severity = 'WARNING' THEN CAST(0 AS DOUBLE)
         ELSE CAST(NULL AS DOUBLE) END AS warning_threshold,
    CASE WHEN check_level = 'ROW' AND severity = 'FAIL' THEN CAST(0 AS DOUBLE)
         ELSE CAST(NULL AS DOUBLE) END AS fail_threshold,
    description,
    CURRENT_TIMESTAMP() AS checked_at
FROM results;




/*
SELECT layer_name, table_name, check_category, check_name, check_level,
       status, total_records, violation_count, violation_rate,
       ROUND(100.0 * violation_rate, 2) AS violation_pct,
       warning_threshold, fail_threshold, description, checked_at
FROM oulad.oulad_quality.dq_check_results_bronze1
WHERE layer_name = 'BRONZE' AND table_name = 'assessments'
ORDER BY checked_at, check_category, check_name;
*/
