-- Phase 4.4: Concurrency Control
-- Target Table: radiology_report (columns: patient_id, clinician_notes)

-- PART 0: Initial Data setup
USE mri_radiology_db;

-- 1. Verify MySQL transaction isolation level/lockwait
SELECT @@transaction_isolation AS default_isolation_level,
       @@innodb_lock_wait_timeout AS lock_wait_timeout_seconds;

-- 2. create table 'patient' and 'radiology_report' if not exist
CREATE TABLE IF NOT EXISTS patient (
    patient_id VARCHAR(10) NOT NULL PRIMARY KEY
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS radiology_report (
    report_id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    patient_id VARCHAR(10) NOT NULL UNIQUE,
    clinician_notes TEXT NULL,
    CONSTRAINT fk_report_patient 
        FOREIGN KEY (patient_id) REFERENCES patient(patient_id) 
        ON DELETE CASCADE
) ENGINE=InnoDB;

-- 3. sample patient record
INSERT IGNORE INTO patient (patient_id) VALUES ('0001');

-- 4. Initialize / Reset baseline report record for patient '0001'
INSERT INTO radiology_report (patient_id, clinician_notes)
VALUES ('0001', 'INITIAL: Patient presenting with mild L4-L5 lumbar disc degeneration.')
ON DUPLICATE KEY UPDATE 
    clinician_notes = 'INITIAL: Patient presenting with mild L4-L5 lumbar disc degeneration.';
SELECT * FROM radiology_report WHERE patient_id = '0001';

-- SCENARIO 1: SESSION A & SESSION B (LOCK CONTENTION & COMMIT SEQUENCE)
-- Description: Two clinicians simultaneously update the report for patient 0001.

--STEP 1: Execute in SESSION A (Doctor A)
USE mri_radiology_db;
START TRANSACTION;

UPDATE radiology_report 
SET clinician_notes = 'DOCTOR A: Identified additional L4-L5 disc herniation compressing nerve roots.'
WHERE patient_id = '0001';


-- STEP 2: Execute in SESSION B (Doctor B) 
-- Simultaneously attempt to modify the same record
USE mri_radiology_db;
START TRANSACTION;

UPDATE radiology_report 
SET clinician_notes = 'DOCTOR B: Identified additional L5-S1 annular tear.'
WHERE patient_id = '0001';

-- [OBSERVED BEHAVIOR AT SESSION B]:
-- Session B is immediately BLOCKED (waiting for Session A's lock).

-- ---------------------------------------------------------------------
-- [CASE 1: TIMEOUT TEST]
-- If A not COMMIT in 50s
-- Session B: ERROR 1205 (HY000): Lock wait timeout exceeded


-- [CASE 2: COMMIT & SERIALIZED RELEASE TEST]
-- STEP3: commit in session A, release lock
COMMIT;

-- [OBSERVED BEHAVIOR AT SESSION B]:
-- Immediately upon Session A's COMMIT, Session B unblocks and displays:

-- STEP 4: In SESSION B, finalize changes with COMMIT 
COMMIT;

-- STEP 5: Verify final stored data 
SELECT * FROM radiology_report WHERE patient_id = '0001';

-- SCENARIO 2: SESSION C & SESSION D (C -> ROLLBACK -> D CONTINUES)

-- 1: Reset test data 
UPDATE radiology_report 
SET clinician_notes = 'INITIAL: Patient presenting with mild L4-L5 lumbar disc degeneration.'
WHERE patient_id = '0001';


-- STEP 2: In SESSION C (Doctor C) 
USE mri_radiology_db;
START TRANSACTION;

UPDATE radiology_report 
SET clinician_notes = 'DOCTOR C: Preliminary unverified draft diagnosis.'
WHERE patient_id = '0001';

-- [SESSION C HOLDS X-LOCK, TRANSACTION REMAINS ACTIVE]


-- STEP 3: In SESSION D (Doctor D) 
USE mri_radiology_db;
START TRANSACTION;

UPDATE radiology_report 
SET clinician_notes = 'DOCTOR D: Formal confirmed diagnosis following spine consultation.'
WHERE patient_id = '0001';

-- [OBSERVED BEHAVIOR]: Session D is BLOCKED (waiting for Session C).


-- STEP 4: In SESSION C, abort draft update via ROLLBACK 
ROLLBACK;

-- [OBSERVED BEHAVIOR]:when C rolls back, Session D unblocks immediately


-- STEP 5: In SESSION D, finalize confirmed diagnosis with COMMIT 
COMMIT;

-- STEP 6: Verify final stored data 
SELECT * FROM radiology_report WHERE patient_id = '0001';
-- Doctor D's confirmed diagnosis is safely stored; Doctor C's draft was discarded cleanly.