"""
Phase 4.2 - do thoi gian that cua Q1/Q2 (lap lai nhieu lan) va luong du lieu tra ve.

EXPLAIN ANALYZE cho thoi gian cua 1 lan chay (rat nho, nhieu nhat vai ms nen
de bi nhieu). Script nay chay moi query N lan qua mysql-connector (giong cach
ung dung Flask goi) roi bao cao median / p95 va so byte tra ve.

Cach dung (o thu muc goc cua project, da kich hoat .venv):
    python 01_Database/phase4_2/phase4_2_benchmark.py --label B_hien_tai
    (tao index tong hop o muc 4.1 cua file SQL)
    python 01_Database/phase4_2/phase4_2_benchmark.py --label C_index_tong_hop
    python 01_Database/phase4_2/phase4_2_benchmark.py --label A_khong_index --database mri_noindex

Ket qua duoc ghi them vao phase4_2_results.csv (cung thu muc voi script).
Lay thong tin ket noi tu file .env o thu muc goc (giong main.py).
"""
import argparse
import csv
import os
import statistics
import time
from pathlib import Path

import mysql.connector
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parents[2]
load_dotenv(BASE_DIR / ".env")

Q1 = """
SELECT p.patient_id, rr.report_id, rr.clinician_notes,
       s.study_id, s.study_name, s.study_date,
       se.series_id, se.series_name, se.sequence_type, se.orientation,
       i.image_id, i.file_name, i.file_path
FROM patient p
LEFT JOIN radiology_report rr ON p.patient_id = rr.patient_id
LEFT JOIN study s             ON p.patient_id = s.patient_id
LEFT JOIN series se           ON s.study_id   = se.study_id
LEFT JOIN mri_image i         ON se.series_id = i.series_id
WHERE p.patient_id = %s
ORDER BY s.study_date, se.series_id, i.image_id
"""

Q1_REWRITTEN_IMAGES = """
SELECT s.study_id, s.study_name, s.study_date,
       se.series_id, se.series_name, se.sequence_type, se.orientation,
       i.image_id, i.file_name, i.file_path
FROM study s
JOIN series se   ON se.study_id = s.study_id
JOIN mri_image i ON i.series_id = se.series_id
WHERE s.patient_id = %s
ORDER BY s.study_date, se.series_id, i.image_id
"""

Q1_REWRITTEN_REPORT = """
SELECT report_id, patient_id, clinician_notes
FROM radiology_report
WHERE patient_id = %s
"""

Q2 = """
SELECT p.patient_id, rr.report_id, rr.clinician_notes,
       s.study_id, s.study_name, s.study_date,
       se.series_id, se.series_name, se.sequence_type, se.orientation,
       i.image_id, i.file_name, i.file_path
FROM patient p
JOIN study s                  ON p.patient_id = s.patient_id
JOIN series se                ON s.study_id   = se.study_id
JOIN mri_image i              ON se.series_id = i.series_id
LEFT JOIN radiology_report rr ON p.patient_id = rr.patient_id
WHERE p.patient_id = %s AND se.sequence_type = %s AND se.orientation = %s
ORDER BY s.study_date, se.series_id, i.image_id
"""


def run_once(cur, queries):
    """Chay danh sach (sql, params); tra ve (so dong, so byte du lieu)."""
    rows_total = bytes_total = 0
    for sql, params in queries:
        cur.execute(sql, params)
        rows = cur.fetchall()
        rows_total += len(rows)
        bytes_total += sum(len(str(v)) for row in rows for v in row if v is not None)
    return rows_total, bytes_total


def bench(cur, name, queries, repeat, warmup=5):
    for _ in range(warmup):
        run_once(cur, queries)
    times = []
    for _ in range(repeat):
        t0 = time.perf_counter()
        rows, size = run_once(cur, queries)
        times.append((time.perf_counter() - t0) * 1000)
    times.sort()
    return {
        "query": name,
        "rows": rows,
        "bytes": size,
        "median_ms": round(statistics.median(times), 3),
        "p95_ms": round(times[int(len(times) * 0.95) - 1], 3),
        "mean_ms": round(statistics.mean(times), 3),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", required=True, help="ten cau hinh, vd B_hien_tai")
    ap.add_argument("--database", default=os.getenv("DATABASE_NAME"))
    ap.add_argument("--patient", default="0230")
    ap.add_argument("--sequence", default="T2")
    ap.add_argument("--orientation", default="SAG")
    ap.add_argument("--repeat", type=int, default=300)
    a = ap.parse_args()

    conn = mysql.connector.connect(
        host=os.getenv("HOST"), port=int(os.getenv("PORT", 3306)),
        user=os.getenv("USER"), password=os.getenv("PASSWORD"),
        database=a.database,
    )
    cur = conn.cursor()
    pid = a.patient
    cases = [
        ("Q1_goc", [(Q1, (pid,))]),
        ("Q1_viet_lai(anh+report)", [(Q1_REWRITTEN_IMAGES, (pid,)), (Q1_REWRITTEN_REPORT, (pid,))]),
        ("Q2_goc", [(Q2, (pid, a.sequence, a.orientation))]),
    ]
    out = Path(__file__).with_name("phase4_2_results.csv")
    new = not out.exists()
    with out.open("a", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["label", "database", "query", "rows",
                                          "bytes", "median_ms", "p95_ms", "mean_ms"])
        if new:
            w.writeheader()
        for name, queries in cases:
            r = bench(cur, name, queries, a.repeat)
            r.update(label=a.label, database=a.database)
            w.writerow(r)
            print(f"{a.label:20s} {name:26s} rows={r['rows']:5d} bytes={r['bytes']:8d} "
                  f"median={r['median_ms']:8.3f} ms  p95={r['p95_ms']:8.3f} ms")
    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
