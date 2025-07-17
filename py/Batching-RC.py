import csv
import os
from collections import defaultdict
from pathlib import Path

MAX_IPS_PER_FILE = 1000

input_file = "/Users/eki/File Eki/2023 - 2024/Kerjaan/System Engineer/Mandiri/Data/SMTP Relay - 19 Juni 2025/Script Parsing/7 Juli 2025/RCUniqueFinalPrintercsv.csv"
output_dir = "/Users/eki/File Eki/2023 - 2024/Kerjaan/System Engineer/Mandiri/Data/SMTP Relay - 19 Juni 2025/Script Parsing/7 Juli 2025/Batching-RC"

Path(output_dir).mkdir(parents=True, exist_ok=True)

# Simpan baris per Identity
identity_rows = defaultdict(list)

# Baca CSV
with open(input_file, newline='', encoding='utf-8-sig') as csvfile:
    reader = csv.DictReader(csvfile, delimiter=';')
    headers = reader.fieldnames
    if not headers:
        raise ValueError("No headers found in CSV")

    for row in reader:
        identity_rows[row['Identity']].append(row)

print(f"📌 Ditemukan {len(identity_rows)} Identity unik.")

# Untuk setiap Identity, split ke file2 dengan max 1000 IP
for identity, rows in identity_rows.items():
    total_chunks = (len(rows) + MAX_IPS_PER_FILE - 1) // MAX_IPS_PER_FILE

    for i in range(total_chunks):
        chunk_rows = rows[i*MAX_IPS_PER_FILE:(i+1)*MAX_IPS_PER_FILE]
        modified_rows = []

        for row in chunk_rows:
            new_row = {}
            # Buat Identity Old
            new_row['Identity Old'] = row['Identity']
            # Buat Identity baru (misal "All New Printer ... Batch 1")
            new_row['Identity'] = f"{row['Identity']} Batch {i+1}"

            # Salin kolom lain
            for h in headers:
                if h != 'Identity':
                    new_row[h] = row[h]
            modified_rows.append(new_row)

        # Buat header baru
        new_headers = ['Identity Old', 'Identity'] + [h for h in headers if h != 'Identity']

        # Filename aman
        safe_identity = identity.replace(' ', '_').replace(';', '_').replace('&', '_').replace('/', '_')
        output_file = os.path.join(output_dir, f"{safe_identity}_Batch_{i+1}.csv")

        # Tulis ke CSV
        with open(output_file, mode='w', newline='', encoding='utf-8') as outcsv:
            writer = csv.DictWriter(outcsv, fieldnames=new_headers, delimiter=';')
            writer.writeheader()
            writer.writerows(modified_rows)

        print(f"✅ Tulis {len(chunk_rows)} baris ke {output_file}")

print("\n🎉 Selesai splitting semua identity.")
