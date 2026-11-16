/*
  EXTERNAL COLLABORATOR TEMPLATE — OMOP -> CLIF hospitalization (BigQuery Standard SQL)


  BEFORE RUNNING:
  1. Replace YOUR_PROJECT, YOUR_OMOP_DATASET, YOUR_CLIF_DATASET.
  2. Confirm that visit_source_value, admitted_from_source_value, and
     discharged_to_source_value contain JSON with the keys used below.
     These JSON paths are source-implementation-specific, NOT standard OMOP fields.
  3. Review the generic mapping examples and ADD institution-specific source
     values only after profiling local data. No invented placeholder values are
     used in executable CASE conditions.
  4. Review all admission/discharge labels, CASE priority, and CLIF version.
  5. Validate source field completeness, date ranges, row counts, duplicates,
     and classification distributions against local data.


  No patient records are included. Internal project/dataset identifiers and
  recognizable institution-specific source labels have been removed.

*/

/* ===========================================================================
   HOSPITALIZATION — example admission type logic
   ---------------------------------------------------------------------------
   Source:
     OMOP visit_occurrence + person + location

   Population:
     All OMOP-defined inpatient hospitalizations:
       visit_concept_id = 9201

   IMPLEMENTATION NOTE (source-specific JSON):
     - admission_type_name is the original admission type extracted from
       visit_source_value JSON key hosp_admsn_type.
     - admitted_from_source_value JSON key admit_source helps assign
       admission_type_category (especially transfer/facility/direct cases).
     - discharged_to_source_value JSON key disch_disp is used for discharge.
     - These JSON structures are NOT guaranteed by the OMOP CDM; replace
       the extraction logic if local source columns use other formats.
   =========================================================================== */

CREATE OR REPLACE TABLE
  `YOUR_PROJECT.YOUR_CLIF_DATASET.hospitalization` AS

WITH src AS (

  SELECT
    v.*,

    JSON_VALUE(
      v.visit_source_value,
      '$.hosp_admsn_type'
    ) AS hosp_admsn_type,

    JSON_VALUE(
      v.admitted_from_source_value,
      '$.admit_source'
    ) AS admit_source,

    -- Replace this JSON path if local discharged_to_source_value is not JSON.
    JSON_VALUE(
      v.discharged_to_source_value,
      '$.disch_disp'
    ) AS disch_disp

  FROM
    `YOUR_PROJECT.YOUR_OMOP_DATASET.visit_occurrence` v

  WHERE
    v.visit_concept_id = 9201  -- OMOP inpatient visit; verify local cohort coverage
)


SELECT

  /* ==========================================================
     IDENTIFIERS — derived from OMOP IDs, not patient records
     ========================================================== */

  CAST(v.person_id AS STRING)
    AS patient_id,

  CAST(v.visit_occurrence_id AS STRING)
    AS hospitalization_id,

  CAST(v.preceding_visit_occurrence_id AS STRING)
    AS hospitalization_joined_id,


  /* ==========================================================
     HOSPITALIZATION TIMES
     ========================================================== */

  v.visit_start_datetime
    AS admission_dttm,

  v.visit_end_datetime
    AS discharge_dttm,


  /* ==========================================================
     AGE AT ADMISSION
     NOTE: Missing month/day defaults to January 1; de-identification or
     date shifting can affect age accuracy. Review locally.
     ========================================================== */

  CAST(
    FLOOR(
      DATE_DIFF(
        DATE(v.visit_start_datetime),
        COALESCE(
          DATE(p.birth_datetime),
          DATE(
            p.year_of_birth,
            COALESCE(p.month_of_birth, 1),
            COALESCE(p.day_of_birth, 1)
          )
        ),
        DAY
      ) / 365.25
    ) AS INT64
  ) AS age_at_admission,


  /* ==========================================================
     ADMISSION TYPE NAME
     Original hospital admission type from source
     ========================================================== */

  v.hosp_admsn_type
    AS admission_type_name,


  /* ==========================================================
     ADMISSION TYPE CATEGORY — CLIF 2.1.0
     EXAMPLE RULES ONLY. Profile local distinct source values and validate
     priority: CASE uses the FIRST matching rule.

     Permissible:
       ed
       facility
       osh
       direct
       elective
       other

     Logic:
       - Preserve explicit outside-hospital/facility transfer context
       - Explicit elective admissions -> elective
       - Explicit emergency/emergent/trauma -> ed
       - Clinic/physician referrals -> direct when not otherwise
         classified as emergency/elective/transfer
       - Remaining urgent/newborn/unknown -> other unless source
         gives a more specific CLIF category
     ========================================================== */

  CASE

    /* ----------------------------------------------------------
       OUTSIDE HOSPITAL TRANSFER
       ---------------------------------------------------------- */

    WHEN LOWER(COALESCE(v.admit_source, '')) IN (
      'acute care facility',
      'transfer from acute hospital (different facility)'
    )
      THEN 'osh'


    /* ----------------------------------------------------------
       FACILITY
       ---------------------------------------------------------- */

    WHEN LOWER(COALESCE(v.admit_source, '')) IN (
      'snf or icf',
      'other health care facility (includes nursing homes)',
      'transfer from a different type of inpatient health care facility',
      'transfer from a skilled nursing facility/intermediate care facility',
      'residential care facility',
      'hospice'
    )
      THEN 'facility'


    /* ----------------------------------------------------------
       ELECTIVE / PLANNED
       ---------------------------------------------------------- */

    WHEN LOWER(COALESCE(v.hosp_admsn_type, '')) = 'elective'
      THEN 'elective'


    /* ----------------------------------------------------------
       EMERGENCY / EMERGENT / TRAUMA
       ---------------------------------------------------------- */

    WHEN LOWER(COALESCE(v.hosp_admsn_type, '')) IN (
      'emergency',
      'emergent',
      'emergent/emtala',
      'trauma center'
    )
      THEN 'ed'


    /* Explicit ED source if source admission type is missing/other */
    WHEN LOWER(COALESCE(v.admit_source, '')) IN (



      'emergency room'
    )
      THEN 'ed'


    /* ----------------------------------------------------------
       DIRECT ADMISSION / REFERRAL
       ---------------------------------------------------------- */

    WHEN LOWER(COALESCE(v.admit_source, '')) IN (
      "community clinic or physician's office",


      'physician referral',

      'community ambulatory surgery center',
      'transfer from ambulatory surgery center',
      'hmo referral'
    )
      THEN 'direct'


    /* ----------------------------------------------------------
       URGENT FROM HOME / COMMUNITY
       No explicit CLIF "urgent" category exists.
       These are community-origin unscheduled admissions.
     CAUTION: mapping urgent-from-home to ed is an implementation
     assumption, not an OMOP or universal CLIF rule.
       ---------------------------------------------------------- */

    WHEN LOWER(COALESCE(v.hosp_admsn_type, '')) = 'urgent'
      AND LOWER(COALESCE(v.admit_source, '')) IN (
        'home',
        'home or workplace',
        'workplace',
        'self referral',
        'court/law enforcement agency',
        'transfer from prison, jail, court',
        'non healthcare facility point of origin'
      )
      THEN 'ed'


    /* ----------------------------------------------------------
       OTHER / NEWBORN / UNKNOWN / INTERNAL TRANSFER
       ---------------------------------------------------------- */

    ELSE 'other'

  END AS admission_type_category,


  /* ==========================================================
     DISCHARGE NAME
     ========================================================== */

  v.disch_disp
    AS discharge_name,


  /* ==========================================================
     DISCHARGE CATEGORY — CLIF 2.1.0
     Example text-pattern rules. Broad LIKE matches can misclassify records;
     validate category counts and individual source labels locally.
     ========================================================== */

  CASE

    WHEN v.disch_disp IS NULL
      THEN 'Missing'


    /* Expired */
    WHEN LOWER(v.disch_disp) LIKE '%expired%'
      OR LOWER(v.disch_disp) LIKE '%deceased%'
      OR LOWER(v.disch_disp) = 'death'
      THEN 'Expired'


    /* Hospice — before Home */
    WHEN LOWER(v.disch_disp) LIKE '%hospice%'
      THEN 'Hospice'


    /* Skilled Nursing Facility */
    WHEN LOWER(v.disch_disp) LIKE '%skilled nursing%'
      OR LOWER(v.disch_disp) LIKE '%transferred to other snf%'
      OR LOWER(v.disch_disp) LIKE '%nursing facility%'
      OR LOWER(v.disch_disp) LIKE '%swing bed%'
      THEN 'Skilled Nursing Facility (SNF)'


    /* Acute Inpatient Rehab */
    WHEN LOWER(v.disch_disp) LIKE '%inpatient rehabilitation%'
      OR LOWER(v.disch_disp) LIKE '%inpatient rehab%'

      THEN 'Acute Inpatient Rehab Facility'


    /* LTACH */
    WHEN LOWER(v.disch_disp) LIKE '%long term care hospital%'
      OR LOWER(v.disch_disp) LIKE '%long-term care hospital%'
      OR LOWER(v.disch_disp) LIKE '%ltch%'
      OR LOWER(v.disch_disp) LIKE '%long term care/subacute%'
      THEN 'Long Term Care Hospital (LTACH)'


    /* AMA */
    WHEN LOWER(v.disch_disp) LIKE '%against medical advice%'
      OR LOWER(v.disch_disp) LIKE '%left without being seen%'
      OR LOWER(v.disch_disp) LIKE '%left before treatment complete%'
      OR LOWER(v.disch_disp) LIKE '%discontinued care%'
      THEN 'Against Medical Advice (AMA)'


    /* Psychiatric Hospital */
    WHEN LOWER(v.disch_disp) LIKE '%psychiatric hospital%'

      OR LOWER(v.disch_disp) LIKE '%psychiatric unit%'
      THEN 'Psychiatric Hospital'


    /* Jail */
    WHEN LOWER(v.disch_disp) LIKE '%jail%'
      OR LOWER(v.disch_disp) LIKE '%prison%'
      OR LOWER(v.disch_disp) LIKE '%police custody%'
      OR LOWER(v.disch_disp) LIKE '%law enforcement custody%'
      THEN 'Jail'


    /* Assisted Living */
    WHEN LOWER(v.disch_disp) LIKE '%residential care facility%'
      OR LOWER(v.disch_disp) LIKE '%custodial or supportive care facility%'
      OR LOWER(v.disch_disp) LIKE '%assisted living%'
      THEN 'Assisted Living'


    /* Group Home */
    WHEN LOWER(v.disch_disp) LIKE '%group home%'
      OR LOWER(v.disch_disp) LIKE '%group living%'
      THEN 'Group Home'


    /* Chemical Dependency */
    WHEN LOWER(v.disch_disp) LIKE '%chemical dependency%'
      OR LOWER(v.disch_disp) LIKE '%chem dep%'
      OR LOWER(v.disch_disp) LIKE '%intensive cd facility%'
      THEN 'Chemical Dependency'


    /* Shelter */
    WHEN LOWER(v.disch_disp) LIKE '%shelter%'
      THEN 'Shelter'


    /* Acute Care Hospital */
    WHEN LOWER(v.disch_disp) LIKE '%acute care hospital%'
      OR LOWER(v.disch_disp) LIKE '%acute inpatient hospital%'
      OR LOWER(v.disch_disp) LIKE '%children%'


      OR LOWER(v.disch_disp) LIKE '%federal hospital%'
      OR LOWER(v.disch_disp) LIKE '%critical access hospital%'
      THEN 'Acute Care Hospital'


    /* Still admitted */
    WHEN LOWER(v.disch_disp) LIKE '%still patient%'
      OR LOWER(v.disch_disp) LIKE '%interim coding%'
      OR LOWER(v.disch_disp) LIKE '%admitted as inpatient%'
      THEN 'Still Admitted'


    /* Home — after Hospice */
    WHEN LOWER(v.disch_disp) LIKE '%home%'
      OR LOWER(v.disch_disp) LIKE '%local hotel/residence%'

      THEN 'Home'


    ELSE 'Other'

  END AS discharge_category,


  /* ==========================================================
     GEOGRAPHIC VARIABLES
     From patient-linked OMOP location, NOT hospital care-site location.
     Do not export patient-level geography; validate privacy policy and
     local code formats before any downstream use.
     ========================================================== */

  CAST(NULL AS STRING)
    AS zipcode_nine_digit,

  CAST(loc.zip AS STRING)
    AS zipcode_five_digit,

  CAST(NULL AS STRING)
    AS census_block_code,

  CAST(NULL AS STRING)
    AS census_block_group_code,

  CAST(NULL AS STRING)
    AS census_tract,

  CAST(NULL AS STRING)
    AS state_code,

  CAST(loc.county AS STRING)
    AS county_code,

  CAST(NULL AS STRING)
    AS fips_version


FROM src v

/* INNER JOIN can exclude inpatient visits without a matching person row. */
INNER JOIN
  `YOUR_PROJECT.YOUR_OMOP_DATASET.person` p
  USING (person_id)

LEFT JOIN
  `YOUR_PROJECT.YOUR_OMOP_DATASET.location` loc
  ON loc.location_id = p.location_id;
