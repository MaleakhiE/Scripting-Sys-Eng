import csv
import ipaddress
import re
from collections import defaultdict

MAX_EXPAND_IPS = 1024  # Batas maksimal IP yang boleh di-expand per range

def expand_ip_range(ip_range_str):
    if not ip_range_str:
        return []

    ip_range_str = ip_range_str.strip()
    raw_parts = re.split(r'[,\s]+', ip_range_str)
    expanded = []

    for part in raw_parts:
        if not part:
            continue

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
        else:
            expanded.append(part)
    return expanded

def parse_csv(filename):
    connector_to_ips = defaultdict(list)
    with open(filename, 'r', newline='', encoding='utf-8-sig') as csvfile:
        reader = csv.DictReader(csvfile, delimiter=',')
        for row in reader:
            connector_name = row['Identity'].strip()
            ip_range_raw = row['$_.RemoteIPRanges'].strip()
            expanded_ips = expand_ip_range(ip_range_raw)
            connector_to_ips[connector_name].extend(expanded_ips)
    return connector_to_ips

def invert_mapping(connector_to_ips):
    ip_to_connectors = defaultdict(set)
    for connector, ip_list in connector_to_ips.items():
        for ip in ip_list:
            ip_to_connectors[ip].add(connector)
    return ip_to_connectors

def save_to_csv_with_shared(connector_to_ips, ip_to_connectors, output_file):
    with open(output_file, 'w', newline='', encoding='utf-8') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(['Identity', 'RemoteIPAddress', 'SharedWith'])
        for connector, ip_list in connector_to_ips.items():
            for ip in ip_list:
                shared_with = ip_to_connectors[ip] - {connector}
                shared_str = ', '.join(shared_with) if shared_with else ''
                writer.writerow([connector, ip, shared_str])
    print(f"✅ File hasil parsing + duplikasi disimpan ke: {output_file}")

def group_by_ip_sets(connector_to_ips):
    ip_set_to_connectors = defaultdict(list)
    for connector, ip_list in connector_to_ips.items():
        key = tuple(sorted(set(ip_list)))
        ip_set_to_connectors[key].append(connector)
    return ip_set_to_connectors

def print_duplicate_sets(ip_set_to_connectors):
    print("\n=== 🔁 Duplikasi RemoteIPRanges (Set Sama) ===")
    for ip_set, connectors in ip_set_to_connectors.items():
        if len(connectors) > 1:
            print(f"Connectors dengan IP sama: {', '.join(connectors)}")
            print("IP:", ' '.join(ip_set))
            print("---")

if __name__ == "__main__":
    filename = "/Users/eki/File Eki/2023 - 2024/Kerjaan/System Engineer/Mandiri/Dokumen/Assessment/ReceiverConnector.csv"
    output_file = "/Users/eki/File Eki/2023 - 2024/Kerjaan/System Engineer/Mandiri/Dokumen/Assessment/Expanded-ReceiverConnector-with-Shared.csv"

    connector_to_ips = parse_csv(filename)
    ip_to_connectors = invert_mapping(connector_to_ips)

    save_to_csv_with_shared(connector_to_ips, ip_to_connectors, output_file)

    ip_set_to_connectors = group_by_ip_sets(connector_to_ips)
    print_duplicate_sets(ip_set_to_connectors)
