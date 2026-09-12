-- Grain: 1 row per student per module presentation
CREATE TABLE IF NOT EXISTS oulad.oulad_gold.dim_student_enrollment (
    student_enrollment_id STRING,           -- 
    student_id            INT,
    course_id             VARCHAR(100),
    num_of_prev_attempts  INT,
    studied_credits       INT,
    final_result          VARCHAR(50),
    date_registration     INT,              -- days from presentation start; can be negative
    date_unregistration   INT,              -- NULL = did not withdraw.
    ingestion_timestamp   TIMESTAMP
)
USING DELTA;

MERGE INTO oulad.oulad_gold.dim_student_enrollment AS target
USING (
    SELECT
        
        CONCAT(si.id_student, '_',
               UPPER(TRIM(si.code_module)), '_',
               UPPER(TRIM(si.code_presentation)))        AS student_enrollment_id,
        si.id_student                                    AS student_id,
        CONCAT(UPPER(TRIM(si.code_module)), '_',
               UPPER(TRIM(si.code_presentation)))        AS course_id,
        CAST(si.num_of_prev_attempts AS INT)             AS num_of_prev_attempts,
        CAST(si.studied_credits AS INT)                  AS studied_credits,
        TRIM(si.final_result)                            AS final_result,

        CAST(sr.date_registration AS INT)                AS date_registration,

        CAST(sr.date_unregistration AS INT)              AS date_unregistration,
        GREATEST(si.ingestion_timestamp, sr.ingestion_timestamp) AS ingestion_timestamp
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (
                   PARTITION BY code_module, code_presentation, id_student
                   ORDER BY ingestion_timestamp DESC
               ) AS row_num
        FROM oulad.oulad_silver.student_info_silver
        WHERE code_module IS NOT NULL
          AND code_presentation IS NOT NULL
          AND id_student IS NOT NULL
    ) si
    INNER JOIN (
        SELECT *,
               ROW_NUMBER() OVER (
                   PARTITION BY code_module, code_presentation, id_student
                   ORDER BY ingestion_timestamp DESC
               ) AS row_num
        FROM oulad.oulad_silver.student_registration_silver
        WHERE code_module IS NOT NULL
          AND code_presentation IS NOT NULL
          AND id_student IS NOT NULL
    ) sr
        ON si.code_module       = sr.code_module
       AND si.code_presentation = sr.code_presentation
       AND si.id_student        = sr.id_student
    WHERE si.row_num = 1
      AND sr.row_num = 1
) AS source
ON target.student_enrollment_id = source.student_enrollment_id
WHEN MATCHED THEN
    UPDATE SET
        target.student_id           = source.student_id,
        target.course_id            = source.course_id,
        target.num_of_prev_attempts = source.num_of_prev_attempts,
        target.studied_credits      = source.studied_credits,
        target.final_result         = source.final_result,
        target.date_registration    = source.date_registration,
        target.date_unregistration  = source.date_unregistration,   
        target.ingestion_timestamp  = source.ingestion_timestamp
WHEN NOT MATCHED THEN
    INSERT (
        student_enrollment_id, student_id, course_id,
        num_of_prev_attempts, studied_credits, final_result,
        date_registration, date_unregistration, ingestion_timestamp   
    )
    VALUES (
        source.student_enrollment_id, source.student_id, source.course_id,
        source.num_of_prev_attempts, source.studied_credits, source.final_result,
        source.date_registration, source.date_unregistration, source.ingestion_timestamp
    );

 /*   SELECT
    COUNT(*)                                                AS rows,
    COUNT(DISTINCT student_enrollment_id)                   AS distinct_keys,
    SUM(CASE WHEN date_unregistration IS NOT NULL THEN 1 ELSE 0 END) AS withdrew,
    MIN(date_registration)                                  AS min_reg,
    MAX(date_registration)                                  AS max_reg
FROM oulad.oulad_gold.dim_student_enrollment;
*/