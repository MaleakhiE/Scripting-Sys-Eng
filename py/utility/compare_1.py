import pandas as pd
import re

def is_ip_address(value):
    """Check if a value looks like an IP address"""
    if not isinstance(value, str):
        return False
    # Simple pattern matching for IP address format
    ip_pattern = re.compile(r'^\d{1,3}(\.\d{1,3}){3}(:\d+)?$')
    return bool(ip_pattern.match(value))

def process_dataframe(df):
    """Process dataframe to ensure proper formatting of IPs and all columns"""
    # First, convert everything to string to prevent numeric conversion
    for col in df.columns:
        df[col] = df[col].astype(str)
        
        # Clean whitespace
        df[col] = df[col].str.strip()
        
        # If column name contains IP or similar, check if we need to fix IPs
        if any(term in col.lower() for term in ['ip', 'address', 'remote', 'host']):
            # Check if values look like numeric-converted IPs and fix them
            df[col] = df[col].apply(lambda x: fix_ip_if_needed(x) if x and x.strip() else x)
    
    return df

def fix_ip_if_needed(value):
    """Try to fix an IP address that might have been converted to a number"""
    if not isinstance(value, str):
        return value
    
    # If it already looks like an IP address, return it
    if is_ip_address(value):
        return value
    
    # Try to detect and fix numeric IP values
    # This is a simple approach - might need to be customized based on your data
    if value.isdigit():
        # If it's a long digit string that might be a concatenated IP
        # Try to extract groups of 1-3 digits that could be IP octets
        potential_ip = re.findall(r'\d{1,3}', value)
        if len(potential_ip) >= 4:
            # Take the first 4 groups and join with dots
            return '.'.join(potential_ip[:4])
    
    return value

# Main code
try:
    excel_file = "Data Keseluruhan.xlsx"  # Replace with your actual file name
    
    # Load both sheets with string datatypes to preserve formatting
    df1 = pd.read_excel(excel_file, sheet_name="Server Dev 1 (Keseluruhan)", dtype=str)
    df2 = pd.read_excel(excel_file, sheet_name="Server Dev 2 (Keseluruhan)", dtype=str)
    
    # Process dataframes to ensure proper formatting
    df1 = process_dataframe(df1)
    df2 = process_dataframe(df2)
    
    # Print column names to verify
    print("DataFrame 1 columns:", df1.columns.tolist())
    print("DataFrame 2 columns:", df2.columns.tolist())
    
    # Ensure same column order for comparison
    common_columns = sorted(list(set(df1.columns).intersection(set(df2.columns))))
    print(f"Common columns for comparison: {common_columns}")
    
    # If any IP columns are identified, check sample values
    ip_columns = [col for col in common_columns if any(term in col.lower() for term in ['ip', 'address', 'remote', 'host'])]
    if ip_columns:
        print("\nSample IP values from DataFrame 1:")
        for col in ip_columns:
            print(f"{col}: {df1[col].head(3).tolist()}")
    
    # Use only common columns for comparison
    df1_compare = df1[common_columns].copy()
    df2_compare = df2[common_columns].copy()
    
    # Add source markers before merging
    df1['source'] = 'Dev 1'
    df2['source'] = 'Dev 2'
    
    # Compare rows
    only_in_dev1 = pd.merge(df1, df2_compare, on=common_columns, how='left', indicator=True)
    only_in_dev1 = only_in_dev1[only_in_dev1['_merge'] == 'left_only'].drop(columns=['_merge'])
    
    only_in_dev2 = pd.merge(df2, df1_compare, on=common_columns, how='left', indicator=True)
    only_in_dev2 = only_in_dev2[only_in_dev2['_merge'] == 'left_only'].drop(columns=['_merge'])
    
    # Common records in both (intersection)
    common_records = pd.merge(df1[common_columns], df2[common_columns])
    common_records_with_source = pd.merge(df1, df2_compare, on=common_columns)
    common_records_with_source['source'] = 'Both'
    
    # Combine for full dataset 
    all_data = pd.concat([only_in_dev1, only_in_dev2, common_records_with_source])
    
    # Save results
    with pd.ExcelWriter("comparison_results_fixed.xlsx", engine='openpyxl') as writer:
        only_in_dev1.to_excel(writer, sheet_name="Only in Dev 1", index=False)
        only_in_dev2.to_excel(writer, sheet_name="Only in Dev 2", index=False)
        common_records_with_source.to_excel(writer, sheet_name="In Both Dev", index=False)
        all_data.to_excel(writer, sheet_name="All Data Combined", index=False)
    
    print("\nComparison complete. Results saved to 'comparison_results_fixed.xlsx'")

except Exception as e:
    print(f"Error occurred: {str(e)}")
    import traceback
    traceback.print_exc()