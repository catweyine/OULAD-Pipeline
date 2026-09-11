
-- =====================================================================
-- 2. student_assessment
--    Grain: one row per assessment per student
-- =====================================================================
 
CREATE TABLE IF NOT EXISTS oulad.oulad_silver.student_assessment_silver (
    id_assessment        INT     NOT NULL,
    id_student           INT     NOT NULL,
    date_submitted       INT     NOT NULL,        -- negative is VALID: days from module start
    is_banked            INT     NOT NULL,
    score                DOUBLE,                  -- nullable: NULL means the student did not submit
    score_source         STRING,           -- score exactly as received: 78, or a question mark, or empty
    ingestion_timestamp  TIMESTAMP NOT NULL,
    ingestion_date       DATE,
    CONSTRAINT student_assessment_silver_pk PRIMARY KEY (id_assessment, id_student)
)
USING DELTA;
 

ALTER TABLE oulad.oulad_silver.student_assessment_silver DROP CONSTRAINT IF EXISTS student_assessment_score_range;
ALTER TABLE oulad.oulad_silver.student_assessment_silver ADD CONSTRAINT student_assessment_score_range
    CHECK (score IS NULL OR (NOT ISNAN(score) AND score BETWEEN 0 AND 100));
 
-- Covers both of your is_banked rules at once: NULL fails IN, so a missing status is refused by the same test as an invalid one.
ALTER TABLE oulad.oulad_silver.student_assessment_silver DROP CONSTRAINT IF EXISTS student_assessment_banked_domain;
ALTER TABLE oulad.oulad_silver.student_assessment_silver ADD CONSTRAINT student_assessment_banked_domain
    CHECK (is_banked IN (0, 1));
 
-- The lower bound is NEGATIVE on purpose:
-- OULAD has submissions as early as day -11, so "date_submitted >= 0" would be
ALTER TABLE oulad.oulad_silver.student_assessment_silver DROP CONSTRAINT IF EXISTS student_assessment_date_valid;
ALTER TABLE oulad.oulad_silver.student_assessment_silver ADD CONSTRAINT student_assessment_date_valid
    CHECK (date_submitted BETWEEN -365 AND 1825);
 
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
            TRY_CAST(score AS DOUBLE),
            CAST(score AS STRING) AS score_source,
            ingestion_timestamp,
            ROW_NUMBER() OVER (
                PARTITION BY id_assessment, id_student
                ORDER BY ingestion_timestamp DESC, date_submitted DESC, score DESC NULLS LAST
            ) AS row_num,
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
      AND date_submitted BETWEEN -365 AND 1825  -- NOT "> 0" — negative days are real
      AND is_banked IN (0, 1)                  
  
      AND (score IS NULL
           OR (NOT ISNAN(score)
               AND score NOT IN (DOUBLE('Infinity'), DOUBLE('-Infinity'))
               AND score BETWEEN 0 AND 100))
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
    INSERT (id_assessment, id_student, date_submitted, is_banked, score, score_source, ingestion_timestamp, ingestion_date)
    VALUES (source.id_assessment, source.id_student, source.date_submitted, source.is_banked, source.score, source.score_source, source.ingestion_timestamp, source.ingestion_date);

