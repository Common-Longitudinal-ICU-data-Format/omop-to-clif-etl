# OMOP-to-CLIF ETL

## Overview

This repository contains SQL scripts and supporting documentation developed as part of Stanford's implementation of the Common Longitudinal ICU Data Format (CLIF) using data from the Observational Medical Outcomes Partnership (OMOP) Common Data Model.

The purpose of this repository is to share our mapping approaches, transformation logic, and implementation decisions with external collaborators who are developing similar OMOP-to-CLIF pipelines.

The scripts are written in Google BigQuery SQL and are intended to serve as reference implementations rather than fully portable ETL pipelines.

## Repository Contents

The repository will include SQL scripts for constructing CLIF tables from OMOP data, along with relevant mapping notes and documentation.

The initial scripts focus on:

- **Hospitalization:** Identifying inpatient encounters using OMOP `visit_occurrence` and mapping demographic information, admission/discharge timestamps, and admission/discharge categories to CLIF specifications.
- **ADT:** Reconstructing patient movement between hospital locations using OMOP `visit_detail` and `care_site`, linked to the hospitalization cohort.

Additional CLIF table mappings will be added as they are reviewed and prepared for sharing.

## Implementation Notes

Our approach uses OMOP tables as the primary data source, supplemented by direct Epic extracts when additional granularity is required.

Some transformations rely on source-specific fields, JSON structures, or institution-specific values. These mappings are documented within the SQL scripts and may require modification to accommodate differences in local OMOP implementations.

The hospitalization table serves as the foundational cohort for linking records across the remaining CLIF tables.

## Important Considerations

- **Work in progress:** The scripts reflect ongoing development and quality control. Mapping logic may change as validation continues.
- **Institution-specific mappings:** Source values, admission/discharge categories, and other transformations should be reviewed and adapted to local data.
- **Local validation required:** Collaborators should independently assess data completeness, cohort definitions, record counts, and mapping accuracy before using these scripts for research or production.
- **Data privacy:** This repository is intended to contain code and documentation only, without patient-level data or protected health information (PHI).

## Collaboration

These materials are shared to facilitate technical collaboration, comparison of mapping approaches, and development of OMOP-to-CLIF pipelines across institutions.

Questions, feedback, and discussions about mapping decisions are welcome.

## References

- [CLIF Website](https://clif-icu.com/)
- [CLIF GitHub Organization](https://github.com/Common-Longitudinal-ICU-data-Format)
- [OHDSI / OMOP Common Data Model](https://ohdsi.github.io/CommonDataModel/)
