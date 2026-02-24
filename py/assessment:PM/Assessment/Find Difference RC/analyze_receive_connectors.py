#!/usr/bin/env python3
"""
Script untuk menganalisis Receive Connector dan menemukan connector dengan nama sama
tapi RemoteIPRanges berbeda (kecuali connector default)
"""

import csv
import re
from collections import defaultdict
from datetime import datetime

# Daftar keyword untuk connector default yang akan di-exclude
DEFAULT_CONNECTOR_KEYWORDS = [
    'Client Proxy',
    'Default',
    'Client Frontend',
    'Outbound Proxy Frontend',
    'Default Internal Receiver Connector'
]

def is_default_connector(connector_name):
    """Check apakah connector termasuk default connector"""
    for keyword in DEFAULT_CONNECTOR_KEYWORDS:
        if keyword.lower() in connector_name.lower():
            return True
    return False

def normalize_ip_ranges(ip_ranges):
    """Normalize IP ranges untuk perbandingan (sort dan clean)"""
    if not ip_ranges:
        return ""
    # Split by semicolon dan clean whitespace
    ips = [ip.strip() for ip in ip_ranges.split(';')]
    # Sort untuk konsistensi perbandingan (urutan tidak penting)
    ips.sort()
    return '; '.join(ips)

def get_ip_set(ip_ranges):
    """Convert IP ranges ke set untuk perbandingan (ignore urutan)"""
    if not ip_ranges:
        return set()
    # Split by semicolon dan clean whitespace
    ips = [ip.strip() for ip in ip_ranges.split(';')]
    return set(ips)

def analyze_receive_connectors(csv_file):
    """Analisis Receive Connector dan temukan yang berbeda RemoteIPRanges"""
    
    # Dictionary untuk menyimpan connector berdasarkan nama
    # Format: {connector_name: [(server, remote_ip_ranges, full_row), ...]}
    connectors = defaultdict(list)
    
    # Baca CSV file
    print(f"Membaca file: {csv_file}")
    with open(csv_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        
        for row in reader:
            connector_name = row['Name']
            server = row['Server'] if row['Server'] else row['Fqdn']
            remote_ip_ranges = row['RemoteIPRanges']
            
            # Skip connector default
            if is_default_connector(connector_name):
                continue
            
            # Simpan data connector
            connectors[connector_name].append({
                'server': server,
                'remote_ip_ranges': remote_ip_ranges,
                'normalized_ip': normalize_ip_ranges(remote_ip_ranges),
                'ip_set': get_ip_set(remote_ip_ranges),
                'full_row': row
            })
    
    # Temukan connector dengan nama sama tapi IP ranges berbeda
    differences = []
    
    print("\n" + "="*80)
    print("ANALISIS RECEIVE CONNECTOR")
    print("="*80)
    
    for connector_name, instances in connectors.items():
        if len(instances) > 1:
            # Check apakah ada perbedaan IP ranges (gunakan set untuk ignore urutan)
            unique_ip_sets = []
            ip_set_to_servers = {}  # Map IP set ke list servers
            
            for inst in instances:
                ip_set = inst['ip_set']
                ip_set_frozen = frozenset(ip_set)  # Convert ke frozenset agar bisa jadi dict key
                
                # Check apakah IP set ini sudah ada
                is_duplicate = False
                for existing_set in unique_ip_sets:
                    if ip_set == existing_set:
                        is_duplicate = True
                        break
                
                if not is_duplicate:
                    unique_ip_sets.append(ip_set)
                
                # Track servers per IP set
                if ip_set_frozen not in ip_set_to_servers:
                    ip_set_to_servers[ip_set_frozen] = []
                ip_set_to_servers[ip_set_frozen].append(inst['server'])
            
            if len(unique_ip_sets) > 1:
                print(f"\n🔍 DITEMUKAN PERBEDAAN: {connector_name}")
                print(f"   Jumlah instance: {len(instances)}")
                print(f"   Jumlah IP ranges berbeda: {len(unique_ip_sets)}")
                print("-" * 80)
                
                # Group by unique IP sets
                for idx, (ip_set_frozen, servers) in enumerate(ip_set_to_servers.items(), 1):
                    ip_list = sorted(list(ip_set_frozen))
                    print(f"\n   Variasi #{idx}: {'; '.join(ip_list)}")
                    print(f"   Servers ({len(servers)}):")
                    for server in servers:
                        print(f"     - {server}")
                
                # Simpan untuk export ke CSV
                differences.append({
                    'connector_name': connector_name,
                    'instances': instances
                })
    
    return differences

def export_differences_to_csv(differences, output_file):
    """Export perbedaan ke CSV file"""
    
    if not differences:
        print("\n✅ Tidak ada perbedaan ditemukan!")
        return
    
    print(f"\n📝 Menyimpan hasil ke: {output_file}")
    
    with open(output_file, 'w', newline='', encoding='utf-8') as f:
        fieldnames = [
            'Connector_Name',
            'Server',
            'RemoteIPRanges',
            'TransportRole',
            'Enabled',
            'Bindings',
            'PermissionGroups',
            'AuthMechanism',
            'MaxMessageSize',
            'Fqdn'
        ]
        
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        
        for diff in differences:
            connector_name = diff['connector_name']
            instances = diff['instances']
            
            for inst in instances:
                row = inst['full_row']
                writer.writerow({
                    'Connector_Name': connector_name,
                    'Server': inst['server'],
                    'RemoteIPRanges': inst['remote_ip_ranges'],
                    'TransportRole': row.get('TransportRole', ''),
                    'Enabled': row.get('Enabled', ''),
                    'Bindings': row.get('Bindings', ''),
                    'PermissionGroups': row.get('PermissionGroups', ''),
                    'AuthMechanism': row.get('AuthMechanism', ''),
                    'MaxMessageSize': row.get('MaxMessageSize', ''),
                    'Fqdn': row.get('Fqdn', '')
                })
    
    print(f"✅ File berhasil disimpan!")

def main():
    # File input
    input_file = '13a_Receive_Connectors_20260107_105413.csv'
    
    # File output dengan timestamp
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    output_file = f'Receive_Connector_Differences_{timestamp}.csv'
    
    print("="*80)
    print("ANALISIS RECEIVE CONNECTOR - PERBEDAAN REMOTE IP RANGES")
    print("="*80)
    print(f"Input file: {input_file}")
    print(f"Output file: {output_file}")
    print(f"\nConnector yang di-exclude (default connectors):")
    for keyword in DEFAULT_CONNECTOR_KEYWORDS:
        print(f"  - {keyword}")
    
    # Analisis
    differences = analyze_receive_connectors(input_file)
    
    # Export hasil
    export_differences_to_csv(differences, output_file)
    
    # Summary
    print("\n" + "="*80)
    print("SUMMARY")
    print("="*80)
    print(f"Total connector dengan perbedaan: {len(differences)}")
    
    if differences:
        print("\nDaftar connector yang berbeda:")
        for idx, diff in enumerate(differences, 1):
            print(f"  {idx}. {diff['connector_name']} ({len(diff['instances'])} instances)")

if __name__ == '__main__':
    main()
