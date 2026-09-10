-- Grain: 1 row per learning resource
-- (id_site)
CREATE TABLE IF NOT EXISTS oulad.oulad_gold.dim_vle (
    vle_id INT,
    activity_type STRING,
    week_from INT,
    week_to INT
)
USING DELTA;

INSERT OVERWRITE oulad.oulad_gold.dim_vle
SELECT DISTINCT
    id_site AS vle_id,
    activity_type,
    week_from,
    week_to
FROM oulad.oulad_silver.vle_silver;