CREATE CATALOG IF NOT EXISTS oulad;

USE CATALOG oulad;

-- Raw tables loaded from the original CSV files.
CREATE SCHEMA IF NOT EXISTS oulad_bronze;

-- Cleaned and standardized tables.
CREATE SCHEMA IF NOT EXISTS oulad_silver;

-- Dimension and fact tables.
CREATE SCHEMA IF NOT EXISTS oulad_gold;

-- Data-quality results and invalid records.
CREATE SCHEMA IF NOT EXISTS oulad_quality;


-- Check that the project schemas are available.
SHOW SCHEMAS IN oulad;
