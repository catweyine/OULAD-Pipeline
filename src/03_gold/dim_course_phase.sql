CREATE TABLE IF NOT EXISTS oulad.oulad_gold.dim_course_phase (
    phase_id INT,
    phase_name STRING
)
USING DELTA;

MERGE INTO oulad.oulad_gold.dim_course_phase AS tgt
USING (

    SELECT 1 AS phase_id, 'Early' AS phase_name
    UNION ALL
    SELECT 2 AS phase_id, 'Middle' AS phase_name
    UNION ALL
    SELECT 3 AS phase_id, 'Late' AS phase_name

) src

ON tgt.phase_id = src.phase_id

WHEN MATCHED THEN
UPDATE SET
    tgt.phase_name = src.phase_name

WHEN NOT MATCHED THEN
INSERT (
    phase_id,
    phase_name
)
VALUES (
    src.phase_id,
    src.phase_name
);