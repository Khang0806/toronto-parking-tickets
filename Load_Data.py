import glob, os, csv
import psycopg2

FOLDER = r"D:\6. Toronto Parking Tickets"  
CONN = dict(host="localhost", port=5432, dbname="postgres",
            user="postgres", password="password")

EXPECTED = ["tag_number_masked", "date_of_infraction", "infraction_code",
            "infraction_description", "set_fine_amount", "time_of_infraction",
            "location1", "location2", "location3", "location4", "province"]

def open_after_header(path):
    fh = open(path, "rb")
    while True:
        line = fh.readline()
        if not line:
            fh.close()
            raise ValueError("Empty File")
        if line.strip():
            break
    text = line.decode("utf-8-sig", errors="replace")
    header = [h.strip().lower() for h in next(csv.reader([text]))]
    return fh, header

files = sorted(glob.glob(os.path.join(FOLDER, "**", "*.csv"), recursive=True))
print(f"Tim thay {len(files)} file")

# 1. Check Header
bad = []
for f in files:
    fh, header = open_after_header(f)
    fh.close()
    if header != EXPECTED:
        bad.append((os.path.basename(f), header))
if bad:
    for name, h in bad:
        print("Different HEADER:", name, h)
    raise SystemExit("Fix or Expected Before Loading.")

# 2. Load
conn = psycopg2.connect(**CONN)
cur = conn.cursor()
cur.execute("ALTER TABLE parking.raw_parking_tickets "
            "ADD COLUMN IF NOT EXISTS source_file TEXT;")
conn.commit()

cols = ", ".join(EXPECTED)
for f in files:
    name = os.path.basename(f)
    for enc in ("UTF8", "WIN1252"):
        fh, _ = open_after_header(f)
        try:
            cur.copy_expert(
                f"COPY parking.raw_parking_tickets ({cols}) FROM STDIN "
                f"WITH (FORMAT csv, HEADER false, ENCODING '{enc}')", fh)
            cur.execute("UPDATE parking.raw_parking_tickets SET source_file = %s "
                        "WHERE source_file IS NULL", (name,))
            conn.commit()
            print(f"OK  {name}  ({enc})")
            break
        except Exception as e:
            conn.rollback()
            print(f"Error {name} with {enc}: {str(e).splitlines()[0]}")
        finally:
            fh.close()

cur.close(); conn.close()