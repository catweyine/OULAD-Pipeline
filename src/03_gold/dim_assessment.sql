{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": 0,
   "metadata": {
    "application/vnd.databricks.v1+cell": {
     "cellMetadata": {
      "byteLimit": 104857600,
      "rowLimit": 1000
     },
     "inputWidgets": {},
     "nuid": "a85b9dc2-38cd-482f-b34b-5e3372e071e6",
     "showTitle": false,
     "tableResultSettingsMap": {},
     "title": ""
    }
   },
   "outputs": [],
   "source": [
    "CREATE OR REPLACE TABLE oulad.oulad_gold.dim_assessment AS\n",
    "SELECT\n",
    "    a.id_assessment AS assessment_key, --Primary key\n",
    "    a.id_assessment, --natural key/source key\n",
    "    XXHASH64(CONCAT_WS('|', a.code_module, a.code_presentation)) AS module_presentation_key,   --foreign key\n",
    "    \n",
    "    a.assessment_type,\n",
    "    a.assessment_type = 'Exam' AS is_exam,\n",
    "    a.date AS assessment_day_offset, -- rename date for clarity (date is information about the final submission date of the assessment calculated as the number of days since the start of the module-presentation.\n",
    "    a.weight,\n",
    "    CASE\n",
    "        WHEN assessment_day_offset IS NULL THEN 'unscheduled'\n",
    "        WHEN c.module_presentation_length IS NULL THEN 'unknown'\n",
    "        WHEN assessment_day_offset <= c.module_presentation_length * 0.33 THEN 'early'\n",
    "        WHEN assessment_day_offset <= c.module_presentation_length * 0.66 THEN 'mid'\n",
    "        ELSE 'late' END AS presentation_phase\n",
    "FROM oulad.oulad_silver.assessments_silver a\n",
    "LEFT JOIN oulad.oulad_silver.courses_silver c\n",
    "       ON a.code_module = c.code_module\n",
    "      AND a.code_presentation = c.code_presentation;"
   ]
  }
 ],
 "metadata": {
  "application/vnd.databricks.v1+notebook": {
   "computePreferences": null,
   "dashboards": [],
   "environmentMetadata": null,
   "inputWidgetPreferences": null,
   "language": "sql",
   "notebookMetadata": {
    "pythonIndentUnit": 4,
    "sqlQueryOptions": {
     "applyAutoLimit": true,
     "catalog": "workspace",
     "metastore": null,
     "schema": "default"
    }
   },
   "notebookName": "dim_assessment.sql.dbquery.ipynb",
   "widgets": {}
  },
  "language_info": {
   "name": "sql"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 0
}
