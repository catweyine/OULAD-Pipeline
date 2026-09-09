 
-- =====================================================================
-- 1. assessments
--    Grain: one row per id_assessment
-- =====================================================================
 
CREATE TABLE IF NOT EXISTS oulad.oulad_silver.assessments_silver (
    id_assessment INT NOT NULL,
    code_module   STRING  NOT NULL,
    code_presentation STRING  NOT NULL,
    assessment_type STRING NOT NULL,        
    `date` INT,                      -- nullable: 11 Exam rows have no published date
    date_source  STRING,                   -- the date column exactly as the file wrote it:
       -- 250, or a question mark, or empty. The only way to tell those apart after TRY_CAST has run
     weight DOUBLE NOT NULL,
    ingestion_timestamp TIMESTAMP NOT NULL,
    ingestion_date DATE,
    CONSTRAINT assessments_silver_pk PRIMARY KEY (id_assessment)
)
USING DELTA;
 
-- CHECK constraints are added by ALTER TABLE, not inside CREATE TABLE.
-- DROP ... IF EXISTS first so this file can be re-run: ADD CONSTRAINT on a
-- constraint that already exists is an error.
 
ALTER TABLE oulad.oulad_silver.assessments_silver DROP CONSTRAINT IF EXISTS assessments_weight_range;
ALTER TABLE oulad.oulad_silver.assessments_silver ADD CONSTRAINT assessments_weight_range
    CHECK (weight BETWEEN 0 AND 100);
 
ALTER TABLE oulad.oulad_silver.assessments_silver DROP CONSTRAINT IF EXISTS assessments_type_domain;
ALTER TABLE oulad.oulad_silver.assessments_silver ADD CONSTRAINT assessments_type_domain
    CHECK (assessment_type IN ('TMA', 'CMA', 'Exam'));
 
ALTER TABLE oulad.oulad_silver.assessments_silver DROP CONSTRAINT IF EXISTS assessments_date_valid;
ALTER TABLE oulad.oulad_silver.assessments_silver ADD CONSTRAINT assessments_date_valid
    CHECK (`date` IS NULL OR `date` BETWEEN 0 AND 1000);
 
MERGE INTO oulad.oulad_silver.assessments_silver AS target
USING (
    SELECT
        id_assessment,
        UPPER(TRIM(code_module))       AS code_module,
        UPPER(TRIM(code_presentation)) AS code_presentation,
        CASE UPPER(TRIM(assessment_type))
            WHEN 'TMA'  THEN 'TMA'
            WHEN 'CMA'  THEN 'CMA'
            WHEN 'EXAM' THEN 'Exam'
        END                            AS assessment_type,
        TRY_CAST(`date` AS INT)        AS `date`,
        date_source,
        weight,
        ingestion_timestamp,
        CAST(ingestion_timestamp AS DATE) AS ingestion_date
    FROM (
        SELECT *,
            CAST(`date` AS STRING) AS date_source,
            ROW_NUMBER() OVER (
                PARTITION BY id_assessment
                ORDER BY ingestion_timestamp DESC, weight DESC, `date` DESC NULLS LAST
            ) AS row_num,
            MIN(CONCAT_WS('|',
                    COALESCE(UPPER(TRIM(code_module)), '~'),
                    COALESCE(UPPER(TRIM(code_presentation)), '~'),
                    COALESCE(UPPER(TRIM(assessment_type)), '~'),
                    COALESCE(CAST(`date` AS STRING), '~'),
                    COALESCE(CAST(weight AS STRING), '~'))) OVER (PARTITION BY id_assessment)
              <>
            MAX(CONCAT_WS('|',
                    COALESCE(UPPER(TRIM(code_module)), '~'),
                    COALESCE(UPPER(TRIM(code_presentation)), '~'),
                    COALESCE(UPPER(TRIM(assessment_type)), '~'),
                    COALESCE(CAST(`date` AS STRING), '~'),
                    COALESCE(CAST(weight AS STRING), '~'))) OVER (PARTITION BY id_assessment)
              AS key_conflict
        FROM oulad.oulad_bronze.assessments_bronze
    ) t
    WHERE row_num = 1        -- rule: keep one copy per key
      AND NOT key_conflict   -- rule: refuse a key that disagrees with itself
      AND id_assessment IS NOT NULL           
      AND id_assessment > 0                  
      AND code_module IS NOT NULL
      AND code_presentation IS NOT NULL
      -- rule 5, orphan. 
      --AND EXISTS (SELECT 1 FROM oulad.oulad_silver.courses_silver c
                  -- WHERE c.code_module = UPPER(TRIM(t.code_module))
                   -- AND c.code_presentation = UPPER(TRIM(t.code_presentation)))
      -- assessment_type: missing AND invalid are both refused. Only three values exist
      AND UPPER(TRIM(assessment_type)) IN ('TMA', 'CMA', 'EXAM')
      AND weight IS NOT NULL  
      AND weight BETWEEN 0 AND 100 
      AND ingestion_timestamp IS NOT NULL
) AS source
ON  target.id_assessment = source.id_assessment
WHEN MATCHED THEN
    UPDATE SET
        target.code_module         = source.code_module,
        target.code_presentation   = source.code_presentation,
        target.assessment_type     = source.assessment_type,
        target.`date`              = source.`date`,
        target.date_source         = source.date_source,
        target.weight              = source.weight,
        target.ingestion_timestamp = source.ingestion_timestamp,
        target.ingestion_date      = source.ingestion_date
WHEN NOT MATCHED THEN
    INSERT (id_assessment, code_module, code_presentation, assessment_type, `date`, date_source, weight, ingestion_timestamp, ingestion_date)
    VALUES (source.id_assessment, source.code_module, source.code_presentation, source.assessment_type, source.`date`, source.date_source, source.weight, source.ingestion_timestamp, source.ingestion_date);
 
-- Check the table
SELECT *
FROM oulad.oulad_silver.assessments_silver
LIMIT 10;
 