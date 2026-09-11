CREATE TABLE IF NOT EXISTS oulad.oulad_gold.dim_course_week (
    course_id STRING,
    week_id INT,
    week_number INT,
    phase_id INT
)
USING DELTA;

MERGE INTO oulad.oulad_gold.dim_course_week AS tgt
USING (

    WITH week_bounds AS (
        SELECT
            CAST(FLOOR(MIN(date) / 7.0) AS INT) AS min_week,
            CAST(CEIL(MAX(date) / 7.0) AS INT) AS max_week
        FROM oulad.oulad_silver.student_vle_silver
    ),

    generated_weeks AS (
        SELECT
            EXPLODE(SEQUENCE(min_week, max_week)) AS week_number
        FROM week_bounds
    )

    SELECT
        CONCAT(c.code_module, '_', c.code_presentation) AS course_id,
        w.week_number AS week_id,
        w.week_number,

        CASE
            WHEN w.week_number <= 10 THEN 1
            WHEN w.week_number <= 20 THEN 2
            ELSE 3
        END AS phase_id

    FROM (
        SELECT DISTINCT
            code_module,
            code_presentation
        FROM oulad.oulad_silver.courses_silver
    ) c

    CROSS JOIN generated_weeks w

) src

ON tgt.course_id = src.course_id
AND tgt.week_id = src.week_id

WHEN MATCHED THEN
UPDATE SET
    tgt.week_number = src.week_number,
    tgt.phase_id = src.phase_id

WHEN NOT MATCHED THEN
INSERT (
    course_id,
    week_id,
    week_number,
    phase_id
)
VALUES (
    src.course_id,
    src.week_id,
    src.week_number,
    src.phase_id
);