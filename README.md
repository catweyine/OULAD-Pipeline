# OULAD Data Pipeline
**Project Status:** Week 7 FTW Activity  
**Pipeline Pattern:** Bronze → Silver → Gold → Quality Check → Dashboard <br>
**Query Language:** SQL

----

## Project Overview

This project implements a data pipeline for the Open University Learning Analytics Dataset (OULAD). The pipeline transforms raw student interaction data into clean, analysis-ready tables to answer key business questions about student engagement, performance, and withdrawal patterns.

The OULAD dataset contains data from courses at the Open University, including student demographics, assessment results, and daily interaction with the Virtual Learning Environment (VLE).

## Repository Structure

```
OULAD-Pipeline/
├── README.md                      
├── source_code/
│   ├── 00_setup/
│   │   └── 01_setup.sql             
│   ├── 01_bronze/
│   │   ├── 02_bronze_assessments.sql  
│   │   ├── 03_bronze_courses.sql     
│   │   ├── 04_bronze_students.sql    
│   │   ├── 05_bronze_studentAssessment.sql   
│   │   ├── 06_bronze_studentVle.sql     
│   │   ├── 07_bronze_vle.sql         
│   │   └── 08_bronze_studentRegistration.sql 
│   ├── 02_silver/
│   │   ├── 09_silver_assessments.sql    
│   │   ├── 10_silver_courses.sql        
│   │   ├── 11_silver_students.sql    
│   │   ├── 12_silver_studentAssessment.sql   
│   │   ├── 13_silver_studentVle.sql    
│   │   ├── 14_silver_vle.sql         
│   │   └── 15_silver_studentRegistration.sql 
│   └── 03_gold/
│       ├── 16_gold_dim_student.sql    
│       ├── 17_gold_dim_course.sql      
│       ├── 18_gold_dim_assessment.sql   
│       ├── 19_gold_fact_student_vle.sql
│       └── 20_gold_fact_assessment_scores.sql
└── quality_check/
    ├── 09_bronze_validation.sql      
    ├── 16_silver_validation.sql       
    └── 11_gold_validation.sql           
```

## Naming Convention

| Layer | Schema | Table Naming | Examples |
|-------|--------|----------------------|----------|
| Bronze | `workspace.oulad_bronze` | `bronze_<table_name>` | `bronze_students`, `bronze_assessments` |
| Silver | `workspace.oulad_silver` | `silver_<table_name>` | `silver_students`, `silver_assessments` |
| Gold | `workspace.oulad_gold` | `gold_dim_<name>` <br>`gold_fact_<name>`  | `gold_dim_student`, <br>`gold_fact_student_vle` |

**Layer Descriptions:**
* **Bronze** — Data loaded as-is from source files
* **Silver** — Type casting, TRIM, NULLIF, validation
* **Gold** — Fact and dimension tables optimized for analysis

## Pipeline Architecture

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐
│   Bronze    │      │   Silver     │      │    Gold     │
│  (Source)   │ ───> │  (Cleaned)   │ ───> │  (Marts)    │
└─────────────┘      └──────────────┘      └─────────────┘
   oulad_bronze        oulad_silver         oulad_gold
```

### Layer Details

1. **Bronze Layer** — Loads data from source files into staging tables with minimal transformation
2. **Silver Layer** — Applies data quality rules:
   * Type casting (dates, numerics)
   * String cleaning (TRIM, NULLIF for empty strings)
   * Range validation (CASE/WHEN for valid values)
   * Referential integrity checks
3. **Gold Layer** — Creates star schema with:
   * Dimension tables (students, courses, assessments, modules)
   * Fact tables (student interactions, assessment scores, VLE activity)

## Business Questions

This pipeline enables analysis to answer key questions about student success:

### How does student engagement relate to performance?
* Correlation between VLE activity frequency and final assessment scores
* Optimal engagement patterns for course completion
* Early indicators of high-performing students

### What patterns appear among students who withdraw?
* Common characteristics of students who withdraw early vs. late
* VLE activity decline patterns before withdrawal
* Assessment performance trajectory leading to withdrawal

### How does student activity change throughout a course?
* Peak activity periods (before assessments, start/end of course)
* Engagement drop-off points
* Resource access patterns over time

## How to Run

### Execution Steps

1. **Setup Schemas**
   * Execute `source_code/00_setup/01_setup.sql`
   * Creates `workspace.oulad_bronze`, `workspace.oulad_silver`, `workspace.oulad_gold` schemas

2. **Load Raw Data**
   * Execute all files in `source_code/01_bronze/` folder (in numeric order)
   * Each file loads one source table into `workspace.oulad_bronze`
   * Verify row counts and schema after loading

3. **Clean and Transform**
   * Execute all files in `source_code/02_silver/` folder (in numeric order)
   * Creates cleaned tables in `workspace.oulad_silver`
   * Review data quality check results

4. **Create Gold Marts**
   * Execute all files in `source_code/03_gold/` folder (in numeric order)
   * Builds fact and dimension tables in `workspace.oulad_gold`
   * Ready for analysis and dashboard creation

5. **Data Quality Validation** 
   * Execute `quality_check/09_bronze_validation.sql` to validate bronze layer
   * Execute `quality_check/10_silver_validation.sql` to validate silver layer
   * Execute `quality_check/11_gold_validation.sql` to validate gold layer



