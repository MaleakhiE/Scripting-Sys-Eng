import pandas as pd

# Load the Excel file and target sheet
df = pd.read_excel("Data Keseluruhan.xlsx", sheet_name="RVEX Server", dtype=str)

# Remove leading/trailing spaces for consistent comparison
df['Identity'] = df['Identity'].astype(str).str.strip()
df['RemoteIPRanges'] = df['RemoteIPRanges'].astype(str).str.strip()

# Group by IP and check if multiple identities use the same IP
ip_group = df.groupby('RemoteIPRanges')['Identity'].nunique()

# Get IPs used by more than one identity
shared_ips = ip_group[ip_group > 1].index.tolist()

# Mark 'Both' in a new column if the IP is shared
df['source'] = df['RemoteIPRanges'].apply(lambda ip: 'Both' if ip in shared_ips else '')

# Save to Excel
df.to_excel("ip_shared_by_multiple_identities.xlsx", index=False)

print("Check complete. Result saved as 'ip_shared_by_multiple_identities.xlsx'")
