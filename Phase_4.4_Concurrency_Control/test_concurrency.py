#Phase 4.4 - Concurrency Control

import time
import threading
import mysql.connector

# MySQL Connection Configuration 
DB_CONFIG = {
    'host': 'localhost',
    'port': 3306,
    'user': 'root',
    'password': 'your_password_here',  # <-- Enter your MySQL root password 
    'database': 'mri_radiology_db'
}

def setup_database():
    """Initializes target database, tables, and sample baseline data."""
    print("=" * 65)
    print("[SETUP] Verifying and initializing sample test environment...")
    conn = mysql.connector.connect(
        host=DB_CONFIG['host'],
        port=DB_CONFIG['port'],
        user=DB_CONFIG['user'],
        password=DB_CONFIG['password']
    )
    cursor = conn.cursor()
    cursor.execute("CREATE DATABASE IF NOT EXISTS mri_radiology_db CHARACTER SET utf8mb4;")
    cursor.execute("USE mri_radiology_db;")
    
    # Create patient table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS patient (
            patient_id VARCHAR(10) NOT NULL PRIMARY KEY
        ) ENGINE=InnoDB;
    """)
    cursor.execute("INSERT IGNORE INTO patient (patient_id) VALUES ('0001');")
    
    # Create radiology_report table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS radiology_report (
            report_id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            patient_id VARCHAR(10) NOT NULL UNIQUE,
            clinician_notes TEXT NULL,
            CONSTRAINT fk_rep_pat FOREIGN KEY (patient_id) REFERENCES patient(patient_id) ON DELETE CASCADE
        ) ENGINE=InnoDB;
    """)
    
    cursor.execute("""
        INSERT INTO radiology_report (patient_id, clinician_notes)
        VALUES ('0001', 'INITIAL: Patient presenting with mild L4-L5 lumbar disc degeneration.')
        ON DUPLICATE KEY UPDATE 
            clinician_notes = 'INITIAL: Patient presenting with mild L4-L5 lumbar disc degeneration.';
    """)
    conn.commit()
    cursor.close()
    conn.close()
    print("[SETUP] Baseline data prepared successfully for patient 0001.")
    print("=" * 65)


def test_scenario_commit():
    """SCENARIO 1: Session A -> UPDATE -> holds lock -> Session B UPDATE (blocks) -> A COMMIT -> B succeeds."""
    print("\n" + "=" * 65)
    print(">>> RUNNING SCENARIO 1: SESSION A -> COMMIT -> SESSION B CONTINUES <<<")
    print("=" * 65)
    
    results = {}

    def session_a():
        conn_a = mysql.connector.connect(**DB_CONFIG)
        conn_a.autocommit = False
        cursor_a = conn_a.cursor()
        
        print(f"[{time.strftime('%H:%M:%S')}] [Session A - Doctor A] Starting transaction and updating patient 0001...")
        cursor_a.execute("""
            UPDATE radiology_report 
            SET clinician_notes = 'DOCTOR A: Identified additional L4-L5 disc herniation compressing nerve roots.' 
            WHERE patient_id = '0001';
        """)
        print(f"[{time.strftime('%H:%M:%S')}] [Session A - Doctor A] Updated successfully (holding X-Lock, uncommitted). Holding lock for 3 seconds...")
        time.sleep(3)
        
        print(f"[{time.strftime('%H:%M:%S')}] [Session A - Doctor A] Executing COMMIT (releasing lock)...")
        conn_a.commit()
        cursor_a.close()
        conn_a.close()
        print(f"[{time.strftime('%H:%M:%S')}] [Session A - Doctor A] COMMITTED successfully!")

    def session_b():
        time.sleep(1)  # Ensure Session A obtains lock first
        conn_b = mysql.connector.connect(**DB_CONFIG)
        conn_b.autocommit = False
        cursor_b = conn_b.cursor()
        
        start_wait = time.time()
        print(f"[{time.strftime('%H:%M:%S')}] [Session B - Doctor B] Attempting to UPDATE patient 0001 (Blocked waiting for lock)...")
        cursor_b.execute("""
            UPDATE radiology_report 
            SET clinician_notes = 'DOCTOR B: Identified additional L5-S1 annular tear.' 
            WHERE patient_id = '0001';
        """)
        wait_duration = time.time() - start_wait
        print(f"[{time.strftime('%H:%M:%S')}] [Session B - Doctor B] Acquired lock after {wait_duration:.2f} seconds of waiting!")
        conn_b.commit()
        cursor_b.close()
        conn_b.close()
        results['b_wait_time'] = wait_duration

    t_a = threading.Thread(target=session_a)
    t_b = threading.Thread(target=session_b)

    t_a.start()
    t_b.start()
    t_a.join()
    t_b.join()

    # Verify final result
    conn = mysql.connector.connect(**DB_CONFIG)
    cur = conn.cursor()
    cur.execute("SELECT clinician_notes FROM radiology_report WHERE patient_id = '0001';")
    final_note = cur.fetchone()[0]
    cur.close()
    conn.close()

    print("\n[SCENARIO 1 EVALUATION]:")
    print(f"- Session B lock wait duration: {results.get('b_wait_time', 0):.2f} seconds.")
    print(f"- Stored clinician note in DB: '{final_note}'")
    if 'DOCTOR B' in final_note:
        print("=> STATUS: PASSED (Serializability verified: Session B successfully overwrote after Session A committed).")


def test_scenario_rollback():
    """SCENARIO 2: Session C -> UPDATE -> Session D UPDATE (blocks) -> C ROLLBACK -> D succeeds."""
    print("\n" + "=" * 65)
    print(">>> RUNNING SCENARIO 2: SESSION C -> ROLLBACK -> SESSION D CONTINUES <<<")
    print("=" * 65)

    # Reset baseline state
    conn = mysql.connector.connect(**DB_CONFIG)
    cur = conn.cursor()
    cur.execute("""
        UPDATE radiology_report 
        SET clinician_notes = 'INITIAL: Patient presenting with mild L4-L5 lumbar disc degeneration.' 
        WHERE patient_id = '0001';
    """)
    conn.commit()
    cur.close()
    conn.close()

    def session_c():
        conn_c = mysql.connector.connect(**DB_CONFIG)
        conn_c.autocommit = False
        cursor_c = conn_c.cursor()
        
        print(f"[{time.strftime('%H:%M:%S')}] [Session C - Doctor C] Updating tentative draft diagnosis (holding X-Lock)...")
        cursor_c.execute("""
            UPDATE radiology_report 
            SET clinician_notes = 'DOCTOR C: Preliminary unverified draft diagnosis.' 
            WHERE patient_id = '0001';
        """)
        time.sleep(3)
        
        print(f"[{time.strftime('%H:%M:%S')}] [Session C - Doctor C] Deciding to ROLLBACK (aborting draft)...")
        conn_c.rollback()
        cursor_c.close()
        conn_c.close()

    def session_d():
        time.sleep(1)
        conn_d = mysql.connector.connect(**DB_CONFIG)
        conn_d.autocommit = False
        cursor_d = conn_d.cursor()
        
        print(f"[{time.strftime('%H:%M:%S')}] [Session D - Doctor D] Updating confirmed diagnosis (Blocked waiting for C)...")
        cursor_d.execute("""
            UPDATE radiology_report 
            SET clinician_notes = 'DOCTOR D: Formal confirmed diagnosis following spine consultation.' 
            WHERE patient_id = '0001';
        """)
        print(f"[{time.strftime('%H:%M:%S')}] [Session D - Doctor D] Released from block after C rolled back. Executing COMMIT...")
        conn_d.commit()
        cursor_d.close()
        conn_d.close()

    t_c = threading.Thread(target=session_c)
    t_d = threading.Thread(target=session_d)

    t_c.start()
    t_d.start()
    t_c.join()
    t_d.join()

    # Verify final result
    conn = mysql.connector.connect(**DB_CONFIG)
    cur = conn.cursor()
    cur.execute("SELECT clinician_notes FROM radiology_report WHERE patient_id = '0001';")
    final_note = cur.fetchone()[0]
    cur.close()
    conn.close()

    print("\n[SCENARIO 2 EVALUATION]:")
    print(f"- Stored clinician note in DB: '{final_note}'")
    if 'DOCTOR D' in final_note:
        print("=> STATUS: PASSED (Draft changes from C cleanly discarded; no Dirty Write anomaly; D saved reliably).")


if __name__ == '__main__':
    print("Automated Concurrency Control Test Runner .")
    print("Notice: Ensure 'password' in DB_CONFIG is configured before executing.")
    try:
        setup_database()
        test_scenario_commit()
        test_scenario_rollback()
        print("\n" + "=" * 65)
        print("ALL AUTOMATED CONCURRENCY TESTS EXECUTED SUCCESSFULLY!")
        print("=" * 65)
    except Exception as e:
        print(f"\n[ERROR] Connection or execution failure: {e}")
        print("Please verify the MySQL user 'root' password in DB_CONFIG.")
