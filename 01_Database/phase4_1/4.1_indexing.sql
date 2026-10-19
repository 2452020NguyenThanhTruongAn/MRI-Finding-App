-- ============================================================
-- Phase 4.1: Indexing experiment
-- Run on a disposable MySQL instance / fresh experiment schemas.
-- This script uses CREATE DATABASE IF NOT EXISTS and CREATE TABLE;
-- drop/recreate the two experiment schemas before rerunning it.
-- ============================================================

USE mri_radiology_db;

SELECT COUNT(*) AS total_patients FROM patient;
SELECT COUNT(*) AS total_studies FROM study;
SELECT COUNT(*) AS total_series FROM series;
SELECT COUNT(*) AS total_images FROM mri_image;

-- Fresh experiment schemas. Uncomment these two lines only when you
-- intentionally want to erase and rebuild the experiment copies:
-- DROP DATABASE IF EXISTS mri_41_noindex;
-- DROP DATABASE IF EXISTS mri_41_indexed;
CREATE DATABASE IF NOT EXISTS mri_41_noindex;
CREATE DATABASE IF NOT EXISTS mri_41_indexed;

-- NOTE: CREATE TABLE ... AS SELECT copies data/columns, but not indexes
-- or constraints. To keep the comparison controlled, create the same
-- baseline keys in BOTH copies first; only the six task indexes below
-- are added to mri_41_indexed. The baseline retains these common keys:
-- uq_series_per_study, mri_image PRIMARY KEY, and uq_image_path.
CREATE TABLE mri_41_noindex.patient AS
SELECT * FROM mri_radiology_db.patient;
CREATE TABLE mri_41_noindex.radiology_report AS
SELECT * FROM mri_radiology_db.radiology_report;
CREATE TABLE mri_41_noindex.study AS
SELECT * FROM mri_radiology_db.study;
CREATE TABLE mri_41_noindex.series AS
SELECT * FROM mri_radiology_db.series;
CREATE TABLE mri_41_noindex.mri_image AS
SELECT * FROM mri_radiology_db.mri_image;

CREATE TABLE mri_41_indexed.patient AS
SELECT * FROM mri_radiology_db.patient;
CREATE TABLE mri_41_indexed.radiology_report AS
SELECT * FROM mri_radiology_db.radiology_report;
CREATE TABLE mri_41_indexed.study AS
SELECT * FROM mri_radiology_db.study;
CREATE TABLE mri_41_indexed.series AS
SELECT * FROM mri_radiology_db.series;
CREATE TABLE mri_41_indexed.mri_image AS
SELECT * FROM mri_radiology_db.mri_image;

-- Common baseline keys: apply equally to both copies so that the
-- experiment differs only by the six secondary indexes below.
CREATE UNIQUE INDEX uq_series_per_study_noindex
    ON mri_41_noindex.series(study_id, series_name);
CREATE UNIQUE INDEX uq_series_per_study_indexed
    ON mri_41_indexed.series(study_id, series_name);

ALTER TABLE mri_41_noindex.mri_image
    ADD PRIMARY KEY (image_id);
ALTER TABLE mri_41_indexed.mri_image
    ADD PRIMARY KEY (image_id);
CREATE UNIQUE INDEX uq_image_path_noindex
    ON mri_41_noindex.mri_image(file_path);
CREATE UNIQUE INDEX uq_image_path_indexed
    ON mri_41_indexed.mri_image(file_path);

-- ============================================================
-- Add the requested indexes ONLY to the indexed experiment schema.
-- idx_patient_id is included per the task checklist. If patient_id
-- already has an equivalent PRIMARY/UNIQUE index, this is redundant;
-- inspect SHOW INDEX first and decide whether to omit it.
-- ============================================================
CREATE INDEX idx_patient_id
    ON mri_41_indexed.patient(patient_id);

CREATE INDEX idx_study_patient
    ON mri_41_indexed.study(patient_id);

CREATE INDEX idx_series_study
    ON mri_41_indexed.series(study_id);

CREATE INDEX idx_series_sequence_type
    ON mri_41_indexed.series(sequence_type);

CREATE INDEX idx_series_orientation
    ON mri_41_indexed.series(orientation);

CREATE INDEX idx_image_series
    ON mri_41_indexed.mri_image(series_id);

-- Check that copied data row counts match.
SELECT 'noindex' AS db_name, COUNT(*) AS total_patients
FROM mri_41_noindex.patient
UNION ALL
SELECT 'indexed', COUNT(*) FROM mri_41_indexed.patient;

SELECT 'noindex' AS db_name, COUNT(*) AS total_studies
FROM mri_41_noindex.study
UNION ALL
SELECT 'indexed', COUNT(*) FROM mri_41_indexed.study;

SELECT 'noindex' AS db_name, COUNT(*) AS total_series
FROM mri_41_noindex.series
UNION ALL
SELECT 'indexed', COUNT(*) FROM mri_41_indexed.series;

SELECT 'noindex' AS db_name, COUNT(*) AS total_images
FROM mri_41_noindex.mri_image
UNION ALL
SELECT 'indexed', COUNT(*) FROM mri_41_indexed.mri_image;

-- ============================================================
-- G1: get_patient_mri-equivalent query (patient 0230)
-- ============================================================
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
-- G2: search_patient_mri-equivalent query (patient 0230, T2, SAG)
-- ============================================================
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

-- Verify index existence in the indexed copy.
SHOW INDEX FROM mri_41_indexed.patient;
SHOW INDEX FROM mri_41_indexed.study;
SHOW INDEX FROM mri_41_indexed.series;
SHOW INDEX FROM mri_41_indexed.mri_image;

ANALYZE TABLE mri_41_indexed.patient,
                mri_41_indexed.radiology_report,
                mri_41_indexed.study,
                mri_41_indexed.series,
                mri_41_indexed.mri_image;
