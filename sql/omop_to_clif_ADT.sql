/*
 EXTERNAL COLLABORATION TEMPLATE — REVIEW BEFORE USE
 - Code and mapping examples only; no patient records included.
 - Replace YOUR_PROJECT / YOUR_OMOP_DATASET / YOUR_CLIF_DATASET.
 - Requires the companion CLIF hospitalization table.
 - Site-specific hospital identifiers and named unit-to-ICU subtype
   mappings were intentionally removed; implement locally.
 - The original site-specific care_site_source_value JSON source_flag
   extraction was removed because it is not used in this template.
 - CASE matching precedence and generic keyword matching are examples,
   not validated rules for other institutions.
 - This is not a production-ready or independently validated ETL.
*/

/* ===========================================================================
   EXTERNAL COLLABORATOR REFERENCE — ADT (BigQuery Standard SQL)
   ---------------------------------------------------------------------------
   Sources:
     OMOP visit_detail       = in-hospital physical location movements
     OMOP care_site          = source department/location metadata
     CLIF hospitalization = inpatient hospitalization cohort + boundaries

   Population:
     ADT/location records that overlap an inpatient hospitalization in
     CLIF hospitalization table.

   CLIF 2.1.0 location_category values:
     ed, ward, stepdown, icu, procedural, l&d, hospice,
     psych, rehab, radiology, dialysis, other

   Major corrections:
     1. hospital_id represents the actual hospital/site, not care_site_id;
        local mapping is intentionally left NULL in this template.
     2. ADT intervals are constrained to hospitalization boundaries.
     3. Rows entirely outside the hospitalization are excluded.
     4. location_type is populated only for ICU rows.
     5. location_type uses only CLIF 2.1.0 permissible ICU subtype values.
     6. Pediatric/neonatal ICU locations map to general_icu in this
        example; confirm the permissible values in your CLIF version.
   =========================================================================== */

CREATE OR REPLACE TABLE
  `YOUR_PROJECT.YOUR_CLIF_DATASET.adt` AS


/* ===========================================================================
   1. Pull source ADT rows and join to hospitalization_v2
   =========================================================================== */

WITH base AS (

  SELECT
    vd.visit_occurrence_id,
    vd.visit_detail_start_datetime,
    vd.visit_detail_end_datetime,

    cs.care_site_id,
    cs.care_site_name,
    h.admission_dttm,
    h.discharge_dttm

  FROM
    `YOUR_PROJECT.YOUR_OMOP_DATASET.visit_detail` AS vd

  INNER JOIN
    `som-nero-phi-ajrogers-hidef.CLIF hospitalization table` AS h
      ON CAST(vd.visit_occurrence_id AS STRING) = h.hospitalization_id

  LEFT JOIN
    `YOUR_PROJECT.YOUR_OMOP_DATASET.care_site` AS cs
      ON cs.care_site_id = vd.care_site_id

  /* Keep only ADT intervals that overlap the hospitalization */
  /* NULL endpoints will not pass this overlap filter.
     Confirm whether your data need open-ended interval handling. */
  WHERE
    vd.visit_detail_start_datetime <= h.discharge_dttm
    AND vd.visit_detail_end_datetime >= h.admission_dttm
),


/* ===========================================================================
   2. Constrain ADT intervals to hospitalization boundaries
   =========================================================================== */

clipped AS (

  SELECT
    * EXCEPT (
      visit_detail_start_datetime,
      visit_detail_end_datetime
    ),

    /* Clip the interval start/end to hospitalization boundaries. */
    GREATEST(
      visit_detail_start_datetime,
      admission_dttm
    ) AS in_dttm,

    LEAST(
      visit_detail_end_datetime,
      discharge_dttm
    ) AS out_dttm

  FROM base
),


/* ===========================================================================
   3. Derive CLIF hospital + location categories
   =========================================================================== */

mapped AS (

  SELECT

    CAST(visit_occurrence_id AS STRING) AS hospitalization_id,


    /* ==========================================================
       HOSPITAL ID / HOSPITAL TYPE — LOCAL CONFIGURATION REQUIRED

       The original implementation inferred physical hospital/site
       using source_flag and site-specific department names.
       Those values are NOT portable and have been removed.

       Replace the NULL expressions with locally reviewed mapping
       logic. hospital_id must represent a physical hospital/site,
       not OMOP care_site_id. hospital_type should use the CLIF
       permitted categories for the targeted CLIF version.
       ========================================================== */

    CAST(NULL AS STRING) AS hospital_id,  -- TODO: local site mapping
    CAST(NULL AS STRING) AS hospital_type, -- TODO: local site type mapping

    in_dttm,
    out_dttm,

    care_site_name AS location_name,


    /* ==========================================================
       CLIF LOCATION CATEGORY
       ========================================================== */

    CASE

      /* Example keyword mapping; locally validate order and specificity. */
      /* Missing source location */
      WHEN care_site_name IS NULL
        THEN 'other'


      /* ----------------------------------------------------------
         Emergency Department
         ---------------------------------------------------------- */

      WHEN LOWER(care_site_name) LIKE '%emergency%'
        OR LOWER(care_site_name) LIKE '% ed %'
        OR LOWER(care_site_name) LIKE 'ed %'
        OR LOWER(care_site_name) LIKE '% ed'
        THEN 'ed'


      /* ----------------------------------------------------------
         ICU

         Local neonatal/pediatric ICU abbreviations require review.
         ---------------------------------------------------------- */

      WHEN LOWER(care_site_name) LIKE '%intensive care%'
        OR LOWER(care_site_name) LIKE '%critical care%'
        OR LOWER(care_site_name) LIKE '%icu%'
        OR LOWER(care_site_name) LIKE '%ccu%'

        OR LOWER(care_site_name) LIKE 'icn 1%'
        OR LOWER(care_site_name) LIKE 'icn 2%'
        OR LOWER(care_site_name) LIKE 'picn 1%'
        OR LOWER(care_site_name) LIKE 'picn 2%'

        THEN 'icu'


      /* ----------------------------------------------------------
         Procedural / OR / perioperative
         ---------------------------------------------------------- */

      WHEN LOWER(care_site_name) LIKE '%pacu%'
        OR LOWER(care_site_name) LIKE '%periop%'
        OR LOWER(care_site_name) LIKE '%pre-op%'
        OR LOWER(care_site_name) LIKE '%preop%'
        OR LOWER(care_site_name) LIKE '%intra-op%'
        OR LOWER(care_site_name) LIKE '%intraop%'
        OR LOWER(care_site_name) LIKE '%operating%'
        OR LOWER(care_site_name) LIKE '%surgery%'
        OR LOWER(care_site_name) LIKE '%procedure%'
        OR LOWER(care_site_name) LIKE '%endoscopy%'
        OR LOWER(care_site_name) LIKE '%cath%'
        OR LOWER(care_site_name) LIKE '%gi lab%'
        THEN 'procedural'


      /* ----------------------------------------------------------
         Labor & Delivery / Obstetrics
         ---------------------------------------------------------- */

      WHEN LOWER(care_site_name) LIKE '%labor%'
        OR LOWER(care_site_name) LIKE '%delivery%'
        OR LOWER(care_site_name) LIKE '%l&d%'
        OR LOWER(care_site_name) LIKE '%birthing%'
        OR LOWER(care_site_name) LIKE '%maternity%'
        OR LOWER(care_site_name) LIKE '%obstetric%'
        OR LOWER(care_site_name) LIKE '%antepartum%'
        OR LOWER(care_site_name) LIKE '%postpartum%'
        THEN 'l&d'


      /* ----------------------------------------------------------
         Stepdown / progressive / intermediate care
         ---------------------------------------------------------- */

      WHEN LOWER(care_site_name) LIKE '%pcu%'
        OR LOWER(care_site_name) LIKE '%stepdown%'
        OR LOWER(care_site_name) LIKE '%step down%'
        OR LOWER(care_site_name) LIKE '%progressive care%'
        OR LOWER(care_site_name) LIKE '%intermediate care%'
        THEN 'stepdown'


      /* Psychiatry */
      WHEN LOWER(care_site_name) LIKE '%psychiatr%'
        OR LOWER(care_site_name) LIKE '%behavioral health%'
        THEN 'psych'


      /* Rehabilitation */
      WHEN LOWER(care_site_name) LIKE '%rehab%'
        OR LOWER(care_site_name) LIKE '%rehabilitation%'
        THEN 'rehab'


      /* Hospice */
      WHEN LOWER(care_site_name) LIKE '%hospice%'
        THEN 'hospice'


      /* Radiology / imaging */
      WHEN LOWER(care_site_name) LIKE '%radiology%'
        OR LOWER(care_site_name) LIKE '%imaging%'
        OR LOWER(care_site_name) LIKE '%mri%'
        OR LOWER(care_site_name) LIKE '%ct scan%'
        OR LOWER(care_site_name) LIKE '%ultrasound%'
        OR LOWER(care_site_name) LIKE '%x-ray%'
        OR LOWER(care_site_name) LIKE '%xray%'
        THEN 'radiology'


      /* Dialysis */
      WHEN LOWER(care_site_name) LIKE '%dialysis%'
        THEN 'dialysis'


      /* ----------------------------------------------------------
         General inpatient wards
         ---------------------------------------------------------- */

      WHEN LOWER(care_site_name) LIKE '%aau%'
        OR LOWER(care_site_name) LIKE '%oncology%'
        OR LOWER(care_site_name) LIKE '%heme/onc%'
        OR LOWER(care_site_name) LIKE '%hematology%'
        OR LOWER(care_site_name) LIKE '%cardiology%'
        OR LOWER(care_site_name) LIKE '%med/surg%'
        OR LOWER(care_site_name) LIKE '%med-surg%'
        OR LOWER(care_site_name) LIKE '%medical surgical%'
        OR LOWER(care_site_name) LIKE '%ward%'
        OR LOWER(care_site_name) LIKE '%acute care%'
        OR LOWER(care_site_name) LIKE '%general medicine%'
        OR LOWER(care_site_name) LIKE '%pediatrics%'
        OR LOWER(care_site_name) LIKE '%general pediatr%'
        OR LOWER(care_site_name) LIKE '%stem cell%'
        OR LOWER(care_site_name) LIKE '%newborn nursery%'
        OR LOWER(care_site_name) LIKE '%well baby nursery%'
        OR LOWER(care_site_name) LIKE '%nursery pleasanton%'
        OR LOWER(care_site_name) LIKE '%2 east%'
        OR LOWER(care_site_name) LIKE '%3 north%'
        OR LOWER(care_site_name) LIKE '%3 east%'
        OR LOWER(care_site_name) LIKE '%3 west%'
        OR LOWER(care_site_name) LIKE '%3 south%'
        OR LOWER(care_site_name) LIKE '%2 north%'
        OR LOWER(care_site_name) LIKE '%2 west%'
        THEN 'ward'


      /* Anything not confidently mapped */
      ELSE 'other'

    END AS location_category,

    care_site_name

  FROM clipped
)


/* ===========================================================================
   4. Final CLIF ADT table + ICU subtype
   =========================================================================== */

SELECT

  hospitalization_id,
  hospital_id,
  hospital_type,

  in_dttm,
  out_dttm,

  location_name,
  location_category,


  /* ============================================================
     ICU LOCATION TYPE

     Only populated for rows categorized as ICU.

     Pediatric/neonatal ICUs are represented as general_icu
     because CLIF 2.1.0 does not define pediatric_icu.
     ============================================================ */

  CASE

    WHEN location_category != 'icu'
      OR care_site_name IS NULL
      THEN NULL


    /* Generic illustrative ICU subtype mapping only.
       Review against local department naming conventions and
       CLIF version; avoid assuming an abbreviation is definitive. */
    WHEN LOWER(care_site_name) LIKE '%picu%'
      OR LOWER(care_site_name) LIKE '%nicu%'
      THEN 'general_icu'

    WHEN LOWER(care_site_name) LIKE '%cvicu%'
      THEN 'mixed_cardiothoracic_icu'

    /* Remaining ICU locations */
    ELSE 'general_icu'

  END AS location_type

FROM mapped;
