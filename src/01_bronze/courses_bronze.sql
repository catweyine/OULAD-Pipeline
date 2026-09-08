CREATE TABLE IF NOT EXISTS oulad.oulad_bronze.courses_bronze
USING DELTA
AS
SELECT *,
  current_timestamp() AS ingestion_timestamp,
  current_date() AS ingestion_date
FROM read_files('/Volumes/instacart/default/ftw_b12_de/shared/week07/courses.csv');