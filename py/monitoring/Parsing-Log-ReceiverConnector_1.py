import csv
import ipaddress
import re
from collections import defaultdict

MAX_EXPAND_IPS = 8000

def expand_ip_range(ip_range_str):
    if not ip_range_str:
        return []

    ip_range_str = ip_range_str.strip()
    raw_parts = re.split(r'[,\s]+', ip_range_str)
    expanded = []

    for part in raw_parts:
        if not part or part.startswith(':'):
            continue  # Skip IPv6 or empty entries

        # IP short range (e.g. 192.168.0.1-10)
        dash_short_match = re.match(r'(\d{1,3}(?:\.\d{1,3}){3})-(\d{1,3})$', part)
        if dash_short_match:
            start_ip = dash_short_match.group(1)
            end_octet = int(dash_short_match.group(2))
            start_last = int(start_ip.split('.')[-1])
            count = end_octet - start_last + 1

            if count > MAX_EXPAND_IPS:
                print(f"⚠️ IP short range terlalu besar: {part} -> dilewati ({count} IP)")
                continue

            for i in range(start_last, end_octet + 1):
                new_ip = '.'.join(start_ip.split('.')[:-1] + [str(i)])
                expanded.append(new_ip)
            continue

        # Full IP range (e.g. 192.168.0.10-192.168.0.20)
        if '-' in part:
            try:
                start_ip, end_ip = part.split('-')
                start = ipaddress.IPv4Address(start_ip)
                end = ipaddress.IPv4Address(end_ip)
                total_ips = int(end) - int(start) + 1

                if total_ips > MAX_EXPAND_IPS:
                    print(f"⚠️ IP range terlalu besar: {part} -> dilewati ({total_ips} IP)")
                    continue

                for ip_int in range(int(start), int(end) + 1):
                    expanded.append(str(ipaddress.IPv4Address(ip_int)))
            except Exception as e:
                print(f"⚠️ Gagal parsing range IP: {part} -> {e}")
            continue

        # CIDR (e.g. 192.168.10.0/30)
        if '/' in part:
            try:
                network = ipaddress.IPv4Network(part.strip(), strict=False)
                count = network.num_addresses
                if count > MAX_EXPAND_IPS:
                    print(f"⚠️ CIDR terlalu besar: {part} -> dilewati ({count} IP)")
                    continue
                expanded.extend([str(ip) for ip in network.hosts()])
            except Exception as e:
                print(f"⚠️ Bukan CIDR valid: {part} -> {e}")
            continue

        # Single IP
        try:
            ipaddress.IPv4Address(part)
            expanded.append(part)
        except Exception:
            print(f"⚠️ Bukan IP valid: {part}")

    return expanded


def parse_and_flatten_csv(input_file, output_file):
    with open(input_file, 'r', newline='', encoding='utf-8-sig') as csvfile_in:
        reader = csv.DictReader(csvfile_in, delimiter=',')
        headers = reader.fieldnames
        if not headers:
            raise ValueError("No headers found in CSV")

        # Replace RemoteIPRanges with RemoteIPAddress in output
        new_headers = []
        for h in headers:
            if h == 'RemoteIPRanges':
                new_headers.append('RemoteIPAddress')
            else:
                new_headers.append(h)

        with open(output_file, 'w', newline='', encoding='utf-8') as csvfile_out:
            writer = csv.writer(csvfile_out, delimiter=',')
            writer.writerow(new_headers)

            for row in reader:
                ip_ranges = row.get('RemoteIPRanges', '').strip()
                expanded_ips = expand_ip_range(ip_ranges)

                for ip in expanded_ips:
                    new_row = []
                    for h in headers:
                        if h == 'RemoteIPRanges':
                            new_row.append(ip)
                        else:
                            new_row.append(row.get(h, ''))
                    writer.writerow(new_row)

    print(f"✅ Expanded CSV written to: {output_file}")


def find_duplicate_and_unique_ips(input_file, duplicate_output_file, unique_output_file, combined_output_file):
    ip_to_rows = defaultdict(list)

    with open(input_file, newline='', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile, delimiter=',')
        all_headers = reader.fieldnames
        print("📌 Input CSV headers:", all_headers)
        
        for row in reader:
            ip = row['RemoteIPAddress'].strip()
            ip_to_rows[ip].append(row)

    duplicates, uniques = {}, {}
    for ip, rows in ip_to_rows.items():
        identities_for_ip = set(row['Identity'].strip() for row in rows)
        if len(identities_for_ip) > 1:
            duplicates[ip] = rows
        else:
            uniques[ip] = rows

    # Duplicate output
    with open(duplicate_output_file, mode='w', newline='', encoding='utf-8') as outcsv:
        writer = csv.DictWriter(outcsv, fieldnames=all_headers + ['DuplicateCount'], delimiter=',')
        writer.writeheader()
        for ip, rows in duplicates.items():
            unique_identities = set(row['Identity'].strip() for row in rows)
            duplicate_count = len(unique_identities)
            unique_combinations = {}
            for row in rows:
                key = (row['RemoteIPAddress'].strip(), row['Identity'].strip())
                if key not in unique_combinations:
                    unique_combinations[key] = row
            for (ip_key, identity_key), row in unique_combinations.items():
                row_with_count = row.copy()
                row_with_count['DuplicateCount'] = duplicate_count
                writer.writerow(row_with_count)

    # Unique output
    with open(unique_output_file, mode='w', newline='', encoding='utf-8') as outcsv:
        writer = csv.DictWriter(outcsv, fieldnames=all_headers, delimiter=',')
        writer.writeheader()
        for ip, rows in uniques.items():
            for row in rows:
                writer.writerow(row)

    # Combined output
    with open(combined_output_file, mode='w', newline='', encoding='utf-8') as outcsv:
        writer = csv.DictWriter(outcsv, fieldnames=all_headers + ['Status', 'DuplicateCount'], delimiter=',')
        writer.writeheader()
        for ip, rows in duplicates.items():
            unique_identities = set(row['Identity'].strip() for row in rows)
            duplicate_count = len(unique_identities)
            for row in rows:
                row_with_status = row.copy()
                row_with_status['Status'] = 'Duplicate'
                row_with_status['DuplicateCount'] = duplicate_count
                writer.writerow(row_with_status)
        for ip, rows in uniques.items():
            for row in rows:
                row_with_status = row.copy()
                row_with_status['Status'] = 'Unique'
                row_with_status['DuplicateCount'] = 1
                writer.writerow(row_with_status)

    # Summary
    total_duplicate_rows = sum(len(rows) for rows in duplicates.values())
    total_unique_rows = sum(len(rows) for rows in uniques.values())
    total_unique_combinations_in_duplicates = sum(
        len(set((row['RemoteIPAddress'].strip(), row['Identity'].strip()) for row in rows))
        for ip, rows in duplicates.items()
    )
    duplicate_identities = set()
    for ip, rows in duplicates.items():
        for row in rows:
            duplicate_identities.add(row['Identity'].strip())

    print(f"\n=== 📊 Analysis Summary ===")
    print(f"Total unique IPs: {len(ip_to_rows)}")
    print(f"Duplicate IPs (shared by multiple identities): {len(duplicates)}")
    print(f"Unique IPs (single identity): {len(uniques)}")
    print(f"Total duplicate rows (raw): {total_duplicate_rows}")
    print(f"Unique IP-Identity pairs in duplicates: {total_unique_combinations_in_duplicates}")
    print(f"Total processed rows: {total_duplicate_rows + total_unique_rows}")
    print(f"Identities involved in duplicates: {len(duplicate_identities)}")
    print(f"⚠️ Eliminated {total_duplicate_rows - total_unique_combinations_in_duplicates} redundant rows")


def analyze_duplicate_patterns(input_file):
    ip_to_identities = defaultdict(set)
    with open(input_file, newline='', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile, delimiter=',')
        for row in reader:
            ip = row['RemoteIPAddress'].strip()
            identity = row['Identity'].strip()
            ip_to_identities[ip].add(identity)

    duplicate_counts = defaultdict(list)
    for ip, identities in ip_to_identities.items():
        if len(identities) > 1:
            duplicate_counts[len(identities)].append((ip, list(identities)))

    if duplicate_counts:
        print(f"\n=== 🔍 Duplicate Patterns Analysis ===")
        for count, ip_list in sorted(duplicate_counts.items(), reverse=True):
            print(f"\nIPs shared by {count} connectors ({len(ip_list)} IPs):")
            for ip, identities in ip_list[:5]:
                print(f"  {ip}: {', '.join(identities)}")
            if len(ip_list) > 5:
                print(f"  ... and {len(ip_list) - 5} more IPs")


if __name__ == "__main__":
    input_file_raw = '/Users/eki/File Eki/2023 - 2024/Kerjaan/System Engineer/Mandiri/Data/SMTP Relay - 19 Juni 2025/Script Parsing/ReceiverConnectors_AllServers_20250703_152340 1.csv'
    expanded_file = '/Users/eki/File Eki/2023 - 2024/Kerjaan/System Engineer/Mandiri/Data/SMTP Relay - 19 Juni 2025/Script Parsing/7 Juli 2025/Output-Expanded.csv'
    duplicate_output_file = '7 Juli 2025/Duplicate-Receiver-Connector.csv'
    unique_output_file = '7 Juli 2025/Unique-Receiver-Connector.csv'
    combined_output_file = '7 Juli 2025/Combined-Analysis-Receiver-Connector.csv'

    parse_and_flatten_csv(input_file_raw, expanded_file)
    find_duplicate_and_unique_ips(expanded_file, duplicate_output_file, unique_output_file, combined_output_file)
    analyze_duplicate_patterns(expanded_file)
