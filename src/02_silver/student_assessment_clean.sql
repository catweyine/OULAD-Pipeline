-- =====================================================================
-- Silver: student_assessment
-- =====================================================================

-- Grain: one row per assessment per student.
CREATE TABLE IF NOT EXISTS oulad.oulad_silver.student_assessment_silver (
    id_assessment       INT,
    id_student          INT,
    date_submitted      INT,       -- negative is VALID: days from module start
    is_banked           INT,
    score               DOUBLE,    -- NULL means the student did not submit
    score_source        STRING,    -- score as received, so ? and blank stay separable
    ingestion_timestamp TIMESTAMP,
    ingestion_date      DATE
)
USING DELTA;

-- =====================================================================
-- silver_student_assessment.sql
-- Loads student_assessment_silver. Table must already exist.
--
-- The WHERE clause is the single statement of what a valid submission is.
-- Refused rows are reported by the oulad_quality views.
-- =====================================================================

MERGE INTO oulad.oulad_silver.student_assessment_silver AS target
USING (
    SELECT
        id_assessment,
        id_student,
        date_submitted,
        is_banked,
        score,
        score_source,
        ingestion_timestamp,
        CAST(ingestion_timestamp AS DATE) AS ingestion_date
    FROM (
        SELECT
            id_assessment,
            id_student,
            date_submitted,
            is_banked,
            -- FIXED: this had no alias, so the outer SELECT could not resolve
            -- `score`. The CAST below still reads the BRONZE column, because an
            -- unqualified name resolves against the input before it resolves
            -- against a sibling alias.
            TRY_CAST(score AS DOUBLE) AS score,
            CAST(score AS STRING) AS score_source,
            ingestion_timestamp,
            ROW_NUMBER() OVER (
                PARTITION BY id_assessment, id_student
                ORDER BY ingestion_timestamp DESC, date_submitted DESC, score DESC NULLS LAST
            ) AS row_num,
            -- A key whose copies disagree has no right answer, so every copy is
            -- refused rather than one picked arbitrarily.
            MIN(CONCAT_WS('|',
                    COALESCE(CAST(date_submitted AS STRING), '~'),
                    COALESCE(CAST(is_banked AS STRING), '~'),
                    COALESCE(CAST(score AS STRING), '~'))) OVER (PARTITION BY id_assessment, id_student)
              <>
            MAX(CONCAT_WS('|',
                    COALESCE(CAST(date_submitted AS STRING), '~'),
                    COALESCE(CAST(is_banked AS STRING), '~'),
                    COALESCE(CAST(score AS STRING), '~'))) OVER (PARTITION BY id_assessment, id_student)
              AS key_conflict
        FROM oulad.oulad_bronze.student_assessment_bronze
    ) t
    WHERE row_num = 1
      AND NOT key_conflict
      AND id_assessment IS NOT NULL
      AND id_assessment > 0
      AND id_student IS NOT NULL
      AND id_student > 0
      AND date_submitted IS NOT NULL
      -- NOT "> 0": OULAD has submissions before the module opens. These are
      -- generous corruption guards, not tight business bounds.
      AND date_submitted BETWEEN -365 AND 1825
      -- NULL fails IN, so a missing status is refused by the same test.
      AND is_banked IN (0, 1)
      -- A NULL score is a NON-SUBMISSION and is kept. ISNAN is explicit because
      -- NaN survives TRY_CAST; the Infinity test was redundant, since BETWEEN
      -- already excludes both.
      AND (score IS NULL
           OR (NOT ISNAN(score) AND score BETWEEN 0 AND 100))
      AND ingestion_timestamp IS NOT NULL
) AS source
ON  target.id_assessment = source.id_assessment
AND target.id_student    = source.id_student
WHEN MATCHED THEN
    UPDATE SET
        target.date_submitted      = source.date_submitted,
        target.is_banked           = source.is_banked,
        target.score               = source.score,
        target.score_source        = source.score_source,
        target.ingestion_timestamp = source.ingestion_timestamp,
        target.ingestion_date      = source.ingestion_date
WHEN NOT MATCHED THEN
    INSERT (id_assessment, id_student, date_submitted, is_banked, score,
            score_source, ingestion_timestamp, ingestion_date)
    VALUES (source.id_assessment, source.id_student, source.date_submitted,
            source.is_banked, source.score, source.score_source,
            source.ingestion_timestamp, source.ingestion_date);