# Data Quality Checks and Results

## Audit Rules Applied

| Data Quality Issue | Condition | Severity Level | Required Audit Action |
|----------|----------|----------|----------|
| Missing Data | 0%–4.99% dropped rows | Acceptable | Log baseline and final row count. Proceed. |
| Missing Data | 5%–10% dropped rows | Warning | Log percentage dropped and document rationale. |
| Missing Data | >10% dropped rows | Unusable | Halt processing and escalate. |
| Invalid Values | ?, out of range, negative values | Flagged | Isolate affected rows and document remediation. |
| Domain Violation | Value not in approved list | Flagged | Log invalid value and document mapping decision. |

---

# Dataset Reviews

> Each dataset follows the same format to ensure a consistent audit trail and simplify future additions.

---

## Courses

### Dataset Information

| Item | Value |
|--------|--------|
| Bronze Table | courses_bronze |
| Silver Table | courses_silver |
| Business Key | (code_module, code_presentation) |
| Operator / Script | courses_dq.sql |
| Audit Date | 2026-09-08 |

### Data Quality Results

| Check | Result | Severity | Action |
|---------|---------|---------|---------|
| Row Count | 22 | ✅ Acceptable | Logged |
| Duplicate Keys | 0 | ✅ Acceptable | No action required |
| Missing Values | 0 | ✅ Acceptable | No action required |
| Invalid Presentation Length | 0 | ✅ Acceptable | No action required |

### Silver Transformations

- Removed duplicate rows using `DISTINCT`
- Standardized `code_module` with `UPPER(TRIM())`
- Standardized `code_presentation` with `UPPER(TRIM())`
- Cast `module_presentation_length` to `INT`
- Retained ingestion metadata columns

### Audit Log

| Metric | Value |
|----------|----------|
| Pre-Check Volume | 22 |
| Post-Check Volume | 22 |
| Rows Dropped | 0 |
| Percent Dropped | 0.00% |
| Flags Triggered | 0 |

### Overall Health

✅ **PASS**

No data quality issues identified. Dataset is approved for downstream consumption.

---

## VLE

### Dataset Information

| Item | Value |
|--------|--------|
| Bronze Table | vle_bronze |
| Silver Table | vle_silver |
| Business Key | id_site |
| Operator / Script | vle_dq.sql |
| Audit Date | 2026-09-08 |

### Data Quality Results

| Check | Result | Severity | Action |
|---------|---------|---------|---------|
| Row Count | 6,364 | ✅ Acceptable | Logged |
| Duplicate Keys | 0 | ✅ Acceptable | No action required |
| Missing Business Fields | 0 | ✅ Acceptable | No action required |
| Activity Type Validation | 20 valid activity types | ✅ Acceptable | No action required |
| Invalid Week Ranges | 0 | ✅ Acceptable | No action required |
| Invalid Placeholder Values (?) | 5,243 records | ⚠️ Flagged | Converted to NULL |

### Silver Transformations

- Removed duplicate rows using `DISTINCT`
- Standardized module and presentation codes
- Standardized `activity_type`
- Converted `'?'` values to `NULL`
- Cast week fields to `INT`
- Retained ingestion metadata columns

### Audit Log

| Metric | Value |
|----------|----------|
| Pre-Check Volume | 6,364 |
| Post-Check Volume | 6,364 |
| Rows Dropped | 0 |
| Percent Dropped | 0.00% |
| Flags Triggered | 5,243 invalid placeholder values |

### Remediation Notes

The source dataset stores unknown week values as `'?'`.

These records were retained and transformed using:

```sql
TRY_CAST(NULLIF(week_from, '?') AS INT)
TRY_CAST(NULLIF(week_to, '?') AS INT)
```

Resulting values were converted to `NULL`.

No rows were removed.

### Overall Health

⚠️ **WARN**

Dataset is suitable for downstream analysis. Invalid placeholder values were documented and handled according to the audit rules.

---

# Pipeline Summary

| Dataset | Health | Dropped Rows | Flags Triggered |
|----------|----------|----------:|----------:|
| Courses | ✅ PASS | 0 | 0 |
| VLE | ⚠️ WARN | 0 | 5,243 |

## Overall Pipeline Health

⚠️ **WARN**

No critical data quality failures were identified.

The only flagged issue was the presence of source-system placeholder values (`'?'`) in the VLE dataset. These values were converted to `NULL` and documented according to audit requirements.

---

# Template For Additional Tables

Copy the section below when onboarding a new dataset:

```md
## <Dataset Name>

### Dataset Information

| Item | Value |
|--------|--------|
| Bronze Table | |
| Silver Table | |
| Business Key | |
| Operator / Script | |
| Audit Date | |

### Data Quality Results

| Check | Result | Severity | Action |
|---------|---------|---------|---------|

### Silver Transformations

- ...

### Audit Log

| Metric | Value |
|----------|----------|
| Pre-Check Volume | |
| Post-Check Volume | |
| Rows Dropped | |
| Percent Dropped | |
| Flags Triggered | |

### Overall Health

✅ PASS / ⚠️ WARN / ❌ FAIL
```