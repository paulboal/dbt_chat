# Data Governance Overview for HCA Analytics

This document defines core concepts for the `hca_analytics` dbt project.

## Unique Encounter Definition
A **Unique Encounter** is defined by a distinct `ENCOUNTER_ID` in the source table. For reporting purposes, we consider an encounter unique if it represents a distinct patient-provider interaction session, regardless of the number of procedures performed.

## Provider ID Handling
The `PCP_ID` (Primary Care Provider ID) used in the `dim_patients` model is sourced directly from the EHR enrollment system. This ID is guaranteed to be non-null for all actively enrolled patients. If a patient is flagged as `IS_HIGH_RISK_PATIENT`, the PCP should be notified via the automated reporting pipeline.

## Diagnosis Codes
All diagnosis codes (`PRIMARY_DX_CODE`) adhere to the ICD-10 standard. The macro `get_dx_group` provides a high-level grouping of these codes for clinical analysis.
