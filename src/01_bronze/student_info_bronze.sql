CREATE TABLE IF NOT EXISTS oulad.oulad_bronze.student_info_bronze
USING DELTA
AS
SELECT *,
       current_timestamp() AS ingestion_timestamp,
       current_date() AS ingestion_date
FROM read_files(
  '/Volumes/workspace/default/ftw_b12_de/shared/week07/studentInfo.csv',
  format => 'csv',
  header => true
);

