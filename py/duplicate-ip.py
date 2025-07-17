import csv
from collections import defaultdict

def find_duplicate_and_unique_ips(input_file, duplicate_output_file, unique_output_file, combined_output_file):
    ip_to_rows = defaultdict(list)
    all_headers = []
    
    # Step 1: Baca input dan kelompokkan IP -> semua data row
    with open(input_file, newline='', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile, delimiter=',')
        all_headers = reader.fieldnames
        print("📌 Input CSV headers:", all_headers)
        
        for row in reader:
            ip = row['RemoteIPAddress'].strip()
            ip_to_rows[ip].append(row)
    
    # Step 2: Pisahkan duplicate dan unique berdasarkan kriteria yang tepat
    duplicates = {}
    uniques = {}
    
    for ip, rows in ip_to_rows.items():
        # Ambil semua Identity untuk IP ini
        identities_for_ip = set(row['Identity'].strip() for row in rows)
        
        # DUPLICATE: RemoteIPAddress sama dengan Identity yang berbeda (lebih dari 1 Identity)
        if len(identities_for_ip) > 1:
            duplicates[ip] = rows
        # UNIQUE: RemoteIPAddress hanya digunakan oleh 1 Identity saja
        else:
            uniques[ip] = rows
    
    # Step 3: Simpan duplicate ke CSV (eliminasi data sama IP + Identity)
    with open(duplicate_output_file, mode='w', newline='', encoding='utf-8') as outcsv:
        writer = csv.DictWriter(outcsv, fieldnames=all_headers + ['DuplicateCount'])
        writer.writeheader()
        
        for ip, rows in duplicates.items():
            # Hitung berapa Identity unik yang menggunakan IP ini
            unique_identities = set(row['Identity'].strip() for row in rows)
            duplicate_count = len(unique_identities)
            
            # Eliminasi duplikasi: buat dictionary dengan key (IP, Identity) untuk ambil 1 data saja
            unique_combinations = {}
            for row in rows:
                key = (row['RemoteIPAddress'].strip(), row['Identity'].strip())
                if key not in unique_combinations:
                    unique_combinations[key] = row
            
            # Tulis hanya data unik per kombinasi IP-Identity
            for (ip_key, identity_key), row in unique_combinations.items():
                row_with_count = row.copy()
                row_with_count['DuplicateCount'] = duplicate_count
                writer.writerow(row_with_count)
    
    # Step 4: Simpan unique ke CSV
    with open(unique_output_file, mode='w', newline='', encoding='utf-8') as outcsv:
        writer = csv.DictWriter(outcsv, fieldnames=all_headers)
        writer.writeheader()
        
        for ip, rows in uniques.items():
            for row in rows:
                writer.writerow(row)
    
    # Step 5: Simpan combined (semua data dengan status duplicate/unique)
    with open(combined_output_file, mode='w', newline='', encoding='utf-8') as outcsv:
        writer = csv.DictWriter(outcsv, fieldnames=all_headers + ['Status', 'DuplicateCount'])
        writer.writeheader()
        
        # Write duplicates with status
        for ip, rows in duplicates.items():
            unique_identities = set(row['Identity'].strip() for row in rows)
            duplicate_count = len(unique_identities)
            
            for row in rows:
                row_with_status = row.copy()
                row_with_status['Status'] = 'Duplicate'
                row_with_status['DuplicateCount'] = duplicate_count
                writer.writerow(row_with_status)
        
        # Write uniques with status
        for ip, rows in uniques.items():
            for row in rows:
                row_with_status = row.copy()
                row_with_status['Status'] = 'Unique'
                row_with_status['DuplicateCount'] = 1
                writer.writerow(row_with_status)
    
    # Step 6: Cetak summary ke layar dengan kriteria yang benar
    print(f"\n=== 📊 Analysis Summary ===")
    print(f"Total unique IP addresses: {len(ip_to_rows)}")
    print(f"IPs with DUPLICATE usage (same IP, different Identity): {len(duplicates)}")
    print(f"IPs with UNIQUE usage (IP only used by one Identity): {len(uniques)}")
    
    total_duplicate_rows = sum(len(rows) for rows in duplicates.values())
    total_unique_rows = sum(len(rows) for rows in uniques.values())
    
    # Hitung total kombinasi unik IP-Identity untuk duplicate
    total_unique_combinations_in_duplicates = 0
    for ip, rows in duplicates.items():
        unique_combinations = set((row['RemoteIPAddress'].strip(), row['Identity'].strip()) for row in rows)
        total_unique_combinations_in_duplicates += len(unique_combinations)
    
    print(f"Total connector entries using duplicate IPs (raw): {total_duplicate_rows}")
    print(f"Total unique IP-Identity combinations in duplicates: {total_unique_combinations_in_duplicates}")
    print(f"Total connector entries using unique IPs: {total_unique_rows}")
    print(f"Total connector entries processed: {total_duplicate_rows + total_unique_rows}")
    
    # Tambahan: Hitung berapa Identity unik yang terlibat dalam duplicate
    duplicate_identities = set()
    for ip, rows in duplicates.items():
        for row in rows:
            duplicate_identities.add(row['Identity'].strip())
    
    print(f"Number of Identities involved in IP conflicts: {len(duplicate_identities)}")
    print(f"⚠️  Eliminated {total_duplicate_rows - total_unique_combinations_in_duplicates} redundant rows in duplicate file")
    
    # Step 7: Cetak detail duplicate IPs dengan penjelasan yang jelas
    if duplicates:
        print(f"\n🔁 DUPLICATE Case Found ({len(duplicates)} IP addresses):")
        print("   → Same RemoteIPAddress used by different Identities")
        for ip, rows in duplicates.items():
            identities = list(set(row['Identity'].strip() for row in rows))
            print(f"\n📍 IP: {ip}")
            print(f"   Used by {len(identities)} different Identities:")
            for identity in identities:
                print(f"     - {identity}")
    else:
        print(f"\n✅ No DUPLICATE cases found.")
        print("   → All RemoteIPAddresses are used by only one Identity each")
    
    if uniques:
        print(f"\n✨ UNIQUE Case Summary ({len(uniques)} IP addresses):")
        print("   → Each RemoteIPAddress is used by only one Identity")
        print(f"   → {len(uniques)} IPs have exclusive usage")
    else:
        print(f"\n⚠️  No UNIQUE cases found.")
        print("   → All IPs are shared between multiple Identities")
    
    # Step 8: Print file locations dengan penjelasan eliminasi
    print(f"\n📁 Output files created:")
    print(f"  - Duplicates only: {duplicate_output_file}")
    print(f"    └─ ✂️  Eliminated duplicate rows with same IP+Identity combination")
    print(f"  - Uniques only: {unique_output_file}")
    print(f"  - Combined (all data): {combined_output_file}")
    print(f"    └─ ⚠️  Contains original data (no elimination applied)")

def analyze_duplicate_patterns(input_file):
    """Additional analysis function to show duplicate patterns"""
    ip_to_identities = defaultdict(set)
    
    with open(input_file, newline='', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile, delimiter=',')
        for row in reader:
            ip = row['RemoteIPAddress'].strip()
            identity = row['Identity'].strip()
            ip_to_identities[ip].add(identity)
    
    # Group by number of duplicates
    duplicate_counts = defaultdict(list)
    for ip, identities in ip_to_identities.items():
        if len(identities) > 1:
            duplicate_counts[len(identities)].append((ip, list(identities)))
    
    if duplicate_counts:
        print(f"\n=== 🔍 Duplicate Patterns Analysis ===")
        for count, ip_list in sorted(duplicate_counts.items(), reverse=True):
            print(f"\nIPs shared by {count} connectors ({len(ip_list)} IPs):")
            for ip, identities in ip_list[:5]:  # Show first 5 examples
                print(f"  {ip}: {', '.join(identities)}")
            if len(ip_list) > 5:
                print(f"  ... and {len(ip_list) - 5} more IPs")

if __name__ == "__main__":
    # File paths
    input_file = '/Users/eki/File Eki/2023 - 2024/Kerjaan/System Engineer/Mandiri/Data/SMTP Relay - 19 Juni 2025/Script Parsing/Output-Parsing.csv'
    duplicate_output_file = '1 Juli 2025/Duplicate-Receiver-Connector.csv'
    unique_output_file = '1 Juli 2025/Unique-Receiver-Connector.csv'
    combined_output_file = '1 Juli 2025/Combined-Analysis-Receiver-Connector.csv'
    
    # Run the analysis
    find_duplicate_and_unique_ips(
        input_file, 
        duplicate_output_file, 
        unique_output_file, 
        combined_output_file
    )
    
    # Run additional pattern analysis
    analyze_duplicate_patterns(input_file)