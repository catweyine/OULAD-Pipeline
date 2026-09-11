CREATE OR REPLACE TABLE oulad.oulad_gold.fact_student_engagement
USING DELTA
AS
SELECT
   -- Identity / foreign keys
   XXHASH64(
        sv.id_student,
        sv.id_site,
        sv.date
    ) AS student_engagement_key, -- Surrogate Primary key
  
   sv.id_student,
   sv.id_site,
   dc.course_id,

   -- Time dimension: days since the start of the module-presentation,
   -- per the OULAD data dictionary. Can be negative (access before
   -- the official start date).
   sv.date                AS interaction_date,


   -- Core measure
   sv.sum_click             AS click_count,


   -- Derived: which week of the course this interaction falls in.
   -- FLOOR handles negative interaction_date correctly.
   CAST(FLOOR(sv.date / 7.0) AS INT) AS week_number,


   -- Derived: flags interactions that happened before the course's
   -- official start date, useful for separating "early access"
   -- behavior from in-course engagement.
   CASE WHEN sv.date < 0 THEN TRUE ELSE FALSE END AS is_pre_course_access,


   -- Attributes brought in from dim_vle for convenience in
   -- downstream slicing, without needing a join at query time
   dv.activity_type,
   dv.week_from            AS material_week_from,
   dv.week_to              AS material_week_to


FROM oulad.oulad_silver.student_vle_silver AS sv


LEFT JOIN oulad.oulad_gold.dim_vle AS dv
   ON sv.id_site = dv.vle_id


LEFT JOIN oulad.oulad_gold.dim_course AS dc
   ON sv.code_module = dc.code_module
  AND sv.code_presentation = dc.code_presentation;




-- ---------------------------------------------------------
-- Sanity check: confirm the fact table populated as expected
-- ---------------------------------------------------------
/* SELECT *
FROM oulad.oulad_gold.fact_student_engagement
LIMIT 10;


SELECT COUNT(*) AS total_rows
FROM oulad.oulad_gold.fact_student_engagement;

SELECT COUNT(*) - COUNT(DISTINCT CONCAT_WS('|',
         CAST(id_student AS STRING), CAST(id_site AS STRING),
         CAST(interaction_date AS STRING))) AS duplicate_grain
FROM oulad.oulad_gold.fact_student_engagement;

SELECT
  COUNT(*) - COUNT(DISTINCT CONCAT_WS('|', CAST(id_student AS STRING),
                   CAST(id_site AS STRING), CAST(interaction_date AS STRING))) AS full_key,
  COUNT(*) - COUNT(DISTINCT CONCAT_WS('|', CAST(id_site AS STRING),
                   CAST(interaction_date AS STRING)))                          AS drop_student,
  COUNT(*) - COUNT(DISTINCT CONCAT_WS('|', CAST(id_student AS STRING),
                   CAST(interaction_date AS STRING)))                          AS drop_site,
  COUNT(*) - COUNT(DISTINCT CONCAT_WS('|', CAST(id_student AS STRING),
                   CAST(id_site AS STRING)))                                   AS drop_date
FROM oulad.oulad_gold.fact_student_engagement;
*/