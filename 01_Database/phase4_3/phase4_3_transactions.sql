-- =====================================================================
-- MRI Radiology Database — Phase 4.3: Transactions

-- Scenario A: register a new patient together with their radiology report
--             (INSERT patient + INSERT radiology_report)
-- Scenario B: amend a radiology report and correct its study date
--             (UPDATE radiology_report + UPDATE study)

USE mri_radiology_db;

-- ---------------------------------------------------------------------
-- 0. RESET TEST DATA (makes the script repeatable)
--    ON DELETE CASCADE also removes the test patients' reports and studies.
-- ---------------------------------------------------------------------
DELETE FROM patient WHERE patient_id BETWEEN '0576' AND '0599';


-- =====================================================================
-- SCENARIO A: register a new patient together with their report
-- =====================================================================

-- ---------------------------------------------------------------------
-- A0. Snapshot BEFORE
-- ---------------------------------------------------------------------
SET SESSION information_schema_stats_expiry = 0;   -- so AUTO_INCREMENT below is current

SELECT COUNT(*) AS patients FROM patient;
SELECT COUNT(*) AS reports  FROM radiology_report;
SELECT * FROM patient          WHERE patient_id BETWEEN '0576' AND '0599';
SELECT * FROM radiology_report WHERE patient_id BETWEEN '0576' AND '0599';
SELECT AUTO_INCREMENT FROM information_schema.TABLES
 WHERE TABLE_SCHEMA = 'mri_radiology_db' AND TABLE_NAME = 'radiology_report';


-- ---------------------------------------------------------------------
-- A1. COMMIT test
-- ---------------------------------------------------------------------
START TRANSACTION;

INSERT INTO patient (patient_id) VALUES ('0576');

INSERT INTO radiology_report (patient_id, clinician_notes)
VALUES ('0576', 'LSS MRI: Diffuse disc bulge noted at L4/L5 level, mildly compressing the thecal sac.');

-- inside the transaction: this session already sees both rows
SELECT p.patient_id, r.report_id, r.clinician_notes
  FROM patient p JOIN radiology_report r ON r.patient_id = p.patient_id
 WHERE p.patient_id = '0576';

COMMIT;
-- re-run A0: both counts +1, 0576 present in both tables


-- ---------------------------------------------------------------------
-- A2. Manual ROLLBACK test (the user cancels)
-- ---------------------------------------------------------------------
START TRANSACTION;
INSERT INTO patient (patient_id) VALUES ('0577');
INSERT INTO radiology_report (patient_id, clinician_notes) VALUES ('0577', 'Draft report - to be cancelled');
SELECT * FROM radiology_report WHERE patient_id = '0577';   -- 1 row (inside the transaction)
ROLLBACK;
SELECT * FROM patient          WHERE patient_id = '0577';   -- 0 rows
SELECT * FROM radiology_report WHERE patient_id = '0577';   -- 0 rows


-- ---------------------------------------------------------------------
-- A3. Failure test without a handler: an error does NOT roll back
--     the transaction. Only the failing statement is undone.
-- ---------------------------------------------------------------------
START TRANSACTION;
INSERT INTO patient (patient_id) VALUES ('0578');                       -- OK
INSERT INTO radiology_report (patient_id, clinician_notes)
VALUES ('0587', 'Typo in patient id');                                   -- EXPECTED ERROR 1452 (FK)
SELECT * FROM patient WHERE patient_id = '0578';                        -- 1 row: step 1 still pending
ROLLBACK;                                                               -- must be done explicitly
SELECT * FROM patient WHERE patient_id = '0578';                        -- 0 rows


-- ---------------------------------------------------------------------
-- A4. Safe design: procedure with an EXIT HANDLER
--     Any SQL error -> ROLLBACK of every step -> original error re-raised
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS add_patient_with_report;
DELIMITER //
CREATE PROCEDURE add_patient_with_report(
    IN p_patient_id VARCHAR(10),
    IN p_notes      LONGTEXT      -- LONGTEXT so an oversize note reaches the INSERT and fails there
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;     -- undo every step of this transaction
        RESIGNAL;     -- pass the original error back to the caller
    END;

    START TRANSACTION;
        INSERT INTO patient (patient_id) VALUES (p_patient_id);
        INSERT INTO radiology_report (patient_id, clinician_notes)
        VALUES (p_patient_id, p_notes);
    COMMIT;
END //
DELIMITER ;

-- Fails at step 2: 70,000 characters exceed TEXT (65,535 bytes)
CALL add_patient_with_report('0578', REPEAT('x', 70000));              -- EXPECTED ERROR 1406
SELECT * FROM patient WHERE patient_id = '0578';                        -- 0 rows: step 1 rolled back automatically

-- Fails at step 1: CHECK chk_patient_id_format (digits only)
CALL add_patient_with_report('A578', 'Bad id');                         -- EXPECTED ERROR 3819
SELECT * FROM patient WHERE patient_id = 'A578';                        -- 0 rows

-- Succeeds: COMMIT path through the procedure
CALL add_patient_with_report('0578', 'No evidence of disc herniation.');
SELECT * FROM radiology_report WHERE patient_id = '0578';               -- 1 row


-- =====================================================================
-- SCENARIO B: amend a report and correct its study
-- =====================================================================

-- ---------------------------------------------------------------------
-- B-setup: give test patient 0576 a study, remember its id in @sid
--          (@sid is per session: re-run the SET line after reconnecting)
-- ---------------------------------------------------------------------
INSERT INTO study (patient_id, study_name, study_date)
VALUES ('0576', 'L-SPINE_LSS_20261010_090000_000000', '2026-10-10');

SELECT study_id INTO @sid FROM study WHERE patient_id = '0576' LIMIT 1;
SELECT @sid;                                                            -- must not be NULL


-- ---------------------------------------------------------------------
-- B0. Snapshot (run before and after each test)
-- ---------------------------------------------------------------------
SELECT r.report_id, r.clinician_notes, s.study_id, s.study_name, s.study_date
  FROM radiology_report r
  JOIN study s ON s.patient_id = r.patient_id
 WHERE r.patient_id = '0576';


-- ---------------------------------------------------------------------
-- B1. COMMIT test
--     study_date is derived from the date inside study_name,
--     so both columns change together.
-- ---------------------------------------------------------------------
START TRANSACTION;

UPDATE radiology_report
   SET clinician_notes = CONCAT(clinician_notes, ' // Addendum: study date corrected to 2026-10-11.')
 WHERE patient_id = '0576';                                             -- 1 row affected

UPDATE study
   SET study_name = REPLACE(study_name, '20261010', '20261011'),
       study_date = '2026-10-11'
 WHERE study_id = @sid AND patient_id = '0576';                         -- 1 row affected

COMMIT;
-- re-run B0: notes end with the addendum, ..._20261011_..., 2026-10-11


-- ---------------------------------------------------------------------
-- B2. Manual ROLLBACK test
-- ---------------------------------------------------------------------
START TRANSACTION;
UPDATE radiology_report SET clinician_notes = 'WRONG TEXT - will be cancelled' WHERE patient_id = '0576';
UPDATE study SET study_date = '2000-01-01' WHERE study_id = @sid AND patient_id = '0576';
SELECT r.clinician_notes, s.study_date
  FROM radiology_report r JOIN study s ON s.patient_id = r.patient_id
 WHERE r.patient_id = '0576';                                           -- both changed
ROLLBACK;
SELECT r.clinician_notes, s.study_date
  FROM radiology_report r JOIN study s ON s.patient_id = r.patient_id
 WHERE r.patient_id = '0576';                                           -- both back to the B1 values


-- ---------------------------------------------------------------------
-- B3. Failure test without validation: an UPDATE that matches no rows
--     is NOT an error, so nothing stops a half-done COMMIT.
-- ---------------------------------------------------------------------
START TRANSACTION;
UPDATE radiology_report SET clinician_notes = 'Addendum for a study that does not exist' WHERE patient_id = '0576';
UPDATE study SET study_date = '2026-10-12' WHERE study_id = 999999 AND patient_id = '0576';   -- 0 rows matched, no error
ROLLBACK;                                                               -- a COMMIT here would save only the report change


-- ---------------------------------------------------------------------
-- B4. Safe design: procedure that validates and rolls back on any error
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS amend_report_and_study;
DELIMITER //
CREATE PROCEDURE amend_report_and_study(
    IN p_patient_id VARCHAR(10),
    IN p_study_id   INT,
    IN p_new_notes  LONGTEXT,
    IN p_new_date   VARCHAR(20)     -- a string, so a bad date fails inside the UPDATE, not at CALL
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

        -- consistency rule: the study must belong to this patient
        IF NOT EXISTS (SELECT 1 FROM study
                        WHERE study_id = p_study_id AND patient_id = p_patient_id) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Study does not belong to this patient';
        END IF;

        -- step 1: amend the report
        UPDATE radiology_report
           SET clinician_notes = p_new_notes
         WHERE patient_id = p_patient_id;

        -- step 2: fix the study. study_name goes FIRST: MySQL applies SET left to right,
        -- so DATE_FORMAT(study_date, ...) must still read the old date
        UPDATE study
           SET study_name = REPLACE(study_name, DATE_FORMAT(study_date, '%Y%m%d'), REPLACE(p_new_date, '-', '')),
               study_date = p_new_date
         WHERE study_id = p_study_id AND patient_id = p_patient_id;

    COMMIT;
END //
DELIMITER ;

-- Fails at step 2: 30 February is not a valid date (strict mode)
CALL amend_report_and_study('0576', @sid, 'This text must NOT be saved', '2026-02-30');   -- EXPECTED ERROR 1292
SELECT r.clinician_notes, s.study_name, s.study_date
  FROM radiology_report r JOIN study s ON s.patient_id = r.patient_id
 WHERE r.patient_id = '0576';                                           -- unchanged: step 1 rolled back

-- Fails validation: the study does not belong to this patient
CALL amend_report_and_study('0576', 999999, 'This text must NOT be saved', '2026-10-12'); -- EXPECTED ERROR 1644
SELECT r.clinician_notes, s.study_name, s.study_date
  FROM radiology_report r JOIN study s ON s.patient_id = r.patient_id
 WHERE r.patient_id = '0576';                                           -- unchanged

-- Succeeds
CALL amend_report_and_study('0576', @sid,
     'LSS MRI: Diffuse disc bulge at L4/L5. // Addendum: study date corrected to 2026-10-12.', '2026-10-12');
SELECT r.clinician_notes, s.study_name, s.study_date
  FROM radiology_report r JOIN study s ON s.patient_id = r.patient_id
 WHERE r.patient_id = '0576';                                           -- new notes, ..._20261012_..., 2026-10-12

