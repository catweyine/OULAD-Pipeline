CREATE TABLE IF NOT EXISTS oulad.oulad_bronze.student_registration_bronze
USING DELTA
AS
SELECT *,
       current_timestamp() AS ingestion_timestamp,
       current_date() AS ingestion_date
FROM read_files(
  '/Volumes/workspace/default/ftw-b12-de/shared/week07/studentRegistration.csv',
  format => 'csv',
  header => true
);
