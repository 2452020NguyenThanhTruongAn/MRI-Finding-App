-- ============================================================
-- Phase 4.1: SETUP
-- Create experiment schemas, copy data, and create indexes.
-- Run on a disposable MySQL instance.
-- ============================================================

USE mri_radiology_db;

-- ------------------------------------------------------------
-- 1. Check original data
-- ------------------------------------------------------------
SELECT COUNT(*) AS total_patients FROM patient;
SELECT COUNT(*) AS total_studies FROM study;
SELECT COUNT(*) AS total_series FROM series;
SELECT COUNT(*) AS total_images FROM mri_image;

-- ------------------------------------------------------------
-- 2. Create experiment schemas
-- ------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS mri_41_noindex;
CREATE DATABASE IF NOT EXISTS mri_41_indexed;

-- IMPORTANT:
-- CREATE TABLE ... AS SELECT copies data and columns,
-- but does not copy indexes or constraints.
--
-- Before rerunning this script, drop and recreate the
-- experiment schemas if the tables already exist.
--
-- Uncomment ONLY if you intentionally want to erase
-- and rebuild both experiment copies:
--
-- DROP DATABASE IF EXISTS mri_41_noindex;
-- DROP DATABASE IF EXISTS mri_41_indexed;

-- ------------------------------------------------------------
-- 3. Copy original data to NOINDEX schema
-- ------------------------------------------------------------
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

-- ------------------------------------------------------------
-- 4. Copy original data to INDEXED schema
-- ------------------------------------------------------------
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

-- ------------------------------------------------------------
-- 5. Create common baseline keys in BOTH schemas
-- ------------------------------------------------------------
-- These keys are shared by both experiment copies.
-- Only the six secondary indexes below distinguish
-- the indexed schema from the noindex schema.

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

-- ------------------------------------------------------------
-- 6. Create requested indexes ONLY in INDEXED schema
-- ------------------------------------------------------------

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

-- ------------------------------------------------------------
-- 7. Update optimizer statistics
-- ------------------------------------------------------------
ANALYZE TABLE
    mri_41_noindex.patient,
    mri_41_noindex.radiology_report,
    mri_41_noindex.study,
    mri_41_noindex.series,
    mri_41_noindex.mri_image;

ANALYZE TABLE
    mri_41_indexed.patient,
    mri_41_indexed.radiology_report,
    mri_41_indexed.study,
    mri_41_indexed.series,
    mri_41_indexed.mri_image;
