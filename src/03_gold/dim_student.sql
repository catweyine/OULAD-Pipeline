-- Create dimension table for student demographic information
CREATE TABLE IF NOT EXISTS oulad.oulad_gold.dim_student (
    student_id INT,
    gender VARCHAR(10),
    region VARCHAR(100),
    highest_education VARCHAR(100),
    imd_band VARCHAR(50),
    age_band VARCHAR(50),
    disability VARCHAR(10),
    ingestion_timestamp TIMESTAMP,
    PRIMARY KEY (student_id)
)
USING DELTA;

-- Merge deduplicated student demographic records
MERGE INTO oulad.oulad_gold.dim_student AS target
USING (
    SELECT 
        id_student AS student_id,
        TRIM(gender) AS gender,
        TRIM(region) AS region,
        TRIM(highest_education) AS highest_education,
        TRIM(imd_band) AS imd_band,
        TRIM(age_band) AS age_band,
        TRIM(disability) AS disability,
        ingestion_timestamp
    FROM (
        SELECT 
            id_student,
            gender,
            region,
            highest_education,
            imd_band,
            age_band,
            disability,
            ingestion_timestamp,
            ROW_NUMBER() OVER (
                PARTITION BY id_student 
                ORDER BY ingestion_timestamp DESC
            ) AS row_num
        FROM oulad.oulad_silver.student_info_silver
        WHERE id_student IS NOT NULL
    )
    WHERE row_num = 1
) AS source
ON target.student_id = source.student_id
WHEN MATCHED THEN
    UPDATE SET
        target.gender = source.gender,
        target.region = source.region,
        target.highest_education = source.highest_education,
        target.imd_band = source.imd_band,
        target.age_band = source.age_band,
        target.disability = source.disability,
        target.ingestion_timestamp = source.ingestion_timestamp
WHEN NOT MATCHED THEN
    INSERT (student_id, gender, region, highest_education, imd_band, age_band, disability, ingestion_timestamp)
    VALUES (source.student_id, source.gender, source.region, source.highest_education, source.imd_band, source.age_band, source.disability, source.ingestion_timestamp);

-- Verify dim_student
SELECT *
FROM oulad.oulad_gold.dim_student
LIMIT 10;