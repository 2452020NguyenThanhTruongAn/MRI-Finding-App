-- ============================================================
-- Phase 4.1: TEST
-- Compare query performance before and after adding indexes.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Verify copied data row counts
-- ------------------------------------------------------------

SELECT 'noindex' AS db_name, COUNT(*) AS total_patients
FROM mri_41_noindex.patient
UNION ALL
SELECT 'indexed', COUNT(*)
FROM mri_41_indexed.patient;

SELECT 'noindex' AS db_name, COUNT(*) AS total_studies
FROM mri_41_noindex.study
UNION ALL
SELECT 'indexed', COUNT(*)
FROM mri_41_indexed.study;

SELECT 'noindex' AS db_name, COUNT(*) AS total_series
FROM mri_41_noindex.series
UNION ALL
SELECT 'indexed', COUNT(*)
FROM mri_41_indexed.series;

SELECT 'noindex' AS db_name, COUNT(*) AS total_images
FROM mri_41_noindex.mri_image
UNION ALL
SELECT 'indexed', COUNT(*)
FROM mri_41_indexed.mri_image;


-- ============================================================
-- 2. G1: get_patient_mri-equivalent query
-- Patient: 0230
-- ============================================================

-- G1: NOINDEX
USE mri_41_noindex;

EXPLAIN ANALYZE
SELECT
    p.patient_id,
    rr.report_id,
    rr.clinician_notes,
    s.study_id,
    s.study_name,
    s.study_date,
    se.series_id,
    se.series_name,
    se.sequence_type,
    se.orientation,
    i.image_id,
    i.file_name,
    i.file_path
FROM patient p
LEFT JOIN radiology_report rr
    ON p.patient_id = rr.patient_id
LEFT JOIN study s
    ON p.patient_id = s.patient_id
LEFT JOIN series se
    ON s.study_id = se.study_id
LEFT JOIN mri_image i
    ON se.series_id = i.series_id
WHERE p.patient_id = '0230'
ORDER BY s.study_date, se.series_id, i.image_id;


-- G1: INDEXED
USE mri_41_indexed;

EXPLAIN ANALYZE
SELECT
    p.patient_id,
    rr.report_id,
    rr.clinician_notes,
    s.study_id,
    s.study_name,
    s.study_date,
    se.series_id,
    se.series_name,
    se.sequence_type,
    se.orientation,
    i.image_id,
    i.file_name,
    i.file_path
FROM patient p
LEFT JOIN radiology_report rr
    ON p.patient_id = rr.patient_id
LEFT JOIN study s
    ON p.patient_id = s.patient_id
LEFT JOIN series se
    ON s.study_id = se.study_id
LEFT JOIN mri_image i
    ON se.series_id = i.series_id
WHERE p.patient_id = '0230'
ORDER BY s.study_date, se.series_id, i.image_id;


-- ============================================================
-- 3. G2: search_patient_mri-equivalent query
-- Patient: 0230
-- Sequence type: T2
-- Orientation: SAG
-- ============================================================

-- G2: NOINDEX
USE mri_41_noindex;

EXPLAIN ANALYZE
SELECT
    p.patient_id,
    rr.report_id,
    rr.clinician_notes,
    s.study_id,
    s.study_name,
    s.study_date,
    se.series_id,
    se.series_name,
    se.sequence_type,
    se.orientation,
    i.image_id,
    i.file_name,
    i.file_path
FROM patient p
JOIN study s
    ON p.patient_id = s.patient_id
JOIN series se
    ON s.study_id = se.study_id
JOIN mri_image i
    ON se.series_id = i.series_id
LEFT JOIN radiology_report rr
    ON p.patient_id = rr.patient_id
WHERE p.patient_id = '0230'
  AND se.sequence_type = 'T2'
  AND se.orientation = 'SAG'
ORDER BY s.study_date, se.series_id, i.image_id;


-- G2: INDEXED
USE mri_41_indexed;

EXPLAIN ANALYZE
SELECT
    p.patient_id,
    rr.report_id,
    rr.clinician_notes,
    s.study_id,
    s.study_name,
    s.study_date,
    se.series_id,
    se.series_name,
    se.sequence_type,
    se.orientation,
    i.image_id,
    i.file_name,
    i.file_path
FROM patient p
JOIN study s
    ON p.patient_id = s.patient_id
JOIN series se
    ON s.study_id = se.study_id
JOIN mri_image i
    ON se.series_id = i.series_id
LEFT JOIN radiology_report rr
    ON p.patient_id = rr.patient_id
WHERE p.patient_id = '0230'
  AND se.sequence_type = 'T2'
  AND se.orientation = 'SAG'
ORDER BY s.study_date, se.series_id, i.image_id;


-- ============================================================
-- 4. Verify indexes in INDEXED schema
-- ============================================================

SHOW INDEX FROM mri_41_indexed.patient;
SHOW INDEX FROM mri_41_indexed.study;
SHOW INDEX FROM mri_41_indexed.series;
SHOW INDEX FROM mri_41_indexed.mri_image;