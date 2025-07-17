import pandas as pd
import ipaddress
import re

def expand_ip_range(ip_range_str):
    """
    Expand IP range strings like '10.243.203.71-10.243.203.74' into individual IP addresses
    Returns a list of individual IP addresses
    """
    # Handle various formats of IP ranges
    if not isinstance(ip_range_str, str):
        return []
    
    # Format: 10.243.203.71-10.243.203.74
    ip_range_match = re.match(r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})-(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})', ip_range_str)
    if ip_range_match:
        start_ip_str, end_ip_str = ip_range_match.groups()
        try:
            start_ip = ipaddress.IPv4Address(start_ip_str)
            end_ip = ipaddress.IPv4Address(end_ip_str)
            
            # Generate list of IPs in the range
            ip_list = []
            current_ip = start_ip
            while current_ip <= end_ip:
                ip_list.append(str(current_ip))
                current_ip += 1
            
            return ip_list
        except Exception as e:
            print(f"Error expanding IP range {ip_range_str}: {str(e)}")
            return [ip_range_str]
    
    # Format: 10.243.203.71/24 (CIDR notation)
    cidr_match = re.match(r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2})', ip_range_str)
    if cidr_match:
        cidr = cidr_match.group(1)
        try:
            # For CIDR, we'll return the network address and limit to 100 IPs max
            # (to avoid generating thousands of rows for large subnets)
            network = ipaddress.IPv4Network(cidr, strict=False)
            ip_list = [str(ip) for ip in network][:100]  # Limit to first 100 IPs
            if len(network) > 100:
                print(f"Warning: CIDR {cidr} has more than 100 IPs, only first 100 will be used")
            return ip_list
        except Exception as e:
            print(f"Error expanding CIDR {cidr}: {str(e)}")
            return [ip_range_str]
    
    # Format for IPv6 range like ::-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff
    if '::' in ip_range_str:
        # For IPv6 ranges, we'll just return as is since expanding could create millions of addresses
        return [ip_range_str]
    
    # If it's just a single IP or unrecognized format, return as is
    return [ip_range_str]

def process_excel_with_range_expansion(input_file, sheet_name, output_file):
    """
    Process Excel file to expand IP ranges into individual IPs from a specific sheet
    """
    try:
        # Read Excel file from specific sheet
        print(f"Reading data from file: {input_file}, sheet: {sheet_name}")
        df = pd.read_excel(input_file, sheet_name=sheet_name)
        
        # Show data information
        print(f"Found {len(df)} rows and {len(df.columns)} columns")
        print(f"Columns: {df.columns.tolist()}")
        
        # Clean up column names
        df.columns = [col.replace('*', '').strip() for col in df.columns]
        
        # Ensure required columns exist
        required_cols = ['Identity', 'AuthMechanism', 'PermissionGroups', 'RemoteIPRanges', 'source']
        missing_cols = []
        for col in required_cols:
            if col not in df.columns:
                missing_cols.append(col)
                # Try to find closest column name
                for actual_col in df.columns:
                    if col.lower() in actual_col.lower():
                        print(f"Using '{actual_col}' instead of '{col}'")
                        df.rename(columns={actual_col: col}, inplace=True)
                        missing_cols.pop()
                        break
        
        if missing_cols:
            print(f"Warning: Could not find columns: {missing_cols}")
            print("Please check your Excel file to ensure these columns exist")
            return
        
        # Create empty list for expanded rows
        expanded_rows = []
        
        # Process each row
        print("Processing rows and expanding IP ranges...")
        row_count = 0
        expanded_count = 0
        
        for _, row in df.iterrows():
            print(f"Processing row {row_count + 1}...")
            row_count += 1
            # Get IP range string
            ip_range_str = row['RemoteIPRanges']
            
            # Expand IP ranges
            expanded_ips = expand_ip_range(ip_range_str)
            expanded_count += len(expanded_ips)
            
            # If no IPs found or expansion failed, add the original row
            if not expanded_ips:
                expanded_rows.append(row.to_dict())
            else:
                # Create a new row for each individual IP
                for ip in expanded_ips:
                    new_row = row.copy()
                    new_row['RemoteIPRanges'] = ip
                    expanded_rows.append(new_row.to_dict())
            
            # Print progress for large datasets
            if row_count % 100 == 0:
                print(f"Processed {row_count} rows, expanded to {expanded_count} IPs so far...")
        
        # Create new dataframe from expanded rows
        expanded_df = pd.DataFrame(expanded_rows)
        
        # Save to new Excel file
        print(f"Saving results to {output_file}...")
        expanded_df.to_excel(output_file, index=False)
        
        print(f"\nProcessing complete!")
        print(f"Original rows: {len(df)}")
        print(f"Expanded rows: {len(expanded_df)}")
        print(f"Results saved to: {output_file}")
        
    except Exception as e:
        print(f"Error: {str(e)}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    input_file = "Data Keseluruhan.xlsx"  # Replace with your actual file name
    sheet_name = "RVEX Server"  # Replace with your specific sheet name
    output_file = "expanded_ip_data.xlsx"
    
    process_excel_with_range_expansion(input_file, sheet_name, output_file)