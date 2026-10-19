


-- =====================================================================
-- 0. KIEM TRA MOI TRUONG VA DU LIEU
-- =====================================================================
USE mri_radiology_db;

SELECT VERSION();   -- phai >= 8.0.18

SELECT 'patient' AS tbl, COUNT(*) AS n FROM patient
UNION ALL SELECT 'radiology_report', COUNT(*) FROM radiology_report
UNION ALL SELECT 'study',            COUNT(*) FROM study
UNION ALL SELECT 'series',           COUNT(*) FROM series
UNION ALL SELECT 'mri_image',        COUNT(*) FROM mri_image;

-- Gia tri thuc te cua sequence_type / orientation (chinh tham so Q2 neu khac)
SELECT sequence_type, orientation, COUNT(*) AS n_series
FROM series
GROUP BY sequence_type, orientation
ORDER BY n_series DESC;

-- Benh nhan co nhieu anh nhat (nen dung de test, ket qua lon -> plan ro hon)
SELECT p.patient_id, COUNT(i.image_id) AS n_images
FROM patient p
JOIN study s        ON s.patient_id = p.patient_id
JOIN series se      ON se.study_id  = s.study_id
JOIN mri_image i    ON i.series_id  = se.series_id
GROUP BY p.patient_id
ORDER BY n_images DESC
LIMIT 5;

-- Cac index hien co (do schema.sql tao + index tu dong cua UNIQUE/FK)
SELECT table_name, index_name,
       GROUP_CONCAT(column_name ORDER BY seq_in_index) AS cols,
       MAX(cardinality) AS cardinality
FROM information_schema.statistics
WHERE table_schema = 'mri_radiology_db'
GROUP BY table_name, index_name
ORDER BY table_name, index_name;

-- Index thua (MySQL tu phat hien: index nay la tien to cua index khac)
SELECT table_name, redundant_index_name, dominant_index_name
FROM sys.schema_redundant_indexes
WHERE table_schema = 'mri_radiology_db';

-- Cap nhat thong ke de optimizer uoc luong dung so dong
ANALYZE TABLE patient, radiology_report, study, series, mri_image;


-- =====================================================================
-- 1. MOC "KHONG INDEX": ban sao cac bang khong co khoa/index nao
--    (CREATE TABLE ... AS SELECT khong copy index) trong DB rieng,
--    nen KHONG dong cham DB that va khong anh huong phan Indexing 4.1.
-- =====================================================================
DROP DATABASE IF EXISTS mri_noindex;
CREATE DATABASE mri_noindex CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE mri_noindex.patient          AS SELECT * FROM mri_radiology_db.patient;
CREATE TABLE mri_noindex.radiology_report AS SELECT * FROM mri_radiology_db.radiology_report;
CREATE TABLE mri_noindex.study            AS SELECT * FROM mri_radiology_db.study;
CREATE TABLE mri_noindex.series           AS SELECT * FROM mri_radiology_db.series;
CREATE TABLE mri_noindex.mri_image        AS SELECT * FROM mri_radiology_db.mri_image;

ANALYZE TABLE mri_noindex.patient, mri_noindex.radiology_report,
              mri_noindex.study,   mri_noindex.series, mri_noindex.mri_image;


-- =====================================================================
-- 2. Q1 = get_patient_mri  (Application 1: nhan ID -> report + toan bo anh)
-- =====================================================================

-- ---- 2A. Q1, KHONG index ----------------------------------------------
USE mri_noindex;

EXPLAIN ANALYZE
SELECT p.patient_id,
       rr.report_id, rr.clinician_notes,
       s.study_id, s.study_name, s.study_date,
       se.series_id, se.series_name, se.sequence_type, se.orientation,
       i.image_id, i.file_name, i.file_path
FROM patient p
LEFT JOIN radiology_report rr ON p.patient_id = rr.patient_id
LEFT JOIN study s             ON p.patient_id = s.patient_id
LEFT JOIN series se           ON s.study_id   = se.study_id
LEFT JOIN mri_image i         ON se.series_id = i.series_id
WHERE p.patient_id = '0230'
ORDER BY s.study_date, se.series_id, i.image_id;

-- ---- 2B. Q1, schema hien tai (co index) -------------------------------
USE mri_radiology_db;

EXPLAIN ANALYZE
SELECT p.patient_id,
       rr.report_id, rr.clinician_notes,
       s.study_id, s.study_name, s.study_date,
       se.series_id, se.series_name, se.sequence_type, se.orientation,
       i.image_id, i.file_name, i.file_path
FROM patient p
LEFT JOIN radiology_report rr ON p.patient_id = rr.patient_id
LEFT JOIN study s             ON p.patient_id = s.patient_id
LEFT JOIN series se           ON s.study_id   = se.study_id
LEFT JOIN mri_image i         ON se.series_id = i.series_id
WHERE p.patient_id = '0230'
ORDER BY s.study_date, se.series_id, i.image_id;


-- =====================================================================
-- 3. Q2 = search_patient_mri  (Application 2: ID + condition -> anh)
-- =====================================================================

-- ---- 3A. Q2, KHONG index ----------------------------------------------
USE mri_noindex;

EXPLAIN ANALYZE
SELECT p.patient_id,
       rr.report_id, rr.clinician_notes,
       s.study_id, s.study_name, s.study_date,
       se.series_id, se.series_name, se.sequence_type, se.orientation,
       i.image_id, i.file_name, i.file_path
FROM patient p
JOIN study s                  ON p.patient_id = s.patient_id
JOIN series se                ON s.study_id   = se.study_id
JOIN mri_image i              ON se.series_id = i.series_id
LEFT JOIN radiology_report rr ON p.patient_id = rr.patient_id
WHERE p.patient_id = '0230'
  AND se.sequence_type = 'T2'
  AND se.orientation   = 'SAG'
ORDER BY s.study_date, se.series_id, i.image_id;

-- ---- 3B. Q2, schema hien tai (co index) -------------------------------
USE mri_radiology_db;

EXPLAIN ANALYZE
SELECT p.patient_id,
       rr.report_id, rr.clinician_notes,
       s.study_id, s.study_name, s.study_date,
       se.series_id, se.series_name, se.sequence_type, se.orientation,
       i.image_id, i.file_name, i.file_path
FROM patient p
JOIN study s                  ON p.patient_id = s.patient_id
JOIN series se                ON s.study_id   = se.study_id
JOIN mri_image i              ON se.series_id = i.series_id
LEFT JOIN radiology_report rr ON p.patient_id = rr.patient_id
WHERE p.patient_id = '0230'
  AND se.sequence_type = 'T2'
  AND se.orientation   = 'SAG'
ORDER BY s.study_date, se.series_id, i.image_id;


-- =====================================================================
-- 4. TOI UU
--    Tren schema hien tai, Q1/Q2 da dung index (PK/UNIQUE/FK) cho moi phep
--    join. Con lai 3 diem co the cai thien:
--      (a) Q2: loc sequence_type/orientation la buoc "Filter" sau khi doc
--          het series cua study, 2 index don cot (cardinality ~3) khong duoc
--          chon -> thay bang index tong hop.
--      (b) Q1: clinician_notes bi lap lai tren MOI dong anh -> tach rieng.
--      (c) Index thua gay ton chi phi ghi/dung luong.
-- =====================================================================
USE mri_radiology_db;

-- ---- 4.1 Q2: index tong hop (study_id, sequence_type, orientation) ----
CREATE INDEX idx_series_study_seq_orient
    ON series (study_id, sequence_type, orientation);
ANALYZE TABLE series;

EXPLAIN ANALYZE
SELECT p.patient_id,
       rr.report_id, rr.clinician_notes,
       s.study_id, s.study_name, s.study_date,
       se.series_id, se.series_name, se.sequence_type, se.orientation,
       i.image_id, i.file_name, i.file_path
FROM patient p
JOIN study s                  ON p.patient_id = s.patient_id
JOIN series se                ON s.study_id   = se.study_id
JOIN mri_image i              ON se.series_id = i.series_id
LEFT JOIN radiology_report rr ON p.patient_id = rr.patient_id
WHERE p.patient_id = '0230'
  AND se.sequence_type = 'T2'
  AND se.orientation   = 'SAG'
ORDER BY s.study_date, se.series_id, i.image_id;

-- ---- 4.2 Q1: viet lai - bo join patient/report khoi truy van anh ------
-- Luu y (danh doi): ban goc dung LEFT JOIN nen benh nhan chua co study van
-- tra ve 1 dong (cac cot anh = NULL). Ban viet lai dung INNER JOIN nen
-- khong tra dong nao; ung dung phai dua vao query report de biet benh nhan
-- ton tai hay khong.
EXPLAIN ANALYZE
SELECT s.study_id, s.study_name, s.study_date,
       se.series_id, se.series_name, se.sequence_type, se.orientation,
       i.image_id, i.file_name, i.file_path
FROM study s
JOIN series se     ON se.study_id = s.study_id
JOIN mri_image i   ON i.series_id = se.series_id
WHERE s.patient_id = '0230'
ORDER BY s.study_date, se.series_id, i.image_id;

-- Report lay rieng (1 dong, tra ve DUNG 1 LAN thay vi lap tren moi dong anh)
EXPLAIN ANALYZE
SELECT report_id, patient_id, clinician_notes
FROM radiology_report
WHERE patient_id = '0230';

-- Do muc lap du lieu: so dong * do dai report bi gui di o ban goc
SELECT COUNT(i.image_id)                            AS so_dong_anh,
       MAX(LENGTH(rr.clinician_notes))              AS bytes_report,
       COUNT(i.image_id) * MAX(LENGTH(rr.clinician_notes)) AS bytes_report_ban_goc,
       MAX(LENGTH(rr.clinician_notes))              AS bytes_report_sau_tach
FROM study s
JOIN series se   ON se.study_id = s.study_id
JOIN mri_image i ON i.series_id = se.series_id
LEFT JOIN radiology_report rr ON rr.patient_id = s.patient_id
WHERE s.patient_id = '0230';

-- ---- 4.3 (thu nghiem) index (patient_id, study_date) cho study --------
-- Y tuong ly thuyet: lay study da sap theo ngay -> bo filesort.
-- Thuc te: ORDER BY gom 3 cot cua 3 bang khac nhau nen MySQL van phai sort
-- (chi bo duoc sort khi moi cot ORDER BY thuoc bang dau tien). Chay thu de
-- ghi nhan ket qua am tinh nay vao report (so sanh ly thuyet vs thuc te).
CREATE INDEX idx_study_patient_date ON study (patient_id, study_date);
ANALYZE TABLE study;

EXPLAIN ANALYZE
SELECT s.study_id, s.study_name, s.study_date,
       se.series_id, se.series_name, se.sequence_type, se.orientation,
       i.image_id, i.file_name, i.file_path
FROM study s
JOIN series se     ON se.study_id = s.study_id
JOIN mri_image i   ON i.series_id = se.series_id
WHERE s.patient_id = '0230'
ORDER BY s.study_date, se.series_id, i.image_id;

-- ---- 4.4 Index thua: xac nhan roi thu bo (tuy chon, chi tren DB cua ban) --
-- sys.schema_redundant_indexes o muc 0 bao idx_study_patient va
-- idx_series_study la tien to cua UNIQUE (patient_id, study_name) va
-- (study_id, series_name) / index tong hop moi. FK van duoc dam bao vi van
-- con index khac bat dau bang cung cot.
ALTER TABLE study  DROP INDEX idx_study_patient;
ALTER TABLE series DROP INDEX idx_series_study;
SELECT table_name, redundant_index_name, dominant_index_name
FROM sys.schema_redundant_indexes
WHERE table_schema = 'mri_radiology_db';
-- Chay lai Q1 (2B) va Q2 (4.1) de xac nhan plan khong doi.


-- =====================================================================
-- 5. DON DEP - TRA SCHEMA VE NHU schema.sql
--    (chay sau khi da luu xong het ket qua)
-- =====================================================================
USE mri_radiology_db;
DROP INDEX idx_study_patient_date      ON study;
DROP INDEX idx_series_study_seq_orient ON series;
CREATE INDEX idx_study_patient ON study (patient_id);
CREATE INDEX idx_series_study  ON series (study_id);
ANALYZE TABLE study, series;
DROP DATABASE IF EXISTS mri_noindex;


-- =====================================================================
-- 6. BANG KET QUA DE DIEN VAO REPORT (lay tu dong goc cua EXPLAIN ANALYZE)
-- =====================================================================
-- | Query | Cau hinh                      | Scan tren mri_image | Kieu join   | Rows doc | actual time (ms) |
-- |-------|-------------------------------|---------------------|-------------|----------|------------------|
-- | Q1    | 2A khong index                |                     |             |          |                  |
-- | Q1    | 2B schema hien tai            |                     |             |          |                  |
-- | Q1    | 4.2 viet lai (tach report)    |                     |             |          |                  |
-- | Q2    | 3A khong index                |                     |             |          |                  |
-- | Q2    | 3B schema hien tai            |                     |             |          |                  |
-- | Q2    | 4.1 + index tong hop          |                     |             |          |                  |
