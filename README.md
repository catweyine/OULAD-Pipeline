# OULAD Data Pipeline
**Project Status:** Week 7 FTW Activity  
**Pipeline Pattern:** Setup → Bronze → Quality Check → Silver → Quality Check → Gold → Quality Check → Dashboard <br>
**Query Language:** SQL

----

## Project Overview

This project implements a data pipeline for the Open University Learning Analytics Dataset (OULAD). The pipeline transforms raw student interaction data into clean, analysis-ready tables to answer key business questions about student engagement, performance, and withdrawal patterns.

The OULAD dataset contains data from courses at the Open University, including student demographics, assessment results, and daily interaction with the Virtual Learning Environment (VLE).

## Repository Structure

```
OULAD-Pipeline/
├── README.md                      
├── src/
│   ├── 00_setup/
│   │   ├── 00_setup.sql
│   │   └── 01_source_inspection.ip.ipynb
│   ├── 01_bronze/
│   │   ├── assessments_bronze.sql  
│   │   ├── courses_bronze.sql     
│   │   ├── student_assessment_bronze.sql   
│   │   ├── student_info_bronze.sql    
│   │   ├── student_registration_bronze.sql 
│   │   ├── student_vle_bronze.sql     
│   │   └── vle_bronze.sql         
│   ├── 02_silver/
│   │   ├── assessments_clean.sql    
│   │   ├── courses_clean.sql        
│   │   ├── student_assessment_clean.sql   
│   │   ├── student_info_clean.sql    
│   │   ├── student_registration_clean.sql 
│   │   ├── student_vle_clean.sql    
│   │   └── vle_clean.sql         
│   └── 03_gold/
│       ├── dim_assessment.sql
│       ├── dim_course.sql
│       ├── dim_course_phase.sql
│       ├── dim_course_week.sql
│       ├── dim_student.sql
│       ├── dim_student_enrollment.sql
│       ├── dim_student_info.sql
│       ├── dim_vle.sql
│       ├── fact_student_performance.sql
│       └── fact_student_vle_engagement.sql
└── tests/
    ├── bronze_validation
    ├── silver_validation       
    └── gold_validation           
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
       ┌─────────────────────┐
       │  00_setup.sql      │
       │  source_inspection │
       └──────────┬──────────┘
                  │
                  ↓
       ┌──────────┴──────────┐
       │   Bronze Layer     │
       │   (7 tables)       │
       │   oulad_bronze     │
       └──────────┬──────────┘
                  │
                  ↓
       ┌──────────┴──────────┐
       │ ✅ Quality Check   │
       │ bronze_validation │
       └──────────┬──────────┘
                  │
                  ↓
       ┌──────────┴──────────┐
       │   Silver Layer     │
       │   (7 tables)       │
       │   oulad_silver     │
       └──────────┬──────────┘
                  │
                  ↓
       ┌──────────┴──────────┐
       │ ✅ Quality Check   │
       │ silver_validation │
       └──────────┬──────────┘
                  │
                  ↓
       ┌──────────┴──────────┐
       │   Gold Layer       │
       │   (8 dim, 2 fact)  │
       │   oulad_gold       │
       └──────────┬──────────┘
                  │
                  ↓
       ┌──────────┴──────────┐
       │ ✅ Quality Check   │
       │ gold_validation   │
       └─────────────────────┘
```

### Layer Details

1. **Bronze Layer** — Loads data from source files into staging tables with minimal transformation
2. **Silver Layer** — Applies data quality rules:
   * Type casting (dates, numerics)
   * String cleaning (TRIM, NULLIF for empty strings)
   * Range validation (CASE/WHEN for valid values)
   * Referential integrity checks
3. **Gold Layer** — Creates star schema with:
   * **Dimension tables (8):** dim_student, dim_student_info, dim_student_enrollment, dim_course, dim_course_phase, dim_course_week, dim_assessment, dim_vle
   * **Fact tables (2):** fact_student_performance, fact_student_vle_engagement

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
   * Execute `src/00_setup/00_setup.sql`
   * Creates `workspace.oulad_bronze`, `workspace.oulad_silver`, `workspace.oulad_gold` schemas

2. **Source Inspection**
   * Execute `src/00_setup/01_source_inspection.ip.ipynb`
   * Inspects source data files and validates structure

3. **Load Raw Data (Bronze Layer)**
   * Execute all files in `src/01_bronze/` folder
   * Each file loads one source table into `workspace.oulad_bronze`
   * 7 tables: assessments, courses, student_assessment, student_info, student_registration, student_vle, vle

4. **Bronze Quality Validation**
   * Execute `tests/bronze_validation`
   * Validates bronze layer row counts, schema, and data integrity

5. **Clean and Transform (Silver Layer)**
   * Execute all files in `src/02_silver/` folder
   * Creates cleaned tables in `workspace.oulad_silver`
   * Applies type casting, TRIM, NULLIF, validation rules

6. **Silver Quality Validation**
   * Execute `tests/silver_validation`
   * Validates silver layer data quality and transformation rules

7. **Create Gold Marts**
   * Execute all files in `src/03_gold/` folder
   * Builds 8 dimension tables (student, course, assessment, VLE, enrollment, phases, weeks) and 2 fact tables (student performance, VLE engagement) in `workspace.oulad_gold`
   * Ready for analysis and dashboard creation

8. **Gold Quality Validation**
   * Execute `tests/gold_validation`
   * Final validation of gold layer dimensional models and metrics



