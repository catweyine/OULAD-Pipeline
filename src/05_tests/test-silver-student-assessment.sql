--====================================
-- Silver DQ: Student Assessments
--====================================


-- Rows that ARE in Silver, with their parent lookups attached.
CREATE OR REPLACE TEMP VIEW tmp_student_assessment_silver_eval AS
WITH assessment_keys AS (
    -- One row per assessment, so this join cannot multiply rows.
    SELECT id_assessment, code_module, code_presentation
    FROM oulad.oulad_silver.assessments_silver),
student_any AS (
    -- Does the student exist in student_info AT ALL, on any module? A separate
    -- question from "is the student on THIS presentation", with a different
    -- cause and a different fix.
    SELECT DISTINCT id_student
    FROM oulad.oulad_silver.student_info_silver),
enrollment_keys AS (
    -- Grain: one row per student per presentation. Carries the columns the
    -- business rules need, so no second join is required.
    SELECT id_student, code_module, code_presentation, num_of_prev_attempts
    FROM oulad.oulad_silver.student_info_silver),
registrations AS (
    SELECT id_student, code_module, code_presentation, date_registration
    FROM oulad.oulad_silver.student_registration_silver)

SELECT sa.*,
    COUNT(*) OVER (PARTITION BY sa.id_assessment, sa.id_student) AS key_occurrences,
    a.id_assessment AS matched_assessment,
    a.code_module,
    a.code_presentation,
    sany.id_student AS student_exists_anywhere,
    e.id_student AS matched_enrollment,
    e.num_of_prev_attempts,
    r.date_registration
FROM oulad.oulad_silver.student_assessment_silver sa
LEFT JOIN assessment_keys a
    ON sa.id_assessment = a.id_assessment
LEFT JOIN student_any sany
    ON sa.id_student = sany.id_student
LEFT JOIN enrollment_keys e
    ON  sa.id_student = e.id_student
    AND a.code_module = e.code_module
    AND a.code_presentation = e.code_presentation
LEFT JOIN registrations r
    ON  sa.id_student = r.id_student
    AND a.code_module = r.code_module
    AND a.code_presentation = r.code_presentation;


-- Rows that did NOT reach Silver. This replaces a quarantine table.
-- Membership is derived from the OUTCOME and cannot drift; the reason column
-- restates the MERGE's WHERE clause and can, which is what
-- 'other_unspecified' is for.
CREATE OR REPLACE TEMP VIEW tmp_student_assessment_refused AS
WITH ranked AS (
    SELECT b.*,
        CAST(b.score AS STRING) AS score_source,
        ROW_NUMBER() OVER (
            PARTITION BY b.id_assessment, b.id_student
            -- TRY_CAST so the tiebreak sorts numerically. On STRING Bronze a raw
            -- sort puts '9' above '10', which would keep a different row than
            -- the MERGE did. Accounting balances either way, but the row named
            -- as the survivor should be the row that actually survived.
            ORDER BY b.ingestion_timestamp DESC,
                     TRY_CAST(b.date_submitted AS INT) DESC NULLS LAST,
                     TRY_CAST(b.score AS DOUBLE) DESC NULLS LAST
        ) AS row_num,
        MIN(CONCAT_WS('|',
                COALESCE(CAST(b.date_submitted AS STRING), '~'),
                COALESCE(CAST(b.is_banked AS STRING), '~'),
                COALESCE(CAST(b.score AS STRING), '~'))) OVER (PARTITION BY b.id_assessment, b.id_student)
          <>
        MAX(CONCAT_WS('|',
                COALESCE(CAST(b.date_submitted AS STRING), '~'),
                COALESCE(CAST(b.is_banked AS STRING), '~'),
                COALESCE(CAST(b.score AS STRING), '~'))) OVER (PARTITION BY b.id_assessment, b.id_student)
          AS key_conflict
    FROM oulad.oulad_bronze.student_assessment_bronze b)

-- TRY_CAST throughout, because Bronze holds these columns as STRING. Comparing
-- the raw '?' to a number yields NULL, not FALSE, so an unparseable value would
-- fall past every WHEN and land on 'other_unspecified' — the drift alarm firing
-- for a cause we already know. TRY_CAST turns it into the NULL the MERGE saw,
-- so the reason reported is the reason the row was actually refused.
SELECT r.id_assessment,
    r.id_student,
    r.date_submitted,
    r.is_banked,
    r.score_source,
    r.ingestion_timestamp,
    r.row_num,
    r.key_conflict,
    COALESCE(
        CASE WHEN TRY_CAST(r.id_assessment AS BIGINT) IS NULL  THEN 'assessment_id_missing_or_unparseable'
             WHEN TRY_CAST(r.id_assessment AS BIGINT) <= 0     THEN 'assessment_id_not_positive'
             WHEN TRY_CAST(r.id_student AS BIGINT) IS NULL     THEN 'student_id_missing_or_unparseable'
             WHEN TRY_CAST(r.id_student AS BIGINT) <= 0        THEN 'student_id_not_positive'
             WHEN r.key_conflict                               THEN 'key_conflict'
             WHEN r.row_num > 1                                THEN 'duplicate_key_dropped'
             WHEN TRY_CAST(r.date_submitted AS INT) IS NULL    THEN 'date_submitted_missing_or_unparseable'
             WHEN TRY_CAST(r.date_submitted AS INT) < -365
                  OR TRY_CAST(r.date_submitted AS INT) > 1825  THEN 'date_submitted_out_of_range'
             WHEN TRY_CAST(r.is_banked AS INT) IS NULL
                  OR TRY_CAST(r.is_banked AS INT) NOT IN (0, 1)
                                                               THEN 'is_banked_missing_or_invalid'
             WHEN TRY_CAST(r.score AS DOUBLE) IS NOT NULL
                  AND (TRY_CAST(r.score AS DOUBLE) < 0
                       OR TRY_CAST(r.score AS DOUBLE) > 100)    THEN 'score_out_of_range'
             WHEN r.ingestion_timestamp IS NULL                THEN 'ingestion_timestamp_missing'
        END,
        'other_unspecified') AS refusal_reason
FROM ranked r
LEFT JOIN oulad.oulad_silver.student_assessment_silver s
    ON  r.id_assessment = s.id_assessment
    AND r.id_student = s.id_student
WHERE s.id_assessment IS NULL
   OR r.row_num > 1;


-- Calculate Silver student assessment DQ statistics
-- Grain: EXACTLY ONE ROW for this DQ evaluation.
CREATE OR REPLACE TEMP VIEW tmp_student_assessment_silver_dq_stats AS
WITH row_metrics AS (
    SELECT COUNT(*) AS total_records,
-- TRANSFORM. score is excluded from the required list: a NULL score is a
-- non-submission, which is a real state the MERGE deliberately keeps.
        COUNT_IF(
            id_assessment IS NULL
            OR id_student IS NULL
            OR date_submitted IS NULL
            OR is_banked IS NULL
            OR ingestion_timestamp IS NULL
        ) AS required_nulls,
        COUNT_IF(
            id_assessment <= 0
            OR id_student <= 0
        ) AS keys_not_positive,
        COUNT_IF(key_occurrences > 1)
            AS duplicate_keys,
        COUNT_IF(is_banked NOT IN (0, 1))
            AS banked_invalid,
        COUNT_IF(
            score IS NOT NULL
            AND (ISNAN(score) OR score < 0 OR score > 100)
        ) AS score_out_of_range,
        COUNT_IF(
            date_submitted < -365
            OR date_submitted > 1825
        ) AS date_out_of_range,
-- LIVE. The MERGE checks no parent at all, so all three of these are real.
        COUNT_IF(matched_assessment IS NULL)
            AS orphan_assessments,
        COUNT_IF(student_exists_anywhere IS NULL)
            AS student_not_in_any_enrollment,
        -- Only meaningful where the assessment resolved, otherwise there is no
        -- module presentation to look the student up in.
        COUNT_IF(
            matched_assessment IS NOT NULL
            AND student_exists_anywhere IS NOT NULL
            AND matched_enrollment IS NULL
        ) AS orphan_enrollments,
        COUNT_IF(
            matched_assessment IS NOT NULL
            AND student_exists_anywhere IS NOT NULL
        ) AS enrollment_evaluable,
-- BUSINESS RULES. Nothing upstream covers either.
        COUNT_IF(
            is_banked = 1
            AND matched_enrollment IS NOT NULL
            AND COALESCE(num_of_prev_attempts, 0) = 0
        ) AS banked_without_prior_attempt,
        COUNT_IF(is_banked = 1)
            AS banked_rows,
        COUNT_IF(
            date_registration IS NOT NULL
            AND date_submitted < date_registration
        ) AS submitted_before_registration,
-- EXPECTED STATES
        COUNT_IF(score IS NULL)
            AS score_missing,
        COUNT_IF(
            score IS NULL
            AND score_source IS NULL
        ) AS score_source_missing
    FROM tmp_student_assessment_silver_eval)

SELECT r.*,
    -- Scalar value: available assessment parents
    (SELECT COUNT(*)
        FROM oulad.oulad_silver.assessments_silver
    ) AS assessment_parent_count,
    -- Scalar value: available student enrollment parents
    (SELECT COUNT(*)
        FROM oulad.oulad_silver.student_info_silver
    ) AS student_parent_count,
    -- Scalar value: Bronze rows, for the accounting check
    (SELECT COUNT(*)
        FROM oulad.oulad_bronze.student_assessment_bronze
    ) AS bronze_records,
    -- Scalar value: rows the filter refused
    (SELECT COUNT(*)
        FROM tmp_student_assessment_refused
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
        'Silver student_assessment should contain at least one record.' AS description
    FROM tmp_student_assessment_silver_dq_stats s
    UNION ALL
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
    FROM tmp_student_assessment_silver_dq_stats s
    UNION ALL
-- TRANSFORM
    SELECT
        'TRANSFORM',
        'Required Column NULL',
        'ROW',
        s.total_records,
        CAST(s.required_nulls AS BIGINT),
        'FAIL',
        TRUE,
        'id_assessment, id_student, date_submitted, is_banked and ingestion_timestamp are all required by the MERGE filter. score is NOT in this list: a NULL score is a non-submission, which is kept on purpose.'
    FROM tmp_student_assessment_silver_dq_stats s
    UNION ALL
    SELECT
        'TRANSFORM',
        'Non-Positive Keys',
        'ROW',
        s.total_records,
        CAST(s.keys_not_positive AS BIGINT),
        'FAIL',
        TRUE,
        'The MERGE filter requires id_assessment > 0 and id_student > 0.'
    FROM tmp_student_assessment_silver_dq_stats s
    UNION ALL
    SELECT
        'UNIQUENESS',
        'Duplicate Student-Assessment Key',
        'ROW',
        s.total_records,
        CAST(s.duplicate_keys AS BIGINT),
        'FAIL',
        TRUE,
        'The Silver grain is one row per student per assessment. No PRIMARY KEY backs this any more; the dedup in the MERGE is the only enforcement.'
    FROM tmp_student_assessment_silver_dq_stats s
    UNION ALL
    SELECT
        'VALIDITY',
        'Invalid is_banked Value',
        'ROW',
        s.total_records,
        CAST(s.banked_invalid AS BIGINT),
        'FAIL',
        TRUE,
        'is_banked must equal 0 or 1. No CHECK constraint backs this any more.'
    FROM tmp_student_assessment_silver_dq_stats s
    UNION ALL
    SELECT
        'VALIDITY',
        'Score Out of Range',
        'ROW',
        s.total_records,
        CAST(s.score_out_of_range AS BIGINT),
        'FAIL',
        TRUE,
        'A non-NULL score must be finite and between 0 and 100. NaN is tested explicitly because it survives TRY_CAST and would pass a BETWEEN test.'
    FROM tmp_student_assessment_silver_dq_stats s
    UNION ALL
    SELECT
        'VALIDITY',
        'Date Submitted Out of Range',
        'ROW',
        s.total_records,
        CAST(s.date_out_of_range AS BIGINT),
        'FAIL',
        TRUE,
        'date_submitted must fall between -365 and 1825. Negative values are VALID: OULAD has submissions before the module opens. These are loose corruption guards, not validated business bounds.'
    FROM tmp_student_assessment_silver_dq_stats s
    UNION ALL
-- LIVE referential checks. The MERGE tests no parent at all.
    SELECT
        'REFERENTIAL_INTEGRITY',
        'Orphan Assessment Reference',
        'ROW',
        s.total_records,
        CAST(s.orphan_assessments AS BIGINT),
        'FAIL',
        s.assessment_parent_count > 0,
        'LIVE CHECK: the MERGE does not test the assessment parent, so a submission can reference an assessment that never reached Silver.'
    FROM tmp_student_assessment_silver_dq_stats s
    UNION ALL
    SELECT
        'REFERENTIAL_INTEGRITY',
        'Student Not In Any Enrollment',
        'ROW',
        s.total_records,
        CAST(s.student_not_in_any_enrollment AS BIGINT),
        'FAIL',
        s.student_parent_count > 0,
        'LIVE CHECK: the student has no student_info row on ANY module. These rows are lost by any downstream fact that joins a student dimension, whatever the module, and they are invisible unless counted here.'
    FROM tmp_student_assessment_silver_dq_stats s
    UNION ALL
    SELECT
        'REFERENTIAL_INTEGRITY',
        'Orphan Student Enrollment Reference',
        'ROW',
        s.total_records,
        CAST(s.orphan_enrollments AS BIGINT),
        'FAIL',
        (s.assessment_parent_count > 0
         AND s.student_parent_count > 0
         AND s.enrollment_evaluable > 0),
        'LIVE CHECK: the student exists somewhere but is not enrolled on the presentation this assessment belongs to. Students absent from student_info entirely are counted separately.'
    FROM tmp_student_assessment_silver_dq_stats s
    UNION ALL
-- BUSINESS RULES
    SELECT
        'BUSINESS_RULE',
        'Banked Without Prior Attempt',
        'ROW',
        s.total_records,
        CAST(s.banked_without_prior_attempt AS BIGINT),
        'WARNING',
        s.banked_rows > 0,
        'is_banked = 1 means the score was carried over from an earlier attempt at the module. Banked with no previous attempts is a contradiction, and it credits the student with work they did not do this time.'
    FROM tmp_student_assessment_silver_dq_stats s
    UNION ALL
    SELECT
        'BUSINESS_RULE',
        'Submitted Before Registration',
        'ROW',
        s.total_records,
        CAST(s.submitted_before_registration AS BIGINT),
        'WARNING',
        TRUE,
        'A submission dated before the student registered for the module. Banked scores legitimately carry an early date, so this is reported rather than rejected.'
    FROM tmp_student_assessment_silver_dq_stats s
    UNION ALL
-- EXPECTED STATES
    SELECT
        'COMPLETENESS',
        'Missing Score',
        'ROW',
        s.total_records,
        CAST(s.score_missing AS BIGINT),
        'WARNING',
        TRUE,
        'A NULL score is a NON-SUBMISSION, a real and documented state rather than a defect. Retained as NULL and never read as zero; the count is reported so its size is known.'
    FROM tmp_student_assessment_silver_dq_stats s
    UNION ALL
    SELECT
        'CONSISTENCY',
        'Score Source Not Captured',
        'ROW',
        s.total_records,
        CAST(s.score_source_missing AS BIGINT),
        'FAIL',
        TRUE,
        'score_source exists to tell a question mark from a blank cell after TRY_CAST has turned both into NULL. A NULL there defeats the only reason the column exists.'
    FROM tmp_student_assessment_silver_dq_stats s
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
    'student_assessment_silver' AS table_name,
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
-- One row per source row however many rules it broke.
SELECT id_assessment, id_student, date_submitted, is_banked, score, score_source,
    code_module, code_presentation, num_of_prev_attempts, date_registration,
    ARRAY_COMPACT(ARRAY(
        CASE WHEN id_assessment IS NULL OR id_student IS NULL
                  OR date_submitted IS NULL OR is_banked IS NULL
                  OR ingestion_timestamp IS NULL                 THEN 'required_column_null' END,
        CASE WHEN id_assessment <= 0 OR id_student <= 0          THEN 'key_not_positive' END,
        CASE WHEN key_occurrences > 1                            THEN 'duplicate_key' END,
        CASE WHEN is_banked NOT IN (0, 1)                        THEN 'is_banked_invalid' END,
        CASE WHEN score IS NOT NULL
                  AND (ISNAN(score) OR score < 0 OR score > 100) THEN 'score_out_of_range' END,
        CASE WHEN date_submitted < -365 OR date_submitted > 1825 THEN 'date_out_of_range' END,
        CASE WHEN matched_assessment IS NULL                     THEN 'orphan_assessment' END,
        CASE WHEN student_exists_anywhere IS NULL                THEN 'student_not_in_any_enrollment' END,
        CASE WHEN matched_assessment IS NOT NULL
                  AND student_exists_anywhere IS NOT NULL
                  AND matched_enrollment IS NULL                 THEN 'orphan_enrollment' END,
        CASE WHEN is_banked = 1 AND matched_enrollment IS NOT NULL
                  AND COALESCE(num_of_prev_attempts, 0) = 0      THEN 'banked_without_prior_attempt' END,
        CASE WHEN date_registration IS NOT NULL
                  AND date_submitted < date_registration         THEN 'submitted_before_registration' END,
        CASE WHEN score IS NULL AND score_source IS NULL         THEN 'score_source_not_captured' END
    )) AS reject_reasons
FROM tmp_student_assessment_silver_eval
WHERE id_assessment IS NULL OR id_student IS NULL OR date_submitted IS NULL
   OR is_banked IS NULL OR ingestion_timestamp IS NULL
   OR id_assessment <= 0 OR id_student <= 0
   OR key_occurrences > 1
   OR is_banked NOT IN (0, 1)
   OR (score IS NOT NULL AND (ISNAN(score) OR score < 0 OR score > 100))
   OR date_submitted < -365 OR date_submitted > 1825
   OR matched_assessment IS NULL
   OR student_exists_anywhere IS NULL
   OR (matched_assessment IS NOT NULL AND student_exists_anywhere IS NOT NULL
       AND matched_enrollment IS NULL)
   OR (is_banked = 1 AND matched_enrollment IS NOT NULL
       AND COALESCE(num_of_prev_attempts, 0) = 0)
   OR (date_registration IS NOT NULL AND date_submitted < date_registration)
   OR (score IS NULL AND score_source IS NULL)
ORDER BY id_assessment, id_student;


-- Rows the filter refused. This is what a quarantine table would have held.
-- other_unspecified MUST be 0.
SELECT refusal_reason, COUNT(*) AS rows_refused
FROM tmp_student_assessment_refused
GROUP BY refusal_reason
ORDER BY rows_refused DESC;

-- The refused rows themselves, so they can be corrected at source.
SELECT * FROM tmp_student_assessment_refused
ORDER BY refusal_reason, id_assessment, id_student
LIMIT 200;
